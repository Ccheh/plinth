// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HelmPlinthBridge, IHelm} from "../src/HelmPlinthBridge.sol";
import {PlinthV05} from "../src/PlinthV05.sol";
import {MockVenue} from "../src/MockVenue.sol";

/// @notice Tests for the fourth on-chain sibling-protocol composition:
/// HelmPlinthBridge — metric-conditional management fees for Plinth agents,
/// resolved by a Helm futarchy issue's binary metricMet outcome.
contract HelmPlinthBridgeTest is Test {
    HelmPlinthBridge bridge;
    PlinthV05 plinth;
    MockHelm helm;
    MockVenue venue;

    address agent     = makeAddr("agent");
    address funder    = makeAddr("funder");
    address attacker  = makeAddr("attacker");
    bytes32 vaultId;
    bytes32 constant ISSUE_ID = bytes32(uint256(0xfeedface));

    function setUp() public {
        plinth = new PlinthV05();
        helm = new MockHelm();
        venue = new MockVenue();
        bridge = new HelmPlinthBridge(address(plinth), address(helm));

        vm.deal(agent,    100 ether);
        vm.deal(funder,   100 ether);
        vm.deal(attacker, 100 ether);
        vm.warp(1_000_000);

        address[] memory venues = new address[](1);
        venues[0] = address(venue);
        vm.prank(agent);
        vaultId = plinth.createVault{value: 0.01 ether}(venues, "BTC strategy");
    }

    /* ====================================================================== */
    /*     Happy paths                                                          */
    /* ====================================================================== */

    function test_metricMet_payoutToAgent() public {
        vm.prank(funder);
        bytes32 feeId = bridge.sponsorMetricFee{value: 1 ether}(vaultId, ISSUE_ID);
        helm.setResolved(ISSUE_ID, true);

        uint256 agentBefore = agent.balance;
        uint256 funderBefore = funder.balance;

        (uint256 paid, uint256 refund) = bridge.settle(feeId);
        assertEq(paid, 1 ether);
        assertEq(refund, 0);
        assertEq(agent.balance, agentBefore + 1 ether);
        assertEq(funder.balance, funderBefore);
    }

    function test_metricNotMet_fullRefund() public {
        vm.prank(funder);
        bytes32 feeId = bridge.sponsorMetricFee{value: 0.5 ether}(vaultId, ISSUE_ID);
        helm.setResolved(ISSUE_ID, false);

        uint256 agentBefore = agent.balance;
        uint256 funderBefore = funder.balance;

        (uint256 paid, uint256 refund) = bridge.settle(feeId);
        assertEq(paid, 0);
        assertEq(refund, 0.5 ether);
        assertEq(agent.balance, agentBefore);
        assertEq(funder.balance, funderBefore + 0.5 ether);
    }

    /* ====================================================================== */
    /*     Agent-spoof resistance + invariants                                  */
    /* ====================================================================== */

    function test_attackerSponsoring_creditsRealAgent() public {
        vm.prank(attacker);
        bytes32 feeId = bridge.sponsorMetricFee{value: 0.3 ether}(vaultId, ISSUE_ID);
        helm.setResolved(ISSUE_ID, true);

        uint256 agentBefore = agent.balance;
        uint256 attackerBefore = attacker.balance;
        bridge.settle(feeId);

        // Real agent gets paid; attacker (as funder, but metricMet=true → 0 refund) gets nothing
        assertEq(agent.balance, agentBefore + 0.3 ether);
        assertEq(attacker.balance, attackerBefore);
    }

    function test_settleBeforeResolve_reverts() public {
        vm.prank(funder);
        bytes32 feeId = bridge.sponsorMetricFee{value: 1 ether}(vaultId, ISSUE_ID);
        // Helm issue is still in default Status.None — should revert
        vm.expectRevert(HelmPlinthBridge.IssueNotResolved.selector);
        bridge.settle(feeId);
    }

    function test_doubleSettle_reverts() public {
        vm.prank(funder);
        bytes32 feeId = bridge.sponsorMetricFee{value: 1 ether}(vaultId, ISSUE_ID);
        helm.setResolved(ISSUE_ID, true);
        bridge.settle(feeId);
        vm.expectRevert(HelmPlinthBridge.AlreadySettled.selector);
        bridge.settle(feeId);
    }

    function test_revertOnZero() public {
        vm.prank(funder);
        vm.expectRevert(HelmPlinthBridge.ZeroAmount.selector);
        bridge.sponsorMetricFee{value: 0}(vaultId, ISSUE_ID);
    }

    function test_revertOnFakeVault() public {
        vm.prank(funder);
        vm.expectRevert(HelmPlinthBridge.VaultNotFound.selector);
        bridge.sponsorMetricFee{value: 1 ether}(keccak256("ghost"), ISSUE_ID);
    }

    function test_perVaultAccumulator() public {
        vm.startPrank(funder);
        bridge.sponsorMetricFee{value: 0.1 ether}(vaultId, ISSUE_ID);
        bridge.sponsorMetricFee{value: 0.2 ether}(vaultId, ISSUE_ID);
        vm.stopPrank();
        assertEq(bridge.totalSponsoredFor(vaultId), 0.3 ether);
    }
}

/* ====================================================================== */
/*     Mock Helm — settable resolution                                      */
/* ====================================================================== */

contract MockHelm is IHelm {
    struct IssueState { bool metricMet; uint8 status; }
    mapping(bytes32 => IssueState) public state;

    function setResolved(bytes32 issueId, bool metricMet) external {
        state[issueId] = IssueState(metricMet, 3); // status=Resolved
    }

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
    ) {
        IssueState memory s = state[issueId];
        return (address(0), address(0), bytes32(0), 0, 0, 0, 0, s.status, 0, s.metricMet, 0);
    }
}
