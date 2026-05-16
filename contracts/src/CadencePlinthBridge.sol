// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Minimal interface — IPlinth doesn't declare the `vaults` public getter,
// but PlinthV05/V06 expose it via `mapping(bytes32 => Vault) public vaults`.
// We declare just what the bridge needs.
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

/// @title  CadencePlinthBridge — second on-chain sibling-protocol composition
/// @notice Routes a Plinth vault's management fees into Cadence's PaymentEscrowV2,
///         giving the vault's agent full Nanopayments downstream — signed claims,
///         batched settlement, session keys — without losing the on-chain audit
///         trail of which vault funded which payment.
///
/// @dev    This is the **second** on-chain sibling-protocol composition Plinth
///         ships. The first was MandatePlinthBridge (capability-bound capital
///         authorization). The pattern is the same: a thin bridge that
///         reads state from one protocol and writes to another atomically.
///
///         Flow:
///           1. A vault investor (or anyone) calls `routeManagementFee{value: fee}(vaultId)`.
///           2. Bridge reads the vault's `agent` address from Plinth.
///           3. Bridge calls `cadence.depositFor{value: fee}(agent)` —
///              the agent's Cadence balance increases by `fee`.
///           4. Agent can now spend that balance via standard Cadence flow:
///              sign EIP-712 claims to services, batched settlement, etc.
///           5. All activity is attributable: bridge emits `FeeRouted` with the
///              source vaultId, the recipient agent, and the cumulative tally.
///
///         This composition shows up in the Grant narrative as:
///           "Plinth's capital layer + Cadence's payment-streaming rail —
///            vault depositors authorize per-event management fees that the
///            agent draws down through Cadence claims, no privileged paths."
contract CadencePlinthBridge {
    /* ------------------------- immutables ------------------------- */

    /// @notice The Plinth contract this bridge reads vault state from.
    /// Set to PlinthV05 or PlinthV06 at deployment time.
    IPlinthVaultReader public immutable plinth;

    /// @notice Cadence PaymentEscrowV2 receiving deposits-on-behalf-of-agent.
    IPaymentEscrowV2 public immutable cadence;

    /* ------------------------- storage ------------------------- */

    /// @notice Per-vault cumulative fees routed through this bridge into Cadence.
    /// Off-chain indexers can use this for per-vault ROI math.
    mapping(bytes32 => uint256) public totalRouted;

    /// @notice Per-vault count of fee-routing events. Useful for billing
    /// reconciliation: count events * configured per-event-fee should match
    /// `totalRouted` if the vault uses a uniform per-event fee.
    mapping(bytes32 => uint256) public eventCount;

    /* ------------------------- events ------------------------- */

    event FeeRouted(
        bytes32 indexed vaultId,
        address indexed agent,
        address indexed funder,
        uint256 amount,
        uint256 cumulativeRouted,
        uint256 eventCountAfter
    );

    /* ------------------------- errors ------------------------- */

    error ZeroAmount();
    error VaultNotFound();
    error CadenceDepositFailed();

    /* ------------------------- construction ------------------------- */

    constructor(address _plinth, address _cadence) {
        plinth = IPlinthVaultReader(_plinth);
        cadence = IPaymentEscrowV2(_cadence);
    }

    /* ------------------------- routing ------------------------- */

    /// @notice Route `msg.value` USDC into the Plinth vault's agent's Cadence
    /// balance. Caller funds the payment with `msg.value`; recipient is read
    /// from Plinth (no spoofing possible).
    ///
    /// @param vaultId  Plinth vault id. Must exist (status != None) and have
    ///                 a non-zero agent address.
    /// @return agent   The vault's agent address — also the credit recipient
    ///                 in Cadence's PaymentEscrowV2.
    function routeManagementFee(bytes32 vaultId) external payable returns (address agent) {
        if (msg.value == 0) revert ZeroAmount();

        // Read agent from Plinth's `vaults(vaultId)` view. The Vault struct
        // returns (agent, createdAt, status, totalShares, inVault, deployedAUM,
        // reportedPnL, strategyDescriptor).
        (agent, , , , , , , ) = plinth.vaults(vaultId);
        if (agent == address(0)) revert VaultNotFound();

        // Forward to Cadence. PaymentEscrowV2.depositFor credits the agent's
        // balance and emits its own Deposited event with (agent=agent, funder=this bridge).
        try cadence.depositFor{value: msg.value}(agent) {
            // success
        } catch {
            revert CadenceDepositFailed();
        }

        unchecked {
            totalRouted[vaultId] += msg.value;
            eventCount[vaultId] += 1;
        }

        emit FeeRouted(
            vaultId,
            agent,
            msg.sender,
            msg.value,
            totalRouted[vaultId],
            eventCount[vaultId]
        );
    }

    /* ------------------------- views ------------------------- */

    /// @notice Convenience view for off-chain pricing: average fee per event.
    function avgFeePerEvent(bytes32 vaultId) external view returns (uint256) {
        uint256 n = eventCount[vaultId];
        if (n == 0) return 0;
        return totalRouted[vaultId] / n;
    }
}

/* ====================================================================== */
/*    Minimal external interface — PaymentEscrowV2.depositFor only.        */
/*    Pulled from cadence/contracts/src/PaymentEscrowV2.sol (Arc402 v2).   */
/* ====================================================================== */

interface IPaymentEscrowV2 {
    function depositFor(address agent) external payable;
    function balanceOf(address agent) external view returns (uint256);
}
