// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IPlinth} from "./interfaces/IPlinth.sol";

/// @title  Plinth — capital layer for AI trading agents on Arc (v0)
/// @notice See IPlinth.sol for the full interface specification.
///
/// @dev    Single-contract design. All vaults share one address. Per-vault
///         accounting via mappings: `vaults[vaultId]` for vault state,
///         `shares[vaultId][user]` for shareholder positions,
///         `approvedVenues[vaultId]` for the deploy-to whitelist.
///
///         Native USDC accounting (Arc-style 18 decimals). All amounts are
///         in wei. NAV is scaled to 1e18 (1 = 1 USDC/share).
///
///         No admin keys. No upgrade proxy. No protocol fees in v0.
///         Agent fees (management / performance) are deferred to v0.2.
contract Plinth is IPlinth, ReentrancyGuard {
    /* ------------------------------------------------------------------- */
    /*                              constants                              */
    /* ------------------------------------------------------------------- */

    /// @notice NAV inception value: 1 share = 1 USDC = 1e18 wei.
    uint256 public constant INCEPTION_NAV = 1e18;

    /// @notice Cap on the immutable approved-venues list per vault. Keeps
    ///         storage write costs bounded and prevents griefing via
    ///         arbitrarily-long arrays.
    uint256 public constant MAX_APPROVED_VENUES = 16;

    /// @notice Minimum single deposit. Filters dust and protects share math
    ///         from precision issues. 0.0001 USDC (18-decimal wei).
    uint256 public constant MIN_DEPOSIT = 0.0001 ether;

    /* ------------------------------------------------------------------- */
    /*                              storage                                */
    /* ------------------------------------------------------------------- */

    mapping(bytes32 => Vault) public vaults;
    mapping(bytes32 => mapping(address => uint256)) public shares;
    mapping(bytes32 => address[]) internal _approvedVenues;
    /// @dev Fast lookup: vault → venue → is-approved
    mapping(bytes32 => mapping(address => bool)) internal _isApprovedVenue;

    /// @dev Monotonic counter per agent for deterministic vaultId derivation.
    mapping(address => uint256) public vaultCount;

    /* ------------------------------------------------------------------- */
    /*                              createVault                            */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function createVault(
        address[] calldata approvedVenues,
        string calldata strategyDescriptor
    ) external payable nonReentrant returns (bytes32 vaultId) {
        if (approvedVenues.length == 0) revert EmptyVenues();
        if (approvedVenues.length > MAX_APPROVED_VENUES) revert TooManyVenues();
        if (msg.value < MIN_DEPOSIT) revert ZeroAmount();

        unchecked { vaultCount[msg.sender]++; }
        vaultId = keccak256(abi.encode(msg.sender, vaultCount[msg.sender], block.chainid));
        if (vaults[vaultId].status != VaultStatus.None) revert VaultExists();

        // Agent's initial deposit mints shares 1:1 with USDC at inception NAV.
        uint256 sharesMinted = msg.value;  // == msg.value * 1e18 / 1e18

        vaults[vaultId] = Vault({
            agent:               msg.sender,
            createdAt:           uint64(block.timestamp),
            status:              VaultStatus.Active,
            totalShares:         sharesMinted,
            inVault:             msg.value,
            deployedAUM:         0,
            reportedPnL:         0,
            strategyDescriptor:  strategyDescriptor
        });
        shares[vaultId][msg.sender] = sharesMinted;

        // Copy approvedVenues into storage + populate fast-lookup map.
        for (uint256 i = 0; i < approvedVenues.length; i++) {
            address v = approvedVenues[i];
            if (v == address(0)) revert ZeroAddress();
            _approvedVenues[vaultId].push(v);
            _isApprovedVenue[vaultId][v] = true;
        }

        emit VaultCreated(vaultId, msg.sender, approvedVenues, strategyDescriptor, msg.value);
        emit Deposit(vaultId, msg.sender, msg.value, sharesMinted, INCEPTION_NAV);
    }

    /* ------------------------------------------------------------------- */
    /*                              deposit                                */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function deposit(bytes32 vaultId) external payable nonReentrant returns (uint256 sharesMinted) {
        Vault storage v = vaults[vaultId];
        if (v.status != VaultStatus.Active) revert NotActive();
        if (msg.value < MIN_DEPOSIT) revert ZeroAmount();

        uint256 currentNav = _navOf(v);
        if (currentNav == 0) revert UnderwaterVault();
        sharesMinted = (msg.value * INCEPTION_NAV) / currentNav;
        if (sharesMinted == 0) revert NoSharesToMint();

        v.totalShares += sharesMinted;
        v.inVault += msg.value;
        shares[vaultId][msg.sender] += sharesMinted;

        emit Deposit(vaultId, msg.sender, msg.value, sharesMinted, currentNav);
    }

    /* ------------------------------------------------------------------- */
    /*                              redeem                                 */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function redeem(bytes32 vaultId, uint256 shareAmount) external nonReentrant returns (uint256 usdcOut) {
        Vault storage v = vaults[vaultId];
        if (v.status == VaultStatus.None) revert NotActive();   // closed/paused still allow redeem
        if (shareAmount == 0) revert ZeroAmount();
        if (shares[vaultId][msg.sender] < shareAmount) revert NoSharesToMint();

        uint256 currentNav = _navOf(v);
        if (currentNav == 0) revert UnderwaterVault();
        usdcOut = (shareAmount * currentNav) / INCEPTION_NAV;
        if (usdcOut == 0) revert NoSharesToMint();
        if (v.inVault < usdcOut) revert InsufficientLiquidity();

        // Effects before interaction (CEI).
        shares[vaultId][msg.sender] -= shareAmount;
        v.totalShares -= shareAmount;
        v.inVault -= usdcOut;

        emit Redeem(vaultId, msg.sender, shareAmount, usdcOut, currentNav);

        (bool ok,) = msg.sender.call{value: usdcOut}("");
        if (!ok) revert TransferFailed();
    }

    /* ------------------------------------------------------------------- */
    /*                              deployToVenue                          */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function deployToVenue(bytes32 vaultId, address venue, uint256 amount) external nonReentrant {
        Vault storage v = vaults[vaultId];
        if (v.status != VaultStatus.Active) revert NotActive();
        if (msg.sender != v.agent) revert NotAgent();
        if (amount == 0) revert ZeroAmount();
        if (!_isApprovedVenue[vaultId][venue]) revert VenueNotApproved();
        if (v.inVault < amount) revert InsufficientLiquidity();

        v.inVault -= amount;
        v.deployedAUM += amount;

        emit DeployToVenue(vaultId, venue, amount, v.inVault, v.deployedAUM);

        (bool ok,) = venue.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /* ------------------------------------------------------------------- */
    /*                              returnFromVenue                        */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    /// @dev `amount` MUST be sent via msg.value in the same call.  Anyone
    ///      can call (typically the venue itself or the agent on its behalf),
    ///      but the value must arrive — we can't yank from the venue. This
    ///      is the agent / venue's responsibility to coordinate.
    function returnFromVenue(bytes32 vaultId, address venue, uint256 amount) external payable nonReentrant {
        Vault storage v = vaults[vaultId];
        if (v.status == VaultStatus.None) revert NotActive();   // accept returns even when paused/closed
        if (amount == 0 || msg.value != amount) revert ZeroAmount();
        if (!_isApprovedVenue[vaultId][venue]) revert VenueNotApproved();
        if (v.deployedAUM < amount) revert InsufficientDeployedAUM();

        v.inVault += amount;
        v.deployedAUM -= amount;

        emit ReturnFromVenue(vaultId, venue, amount, v.inVault, v.deployedAUM);
    }

    /* ------------------------------------------------------------------- */
    /*                              reportPnL                              */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function reportPnL(bytes32 vaultId, int256 newPnL) external {
        Vault storage v = vaults[vaultId];
        if (v.status == VaultStatus.None) revert NotActive();
        if (msg.sender != v.agent) revert NotAgent();
        int256 oldPnL = v.reportedPnL;
        v.reportedPnL = newPnL;
        emit PnLReported(vaultId, oldPnL, newPnL, _totalAUMOf(v));
    }

    /* ------------------------------------------------------------------- */
    /*                              setPaused                              */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function setPaused(bytes32 vaultId, bool paused) external {
        Vault storage v = vaults[vaultId];
        if (v.status == VaultStatus.None || v.status == VaultStatus.Closed) revert NotActive();
        if (msg.sender != v.agent) revert NotAgent();
        v.status = paused ? VaultStatus.Paused : VaultStatus.Active;
        emit VaultPaused(vaultId, paused);
    }

    /* ------------------------------------------------------------------- */
    /*                              closeVault                             */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function closeVault(bytes32 vaultId) external {
        Vault storage v = vaults[vaultId];
        if (v.status == VaultStatus.None || v.status == VaultStatus.Closed) revert NotActive();
        if (msg.sender != v.agent) revert NotAgent();
        v.status = VaultStatus.Closed;
        emit VaultClosed(vaultId);
    }

    /* ------------------------------------------------------------------- */
    /*                              postUnderwriterReview                  */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function postUnderwriterReview(bytes32 vaultId, bytes32 reviewHash, string calldata reviewUri) external {
        if (vaults[vaultId].status == VaultStatus.None) revert NotActive();
        emit UnderwriterReviewPosted(vaultId, msg.sender, reviewHash, reviewUri);
    }

    /* ------------------------------------------------------------------- */
    /*                              views                                  */
    /* ------------------------------------------------------------------- */

    /// @inheritdoc IPlinth
    function totalAUM(bytes32 vaultId) external view returns (int256) {
        return _totalAUMOf(vaults[vaultId]);
    }

    /// @inheritdoc IPlinth
    function nav(bytes32 vaultId) external view returns (uint256) {
        return _navOf(vaults[vaultId]);
    }

    /// @inheritdoc IPlinth
    function summary(bytes32 vaultId) external view returns (
        uint256 totalShares_, uint256 inVault_, uint256 deployedAUM_, int256 reportedPnL_
    ) {
        Vault storage v = vaults[vaultId];
        return (v.totalShares, v.inVault, v.deployedAUM, v.reportedPnL);
    }

    /// @inheritdoc IPlinth
    function previewNextVaultId(address agent) external view returns (bytes32) {
        return keccak256(abi.encode(agent, vaultCount[agent] + 1, block.chainid));
    }

    /// @inheritdoc IPlinth
    function getApprovedVenues(bytes32 vaultId) external view returns (address[] memory) {
        return _approvedVenues[vaultId];
    }

    /// @inheritdoc IPlinth
    function sharesOf(bytes32 vaultId, address user) external view returns (uint256) {
        return shares[vaultId][user];
    }

    /* ------------------------------------------------------------------- */
    /*                              internal math                          */
    /* ------------------------------------------------------------------- */

    function _totalAUMOf(Vault storage v) internal view returns (int256) {
        // totalAUM = inVault + deployedAUM + reportedPnL  (signed)
        return int256(v.inVault) + int256(v.deployedAUM) + v.reportedPnL;
    }

    function _navOf(Vault storage v) internal view returns (uint256) {
        if (v.totalShares == 0) return INCEPTION_NAV;
        int256 t = _totalAUMOf(v);
        if (t <= 0) return 0;  // underwater — block deposit/redeem
        return (uint256(t) * INCEPTION_NAV) / v.totalShares;
    }
}
