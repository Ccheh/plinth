// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  CruciblePlinthBridge — 3rd on-chain sibling-protocol composition
/// @notice Quality-conditional management fees for AI trading agents on Arc.
///
///         The traditional fund management fee is unconditional: investor pays
///         2/20 regardless of strategy performance, regardless of whether the
///         agent followed its declared mandate. CruciblePlinthBridge turns
///         that into a quality-conditional release: vault investors escrow a
///         management-fee budget into the bridge, tied to a Crucible quality
///         market that scores the agent's performance over a period. When
///         the market resolves, the bridge releases a fraction of the budget
///         proportional to the resolved score (0-10000 basis points = 0%-100%).
///
///         This is the **first on-chain implementation of quality-conditional
///         management fees** the author is aware of — and the third on-chain
///         sibling-protocol composition Plinth ships:
///
///           1. MandatePlinthBridge      — Mandate v0  + PlinthV05  (capability-bound credit)
///           2. CadencePlinthBridge       — Plinth     + Cadence v2  (Nanopayments fee rail)
///           3. CruciblePlinthBridge     — Plinth      + Crucible v6 (quality-conditional fee release) ← NEW
///
///         All three follow the same pattern: a thin bridge that atomically
///         reads state from one protocol and writes to another. No admin keys,
///         no off-chain orchestration required for the core flow.
///
/// @dev    Flow (3 phases, all on-chain, all permissionless):
///
///         PHASE 1: SPONSOR
///           Investor calls sponsorConditionalFee{value: fee}(vaultId, marketId, minScoreBps).
///           Bridge reads agent from Plinth (no spoofing). Bridge holds the escrowed
///           USDC and records the (vaultId, marketId, minScoreBps, funder) tuple.
///
///         PHASE 2: CRUCIBLE RESOLUTION (external — bridge does not participate)
///           Agent and validators play out the Crucible market over the dispute window.
///           Eventually `markets[marketId].status == Resolved` and `scoreBps` is set.
///
///         PHASE 3: SETTLE
///           Anyone calls settle(feeId). Bridge reads Crucible's resolved score:
///             - If status != Resolved: revert (settle too early)
///             - If scoreBps < minScoreBps: full refund to funder
///             - Else: agent receives (budget × scoreBps / 10_000); remainder to funder
///
///         Investors get a soft guarantee: if the agent doesn't meet the minimum
///         quality bar, they get their fee back. Agents get a hard incentive:
///         the better Crucible scores them, the more fee they collect.
contract CruciblePlinthBridge {
    /* ------------------------- immutables ------------------------- */

    IPlinthVaultReader public immutable plinth;
    ICrucibleMarketV6  public immutable crucible;

    /* ------------------------- storage ------------------------- */

    struct ConditionalFee {
        bytes32 vaultId;
        bytes32 marketId;     // Crucible market that resolves the quality score
        address agent;        // resolved from Plinth at sponsor time
        address funder;
        uint256 budget;       // escrowed USDC (wei, 18 decimals on Arc)
        uint16  minScoreBps;  // below this, full refund; above, proportional payout
        bool    settled;
    }

    mapping(bytes32 => ConditionalFee) public fees;
    mapping(bytes32 => uint256) public totalSponsoredFor; // per-vault accumulator

    /* ------------------------- events ------------------------- */

    event ConditionalFeeSponsored(
        bytes32 indexed feeId,
        bytes32 indexed vaultId,
        bytes32 indexed marketId,
        address funder,
        address agent,
        uint256 budget,
        uint16  minScoreBps
    );

    event ConditionalFeeSettled(
        bytes32 indexed feeId,
        uint16  resolvedScoreBps,
        uint256 paidToAgent,
        uint256 refundedToFunder,
        bool    minScoreMet
    );

    /* ------------------------- errors ------------------------- */

    error ZeroAmount();
    error VaultNotFound();
    error MarketNotResolved();
    error AlreadySettled();
    error FeeNotFound();
    error TransferFailed();
    error InvalidMinScore();

    /* ------------------------- construction ------------------------- */

    constructor(address _plinth, address _crucible) {
        plinth = IPlinthVaultReader(_plinth);
        crucible = ICrucibleMarketV6(_crucible);
    }

    /* ------------------------- sponsor (phase 1) ------------------------- */

    /// @notice Escrow a management-fee budget for the agent of `vaultId`,
    /// conditional on the Crucible market `marketId` resolving with a score
    /// at or above `minScoreBps`. Funder = msg.sender. Agent address is
    /// read from Plinth (no spoofing).
    ///
    /// @param vaultId       Plinth vault id. Must exist (status != None).
    /// @param marketId      Crucible market id that will resolve quality.
    /// @param minScoreBps   Minimum scoreBps (0-10000) below which the fee
    ///                      is fully refunded. Set to 0 for "any resolution
    ///                      triggers proportional payout".
    /// @return feeId        Deterministic fee id. Anyone can call settle(feeId) once Crucible resolves.
    function sponsorConditionalFee(
        bytes32 vaultId,
        bytes32 marketId,
        uint16 minScoreBps
    ) external payable returns (bytes32 feeId) {
        if (msg.value == 0) revert ZeroAmount();
        if (minScoreBps > 10_000) revert InvalidMinScore();

        // Read agent from Plinth — caller cannot spoof who gets the fee.
        (address agent, , , , , , , ) = plinth.vaults(vaultId);
        if (agent == address(0)) revert VaultNotFound();

        feeId = keccak256(abi.encode(vaultId, marketId, msg.sender, block.timestamp, block.number));

        fees[feeId] = ConditionalFee({
            vaultId: vaultId,
            marketId: marketId,
            agent: agent,
            funder: msg.sender,
            budget: msg.value,
            minScoreBps: minScoreBps,
            settled: false
        });

        totalSponsoredFor[vaultId] += msg.value;

        emit ConditionalFeeSponsored(feeId, vaultId, marketId, msg.sender, agent, msg.value, minScoreBps);
    }

    /* ------------------------- settle (phase 3) ------------------------- */

    /// @notice Read the resolved Crucible score and disburse the fee. Anyone
    /// can call once Crucible has resolved the market. Math:
    ///   - if resolvedScore < minScoreBps  → full refund to funder
    ///   - else                            → agent gets (budget × resolvedScore / 10_000)
    ///                                        funder gets the remainder
    ///
    /// @dev Idempotent — settling twice reverts AlreadySettled.
    function settle(bytes32 feeId) external returns (uint256 paidToAgent, uint256 refundedToFunder) {
        ConditionalFee storage f = fees[feeId];
        if (f.budget == 0) revert FeeNotFound();
        if (f.settled) revert AlreadySettled();

        // Read Crucible's resolved score for the market.
        (
            /* address service */,
            /* address agent */,
            /* address resolver */,
            /* uint256 agentEscrow */,
            /* uint256 bondLocked */,
            /* uint256 disputeBond */,
            /* uint16 disputeBondBps */,
            /* bytes32 commitmentHash */,
            /* uint64 disputeDeadline */,
            /* uint64 disputedAt */,
            uint16 resolvedScoreBps,
            uint8 status
        ) = crucible.markets(f.marketId);

        // Crucible status: 0=None, 1=Open, 2=Disputed, 3=Resolved
        if (status != 3) revert MarketNotResolved();

        bool minMet = resolvedScoreBps >= f.minScoreBps;
        if (!minMet) {
            // Refund full budget to funder
            paidToAgent = 0;
            refundedToFunder = f.budget;
        } else {
            // Proportional release
            paidToAgent = (f.budget * resolvedScoreBps) / 10_000;
            refundedToFunder = f.budget - paidToAgent;
        }

        f.settled = true;

        emit ConditionalFeeSettled(feeId, resolvedScoreBps, paidToAgent, refundedToFunder, minMet);

        if (paidToAgent > 0) {
            (bool okA,) = f.agent.call{value: paidToAgent}("");
            if (!okA) revert TransferFailed();
        }
        if (refundedToFunder > 0) {
            (bool okF,) = f.funder.call{value: refundedToFunder}("");
            if (!okF) revert TransferFailed();
        }
    }

    /* ------------------------- views ------------------------- */

    function isSettled(bytes32 feeId) external view returns (bool) {
        return fees[feeId].settled;
    }
}

/* ====================================================================== */
/*    Minimal external interfaces                                          */
/* ====================================================================== */

interface IPlinthVaultReader {
    function vaults(bytes32 vaultId) external view returns (
        address agent,
        uint64 createdAt,
        uint8 status,
        uint256 totalShares,
        uint256 inVault,
        uint256 deployedAUM,
        int256 reportedPnL,
        string memory strategyDescriptor
    );
}

/// @notice Minimal view-side interface to Crucible v6's markets mapping.
/// Crucible's Market struct (defined in CrucibleMarketV6.sol) has this layout.
/// The auto-generated public getter returns the fields in declaration order.
interface ICrucibleMarketV6 {
    function markets(bytes32 marketId) external view returns (
        address service,
        address agent,
        address resolver,
        uint256 agentEscrow,
        uint256 bondLocked,
        uint256 disputeBond,
        uint16 disputeBondBps,
        bytes32 commitmentHash,
        uint64 disputeDeadline,
        uint64 disputedAt,
        uint16 scoreBps,
        uint8 status
    );
}
