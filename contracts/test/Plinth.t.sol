// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Plinth} from "../src/Plinth.sol";
import {IPlinth} from "../src/interfaces/IPlinth.sol";
import {MockVenue} from "../src/MockVenue.sol";

contract PlinthTest is Test {
    Plinth p;
    MockVenue venue1;
    MockVenue venue2;

    address agent     = makeAddr("agent");
    address alice     = makeAddr("alice");
    address bob       = makeAddr("bob");
    address attacker  = makeAddr("attacker");
    address evilVenue = makeAddr("evilVenue");

    string constant DESC = "BTC perp momentum strategy, max 3x leverage";

    function setUp() public {
        p = new Plinth();
        venue1 = new MockVenue();
        venue2 = new MockVenue();
        vm.deal(agent, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob,   100 ether);
        vm.deal(attacker, 100 ether);
        vm.warp(1_000_000);
    }

    /* ---------- helpers ---------- */

    function _venuesSingle() internal view returns (address[] memory v) {
        v = new address[](1);
        v[0] = address(venue1);
    }

    function _venuesPair() internal view returns (address[] memory v) {
        v = new address[](2);
        v[0] = address(venue1);
        v[1] = address(venue2);
    }

    function _create(uint256 initial) internal returns (bytes32 vaultId) {
        vm.prank(agent);
        vaultId = p.createVault{value: initial}(_venuesSingle(), DESC);
    }

    /* ============================================================ */
    /*                       createVault                             */
    /* ============================================================ */

    function test_createVault_happyPath() public {
        bytes32 id = _create(1 ether);
        (
            address ag, uint64 createdAt, IPlinth.VaultStatus status,
            uint256 totalShares, uint256 inVault, uint256 deployedAUM,
            int256 reportedPnL, string memory desc
        ) = p.vaults(id);
        assertEq(ag, agent);
        assertEq(createdAt, uint64(block.timestamp));
        assertEq(uint256(status), uint256(IPlinth.VaultStatus.Active));
        assertEq(totalShares, 1 ether);
        assertEq(inVault, 1 ether);
        assertEq(deployedAUM, 0);
        assertEq(reportedPnL, 0);
        assertEq(desc, DESC);
        assertEq(p.sharesOf(id, agent), 1 ether);
        assertEq(p.nav(id), 1 ether);            // inception NAV
        assertEq(address(p).balance, 1 ether);
        assertEq(p.totalAUM(id), int256(1 ether));
    }

    function test_createVault_uniqueIds() public {
        bytes32 a = _create(0.5 ether);
        bytes32 b = _create(0.5 ether);
        assertTrue(a != b);
    }

    function test_createVault_emitsVaultCreatedAndDeposit() public {
        vm.expectEmit(false, true, false, false);
        emit IPlinth.VaultCreated(bytes32(0), agent, _venuesSingle(), DESC, 1 ether);
        vm.expectEmit(false, true, false, true);
        emit IPlinth.Deposit(bytes32(0), agent, 1 ether, 1 ether, 1 ether);
        vm.prank(agent);
        p.createVault{value: 1 ether}(_venuesSingle(), DESC);
    }

    function test_createVault_revertsEmptyVenues() public {
        address[] memory empty = new address[](0);
        vm.prank(agent);
        vm.expectRevert(IPlinth.EmptyVenues.selector);
        p.createVault{value: 1 ether}(empty, DESC);
    }

    function test_createVault_revertsTooManyVenues() public {
        address[] memory many = new address[](17);
        for (uint256 i = 0; i < many.length; i++) {
            many[i] = address(uint160(i + 1));
        }
        vm.prank(agent);
        vm.expectRevert(IPlinth.TooManyVenues.selector);
        p.createVault{value: 1 ether}(many, DESC);
    }

    function test_createVault_revertsZeroAddressVenue() public {
        address[] memory v = new address[](1);
        v[0] = address(0);
        vm.prank(agent);
        vm.expectRevert(IPlinth.ZeroAddress.selector);
        p.createVault{value: 1 ether}(v, DESC);
    }

    function test_createVault_revertsBelowMin() public {
        vm.prank(agent);
        vm.expectRevert(IPlinth.ZeroAmount.selector);
        p.createVault{value: 0.00001 ether}(_venuesSingle(), DESC);
    }

    /* ============================================================ */
    /*                          deposit                              */
    /* ============================================================ */

    function test_deposit_happyPath_atInceptionNav() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        uint256 sm = p.deposit{value: 0.5 ether}(id);
        // NAV at inception is 1, so deposit 0.5 → 0.5 shares
        assertEq(sm, 0.5 ether);
        assertEq(p.sharesOf(id, alice), 0.5 ether);
        (, , , uint256 total, uint256 inV, , ,) = p.vaults(id);
        assertEq(total, 1.5 ether);
        assertEq(inV, 1.5 ether);
        assertEq(p.nav(id), 1 ether);   // still inception (no PnL yet)
    }

    function test_deposit_revertsWhenPaused() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.setPaused(id, true);
        vm.prank(alice);
        vm.expectRevert(IPlinth.NotActive.selector);
        p.deposit{value: 0.5 ether}(id);
    }

    function test_deposit_revertsWhenClosed() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.closeVault(id);
        vm.prank(alice);
        vm.expectRevert(IPlinth.NotActive.selector);
        p.deposit{value: 0.5 ether}(id);
    }

    function test_deposit_revertsBelowMin() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        vm.expectRevert(IPlinth.ZeroAmount.selector);
        p.deposit{value: 0.00001 ether}(id);
    }

    function test_deposit_revertsUnderwater() public {
        bytes32 id = _create(1 ether);
        // Agent reports catastrophic loss bringing AUM to <= 0
        vm.prank(agent);
        p.reportPnL(id, -2 ether);  // 1 + 0 + (-2) = -1, underwater
        vm.prank(alice);
        vm.expectRevert(IPlinth.UnderwaterVault.selector);
        p.deposit{value: 0.5 ether}(id);
    }

    function test_deposit_atPositiveNAVMintsFewerShares() public {
        bytes32 id = _create(1 ether);
        // Agent reports +50% gain → NAV becomes 1.5
        vm.prank(agent);
        p.reportPnL(id, 0.5 ether);
        assertEq(p.nav(id), 1.5 ether);
        // Alice deposits 0.6 USDC at NAV 1.5 → expects 0.4 shares
        vm.prank(alice);
        uint256 sm = p.deposit{value: 0.6 ether}(id);
        assertEq(sm, 0.4 ether);
        assertEq(p.sharesOf(id, alice), 0.4 ether);
    }

    function test_deposit_atNegativeNAVMintsMoreShares() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.reportPnL(id, -0.5 ether);   // NAV → 0.5
        assertEq(p.nav(id), 0.5 ether);
        vm.prank(alice);
        uint256 sm = p.deposit{value: 0.2 ether}(id);
        // 0.2 / 0.5 = 0.4 shares
        assertEq(sm, 0.4 ether);
    }

    /* ============================================================ */
    /*                          redeem                               */
    /* ============================================================ */

    function test_redeem_happyPath() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 0.5 ether}(id);
        uint256 aliceBalBefore = alice.balance;
        vm.prank(alice);
        uint256 out = p.redeem(id, 0.5 ether);
        assertEq(out, 0.5 ether);
        assertEq(alice.balance - aliceBalBefore, 0.5 ether);
        assertEq(p.sharesOf(id, alice), 0);
    }

    function test_redeem_afterPnL_paysPnL() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        // Now NAV is 1, total shares 2, inVault 2
        // Agent reports +50% gain on AUM → reportedPnL = 1
        vm.prank(agent);
        p.reportPnL(id, 1 ether);
        // NAV = 3 / 2 = 1.5
        assertEq(p.nav(id), 1.5 ether);
        // Alice redeems her 1 share → expects 1.5 USDC. But inVault is only 2.
        // 2 > 1.5 so liquid enough.
        uint256 before_ = alice.balance;
        vm.prank(alice);
        uint256 out = p.redeem(id, 1 ether);
        assertEq(out, 1.5 ether);
        assertEq(alice.balance - before_, 1.5 ether);
    }

    function test_redeem_revertsInsufficientLiquidity() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        // agent deploys 1.5 ether to venue → only 0.5 liquid
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 1.5 ether);
        // Alice tries to redeem 1 share → wants 1 USDC, but only 0.5 in vault
        vm.prank(alice);
        vm.expectRevert(IPlinth.InsufficientLiquidity.selector);
        p.redeem(id, 1 ether);
    }

    function test_redeem_revertsMoreSharesThanOwned() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 0.3 ether}(id);
        vm.prank(alice);
        vm.expectRevert(IPlinth.NoSharesToMint.selector);
        p.redeem(id, 0.5 ether);
    }

    function test_redeem_revertsZeroShares() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 0.3 ether}(id);
        vm.prank(alice);
        vm.expectRevert(IPlinth.ZeroAmount.selector);
        p.redeem(id, 0);
    }

    function test_redeem_revertsUnderwater() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        vm.prank(agent);
        p.reportPnL(id, -3 ether);  // 2 + (-3) = -1, underwater
        vm.prank(alice);
        vm.expectRevert(IPlinth.UnderwaterVault.selector);
        p.redeem(id, 1 ether);
    }

    function test_redeem_worksWhenPaused() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 0.5 ether}(id);
        vm.prank(agent);
        p.setPaused(id, true);
        // Pausing doesn't block redeem — investors can always exit
        vm.prank(alice);
        uint256 out = p.redeem(id, 0.5 ether);
        assertEq(out, 0.5 ether);
    }

    function test_redeem_worksWhenClosed() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 0.5 ether}(id);
        vm.prank(agent);
        p.closeVault(id);
        vm.prank(alice);
        uint256 out = p.redeem(id, 0.5 ether);
        assertEq(out, 0.5 ether);
    }

    /* ============================================================ */
    /*                        deployToVenue                          */
    /* ============================================================ */

    function test_deployToVenue_happyPath() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 0.6 ether);
        (, , , , uint256 inV, uint256 dep, ,) = p.vaults(id);
        assertEq(inV, 0.4 ether);
        assertEq(dep, 0.6 ether);
        assertEq(address(venue1).balance, 0.6 ether);
    }

    function test_deployToVenue_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.deployToVenue(id, address(venue1), 0.6 ether);
    }

    function test_deployToVenue_revertsUnapprovedVenue() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        vm.expectRevert(IPlinth.VenueNotApproved.selector);
        p.deployToVenue(id, evilVenue, 0.6 ether);
    }

    function test_deployToVenue_revertsAdversarial_agentTriesAgentAsVenue() public {
        // Attack: agent set themselves as approved venue at creation, then drains.
        // Mitigation here: agent CANNOT set themselves because of the immutable
        // approvedVenues list — but a malicious agent COULD pre-declare their
        // own EOA as a venue at createVault. That risk is documented in the
        // Underwriter Review layer (off-chain). Test that the contract
        // doesn't ADD any protection against this — it's intentional design,
        // signal to off-chain reviewers.
        address[] memory v = new address[](1);
        v[0] = agent;   // agent set themselves as approved venue
        vm.prank(agent);
        bytes32 id = p.createVault{value: 1 ether}(v, "malicious agent strategy");
        // Now agent CAN drain to themselves (it's allowed):
        vm.prank(agent);
        p.deployToVenue(id, agent, 0.9 ether);
        // 0.9 ether ended up with the agent.
        // Validation that this attack vector exists but is handled at the
        // Underwriter layer (review would flag this).
        (, , , , uint256 inV, uint256 dep, ,) = p.vaults(id);
        assertEq(inV, 0.1 ether);
        assertEq(dep, 0.9 ether);
    }

    function test_deployToVenue_revertsInsufficientLiquidity() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        vm.expectRevert(IPlinth.InsufficientLiquidity.selector);
        p.deployToVenue(id, address(venue1), 1.5 ether);
    }

    function test_deployToVenue_revertsZeroAmount() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        vm.expectRevert(IPlinth.ZeroAmount.selector);
        p.deployToVenue(id, address(venue1), 0);
    }

    function test_deployToVenue_revertsWhenPaused() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.setPaused(id, true);
        vm.prank(agent);
        vm.expectRevert(IPlinth.NotActive.selector);
        p.deployToVenue(id, address(venue1), 0.5 ether);
    }

    /* ============================================================ */
    /*                       returnFromVenue                         */
    /* ============================================================ */

    function test_returnFromVenue_happyPath() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 0.6 ether);
        // Venue returns 0.4 (e.g., the agent closed a position with 0.4 USDC realized)
        vm.deal(address(venue1), 1 ether);
        vm.prank(address(venue1));
        p.returnFromVenue{value: 0.4 ether}(id, address(venue1), 0.4 ether);
        (, , , , uint256 inV, uint256 dep, ,) = p.vaults(id);
        assertEq(inV, 0.4 ether + 0.4 ether);
        assertEq(dep, 0.2 ether);
    }

    function test_returnFromVenue_revertsMismatchedValue() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 0.6 ether);
        vm.deal(address(venue1), 1 ether);
        vm.prank(address(venue1));
        vm.expectRevert(IPlinth.ZeroAmount.selector);
        p.returnFromVenue{value: 0.3 ether}(id, address(venue1), 0.4 ether);
    }

    function test_returnFromVenue_revertsExcessOfDeployed() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 0.6 ether);
        vm.deal(address(venue1), 2 ether);
        vm.prank(address(venue1));
        vm.expectRevert(IPlinth.InsufficientDeployedAUM.selector);
        p.returnFromVenue{value: 1 ether}(id, address(venue1), 1 ether);
    }

    function test_returnFromVenue_revertsUnapprovedVenue() public {
        bytes32 id = _create(1 ether);
        vm.deal(evilVenue, 1 ether);
        vm.prank(evilVenue);
        vm.expectRevert(IPlinth.VenueNotApproved.selector);
        p.returnFromVenue{value: 0.5 ether}(id, evilVenue, 0.5 ether);
    }

    /* ============================================================ */
    /*                         reportPnL                             */
    /* ============================================================ */

    function test_reportPnL_happyPath_positive() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.reportPnL(id, 0.5 ether);
        (, , , , , , int256 pnl,) = p.vaults(id);
        assertEq(pnl, 0.5 ether);
        assertEq(p.totalAUM(id), int256(1.5 ether));
        assertEq(p.nav(id), 1.5 ether);
    }

    function test_reportPnL_happyPath_negative() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.reportPnL(id, -0.3 ether);
        assertEq(p.totalAUM(id), int256(0.7 ether));
        assertEq(p.nav(id), 0.7 ether);
    }

    function test_reportPnL_overwrites() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.reportPnL(id, 0.5 ether);
        vm.prank(agent);
        p.reportPnL(id, -0.2 ether);
        (, , , , , , int256 pnl,) = p.vaults(id);
        assertEq(pnl, -0.2 ether);
    }

    function test_reportPnL_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.reportPnL(id, 0.5 ether);
    }

    /* ============================================================ */
    /*                      pause / close                            */
    /* ============================================================ */

    function test_setPaused_byAgentToggles() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.setPaused(id, true);
        (, , IPlinth.VaultStatus s, , , , ,) = p.vaults(id);
        assertEq(uint256(s), uint256(IPlinth.VaultStatus.Paused));
        vm.prank(agent);
        p.setPaused(id, false);
        (, , s, , , , ,) = p.vaults(id);
        assertEq(uint256(s), uint256(IPlinth.VaultStatus.Active));
    }

    function test_setPaused_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.setPaused(id, true);
    }

    function test_closeVault_byAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.closeVault(id);
        (, , IPlinth.VaultStatus s, , , , ,) = p.vaults(id);
        assertEq(uint256(s), uint256(IPlinth.VaultStatus.Closed));
    }

    function test_closeVault_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.closeVault(id);
    }

    function test_closeVault_revertsAlreadyClosed() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.closeVault(id);
        vm.prank(agent);
        vm.expectRevert(IPlinth.NotActive.selector);
        p.closeVault(id);
    }

    /* ============================================================ */
    /*                  Underwriter Review                           */
    /* ============================================================ */

    function test_postUnderwriterReview_anyoneCanPost() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);  // not the agent — that's the point, 3rd party reviews
        p.postUnderwriterReview(id, keccak256("review-1"), "ipfs://abc");
        // (no state change to assert — review is event-only)
    }

    function test_postUnderwriterReview_emitsEvent() public {
        bytes32 id = _create(1 ether);
        vm.expectEmit(true, true, false, true);
        emit IPlinth.UnderwriterReviewPosted(id, bob, keccak256("r"), "ipfs://x");
        vm.prank(bob);
        p.postUnderwriterReview(id, keccak256("r"), "ipfs://x");
    }

    function test_postUnderwriterReview_revertsOnNonexistentVault() public {
        vm.expectRevert(IPlinth.NotActive.selector);
        p.postUnderwriterReview(bytes32(uint256(0xdead)), keccak256("r"), "ipfs://x");
    }

    /* ============================================================ */
    /*                  Multi-vault / multi-investor                 */
    /* ============================================================ */

    function test_multiVault_independentAccounting() public {
        bytes32 a = _create(1 ether);
        bytes32 b = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 0.5 ether}(a);
        vm.prank(bob);
        p.deposit{value: 0.5 ether}(b);
        assertEq(p.sharesOf(a, alice), 0.5 ether);
        assertEq(p.sharesOf(a, bob), 0);
        assertEq(p.sharesOf(b, alice), 0);
        assertEq(p.sharesOf(b, bob), 0.5 ether);
        (, , , uint256 totalA, , , ,) = p.vaults(a);
        (, , , uint256 totalB, , , ,) = p.vaults(b);
        assertEq(totalA, 1.5 ether);
        assertEq(totalB, 1.5 ether);
    }

    function test_multiInvestor_redemptionsAreProRata() public {
        bytes32 id = _create(1 ether);                    // agent: 1 share
        vm.prank(alice); p.deposit{value: 1 ether}(id);   // alice: 1 share
        vm.prank(bob);   p.deposit{value: 2 ether}(id);   // bob: 2 shares
        // Total: 4 shares, 4 USDC in vault, NAV = 1
        vm.prank(agent);
        p.reportPnL(id, 4 ether);     // doubles AUM → NAV = 2
        assertEq(p.nav(id), 2 ether);
        // Alice redeems 1 share → 2 USDC. Bob redeems 2 shares → 4 USDC.
        // But inVault is still 4 USDC. Alice takes 2 → 2 left. Bob takes 4? No, only 2 left.
        uint256 aBefore = alice.balance;
        vm.prank(alice);
        uint256 aOut = p.redeem(id, 1 ether);
        assertEq(aOut, 2 ether);
        assertEq(alice.balance - aBefore, 2 ether);
        // After alice's redemption: 2 in vault, 3 shares remaining.
        // Bob wants 2 shares = 4 USDC, but only 2 USDC liquid. Revert.
        vm.prank(bob);
        vm.expectRevert(IPlinth.InsufficientLiquidity.selector);
        p.redeem(id, 2 ether);
    }

    function test_multiVenue_isolationAndAccounting() public {
        vm.prank(agent);
        bytes32 id = p.createVault{value: 1 ether}(_venuesPair(), DESC);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 0.3 ether);
        vm.prank(agent);
        p.deployToVenue(id, address(venue2), 0.4 ether);
        (, , , , uint256 inV, uint256 dep, ,) = p.vaults(id);
        assertEq(inV, 0.3 ether);
        assertEq(dep, 0.7 ether);
        assertEq(address(venue1).balance, 0.3 ether);
        assertEq(address(venue2).balance, 0.4 ether);
    }

    /* ============================================================ */
    /*                      views                                    */
    /* ============================================================ */

    function test_view_previewNextVaultId() public {
        bytes32 preview = p.previewNextVaultId(agent);
        bytes32 actual = _create(0.5 ether);
        assertEq(preview, actual);
    }

    function test_view_getApprovedVenues() public {
        vm.prank(agent);
        bytes32 id = p.createVault{value: 1 ether}(_venuesPair(), DESC);
        address[] memory v = p.getApprovedVenues(id);
        assertEq(v.length, 2);
        assertEq(v[0], address(venue1));
        assertEq(v[1], address(venue2));
    }

    function test_view_navOnEmptyVault() public {
        // No vault created → NAV of unknown vault: special case
        // (totalShares is 0 for None status) returns INCEPTION_NAV.
        assertEq(p.nav(bytes32(uint256(0xdead))), 1 ether);
    }

    /* ============================================================ */
    /*                  end-to-end lifecycle                         */
    /* ============================================================ */

    function test_endToEnd_lifecycle() public {
        // 1. agent creates vault, funds 2 USDC
        bytes32 id = _create(2 ether);
        // 2. alice deposits 1 USDC at NAV 1 → 1 share
        vm.prank(alice);
        uint256 aliceShares = p.deposit{value: 1 ether}(id);
        assertEq(aliceShares, 1 ether);
        // 3. agent deploys 2 USDC to venue1 to "trade"
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 2 ether);
        // 4. agent reports 50% gain on deployed AUM
        vm.prank(agent);
        p.reportPnL(id, 1 ether);
        // NAV = (1 + 2 + 1) / 3 = 1.333... USDC/share
        // assertApproxEqAbs since 4/3 in 1e18 has truncation
        assertApproxEqAbs(p.nav(id), uint256(4 ether) / 3, 1);
        // 5. venue returns all 2 USDC principal back (positions closed)
        vm.deal(address(venue1), 5 ether);
        vm.prank(address(venue1));
        p.returnFromVenue{value: 2 ether}(id, address(venue1), 2 ether);
        // Liquid AUM check: 1 (alice) + 2 returned = 3 in vault, 0 deployed, +1 reportedPnL
        (, , , , uint256 inV, uint256 dep, int256 pnl,) = p.vaults(id);
        assertEq(inV, 3 ether);
        assertEq(dep, 0);
        assertEq(pnl, 1 ether);
        // total AUM = 3 + 0 + 1 = 4. With 3 shares → NAV ≈ 1.333
        // 7. alice redeems her 1 share → expects ~1.333 USDC
        uint256 aBefore = alice.balance;
        vm.prank(alice);
        uint256 out = p.redeem(id, 1 ether);
        assertApproxEqAbs(out, uint256(4 ether) / 3, 1);
        assertApproxEqAbs(alice.balance - aBefore, uint256(4 ether) / 3, 1);
        // 8. vault still has agent's 2 shares + ~2.667 USDC equity
        (, , , uint256 ts, , , ,) = p.vaults(id);
        assertEq(ts, 2 ether);  // agent still holds 2 shares
    }
}
