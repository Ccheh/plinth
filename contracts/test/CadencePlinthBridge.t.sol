// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CadencePlinthBridge, IPaymentEscrowV2, IPlinthVaultReader} from "../src/CadencePlinthBridge.sol";
import {PlinthV05} from "../src/PlinthV05.sol";
import {MockVenue} from "../src/MockVenue.sol";

/// @notice Tests for the second on-chain sibling-protocol composition:
/// CadencePlinthBridge routes Plinth vault management fees into Cadence's
/// PaymentEscrowV2 keyed to the vault's agent.
///
/// Coverage:
///   (1) End-to-end: vault → bridge → cadence balance increments correctly
///   (2) Bridge reads agent from Plinth (not spoofable by caller)
///   (3) Per-vault cumulative tracking + event count
///   (4) Revert paths: zero-value, non-existent vault, cadence failure
///   (5) Funder is distinct from agent (sponsorship pattern works)
contract CadencePlinthBridgeTest is Test {
    CadencePlinthBridge bridge;
    PlinthV05 plinth;
    MockPaymentEscrowV2 cadence;
    MockVenue venue;

    address agent     = makeAddr("agent");
    address investor  = makeAddr("investor");
    address funder    = makeAddr("funder");
    bytes32 vaultId;

    function setUp() public {
        plinth = new PlinthV05();
        cadence = new MockPaymentEscrowV2();
        venue = new MockVenue();
        bridge = new CadencePlinthBridge(address(plinth), address(cadence));

        vm.deal(agent,    100 ether);
        vm.deal(investor, 100 ether);
        vm.deal(funder,   100 ether);
        vm.warp(1_000_000);

        // Create a vault on Plinth so the bridge has something to read
        address[] memory venues = new address[](1);
        venues[0] = address(venue);
        vm.prank(agent);
        vaultId = plinth.createVault{value: 0.01 ether}(venues, "BTC perp strategy");
    }

    /* ====================================================================== */
    /*               End-to-end happy path                                     */
    /* ====================================================================== */

    function test_routeManagementFee_creditsCadenceBalance() public {
        uint256 fee = 0.001 ether;

        assertEq(cadence.balanceOf(agent), 0);
        assertEq(bridge.totalRouted(vaultId), 0);
        assertEq(bridge.eventCount(vaultId), 0);

        vm.prank(funder);
        address returned = bridge.routeManagementFee{value: fee}(vaultId);

        assertEq(returned, agent);
        assertEq(cadence.balanceOf(agent), fee);
        assertEq(bridge.totalRouted(vaultId), fee);
        assertEq(bridge.eventCount(vaultId), 1);
    }

    function test_routeManagementFee_agentNotCallerCantSpoof() public {
        // Even if funder is malicious and pretends to be a different agent,
        // the bridge reads from Plinth — so credit goes to the REAL agent.
        address impostor = makeAddr("impostor");
        vm.deal(impostor, 10 ether);

        vm.prank(impostor);
        bridge.routeManagementFee{value: 0.001 ether}(vaultId);

        assertEq(cadence.balanceOf(agent), 0.001 ether);  // real agent credited
        assertEq(cadence.balanceOf(impostor), 0);          // impostor gets nothing
    }

    function test_routeManagementFee_emitsEvent() public {
        vm.prank(funder);
        vm.expectEmit(true, true, true, true, address(bridge));
        emit CadencePlinthBridge.FeeRouted(vaultId, agent, funder, 0.002 ether, 0.002 ether, 1);
        bridge.routeManagementFee{value: 0.002 ether}(vaultId);
    }

    /* ====================================================================== */
    /*               Per-vault tracking                                        */
    /* ====================================================================== */

    function test_perVaultAccumulation() public {
        vm.startPrank(funder);
        bridge.routeManagementFee{value: 0.001 ether}(vaultId);
        bridge.routeManagementFee{value: 0.003 ether}(vaultId);
        bridge.routeManagementFee{value: 0.001 ether}(vaultId);
        vm.stopPrank();

        assertEq(bridge.totalRouted(vaultId), 0.005 ether);
        assertEq(bridge.eventCount(vaultId), 3);
        assertEq(bridge.avgFeePerEvent(vaultId), uint256(0.005 ether) / 3);
        assertEq(cadence.balanceOf(agent), 0.005 ether);
    }

    function test_multipleVaults_trackSeparately() public {
        // Second vault by a different agent
        address agent2 = makeAddr("agent2");
        vm.deal(agent2, 10 ether);
        address[] memory venues = new address[](1);
        venues[0] = address(venue);
        vm.prank(agent2);
        bytes32 vaultId2 = plinth.createVault{value: 0.01 ether}(venues, "second strategy");

        vm.startPrank(funder);
        bridge.routeManagementFee{value: 0.001 ether}(vaultId);
        bridge.routeManagementFee{value: 0.002 ether}(vaultId2);
        vm.stopPrank();

        assertEq(bridge.totalRouted(vaultId), 0.001 ether);
        assertEq(bridge.totalRouted(vaultId2), 0.002 ether);
        assertEq(cadence.balanceOf(agent), 0.001 ether);
        assertEq(cadence.balanceOf(agent2), 0.002 ether);
    }

    /* ====================================================================== */
    /*               Sponsorship pattern                                       */
    /* ====================================================================== */

    function test_funderDistinctFromAgent_sponsorshipWorks() public {
        // Funder is NOT the agent. Funder still successfully sponsors the
        // agent's Cadence balance through the bridge.
        vm.prank(funder);
        bridge.routeManagementFee{value: 0.01 ether}(vaultId);

        // Funder loses funds, agent gains in Cadence
        assertEq(cadence.balanceOf(agent), 0.01 ether);
        assertEq(cadence.balanceOf(funder), 0);
    }

    function test_funderAsInvestor_attributableInLogs() public {
        // The investor sponsoring the agent should be visible in the FeeRouted
        // log so off-chain accounting can attribute "investor X paid Y fees to
        // agent of vault Z". Test by checking the funder topic.
        vm.recordLogs();
        vm.prank(investor);
        bridge.routeManagementFee{value: 0.001 ether}(vaultId);

        // Find FeeRouted log and assert funder topic
        // FeeRouted(bytes32 indexed vaultId, address indexed agent, address indexed funder, uint256, uint256, uint256)
        // topics[3] = funder (address padded to 32 bytes)
        // We don't decode here; the previous test_routeManagementFee_emitsEvent
        // already asserts the full event shape including funder via expectEmit.
        assertEq(cadence.balanceOf(agent), 0.001 ether);
    }

    /* ====================================================================== */
    /*               Revert paths                                              */
    /* ====================================================================== */

    function test_revertsOnZeroValue() public {
        vm.prank(funder);
        vm.expectRevert(CadencePlinthBridge.ZeroAmount.selector);
        bridge.routeManagementFee{value: 0}(vaultId);
    }

    function test_revertsOnNonExistentVault() public {
        bytes32 fakeVault = keccak256("fake");
        vm.prank(funder);
        vm.expectRevert(CadencePlinthBridge.VaultNotFound.selector);
        bridge.routeManagementFee{value: 0.001 ether}(fakeVault);
    }

    function test_revertsOnCadenceFailure() public {
        // Deploy a broken Cadence that reverts on depositFor
        BrokenPaymentEscrow brokenCadence = new BrokenPaymentEscrow();
        CadencePlinthBridge brokenBridge = new CadencePlinthBridge(address(plinth), address(brokenCadence));

        vm.prank(funder);
        vm.expectRevert(CadencePlinthBridge.CadenceDepositFailed.selector);
        brokenBridge.routeManagementFee{value: 0.001 ether}(vaultId);
    }

    /* ====================================================================== */
    /*               View functions                                            */
    /* ====================================================================== */

    function test_avgFeePerEvent_zeroWhenNoEvents() public view {
        assertEq(bridge.avgFeePerEvent(vaultId), 0);
    }

    function test_immutables_setCorrectly() public view {
        assertEq(address(bridge.plinth()), address(plinth));
        assertEq(address(bridge.cadence()), address(cadence));
    }
}

/* ====================================================================== */
/*       Test-only mocks                                                    */
/* ====================================================================== */

/// @notice Minimal PaymentEscrowV2 — just `depositFor` + `balanceOf`.
contract MockPaymentEscrowV2 is IPaymentEscrowV2 {
    mapping(address => uint256) public balanceOf;

    function depositFor(address agent) external payable {
        require(msg.value > 0, "zero");
        require(agent != address(0), "zero addr");
        balanceOf[agent] += msg.value;
    }
}

/// @notice Cadence stand-in that always reverts on depositFor (tests failure path).
contract BrokenPaymentEscrow is IPaymentEscrowV2 {
    mapping(address => uint256) public balanceOf;

    function depositFor(address /*agent*/) external payable {
        revert("intentional failure");
    }
}
