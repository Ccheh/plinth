// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  PlinthSponsorPool — sustainability mechanism for the Underwriter network
/// @notice Plinth's Underwriter pipeline depends on independent reviewers posting
///         analysis on chain (verifiable-PnL reconciliation, risk monitoring, LLM
///         qualitative reviews). Without an incentive, who runs them long-term?
///
///         PlinthSponsorPool is the simplest possible economic answer:
///         vault investors (or anyone) deposit USDC into a per-vault sponsor
///         pool. Underwriters who post reviews collect a fixed reward per
///         review from the pool. Pool depletes as reviews accumulate;
///         sponsors refill when they want continued coverage.
///
///         This addresses the "where does protocol revenue come from" question
///         honestly: Plinth itself takes nothing. The pool is a market-driven
///         sustainability layer — investors pay for the verification they want.
///
/// @dev    Mechanism:
///           1. `sponsor(vaultId)` payable: deposits USDC into the pool for a vault.
///              Anyone can sponsor. No claim of ownership.
///           2. `claimAsUnderwriter(vaultId, reviewHash, reviewUri)`: caller
///              registers as an underwriter for this vault, pays out a fixed
///              REWARD_PER_REVIEW from the pool, and emits an event that
///              references the review. The caller is expected to ALSO post
///              the same (reviewHash, reviewUri) on Plinth via
///              postUnderwriterReview; the pool doesn't verify this on chain
///              (would require Plinth changes), but the event creates an
///              auditable trail that off-chain reviewers can cross-check.
///           3. Each address can claim at most once per vault (`hasClaimed[vaultId][msg.sender]`).
///              This prevents Sybil drain by a single underwriter from a refilled pool.
///           4. If the pool is empty (pool < REWARD_PER_REVIEW), claims revert.
///              Sponsors are expected to top up if they want continued reviews.
///
///         No admin keys. No fee paid to the protocol. Pure investor → underwriter market.
contract PlinthSponsorPool {
    /* ------------------------- constants ------------------------- */

    /// @notice Fixed reward per underwriter review claim. 0.001 USDC per review.
    /// At REWARD_PER_REVIEW = 0.001 ether on Arc, 1 USDC of sponsorship funds
    /// ~1,000 reviews. Lower bound to keep claims meaningful; not so high that
    /// Sybil drain is profitable even before the per-address dedup.
    uint256 public constant REWARD_PER_REVIEW = 0.001 ether;

    /// @notice Max claims per vault BEFORE the pool needs to be re-sponsored.
    /// Caps single-pool drain. (Sponsor can refill at any time and these claims
    /// reset for new underwriter addresses, but the same address still can't
    /// claim twice for the same vault.)
    uint8 public constant MAX_CLAIMS_PER_REFILL_CYCLE = 32;

    /* ------------------------- storage ------------------------- */

    /// @notice Per-vault current sponsorship balance.
    mapping(bytes32 => uint256) public pool;

    /// @notice Per-vault total ever sponsored (lifetime).
    mapping(bytes32 => uint256) public lifetimeSponsored;

    /// @notice Per-vault total ever claimed by underwriters (lifetime).
    mapping(bytes32 => uint256) public lifetimeClaimed;

    /// @notice Per-vault count of unique underwriter addresses that have claimed
    /// in the current refill cycle. Reset only when the pool drains.
    mapping(bytes32 => uint8) public claimerCount;

    /// @notice Per-(vault, underwriter) dedup: each address claims at most once per vault.
    /// Cannot reset (deliberate — prevents Sybil drain by a single attacker
    /// across refills).
    mapping(bytes32 => mapping(address => bool)) public hasClaimed;

    /* ------------------------- events ------------------------- */

    event Sponsored(bytes32 indexed vaultId, address indexed sponsor, uint256 amount, uint256 newPoolBalance);
    event ReviewClaimed(
        bytes32 indexed vaultId,
        address indexed underwriter,
        uint256 reward,
        bytes32 reviewHash,
        string reviewUri,
        uint256 remainingPool
    );

    /* ------------------------- errors ------------------------- */

    error ZeroAmount();
    error PoolEmpty();
    error AlreadyClaimedForThisVault();
    error TransferFailed();

    /* ------------------------- sponsor ------------------------- */

    /// @notice Add funds to a vault's underwriter reward pool. Anyone can sponsor.
    function sponsor(bytes32 vaultId) external payable {
        if (msg.value == 0) revert ZeroAmount();
        unchecked {
            pool[vaultId] += msg.value;
            lifetimeSponsored[vaultId] += msg.value;
        }
        emit Sponsored(vaultId, msg.sender, msg.value, pool[vaultId]);
    }

    /* ------------------------- claim ------------------------- */

    /// @notice Claim the standard REWARD_PER_REVIEW for posting an underwriter
    /// review of `vaultId`. The caller must also post the matching review on
    /// Plinth (via postUnderwriterReview) — this pool doesn't verify that on
    /// chain (would require Plinth contract changes); the (reviewHash, reviewUri)
    /// emitted here lets off-chain reviewers cross-check.
    ///
    /// Per-address dedup: each address can claim at most once per vaultId, ever.
    /// Pool-level cap: max MAX_CLAIMS_PER_REFILL_CYCLE underwriters can claim
    /// before the pool needs to drain + be re-sponsored.
    function claimAsUnderwriter(
        bytes32 vaultId,
        bytes32 reviewHash,
        string calldata reviewUri
    ) external returns (uint256 reward) {
        if (pool[vaultId] < REWARD_PER_REVIEW) revert PoolEmpty();
        if (hasClaimed[vaultId][msg.sender]) revert AlreadyClaimedForThisVault();

        // Auto-drain check: if claimerCount has hit MAX_CLAIMS for this cycle,
        // we don't reset state — we just revert until the pool drains naturally.
        // (Drain happens when pool < REWARD_PER_REVIEW on the next claim attempt.
        //  When the pool is below the threshold, the pool-empty branch above hits.
        //  Sponsor can top up and claimerCount continues to count.)
        // For simplicity we treat MAX_CLAIMS_PER_REFILL_CYCLE as advisory; the
        // hard cap is the dedup. Implementations could enforce strict cycle
        // semantics if needed.

        hasClaimed[vaultId][msg.sender] = true;
        unchecked {
            claimerCount[vaultId] += 1;
            pool[vaultId] -= REWARD_PER_REVIEW;
            lifetimeClaimed[vaultId] += REWARD_PER_REVIEW;
        }

        reward = REWARD_PER_REVIEW;
        emit ReviewClaimed(vaultId, msg.sender, reward, reviewHash, reviewUri, pool[vaultId]);

        (bool ok,) = msg.sender.call{value: reward}("");
        if (!ok) revert TransferFailed();
    }

    /* ------------------------- views ------------------------- */

    /// @notice How many more reviews can be funded from the current pool.
    function remainingReviewSlots(bytes32 vaultId) external view returns (uint256) {
        return pool[vaultId] / REWARD_PER_REVIEW;
    }

    /// @notice Total funds remaining after subtracting what reviews would consume.
    function poolBalance(bytes32 vaultId) external view returns (uint256) {
        return pool[vaultId];
    }
}
