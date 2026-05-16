// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IPlinthV05} from "./interfaces/IPlinthV05.sol";
import {IPlinth} from "./interfaces/IPlinth.sol";

/// @title  PlinthV06 — v0.5 + on-chain RiskGuard enforcement
/// @notice Closes the persona-8 critique of v0.5: "Risk Monitor is an off-chain
///         script the author can turn off — no cryptographic guarantee it keeps
///         running". V06 lifts four risk signals from the off-chain Risk Monitor
///         (`underwriter/risk-monitor.ts`) into on-chain enforcement that any
///         agent or investor inherits, with no admin keys to override.
///
/// @dev    v0.6 additions over v0.5 (all v0.5 hardenings retained):
///
///         | # | Signal                       | v0.5 (off-chain)   | v0.6 (on-chain)                       |
///         |---|------------------------------|--------------------|---------------------------------------|
///         | 1 | Agent listed as own venue    | Risk Monitor flag  | createVault emits AgentAsVenueFlag    |
///         | 2 | Single-venue concentration   | Risk Monitor flag  | deployToVenue REVERTS at > 80% of AUM |
///         | 3 | NAV underwater (auto-close)  | Risk Monitor flag  | reportPnL auto-Closes vault < 10% NAV |
///         | 4 | Whale deposit (NAV distort)  | Risk Monitor flag  | deposit emits WhaleDeposit            |
///
///         Per-venue balance accounting (`venueBalance`) is new in v0.6 — required
///         for the concentration check. Storage layout is NOT compatible with v0.5;
///         v0.6 is deployed as a fresh contract, same as v0 → v0.5.
contract PlinthV06 is IPlinthV05, ReentrancyGuard {
    /* ------------------------------------------------------------------- */
    /*                       inherited v0.5 constants                       */
    /* ------------------------------------------------------------------- */

    uint256 public constant INCEPTION_NAV = 1e18;
    uint256 public constant MAX_APPROVED_VENUES = 16;
    uint256 public constant MIN_DEPOSIT = 0.0001 ether;
    uint256 public constant DEPOSIT_COOLDOWN = 1 hours;
    uint256 public constant MAX_PNL_MULTIPLE = 10;
    uint256 public constant PNL_RATE_PCT = 25;
    uint256 public constant PNL_RATE_WINDOW = 1 hours;
    uint256 public constant MAX_STRATEGY_LEN = 1024;

    /* ------------------------------------------------------------------- */
    /*                       v0.6 RiskGuard parameters                      */
    /* ------------------------------------------------------------------- */

    /// @notice Maximum share of `deployedAUM` that any single venue may hold,
    /// in basis points (8000 = 80%). deployToVenue REVERTS if a transfer
    /// would push the destination venue past this. First deployment exempt
    /// (a vault with one venue trivially has 100% concentration after the
    /// first call; the check only fires once deployedAUM > amount).
    uint256 public constant MAX_VENUE_CONCENTRATION_BPS = 8000;

    /// @notice Auto-close threshold: vault NAV must stay above this fraction
    /// of INCEPTION_NAV, in basis points (1000 = 10%). If `reportPnL` would
    /// push NAV below the floor, the vault is auto-Closed (no further deposits,
    /// existing investors retain redemption rights against remaining capital).
    uint256 public constant NAV_FLOOR_BPS = 1000;

    /// @notice Single-deposit "whale" threshold: deposits that exceed this
    /// fraction of pre-deposit `totalAUM` emit a `WhaleDeposit` flag, in basis
    /// points (5000 = 50%). Informational — does not block. Useful for the
    /// Underwriter pipeline to mark NAV-distortion risk for downstream review.
    uint256 public constant WHALE_DEPOSIT_BPS = 5000;

    /* ------------------------------------------------------------------- */
    /*                              storage                                */
    /* ------------------------------------------------------------------- */

    mapping(bytes32 => Vault) public vaults;
    mapping(bytes32 => mapping(address => uint256)) public shares;
    mapping(bytes32 => address[]) internal _approvedVenues;
    mapping(bytes32 => mapping(address => bool)) internal _isApprovedVenue;
    mapping(address => uint256) public vaultCount;
    mapping(bytes32 => mapping(address => uint256)) public lastDepositAt;
    mapping(bytes32 => uint256) public lastReportAt;

    /// @notice v0.6: per-(vault, venue) current balance. Updated on
    /// deployToVenue (+= amount) and returnFromVenue (-= amount). Used for
    /// the concentration check at deploy-time. Sum across venues = deployedAUM.
    mapping(bytes32 => mapping(address => uint256)) public venueBalance;

    /* ------------------------------------------------------------------- */
    /*                              v0.6 events                             */
    /* ------------------------------------------------------------------- */

    /// @notice Emitted at createVault when the agent's address appears in
    /// `approvedVenues`. The agent-as-venue pattern is the classic Plinth
    /// red flag: the agent could route capital to itself and then mark it
    /// "deployed" without any actual venue activity. Off-chain Underwriters
    /// can filter on this event to surface vaults that need extra scrutiny.
    event AgentAsVenueFlag(bytes32 indexed vaultId, address indexed agent);

    /// @notice Emitted when a single deposit is large relative to existing AUM
    /// (large depositors can move NAV meaningfully, which is informative for
    /// downstream Underwriter reviews of fairness).
    event WhaleDeposit(
        bytes32 indexed vaultId,
        address indexed investor,
        uint256 amount,
        uint256 preDepositTotalAUM
    );

    /// @notice Emitted when reportPnL pushes NAV below NAV_FLOOR_BPS,
    /// auto-Closing the vault. Investors can still redeem; agent cannot deploy.
    event VaultAutoClosed(bytes32 indexed vaultId, uint256 navAtClose, string reason);

    /* ------------------------------------------------------------------- */
    /*                              v0.6 errors                             */
    /* ------------------------------------------------------------------- */

    error VenueConcentrationExceeded();

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

        vaultCount[msg.sender] += 1;
        vaultId = keccak256(abi.encode(msg.sender, vaultCount[msg.sender], block.chainid));

        Vault storage v = vaults[vaultId];
        v.agent = msg.sender;
        v.createdAt = uint64(block.timestamp);
        v.status = VaultStatus.Active;
        v.totalShares = msg.value;
        v.inVault = msg.value;
        v.strategyDescriptor = strategyDescriptor;

        uint256 sharesMinted = msg.value;
        shares[vaultId][msg.sender] = sharesMinted;
        lastDepositAt[vaultId][msg.sender] = block.timestamp;

        // v0.6: agent-as-venue detection (informational flag)
        bool agentIsVenue = false;
        for (uint256 i = 0; i < approvedVenues.length; i++) {
            address ve = approvedVenues[i];
            if (ve == address(0)) revert ZeroAddress();
            _approvedVenues[vaultId].push(ve);
            _isApprovedVenue[vaultId][ve] = true;
            if (ve == msg.sender) agentIsVenue = true;
        }

        emit VaultCreated(vaultId, msg.sender, approvedVenues, strategyDescriptor, msg.value);
        emit Deposit(vaultId, msg.sender, msg.value, sharesMinted, INCEPTION_NAV);
        if (agentIsVenue) emit AgentAsVenueFlag(vaultId, msg.sender);
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

        // v0.6: whale-deposit detection (informational flag)
        uint256 preTotalAUM = v.inVault + v.deployedAUM;
        if (preTotalAUM > 0 && msg.value * 10_000 >= preTotalAUM * WHALE_DEPOSIT_BPS) {
            emit WhaleDeposit(vaultId, msg.sender, msg.value, preTotalAUM);
        }

        v.totalShares += sharesMinted;
        v.inVault += msg.value;
        shares[vaultId][msg.sender] += sharesMinted;
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

        // v0.6: concentration check.
        // After deploy: deployedAUM' = deployedAUM + amount, venueBalance' = venueBalance + amount.
        // Require: venueBalance' / deployedAUM' ≤ MAX_VENUE_CONCENTRATION_BPS / 10_000
        // Equivalently: venueBalance' * 10_000 ≤ deployedAUM' * MAX_VENUE_CONCENTRATION_BPS
        // Note: when this is the first deploy (deployedAUM == 0), the new venue holds 100%
        // (single-venue vault). That's allowed — the cap kicks in once there's something
        // to compare against.
        uint256 newDeployed = v.deployedAUM + amount;
        if (v.deployedAUM > 0) {
            uint256 newVenueBalance = venueBalance[vaultId][venue] + amount;
            if (newVenueBalance * 10_000 > newDeployed * MAX_VENUE_CONCENTRATION_BPS) {
                revert VenueConcentrationExceeded();
            }
        }

        v.inVault -= amount;
        v.deployedAUM = newDeployed;
        venueBalance[vaultId][venue] += amount;

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
        if (msg.sender != venue && msg.sender != v.agent) revert NotAuthorized();
        if (venueBalance[vaultId][venue] < amount) revert InsufficientDeployedAUM();

        v.inVault += amount;
        v.deployedAUM -= amount;
        venueBalance[vaultId][venue] -= amount;

        emit ReturnFromVenue(vaultId, venue, amount, v.inVault, v.deployedAUM);
    }

    /* ------------------------------------------------------------------- */
    /*                              reportPnL                              */
    /* ------------------------------------------------------------------- */

    function reportPnL(bytes32 vaultId, int256 newPnL) external {
        Vault storage v = vaults[vaultId];
        if (v.status != VaultStatus.Active && v.status != VaultStatus.Paused) revert NotActive();
        if (msg.sender != v.agent) revert NotAgent();

        uint256 capital = v.inVault + v.deployedAUM;
        uint256 newPnLAbs = newPnL >= 0 ? uint256(newPnL) : uint256(-newPnL);

        // v0.5 #3 + #6: magnitude bound
        if (capital == 0) {
            if (newPnLAbs != 0) revert PnLOutOfBounds();
        } else {
            if (newPnLAbs > capital * MAX_PNL_MULTIPLE) revert PnLOutOfBounds();
        }

        // v0.5 #3: rate limit
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

        // v0.6: NAV-floor auto-close. After the report, if NAV has dropped below
        // 10% of inception, the vault auto-Closes. Investors retain redemption
        // rights against remaining inVault capital; agent can no longer deposit.
        uint256 navAfter = _navOf(v);
        if (navAfter < (INCEPTION_NAV * NAV_FLOOR_BPS) / 10_000) {
            v.status = VaultStatus.Closed;
            emit VaultAutoClosed(vaultId, navAfter, "NAV below floor (10% of inception)");
            emit VaultClosed(vaultId);
        }
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
    /*                       postUnderwriterReview                          */
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

    function unlocksAt(bytes32 vaultId, address user) external view returns (uint256) {
        uint256 last = lastDepositAt[vaultId][user];
        return last == 0 ? 0 : last + DEPOSIT_COOLDOWN;
    }

    /// @notice v0.6 view: current single-venue concentration in basis points.
    /// Returns the % of `deployedAUM` held by the largest venue. UIs / Risk
    /// Monitor can read this to surface vaults near the cap.
    function venueConcentrationBps(bytes32 vaultId) external view returns (uint256) {
        Vault storage v = vaults[vaultId];
        if (v.deployedAUM == 0) return 0;
        address[] memory ves = _approvedVenues[vaultId];
        uint256 maxBal = 0;
        for (uint256 i = 0; i < ves.length; i++) {
            uint256 bal = venueBalance[vaultId][ves[i]];
            if (bal > maxBal) maxBal = bal;
        }
        return (maxBal * 10_000) / v.deployedAUM;
    }

    /* ------------------------------------------------------------------- */
    /*                            internal helpers                          */
    /* ------------------------------------------------------------------- */

    function _totalAUMOf(Vault storage v) internal view returns (int256) {
        int256 capital = int256(v.inVault) + int256(v.deployedAUM);
        return capital + v.reportedPnL;
    }

    function _navOf(Vault storage v) internal view returns (uint256) {
        if (v.totalShares == 0) return INCEPTION_NAV;
        int256 t = _totalAUMOf(v);
        if (t <= 0) return 0;
        return (uint256(t) * INCEPTION_NAV) / v.totalShares;
    }
}
