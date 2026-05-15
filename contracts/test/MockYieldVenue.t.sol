// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockYieldVenue} from "../src/MockYieldVenue.sol";
import {PlinthV05} from "../src/PlinthV05.sol";

/// @notice Tests for MockYieldVenue + its integration with PlinthV05 as an
/// approved-venue. Covers yield accrual math, principal-return path, and an
/// end-to-end demo of "Plinth vault sweeps idle USDC into yield strategy."
contract MockYieldVenueTest is Test {
    MockYieldVenue venue;
    PlinthV05 plinth;

    address agent     = makeAddr("agent");
    address operator  = makeAddr("operator");
    address investor  = makeAddr("investor");

    function setUp() public {
        plinth = new PlinthV05();
        // Operator deploys the yield venue
        vm.prank(operator);
        venue = new MockYieldVenue();
        // Operator pre-funds reserve so yield payouts are backed
        vm.deal(operator, 10 ether);
        vm.prank(operator);
        venue.fundReserve{value: 1 ether}();

        // Fund agent + investor for vault ops
        vm.deal(agent,    10 ether);
        vm.deal(investor, 10 ether);
        vm.warp(1_000_000);
    }

    /* ============================================================ */
    /*               yield-math invariants                           */
    /* ============================================================ */

    function test_yield_zero_when_no_principal() public {
        assertEq(venue.accruedYield(), 0);
        assertEq(venue.currentBalance(), 0);
    }

    function test_yield_accrues_simple_interest_5pct_apr() public {
        // Send 1 USDC from a non-Plinth address → tracked as principal anyway
        vm.deal(agent, 10 ether);
        vm.prank(agent);
        (bool ok,) = address(venue).call{value: 1 ether}("");
        assertTrue(ok);

        // Advance 1 year exactly
        vm.warp(block.timestamp + 365 days);
        // Yield = 1 USDC * 5% * 1 year = 0.05 USDC
        uint256 expected = 0.05 ether;
        assertApproxEqAbs(venue.accruedYield(), expected, 100);
        assertApproxEqAbs(venue.currentBalance(), 1.05 ether, 100);
    }

    function test_yield_accrues_proportionally_for_partial_year() public {
        vm.deal(agent, 10 ether);
        vm.prank(agent);
        (bool ok,) = address(venue).call{value: 1 ether}("");
        assertTrue(ok);

        // Advance 1 day = 1/365 of a year
        vm.warp(block.timestamp + 1 days);
        // Daily yield ≈ 0.05 / 365 ≈ 0.000136986... USDC
        uint256 oneEth = 1 ether;
        uint256 expected = (oneEth * 500 * 1 days) / (10_000 * 365 days);
        assertEq(venue.accruedYield(), expected);
    }

    function test_settle_yield_rolls_into_principal() public {
        vm.deal(agent, 10 ether);
        vm.prank(agent);
        (bool ok,) = address(venue).call{value: 1 ether}("");
        assertTrue(ok);

        vm.warp(block.timestamp + 1 days);
        uint256 pendingYield = venue.accruedYield();

        // Another deposit triggers _settleYield
        vm.prank(agent);
        (ok,) = address(venue).call{value: 0.5 ether}("");
        assertTrue(ok);

        // principal should now be 1 + pending yield + 0.5
        uint256 expected = 1 ether + pendingYield + 0.5 ether;
        assertEq(venue.principal(), expected);
        // Fresh yield should be 0 (just settled)
        assertEq(venue.accruedYield(), 0);
    }

    /* ============================================================ */
    /*               principal return path                           */
    /* ============================================================ */

    function test_returnPrincipal_back_to_plinth_via_returnFromVenue() public {
        // 1. Create vault with venue as approved venue
        address[] memory venues = new address[](1);
        venues[0] = address(venue);
        vm.prank(agent);
        bytes32 vaultId = plinth.createVault{value: 1 ether}(venues, "BTC perp + cash sweep");

        // 2. Investor deposits 5 USDC; agent deploys 4 to yield venue
        vm.prank(investor);
        plinth.deposit{value: 5 ether}(vaultId);
        vm.prank(agent);
        plinth.deployToVenue(vaultId, address(venue), 4 ether);
        assertEq(venue.principal(), 4 ether);

        // 3. Advance time so yield accrues
        vm.warp(block.timestamp + 30 days);
        uint256 yieldEarned = venue.accruedYield();
        assertGt(yieldEarned, 0);

        // 4. Return principal via venue helper
        bytes4 sel = bytes4(keccak256("returnFromVenue(bytes32,address,uint256)"));
        venue.returnPrincipal(payable(address(plinth)), vaultId, 4 ether, sel);

        // 5. Vault accounting should match
        (, , , , uint256 inV, uint256 dep, ,) = plinth.vaults(vaultId);
        assertEq(inV, 6 ether - 0);  // 1 agent + 5 investor + 0 inflow = 6 total
        assertEq(dep, 0);
        // Venue: principal includes the settled yield, less the 4 returned
        assertGt(venue.principal(), yieldEarned - 100);
    }

    function test_returnPrincipal_reverts_if_amount_exceeds_principal() public {
        vm.deal(agent, 10 ether);
        vm.prank(agent);
        (bool ok,) = address(venue).call{value: 1 ether}("");
        assertTrue(ok);

        bytes4 sel = bytes4(keccak256("returnFromVenue(bytes32,address,uint256)"));
        vm.expectRevert(bytes("exceeds tracked principal"));
        venue.returnPrincipal(payable(address(plinth)), bytes32(0), 2 ether, sel);
    }

    /* ============================================================ */
    /*               harvest yield path                              */
    /* ============================================================ */

    function test_harvestYield_pays_out_of_reserve() public {
        vm.deal(agent, 10 ether);
        vm.prank(agent);
        (bool ok,) = address(venue).call{value: 1 ether}("");
        assertTrue(ok);

        vm.warp(block.timestamp + 30 days);
        uint256 expectedYield = venue.accruedYield();

        uint256 balBefore = agent.balance;
        venue.harvestYield(payable(agent), expectedYield);
        uint256 received = agent.balance - balBefore;
        assertEq(received, expectedYield);
    }

    /* ============================================================ */
    /*               end-to-end demo                                 */
    /* ============================================================ */

    function test_e2e_vault_with_yield_strategy() public {
        // Agent creates vault with yield venue as approved
        address[] memory venues = new address[](1);
        venues[0] = address(venue);
        vm.prank(agent);
        bytes32 vaultId = plinth.createVault{value: 1 ether}(venues, "BTC perp + 5% APR cash sweep");

        // Investor deposits 4 USDC
        vm.prank(investor);
        plinth.deposit{value: 4 ether}(vaultId);

        // Initial state: 5 USDC in vault, NAV = 1.0
        assertEq(plinth.nav(vaultId), 1 ether);

        // Agent sweeps 4 USDC into yield venue
        vm.prank(agent);
        plinth.deployToVenue(vaultId, address(venue), 4 ether);

        // 30 days pass; yield accrues on the deployed 4 USDC
        vm.warp(block.timestamp + 30 days);
        uint256 expectedYield = venue.accruedYield();

        // Agent reports the yield as PnL — Underwriter could verify by reading
        // venue.currentBalance() on chain
        vm.prank(agent);
        plinth.reportPnL(vaultId, int256(expectedYield));

        // NAV should reflect the yield (5 USDC total + tiny yield, divided by 5 shares)
        uint256 navAfter = plinth.nav(vaultId);
        assertGt(navAfter, 1 ether);

        // Agent unwinds principal back to the vault so there's liquidity
        bytes4 sel = bytes4(keccak256("returnFromVenue(bytes32,address,uint256)"));
        venue.returnPrincipal(payable(address(plinth)), vaultId, 4 ether, sel);

        // 5-week-old shares can be redeemed (past 1h cooldown)
        vm.warp(block.timestamp + 1 hours + 1);
        // Investor pulls out principal + share of yield
        vm.prank(investor);
        uint256 out = plinth.redeem(vaultId, 4 ether);
        // 4 shares × NAV-something = ~4 USDC plus small yield share
        assertGt(out, 4 ether);
    }
}
