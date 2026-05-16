// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  HelmPlinthBridge — 4th on-chain sibling-protocol composition
/// @notice Metric-conditional management fees for Plinth vault agents,
///         settled by a Helm futarchy issue's resolved metric outcome.
///
///         Contrast with the 3rd composition (CruciblePlinthBridge):
///           - Crucible bridge releases fee proportional to a stake-weighted
///             Schelling score (validators bond stake to assess quality).
///           - Helm bridge releases fee conditional on a metric oracle
///             ATTESTATION — at resolution time, an off-chain metric reaches
///             (or fails) a threshold, and that binary outcome determines
///             whether the agent collects the full fee or the investor
///             gets a refund.
///
///         Both bridges are useful for different fee-conditioning logic:
///           Crucible → "human-judged strategy quality from staked validators"
///           Helm     → "objective metric crossed threshold, attested by oracle"
///
///         Example Helm issues an investor might sponsor for fee release:
///           "Did Plinth-Vault X reach >$10K TVL by T+90 days?"
///           "Did the agent's reported PnL stay above -10% drawdown over Q1?"
///           "Did BTC close above $100K on the futarchy resolution date?"
///
///         Bridge does not participate in the Helm market — it simply reads
///         `issues[issueId].status == Resolved` and `issues[issueId].metricMet`
///         after the Helm flow runs externally.
///
/// @dev    Three-phase flow (mirrors CruciblePlinthBridge):
///
///         PHASE 1: SPONSOR
///           Investor calls sponsorMetricFee{value: fee}(vaultId, issueId).
///           Bridge reads agent from Plinth + escrows the budget.
///
///         PHASE 2: HELM RESOLUTION (external)
///           Helm issue plays out: bet phase, decide(), resolve() reads
///           metric oracle, sets metricMet flag.
///
///         PHASE 3: SETTLE
///           Anyone calls settle(feeId). Bridge reads Helm's metricMet:
///             - true   → full payout to agent
///             - false  → full refund to investor
///           (Helm's binary outcome maps to all-or-nothing fee release.
///            For proportional release tied to a continuous metric value,
///            use CruciblePlinthBridge instead.)
contract HelmPlinthBridge {
    /* ------------------------- immutables ------------------------- */

    IPlinthVaultReader public immutable plinth;
    IHelm public immutable helm;

    /* ------------------------- storage ------------------------- */

    struct MetricFee {
        bytes32 vaultId;
        bytes32 issueId;   // Helm issue that resolves the metric
        address agent;     // resolved from Plinth at sponsor time
        address funder;
        uint256 budget;
        bool    settled;
    }

    mapping(bytes32 => MetricFee) public fees;
    mapping(bytes32 => uint256) public totalSponsoredFor;

    /* ------------------------- events ------------------------- */

    event MetricFeeSponsored(
        bytes32 indexed feeId,
        bytes32 indexed vaultId,
        bytes32 indexed issueId,
        address funder,
        address agent,
        uint256 budget
    );

    event MetricFeeSettled(
        bytes32 indexed feeId,
        bool   metricMet,
        uint256 paidToAgent,
        uint256 refundedToFunder
    );

    /* ------------------------- errors ------------------------- */

    error ZeroAmount();
    error VaultNotFound();
    error IssueNotResolved();
    error AlreadySettled();
    error FeeNotFound();
    error TransferFailed();

    /* ------------------------- construction ------------------------- */

    constructor(address _plinth, address _helm) {
        plinth = IPlinthVaultReader(_plinth);
        helm = IHelm(_helm);
    }

    /* ------------------------- sponsor ------------------------- */

    function sponsorMetricFee(
        bytes32 vaultId,
        bytes32 issueId
    ) external payable returns (bytes32 feeId) {
        if (msg.value == 0) revert ZeroAmount();

        (address agent, , , , , , , ) = plinth.vaults(vaultId);
        if (agent == address(0)) revert VaultNotFound();

        feeId = keccak256(abi.encode(vaultId, issueId, msg.sender, block.timestamp, block.number));

        fees[feeId] = MetricFee({
            vaultId: vaultId,
            issueId: issueId,
            agent: agent,
            funder: msg.sender,
            budget: msg.value,
            settled: false
        });

        totalSponsoredFor[vaultId] += msg.value;

        emit MetricFeeSponsored(feeId, vaultId, issueId, msg.sender, agent, msg.value);
    }

    /* ------------------------- settle ------------------------- */

    function settle(bytes32 feeId) external returns (uint256 paidToAgent, uint256 refundedToFunder) {
        MetricFee storage f = fees[feeId];
        if (f.budget == 0) revert FeeNotFound();
        if (f.settled) revert AlreadySettled();

        // Read Helm's issue resolution.
        // Helm.issues(issueId) returns (proposer, metricOracle, metricKey, threshold,
        //                                decideAt, resolveAt, defaultDecision, status,
        //                                chosenBranch, metricMet, metricValue)
        (
            /* address proposer */,
            /* address metricOracle */,
            /* bytes32 metricKey */,
            /* uint256 threshold */,
            /* uint64 decideAt */,
            /* uint64 resolveAt */,
            /* uint8 defaultDecision */,
            uint8 status,
            /* uint8 chosenBranch */,
            bool metricMet,
            /* uint256 metricValue */
        ) = helm.issues(f.issueId);

        // Helm status enum: 0=None, 1=Open, 2=Decided, 3=Resolved
        if (status != 3) revert IssueNotResolved();

        if (metricMet) {
            paidToAgent = f.budget;
            refundedToFunder = 0;
        } else {
            paidToAgent = 0;
            refundedToFunder = f.budget;
        }

        f.settled = true;

        emit MetricFeeSettled(feeId, metricMet, paidToAgent, refundedToFunder);

        if (paidToAgent > 0) {
            (bool ok,) = f.agent.call{value: paidToAgent}("");
            if (!ok) revert TransferFailed();
        }
        if (refundedToFunder > 0) {
            (bool ok,) = f.funder.call{value: refundedToFunder}("");
            if (!ok) revert TransferFailed();
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

/// @notice Minimal view interface to Helm v0's `issues` mapping.
/// Helm.Issue struct (in Helm.sol) auto-getter returns fields in declaration order.
interface IHelm {
    function issues(bytes32 issueId) external view returns (
        address proposer,
        address metricOracle,
        bytes32 metricKey,
        uint256 threshold,
        uint64 decideAt,
        uint64 resolveAt,
        uint8 defaultDecision,
        uint8 status,
        uint8 chosenBranch,
        bool metricMet,
        uint256 metricValue
    );
}
