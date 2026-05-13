// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  IPlinth — capital layer for AI trading agents on Arc
/// @notice A Plinth Vault is a tokenized pool of USDC managed by a single AI
///         agent. Anyone can deposit USDC into a vault and receive shares
///         (internal accounting; tradable externally if wrapped). The agent
///         deploys vault capital to approved external venues (DEXes, perps,
///         prediction markets), reports daily PnL, and shareholders redeem
///         at the current NAV (net asset value) at any time.
///
///         "Hedge fund infrastructure for AI agents" — agents raise external
///         capital; investors get diversified exposure to AI strategies;
///         both sides settle in USDC on Arc.
///
/// @dev    Single-contract design: all vaults live in `vaults` mapping; share
///         accounting is internal (`shares[vaultId][user]`). No per-vault
///         ERC-20 deployment cost.
///
///         Approved-venues whitelist is immutable per vault to prevent the
///         agent from draining funds to arbitrary addresses — this is the
///         Mandate-style capability constraint applied to fund operations.
interface IPlinth {
    /* ------------------------------ types ------------------------------ */

    enum VaultStatus { None, Active, Paused, Closed }

    struct Vault {
        address agent;             // strategy owner; only agent can deployToVenue / reportPnL
        uint64  createdAt;
        VaultStatus status;
        // capital accounting (all in USDC wei, 18 decimals on Arc):
        uint256 totalShares;       // outstanding share count
        uint256 inVault;           // USDC currently held in Plinth contract
        uint256 deployedAUM;       // USDC currently at approved venues
        int256  reportedPnL;       // signed; agent's mark-to-market PnL update
        // metadata:
        string  strategyDescriptor;  // free text — Underwriter analyzes this
    }

    /* ------------------------------ events ----------------------------- */

    event VaultCreated(
        bytes32 indexed vaultId,
        address indexed agent,
        address[] approvedVenues,
        string strategyDescriptor,
        uint256 initialDeposit
    );
    event Deposit(bytes32 indexed vaultId, address indexed investor, uint256 usdcIn, uint256 sharesMinted, uint256 navAtDeposit);
    event Redeem(bytes32 indexed vaultId, address indexed investor, uint256 sharesBurned, uint256 usdcOut, uint256 navAtRedeem);
    event DeployToVenue(bytes32 indexed vaultId, address indexed venue, uint256 amount, uint256 newInVault, uint256 newDeployedAUM);
    event ReturnFromVenue(bytes32 indexed vaultId, address indexed venue, uint256 amount, uint256 newInVault, uint256 newDeployedAUM);
    event PnLReported(bytes32 indexed vaultId, int256 oldPnL, int256 newPnL, int256 totalAUMNow);
    event VaultPaused(bytes32 indexed vaultId, bool paused);
    event VaultClosed(bytes32 indexed vaultId);
    event UnderwriterReviewPosted(bytes32 indexed vaultId, address indexed underwriter, bytes32 reviewHash, string reviewUri);

    /* ------------------------------ errors ----------------------------- */

    error NotAgent();
    error NotActive();
    error VaultExists();
    error ZeroAddress();
    error ZeroAmount();
    error VenueNotApproved();
    error InsufficientLiquidity();
    error InsufficientDeployedAUM();
    error TooManyVenues();
    error EmptyVenues();
    error NoSharesToMint();
    error UnderwaterVault();
    error TransferFailed();

    /* ------------------------------ writes ----------------------------- */

    /// @notice Agent creates a new vault. `msg.value` is the initial USDC the
    ///         agent commits — this funds the vault and earns the agent's
    ///         own first shares at 1 share = 1 USDC NAV inception.
    /// @param approvedVenues   Immutable whitelist of contract addresses the
    ///                         agent may deploy capital to. Up to 16.
    /// @param strategyDescriptor Free text used by Underwriter agents for
    ///                           risk rating. Stored on chain.
    function createVault(
        address[] calldata approvedVenues,
        string calldata strategyDescriptor
    ) external payable returns (bytes32 vaultId);

    /// @notice Investor deposits USDC into a vault at current NAV.
    ///         `msg.value` is the deposit amount. Returns shares minted.
    function deposit(bytes32 vaultId) external payable returns (uint256 sharesMinted);

    /// @notice Investor burns shares to redeem USDC at current NAV.
    ///         Reverts if vault doesn't have enough liquid USDC (`inVault`).
    function redeem(bytes32 vaultId, uint256 shareAmount) external returns (uint256 usdcOut);

    /// @notice Agent deploys vault capital to an approved venue. Decreases
    ///         `inVault`, increases `deployedAUM`. Transfers `amount` USDC to
    ///         the venue address via raw call.
    function deployToVenue(bytes32 vaultId, address venue, uint256 amount) external;

    /// @notice Agent records USDC returning from a venue. The venue must
    ///         have actually transferred `amount` USDC to Plinth in the same
    ///         tx (or a prior tx) — this fn updates accounting.
    function returnFromVenue(bytes32 vaultId, address venue, uint256 amount) external payable;

    /// @notice Agent reports current mark-to-market PnL of deployed positions.
    ///         Signed; can be negative. This is the entire signal that moves
    ///         NAV up/down between trade deployments.
    function reportPnL(bytes32 vaultId, int256 newPnL) external;

    /// @notice Agent toggles vault pause state. Paused vaults reject new
    ///         deposits but still allow redemptions.
    function setPaused(bytes32 vaultId, bool paused) external;

    /// @notice Agent closes the vault. No more deposits ever. Existing
    ///         shareholders can still redeem against remaining liquidity.
    function closeVault(bytes32 vaultId) external;

    /// @notice Anyone can post an Underwriter review. The hash is committed
    ///         on chain; the full review body lives at `reviewUri`
    ///         (IPFS / HTTPS).  Multiple reviewers can post; consumers pick
    ///         which signature to trust.
    function postUnderwriterReview(bytes32 vaultId, bytes32 reviewHash, string calldata reviewUri) external;

    /* ------------------------------ views ------------------------------ */

    /// @notice Total assets under management (signed; can be negative if
    ///         agent has reported large losses against a small deployment).
    function totalAUM(bytes32 vaultId) external view returns (int256);

    /// @notice Net Asset Value per share, scaled to 1e18. 1e18 == 1 USDC/share.
    ///         If totalShares is 0, returns 1e18 (inception). If totalAUM
    ///         <= 0, returns 0 (underwater).
    function nav(bytes32 vaultId) external view returns (uint256);

    /// @notice (totalShares, inVault, deployedAUM, reportedPnL) snapshot.
    function summary(bytes32 vaultId) external view returns (
        uint256 totalShares,
        uint256 inVault,
        uint256 deployedAUM,
        int256  reportedPnL
    );

    /// @notice Pre-compute vaultId for the next createVault call by `agent`.
    function previewNextVaultId(address agent) external view returns (bytes32);

    /// @notice Read approved venues array.
    function getApprovedVenues(bytes32 vaultId) external view returns (address[] memory);

    /// @notice Read user's current share balance.
    function sharesOf(bytes32 vaultId, address user) external view returns (uint256);
}
