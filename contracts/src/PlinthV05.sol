// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IPlinthV05} from "./interfaces/IPlinthV05.sol";
import {IPlinth} from "./interfaces/IPlinth.sol";

/// @title  PlinthV05 — security-hardened capital layer for AI trading agents on Arc
/// @notice See IPlinth + IPlinthV05 for the interface. See
///         docs/security-audit.md for the full audit report on what v0.5
///         fixes vs the v0 deployment.
///
///         v0.5 additions:
///           - DEPOSIT_COOLDOWN: shares vest for 1 hour before being
///             redeemable (defense against #1 sandwich-on-reportPnL)
///           - returnFromVenue caller restricted to (venue || agent) (#2)
///           - reportPnL bounded by MAX_PNL_MULTIPLE × capital and
///             rate-limited to PNL_RATE_PCT per PNL_RATE_WINDOW (#3 + #6)
///           - reportPnL rejected on Closed vaults (#4)
///           - strategyDescriptor capped at MAX_STRATEGY_LEN bytes (#8)
///
///         All v0 invariants retained: capability constraint, no agent
///         withdraw, no admin keys.
contract PlinthV05 is IPlinthV05, ReentrancyGuard {
    /* ------------------------------------------------------------------- */
    /*                              constants                              */
    /* ------------------------------------------------------------------- */

    /// @notice NAV inception value: 1 share = 1 USDC = 1e18 wei.
    uint256 public constant INCEPTION_NAV = 1e18;

    /// @notice Cap on the immutable approved-venues list per vault.
    uint256 public constant MAX_APPROVED_VENUES = 16;

    /// @notice Minimum single deposit. Filters dust. 0.0001 USDC.
    uint256 public constant MIN_DEPOSIT = 0.0001 ether;

    /// @notice Deposit cooldown — shares minted via deposit() cannot be
    /// redeemed within this window. Defense against #1 sandwich-on-reportPnL.
    uint256 public constant DEPOSIT_COOLDOWN = 1 hours;

    /// @notice |reportedPnL| cap relative to total capital (inVault + deployedAUM).
    /// Catches insane / overflow-probing values. (#6)
    uint256 public constant MAX_PNL_MULTIPLE = 10;

    /// @notice reportPnL rate-limit percent of capital per PNL_RATE_WINDOW. (#3)
    uint256 public constant PNL_RATE_PCT = 25;
    uint256 public constant PNL_RATE_WINDOW = 1 hours;

    /// @notice Maximum length of `strategyDescriptor` in bytes. (#8)
    uint256 public constant MAX_STRATEGY_LEN = 1024;

    /* ------------------------------------------------------------------- */
    /*                              storage                                */
    /* ------------------------------------------------------------------- */

    mapping(bytes32 => Vault) public vaults;
    mapping(bytes32 => mapping(address => uint256)) public shares;
    mapping(bytes32 => address[]) internal _approvedVenues;
    mapping(bytes32 => mapping(address => bool)) internal _isApprovedVenue;
    mapping(address => uint256) public vaultCount;

    /// @notice Per-(vault, user) timestamp of the user's most recent deposit.
    /// Used by redeem() to enforce DEPOSIT_COOLDOWN.
    mapping(bytes32 => mapping(address => uint256)) public lastDepositAt;

    /// @notice Per-vault timestamp of the most recent reportPnL. Used by
    /// reportPnL() to enforce PNL_RATE_PCT / PNL_RATE_WINDOW.
    mapping(bytes32 => uint256) public lastReportAt;

    /* ------------------------------------------------------------------- */
    /*                              createVault                            */
    /* ------------------------------------------------------------------- */

    function createVault(
        address[] calldata approvedVenues,
        string calldata strategyDescriptor
    ) external payable nonReentrant returns (bytes32 vaultId) {
        if (approvedVenues.length == 0) revert EmptyVenues();
        if (approvedVenues.length > MAX_APPROVED_VENUES) revert TooManyVenues();
        if (msg.value < MIN_DEPOSIT) revert ZeroAmount();
        if (bytes(strategyDescriptor).length > MAX_STRATEGY_LEN) revert StrategyDescriptorTooLong();

        unchecked { vaultCount[msg.sender]++; }
        vaultId = keccak256(abi.encode(msg.sender, vaultCount[msg.sender], block.chainid));
        if (vaults[vaultId].status != VaultStatus.None) revert VaultExists();

        uint256 sharesMinted = msg.value;

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
        lastDepositAt[vaultId][msg.sender] = block.timestamp;

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

        // v0.5: refresh the user's cooldown clock. A user who deposits
        // multiple times resets the timer (FIFO would be more granular but
        // simple is preferable here; bounded blast radius).
        lastDepositAt[vaultId][msg.sender] = block.timestamp;

        emit Deposit(vaultId, msg.sender, msg.value, sharesMinted, currentNav);
    }

    /* ------------------------------------------------------------------- */
    /*                              redeem                                 */
    /* ------------------------------------------------------------------- */

    function redeem(bytes32 vaultId, uint256 shareAmount) external nonReentrant returns (uint256 usdcOut) {
        Vault storage v = vaults[vaultId];
        if (v.status == VaultStatus.None) revert NotActive();
        if (shareAmount == 0) revert ZeroAmount();
        if (shares[vaultId][msg.sender] < shareAmount) revert NoSharesToMint();

        // v0.5: enforce share vesting (sandwich defense).
        if (block.timestamp < lastDepositAt[vaultId][msg.sender] + DEPOSIT_COOLDOWN) {
            revert SharesPendingVesting();
        }

        uint256 currentNav = _navOf(v);
        if (currentNav == 0) revert UnderwaterVault();
        usdcOut = (shareAmount * currentNav) / INCEPTION_NAV;
        if (usdcOut == 0) revert NoSharesToMint();
        if (v.inVault < usdcOut) revert InsufficientLiquidity();

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

    function returnFromVenue(bytes32 vaultId, address venue, uint256 amount) external payable nonReentrant {
        Vault storage v = vaults[vaultId];
        if (v.status == VaultStatus.None) revert NotActive();
        if (amount == 0 || msg.value != amount) revert ZeroAmount();
        if (!_isApprovedVenue[vaultId][venue]) revert VenueNotApproved();
        if (v.deployedAUM < amount) revert InsufficientDeployedAUM();

        // v0.5 (#2 fix): only the venue itself or the agent may push funds back.
        // Closes the third-party griefing vector documented in audit #2.
        if (msg.sender != venue && msg.sender != v.agent) revert NotAuthorized();

        v.inVault += amount;
        v.deployedAUM -= amount;

        emit ReturnFromVenue(vaultId, venue, amount, v.inVault, v.deployedAUM);
    }

    /* ------------------------------------------------------------------- */
    /*                              reportPnL                              */
    /* ------------------------------------------------------------------- */

    function reportPnL(bytes32 vaultId, int256 newPnL) external {
        Vault storage v = vaults[vaultId];
        // v0.5 (#4 fix): reject Closed vaults — only Active or Paused can update PnL.
        if (v.status != VaultStatus.Active && v.status != VaultStatus.Paused) revert NotActive();
        if (msg.sender != v.agent) revert NotAgent();

        uint256 capital = v.inVault + v.deployedAUM;
        uint256 newPnLAbs = newPnL >= 0 ? uint256(newPnL) : uint256(-newPnL);

        // v0.5 (#3 + #6 fix): magnitude bound. |newPnL| ≤ MAX_PNL_MULTIPLE × capital.
        // If capital is zero (vault is empty), no PnL claim is allowed.
        if (capital == 0) {
            if (newPnLAbs != 0) revert PnLOutOfBounds();
        } else {
            if (newPnLAbs > capital * MAX_PNL_MULTIPLE) revert PnLOutOfBounds();
        }

        // v0.5 (#3 fix): rate limit. If a previous report was within
        // PNL_RATE_WINDOW, |Δ PnL| ≤ PNL_RATE_PCT% of capital.
        int256 oldPnL = v.reportedPnL;
        uint256 lastReport = lastReportAt[vaultId];
        if (lastReport != 0 && block.timestamp < lastReport + PNL_RATE_WINDOW && capital > 0) {
            int256 delta = newPnL > oldPnL ? newPnL - oldPnL : oldPnL - newPnL;
            uint256 deltaAbs = uint256(delta);
            if (deltaAbs * 100 > capital * PNL_RATE_PCT) revert PnLRateLimitExceeded();
        }

        v.reportedPnL = newPnL;
        lastReportAt[vaultId] = block.timestamp;
        emit PnLReported(vaultId, oldPnL, newPnL, _totalAUMOf(v));
    }

    /* ------------------------------------------------------------------- */
    /*                              setPaused                              */
    /* ------------------------------------------------------------------- */

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

    function postUnderwriterReview(bytes32 vaultId, bytes32 reviewHash, string calldata reviewUri) external {
        if (vaults[vaultId].status == VaultStatus.None) revert NotActive();
        emit UnderwriterReviewPosted(vaultId, msg.sender, reviewHash, reviewUri);
    }

    /* ------------------------------------------------------------------- */
    /*                              views                                  */
    /* ------------------------------------------------------------------- */

    function totalAUM(bytes32 vaultId) external view returns (int256) {
        return _totalAUMOf(vaults[vaultId]);
    }

    function nav(bytes32 vaultId) external view returns (uint256) {
        return _navOf(vaults[vaultId]);
    }

    function summary(bytes32 vaultId) external view returns (
        uint256 totalShares_, uint256 inVault_, uint256 deployedAUM_, int256 reportedPnL_
    ) {
        Vault storage v = vaults[vaultId];
        return (v.totalShares, v.inVault, v.deployedAUM, v.reportedPnL);
    }

    function previewNextVaultId(address agent) external view returns (bytes32) {
        return keccak256(abi.encode(agent, vaultCount[agent] + 1, block.chainid));
    }

    function getApprovedVenues(bytes32 vaultId) external view returns (address[] memory) {
        return _approvedVenues[vaultId];
    }

    function sharesOf(bytes32 vaultId, address user) external view returns (uint256) {
        return shares[vaultId][user];
    }

    /// @notice Returns the timestamp at which `user`'s shares can be redeemed.
    /// Pure convenience for UIs — `redeem()` will revert with
    /// `SharesPendingVesting` before this time anyway.
    function unlocksAt(bytes32 vaultId, address user) external view returns (uint256) {
        uint256 last = lastDepositAt[vaultId][user];
        return last == 0 ? 0 : last + DEPOSIT_COOLDOWN;
    }

    /* ------------------------------------------------------------------- */
    /*                              internal math                          */
    /* ------------------------------------------------------------------- */

    function _totalAUMOf(Vault storage v) internal view returns (int256) {
        return int256(v.inVault) + int256(v.deployedAUM) + v.reportedPnL;
    }

    function _navOf(Vault storage v) internal view returns (uint256) {
        if (v.totalShares == 0) return INCEPTION_NAV;
        int256 t = _totalAUMOf(v);
        if (t <= 0) return 0;
        return (uint256(t) * INCEPTION_NAV) / v.totalShares;
    }
}
