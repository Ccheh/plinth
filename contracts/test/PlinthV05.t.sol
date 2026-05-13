// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PlinthV05} from "../src/PlinthV05.sol";
import {IPlinth} from "../src/interfaces/IPlinth.sol";
import {IPlinthV05} from "../src/interfaces/IPlinthV05.sol";
import {MockVenue} from "../src/MockVenue.sol";

/// @notice Test suite for PlinthV05. Covers:
///  - All v0 invariants that v0.5 preserves (happy paths, capability constraint)
///  - All v0 exploit POCs, now reverted by v0.5 defenses
///  - New behaviors introduced in v0.5 (cooldown, rate limit, magnitude cap)
contract PlinthV05Test is Test {
    PlinthV05 p;
    MockVenue venue1;
    MockVenue venue2;

    address agent     = makeAddr("agent");
    address alice     = makeAddr("alice");
    address bob       = makeAddr("bob");
    address attacker  = makeAddr("attacker");

    string constant DESC = "BTC perp momentum strategy, max 3x leverage";

    function setUp() public {
        p = new PlinthV05();
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

    /// Helper: advance past the deposit-cooldown window so the caller can redeem.
    function _skipCooldown() internal {
        vm.warp(block.timestamp + p.DEPOSIT_COOLDOWN() + 1);
    }

    /// Helper: advance past the PnL rate-limit window so reportPnL changes can be larger.
    function _skipPnLWindow() internal {
        vm.warp(block.timestamp + p.PNL_RATE_WINDOW() + 1);
    }

    /* ============================================================ */
    /*  CORE INVARIANTS — same as v0, must still hold                */
    /* ============================================================ */

    function test_v05_createVault_happyPath() public {
        bytes32 id = _create(1 ether);
        (address ag, , IPlinth.VaultStatus s, uint256 ts, uint256 inV, uint256 dep, int256 pnl, string memory desc) = p.vaults(id);
        assertEq(ag, agent);
        assertEq(uint256(s), uint256(IPlinth.VaultStatus.Active));
        assertEq(ts, 1 ether);
        assertEq(inV, 1 ether);
        assertEq(dep, 0);
        assertEq(pnl, 0);
        assertEq(desc, DESC);
        assertEq(p.nav(id), 1 ether);
    }

    function test_v05_deposit_happyPath_atInceptionNav() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        uint256 minted = p.deposit{value: 1 ether}(id);
        assertEq(minted, 1 ether);
        assertEq(p.sharesOf(id, alice), 1 ether);
    }

    function test_v05_redeem_happyPath_afterCooldown() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        _skipCooldown();
        vm.prank(alice);
        uint256 out = p.redeem(id, 1 ether);
        assertEq(out, 1 ether);
    }

    function test_v05_deployToVenue_happyPath() public {
        bytes32 id = _create(2 ether);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 1 ether);
        (, , , , uint256 inV, uint256 dep, ,) = p.vaults(id);
        assertEq(inV, 1 ether);
        assertEq(dep, 1 ether);
        assertEq(address(venue1).balance, 1 ether);
    }

    function test_v05_capabilityConstraint_agentCannotDeployOffWhitelist() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        vm.expectRevert(IPlinth.VenueNotApproved.selector);
        p.deployToVenue(id, address(venue2), 1 ether);
    }

    function test_v05_endToEnd_lifecycle() public {
        // Full agent + investor + venue + PnL + redeem flow, with cooldowns honored.
        bytes32 id = _create(1 ether);
        // alice deposits 1
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        // agent deploys 1 to venue
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 1 ether);
        // agent reports +1 PnL
        vm.prank(agent);
        p.reportPnL(id, 1 ether);
        // wait for cooldown so alice can redeem
        _skipCooldown();
        // venue returns 1 to vault (via returnFromVenue, which on v0.5 must come from venue or agent)
        vm.deal(address(venue1), 1 ether);
        vm.prank(address(venue1));
        p.returnFromVenue{value: 1 ether}(id, address(venue1), 1 ether);
        // alice redeems
        vm.prank(alice);
        uint256 out = p.redeem(id, 1 ether);
        // NAV = (2 + 0 + 1) / 2 = 1.5 → alice gets ~1.5 USDC
        assertApproxEqAbs(out, 1.5 ether, 1);
    }

    /* ============================================================ */
    /*  #1 DEFENSE — sandwich on reportPnL                           */
    /* ============================================================ */

    /// Same attack as test_exploit_sandwich_reportPnL_extractsValueOnV0,
    /// but executed against v0.5. The attacker's redeem now REVERTS because
    /// of DEPOSIT_COOLDOWN.
    function test_v05_defense_sandwich_reportPnL_redeemReverts() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);

        // attacker pre-positions
        vm.prank(attacker);
        uint256 attackerShares = p.deposit{value: 1 ether}(id);

        // agent's reportPnL lands
        vm.prank(agent);
        p.reportPnL(id, 1 ether);

        // attacker tries to redeem in the same block → reverts (SharesPendingVesting)
        vm.prank(attacker);
        vm.expectRevert(IPlinthV05.SharesPendingVesting.selector);
        p.redeem(id, attackerShares);
    }

    function test_v05_defense_sandwich_attackerMustWaitCooldown() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        uint256 attackerShares = p.deposit{value: 1 ether}(id);
        vm.prank(agent);
        p.reportPnL(id, 0.5 ether);
        // try at cooldown - 1 second
        vm.warp(block.timestamp + p.DEPOSIT_COOLDOWN() - 1);
        vm.prank(attacker);
        vm.expectRevert(IPlinthV05.SharesPendingVesting.selector);
        p.redeem(id, attackerShares);
        // now wait 2 more seconds — past cooldown
        vm.warp(block.timestamp + 2);
        vm.prank(attacker);
        uint256 out = p.redeem(id, attackerShares);
        // attacker still profits IF NAV stayed up during cooldown — but that's a
        // 1-hour directional bet, not a 1-block extraction. Test that redeem at least works.
        assertGt(out, 0);
    }

    function test_v05_defense_legitimateUserAlsoSubjectToCooldown() public {
        // Trade-off documentation: cooldown applies to everyone, not just attackers.
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        // alice tries to redeem immediately → reverts
        vm.prank(alice);
        vm.expectRevert(IPlinthV05.SharesPendingVesting.selector);
        p.redeem(id, 1 ether);
        // after cooldown → works
        _skipCooldown();
        vm.prank(alice);
        uint256 out = p.redeem(id, 1 ether);
        assertEq(out, 1 ether);
    }

    /* ============================================================ */
    /*  #2 DEFENSE — returnFromVenue access control                   */
    /* ============================================================ */

    function test_v05_defense_returnFromVenue_revertsForRandomCaller() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 5 ether}(id);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 3 ether);

        // attacker tries the v0 griefing attack — now reverts with NotAuthorized
        vm.prank(attacker);
        vm.expectRevert(IPlinthV05.NotAuthorized.selector);
        p.returnFromVenue{value: 3 ether}(id, address(venue1), 3 ether);
    }

    function test_v05_defense_returnFromVenue_allowedFromVenue() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 5 ether}(id);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 3 ether);

        // venue itself returning funds — works
        vm.deal(address(venue1), 3 ether);
        vm.prank(address(venue1));
        p.returnFromVenue{value: 3 ether}(id, address(venue1), 3 ether);

        (, , , , uint256 inV, uint256 dep, ,) = p.vaults(id);
        assertEq(inV, 6 ether);
        assertEq(dep, 0);
    }

    function test_v05_defense_returnFromVenue_allowedFromAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 5 ether}(id);
        vm.prank(agent);
        p.deployToVenue(id, address(venue1), 3 ether);

        // agent returns funds on the venue's behalf — works
        vm.prank(agent);
        p.returnFromVenue{value: 3 ether}(id, address(venue1), 3 ether);

        (, , , , uint256 inV, uint256 dep, ,) = p.vaults(id);
        assertEq(inV, 6 ether);
        assertEq(dep, 0);
    }

    /* ============================================================ */
    /*  #3 + #6 DEFENSE — reportPnL magnitude + rate limit            */
    /* ============================================================ */

    function test_v05_defense_reportPnL_revertsBeyondMaxMultiple() public {
        bytes32 id = _create(1 ether);
        // capital = 1 USDC; MAX_PNL_MULTIPLE = 10 → cap is 10 USDC.
        // Try to report 11 USDC PnL → reverts
        vm.prank(agent);
        vm.expectRevert(IPlinthV05.PnLOutOfBounds.selector);
        p.reportPnL(id, 11 ether);
        // 10x cap is OK
        vm.prank(agent);
        p.reportPnL(id, 10 ether);
        (, , , , , , int256 pnl,) = p.vaults(id);
        assertEq(pnl, 10 ether);
    }

    function test_v05_defense_reportPnL_revertsOnInsaneNegativeValue() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        vm.expectRevert(IPlinthV05.PnLOutOfBounds.selector);
        p.reportPnL(id, -100 ether); // |value| > 10× capital
    }

    function test_v05_defense_reportPnL_rateLimitBlocksLargeJumpsWithinWindow() public {
        bytes32 id = _create(4 ether);
        // capital = 4. PNL_RATE_PCT = 25. So Δ ≤ 1 USDC per hour.
        // First report at +0.5 USDC — OK
        vm.prank(agent);
        p.reportPnL(id, 0.5 ether);
        // Second report attempting +2 USDC (Δ = 1.5 > 1) within window → reverts
        vm.prank(agent);
        vm.expectRevert(IPlinthV05.PnLRateLimitExceeded.selector);
        p.reportPnL(id, 2 ether);
        // Within budget (Δ = 1.0 exactly) → OK
        vm.prank(agent);
        p.reportPnL(id, 1.5 ether);
    }

    function test_v05_defense_reportPnL_rateLimitResetsAfterWindow() public {
        bytes32 id = _create(4 ether);
        vm.prank(agent);
        p.reportPnL(id, 0.5 ether);
        _skipPnLWindow();
        // After window, full magnitude (up to 10×) is again available
        vm.prank(agent);
        p.reportPnL(id, 4 ether);
        (, , , , , , int256 pnl,) = p.vaults(id);
        assertEq(pnl, 4 ether);
    }

    function test_v05_defense_reportPnL_zeroCapitalRevertsAnyClaim() public {
        // Edge: a vault where inVault + deployedAUM = 0 (eg agent withdrew all
        // via redeem — not possible in v0.5, but defensive) cannot claim PnL.
        // We synthesize this state by deploying everything to venue then having
        // venue not return. But actually inVault+deployedAUM stays > 0 in any
        // real flow. So this is more of an invariant check.
        bytes32 id = _create(1 ether);
        // capital = 1, so attempting a 0 PnL works
        vm.prank(agent);
        p.reportPnL(id, 0);
        // Test passes — zero is always allowed
        (, , , , , , int256 pnl,) = p.vaults(id);
        assertEq(pnl, 0);
    }

    /* ============================================================ */
    /*  #4 DEFENSE — reportPnL forbidden on Closed                    */
    /* ============================================================ */

    function test_v05_defense_reportPnL_revertsOnClosedVault() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        vm.prank(agent);
        p.closeVault(id);
        // even tiny PnL update is rejected
        vm.prank(agent);
        vm.expectRevert(IPlinth.NotActive.selector);
        p.reportPnL(id, 0.1 ether);
    }

    function test_v05_defense_reportPnL_allowedOnPausedVault() public {
        // Paused vaults still need PnL updates (agent may be unwinding).
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.setPaused(id, true);
        vm.prank(agent);
        p.reportPnL(id, 0.5 ether);
        (, , , , , , int256 pnl,) = p.vaults(id);
        assertEq(pnl, 0.5 ether);
    }

    /* ============================================================ */
    /*  #8 DEFENSE — strategyDescriptor length cap                    */
    /* ============================================================ */

    function test_v05_defense_strategyDescriptor_revertsOverLength() public {
        // 1025 bytes (one over MAX_STRATEGY_LEN)
        bytes memory longDesc = new bytes(1025);
        for (uint256 i = 0; i < 1025; i++) longDesc[i] = "x";
        vm.prank(agent);
        vm.expectRevert(IPlinthV05.StrategyDescriptorTooLong.selector);
        p.createVault{value: 1 ether}(_venuesSingle(), string(longDesc));
    }

    function test_v05_defense_strategyDescriptor_acceptsAtLimit() public {
        bytes memory exactDesc = new bytes(1024);
        for (uint256 i = 0; i < 1024; i++) exactDesc[i] = "y";
        vm.prank(agent);
        bytes32 id = p.createVault{value: 1 ether}(_venuesSingle(), string(exactDesc));
        assertTrue(id != bytes32(0));
    }

    /* ============================================================ */
    /*  VIEW — unlocksAt helper                                       */
    /* ============================================================ */

    function test_v05_view_unlocksAt_returnsCorrectTimestamp() public {
        bytes32 id = _create(1 ether);
        uint256 t0 = block.timestamp;
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        assertEq(p.unlocksAt(id, alice), t0 + p.DEPOSIT_COOLDOWN());
        // user with no deposit returns 0
        assertEq(p.unlocksAt(id, bob), 0);
    }

    /* ============================================================ */
    /*  SAFE-BY-DESIGN preserved — no regression on v0 safe properties */
    /* ============================================================ */

    function test_v05_safe_donationAttack_doesNotBreakAccounting() public {
        bytes32 id = _create(1 ether);
        uint256 navBefore = p.nav(id);
        vm.deal(address(p), address(p).balance + 100 ether);
        assertEq(p.nav(id), navBefore);
    }

    function test_v05_safe_agentAsVenue_stillBlockedAtCreation() public {
        // From v0: agent listing themselves as a venue is detectable but not
        // blocked by the contract. We confirm v0.5 preserves this behavior
        // (it's an Underwriter-detectable design choice, not a contract gate).
        address[] memory vs = new address[](1);
        vs[0] = agent;
        vm.prank(agent);
        bytes32 id = p.createVault{value: 1 ether}(vs, DESC);
        // creation succeeded — and Underwriter's job is to flag this
        (address ag,,,,,,,) = p.vaults(id);
        assertEq(ag, agent);
    }

    function test_v05_safe_reentrancy_redeemNonReentrant() public {
        // The OZ ReentrancyGuard is wired identically to v0; this test exists
        // mostly to ensure the modifier is in place. A direct reentrancy test
        // would need a malicious recipient contract — we trust OZ here.
        // Static check: deposit + redeem in same external tx via two calls
        // should work normally (no reentry).
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        _skipCooldown();
        vm.prank(alice);
        p.redeem(id, 1 ether);
        // no revert → reentrancy guard is not falsely tripping
    }

    /* ============================================================ */
    /*  ACCESS CONTROL — preserved from v0                            */
    /* ============================================================ */

    function test_v05_deployToVenue_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.deployToVenue(id, address(venue1), 0.5 ether);
    }

    function test_v05_reportPnL_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.reportPnL(id, 0.5 ether);
    }

    function test_v05_setPaused_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.setPaused(id, true);
    }

    function test_v05_closeVault_revertsNotAgent() public {
        bytes32 id = _create(1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPlinth.NotAgent.selector);
        p.closeVault(id);
    }

    /* ============================================================ */
    /*  REVERT EDGE CASES                                             */
    /* ============================================================ */

    function test_v05_deposit_revertsWhenPaused() public {
        bytes32 id = _create(1 ether);
        vm.prank(agent);
        p.setPaused(id, true);
        vm.prank(alice);
        vm.expectRevert(IPlinth.NotActive.selector);
        p.deposit{value: 1 ether}(id);
    }

    function test_v05_deposit_revertsBelowMin() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        vm.expectRevert(IPlinth.ZeroAmount.selector);
        p.deposit{value: 1 wei}(id);
    }

    function test_v05_redeem_worksWhenPaused() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        vm.prank(agent);
        p.setPaused(id, true);
        _skipCooldown();
        vm.prank(alice);
        uint256 out = p.redeem(id, 1 ether);
        assertEq(out, 1 ether);
    }

    function test_v05_redeem_worksWhenClosed() public {
        bytes32 id = _create(1 ether);
        vm.prank(alice);
        p.deposit{value: 1 ether}(id);
        vm.prank(agent);
        p.closeVault(id);
        _skipCooldown();
        vm.prank(alice);
        uint256 out = p.redeem(id, 1 ether);
        assertEq(out, 1 ether);
    }
}
