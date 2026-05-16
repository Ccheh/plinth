// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PlinthSponsorPool} from "../src/PlinthSponsorPool.sol";

contract PlinthSponsorPoolTest is Test {
    PlinthSponsorPool pool;

    address sponsor1 = makeAddr("sponsor1");
    address sponsor2 = makeAddr("sponsor2");
    address uw1 = makeAddr("underwriter1");
    address uw2 = makeAddr("underwriter2");
    bytes32 vaultId = keccak256("vault-1");

    function setUp() public {
        pool = new PlinthSponsorPool();
        vm.deal(sponsor1, 10 ether);
        vm.deal(sponsor2, 10 ether);
        vm.deal(uw1, 0);
        vm.deal(uw2, 0);
    }

    function test_sponsorIncreasesPool() public {
        vm.prank(sponsor1);
        pool.sponsor{value: 0.01 ether}(vaultId);

        assertEq(pool.pool(vaultId), 0.01 ether);
        assertEq(pool.lifetimeSponsored(vaultId), 0.01 ether);
        assertEq(pool.remainingReviewSlots(vaultId), 10);  // 0.01 / 0.001 = 10 slots
    }

    function test_multipleSponsorsAdditive() public {
        vm.prank(sponsor1);
        pool.sponsor{value: 0.003 ether}(vaultId);
        vm.prank(sponsor2);
        pool.sponsor{value: 0.005 ether}(vaultId);

        assertEq(pool.pool(vaultId), 0.008 ether);
        assertEq(pool.lifetimeSponsored(vaultId), 0.008 ether);
    }

    function test_claimPaysFixedRewardToUnderwriter() public {
        vm.prank(sponsor1);
        pool.sponsor{value: 0.005 ether}(vaultId);

        uint256 uw1BalBefore = uw1.balance;
        vm.prank(uw1);
        uint256 reward = pool.claimAsUnderwriter(vaultId, keccak256("review1"), "ipfs://review1");

        assertEq(reward, 0.001 ether);
        assertEq(uw1.balance, uw1BalBefore + 0.001 ether);
        assertEq(pool.pool(vaultId), 0.004 ether);
        assertEq(pool.lifetimeClaimed(vaultId), 0.001 ether);
        assertTrue(pool.hasClaimed(vaultId, uw1));
        assertEq(pool.claimerCount(vaultId), 1);
    }

    function test_dedup_singleAddressCanOnlyClaimOncePerVault() public {
        vm.prank(sponsor1);
        pool.sponsor{value: 0.005 ether}(vaultId);

        vm.prank(uw1);
        pool.claimAsUnderwriter(vaultId, keccak256("r1"), "ipfs://r1");

        // Same address tries to claim again — must revert
        vm.prank(uw1);
        vm.expectRevert(PlinthSponsorPool.AlreadyClaimedForThisVault.selector);
        pool.claimAsUnderwriter(vaultId, keccak256("r2"), "ipfs://r2");
    }

    function test_multipleUnderwritersCanClaimSamePool() public {
        vm.prank(sponsor1);
        pool.sponsor{value: 0.005 ether}(vaultId);

        vm.prank(uw1);
        pool.claimAsUnderwriter(vaultId, keccak256("r1"), "ipfs://r1");
        vm.prank(uw2);
        pool.claimAsUnderwriter(vaultId, keccak256("r2"), "ipfs://r2");

        assertEq(pool.claimerCount(vaultId), 2);
        assertEq(pool.pool(vaultId), 0.003 ether);
        assertEq(uw1.balance, 0.001 ether);
        assertEq(uw2.balance, 0.001 ether);
    }

    function test_claimRevertsWhenPoolEmpty() public {
        // Pool starts at 0
        vm.prank(uw1);
        vm.expectRevert(PlinthSponsorPool.PoolEmpty.selector);
        pool.claimAsUnderwriter(vaultId, keccak256("r1"), "ipfs://r1");
    }

    function test_claimRevertsWhenPoolBelowReward() public {
        vm.prank(sponsor1);
        pool.sponsor{value: 0.0005 ether}(vaultId);  // half a reward

        vm.prank(uw1);
        vm.expectRevert(PlinthSponsorPool.PoolEmpty.selector);
        pool.claimAsUnderwriter(vaultId, keccak256("r1"), "ipfs://r1");
    }

    function test_sponsorWithZeroReverts() public {
        vm.prank(sponsor1);
        vm.expectRevert(PlinthSponsorPool.ZeroAmount.selector);
        pool.sponsor{value: 0}(vaultId);
    }

    function test_poolRefillAfterDrain_newUnderwritersCanClaim() public {
        // Pool funded for 2 claims
        vm.prank(sponsor1);
        pool.sponsor{value: 0.002 ether}(vaultId);
        vm.prank(uw1);
        pool.claimAsUnderwriter(vaultId, keccak256("r1"), "ipfs://r1");
        vm.prank(uw2);
        pool.claimAsUnderwriter(vaultId, keccak256("r2"), "ipfs://r2");

        assertEq(pool.pool(vaultId), 0);

        // Pool drained. Sponsor refills.
        vm.prank(sponsor2);
        pool.sponsor{value: 0.002 ether}(vaultId);

        // A NEW underwriter can still claim
        address uw3 = makeAddr("uw3");
        vm.deal(uw3, 0);
        vm.prank(uw3);
        uint256 reward = pool.claimAsUnderwriter(vaultId, keccak256("r3"), "ipfs://r3");
        assertEq(reward, 0.001 ether);

        // But uw1 (who already claimed for this vaultId) STILL can't claim again
        // even after refill — dedup is permanent per vault
        vm.prank(uw1);
        vm.expectRevert(PlinthSponsorPool.AlreadyClaimedForThisVault.selector);
        pool.claimAsUnderwriter(vaultId, keccak256("r1-again"), "ipfs://r1-again");
    }

    function test_remainingSlotsView() public {
        vm.prank(sponsor1);
        pool.sponsor{value: 0.0075 ether}(vaultId);  // 7 full slots + 0.0005 remainder
        assertEq(pool.remainingReviewSlots(vaultId), 7);
    }
}
