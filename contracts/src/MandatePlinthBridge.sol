// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal interfaces for the contracts this bridge integrates.
///         Defined inline to avoid pulling in the full Mandate / Plinth code as
///         dependencies — only the two methods we actually call.
interface IMandateExternal {
    function execute(
        bytes32 mandateId,
        address to,
        uint256 amount,
        bytes32 purposeCode,
        bytes32 counterpartyTag,
        bytes32[] calldata counterpartyProof,
        bytes32[] calldata purposeProof,
        bytes   calldata encryptedMetadata
    ) external returns (bytes32 actionId);

    function mandates(bytes32 mandateId) external view returns (
        address issuer,
        address principal,
        uint32  capabilityBitmap,
        uint256 spendCeiling,
        uint256 spent,
        uint256 funded,
        bytes32 counterpartyMerkleRoot,
        bytes32 purposeMerkleRoot,
        uint64  validFrom,
        uint64  validUntil,
        address auditViewKeyHolder,
        uint8   status
    );
}

interface IPlinthExternal {
    function deposit(bytes32 vaultId) external payable returns (uint256 sharesMinted);
    function redeem(bytes32 vaultId, uint256 shareAmount) external returns (uint256 usdcOut);
    function sharesOf(bytes32 vaultId, address user) external view returns (uint256);
}

/// @title  MandatePlinthBridge — institutional capital path: Mandate → Plinth Vault
/// @notice This is the first real compose-on-chain of two Plinth-sibling
///         protocols. The story it makes possible:
///
///           1. An institutional issuer (a bank, fund, corporate treasury —
///              modeled by a multi-sig) creates a Mandate on the Mandate
///              contract, authorizing an AI agent (the principal) to deposit
///              up to X USDC into a specific Plinth Vault, bounded by purpose
///              and counterparty whitelist.
///           2. The agent calls `depositViaMandate` on this bridge. The bridge
///              calls `Mandate.execute` to pull USDC out (Mandate verifies
///              all capability / ceiling / whitelist / time-window rules), then
///              calls `Plinth.deposit` to mint shares.
///           3. The bridge holds shares on the issuer's behalf — only the
///              mandate's issuer can `redeemForIssuer`. Even if the agent's
///              private key is compromised, the agent cannot redeem the
///              shares — capability constraint preserved across both protocols.
///
///         This is the architectural payoff of the sibling-protocol stack:
///         Mandate (auth) + Plinth (vault) compose into a single audited
///         capital flow. Identity attribution (which mandate funded which
///         vault) is preserved end to end via on-chain events.
contract MandatePlinthBridge {
    IMandateExternal public immutable mandate;
    IPlinthExternal  public immutable plinth;

    /// @notice (mandateId, vaultId) => shares held on issuer's behalf.
    /// Allows multiple mandates to fund the same vault without share
    /// commingling.
    mapping(bytes32 => mapping(bytes32 => uint256)) public sharesOfMandate;

    /// @notice Mirror of total deposits, useful for read-side accounting.
    mapping(bytes32 => uint256) public totalDepositedViaMandate;

    event MandateDeposited(
        bytes32 indexed mandateId,
        bytes32 indexed vaultId,
        address indexed issuer,
        uint256 amount,
        uint256 sharesMinted
    );
    event MandateRedeemed(
        bytes32 indexed mandateId,
        bytes32 indexed vaultId,
        address indexed issuer,
        uint256 sharesBurned,
        uint256 usdcOut
    );

    error NotIssuer();
    error InsufficientShares();
    error MandateRouteFailed();
    error DepositFailed();
    error TransferFailed();

    constructor(IMandateExternal _mandate, IPlinthExternal _plinth) {
        mandate = _mandate;
        plinth  = _plinth;
    }

    /* --------------- inbound (called by Mandate.execute) --------------- */

    /// @notice Mandate.execute sends USDC here via raw call. We hold it in our
    ///         balance until the next step. (In a single-call wrapper this
    ///         function would also auto-deposit, but Mandate.execute does the
    ///         transfer before returning the actionId — so we split into two
    ///         calls and let the agent invoke us a second time to complete.)
    receive() external payable {}

    /* --------------- main composition entry point --------------- */

    /// @notice Agent calls this to do "Mandate.execute → Plinth.deposit" in
    ///         one transaction. The agent must already be the principal on
    ///         the mandate.
    /// @dev    Caller must be the mandate's principal (Mandate enforces this).
    ///         The mandate must list this bridge contract as an allowed
    ///         counterparty (Merkle-verified in Mandate.execute).
    function depositViaMandate(
        bytes32 mandateId,
        bytes32 vaultId,
        uint256 amount,
        bytes32 purposeCode,
        bytes32 counterpartyTag,
        bytes32[] calldata counterpartyProof,
        bytes32[] calldata purposeProof,
        bytes   calldata encryptedMetadata
    ) external returns (uint256 sharesMinted) {
        // 1. Snapshot our balance so we know what arrived from Mandate.execute
        uint256 balBefore = address(this).balance;

        // 2. Trigger the Mandate to send `amount` USDC to this contract.
        //    Mandate.execute enforces:
        //      - msg.sender == principal
        //      - capability bit + status + time window
        //      - counterparty + purpose Merkle proofs
        //      - spend ceiling not exceeded
        //      - funded balance available
        //    If any check fails, the call reverts and no state changes.
        try mandate.execute(
            mandateId,
            address(this),
            amount,
            purposeCode,
            counterpartyTag,
            counterpartyProof,
            purposeProof,
            encryptedMetadata
        ) returns (bytes32 /* actionId */) {
            // ok
        } catch {
            revert MandateRouteFailed();
        }

        // 3. Confirm we actually received the funds
        uint256 received = address(this).balance - balBefore;
        require(received == amount, "amount mismatch");

        // 4. Deposit into Plinth Vault. Shares are minted to this bridge.
        try plinth.deposit{value: amount}(vaultId) returns (uint256 minted) {
            sharesMinted = minted;
        } catch {
            revert DepositFailed();
        }

        // 5. Record the shares as belonging to the mandate's issuer
        sharesOfMandate[mandateId][vaultId] += sharesMinted;
        totalDepositedViaMandate[mandateId] += amount;

        // 6. Read issuer for event indexing
        (address issuer, , , , , , , , , , , ) = mandate.mandates(mandateId);
        emit MandateDeposited(mandateId, vaultId, issuer, amount, sharesMinted);
    }

    /* --------------- redemption (issuer-only) --------------- */

    /// @notice The mandate's issuer redeems shares held on their behalf by
    ///         this bridge, getting USDC back.
    function redeemForIssuer(
        bytes32 mandateId,
        bytes32 vaultId,
        uint256 shareAmount
    ) external returns (uint256 usdcOut) {
        (address issuer, , , , , , , , , , , ) = mandate.mandates(mandateId);
        if (msg.sender != issuer) revert NotIssuer();
        if (sharesOfMandate[mandateId][vaultId] < shareAmount) revert InsufficientShares();

        sharesOfMandate[mandateId][vaultId] -= shareAmount;

        usdcOut = plinth.redeem(vaultId, shareAmount);
        (bool ok,) = issuer.call{value: usdcOut}("");
        if (!ok) revert TransferFailed();

        emit MandateRedeemed(mandateId, vaultId, issuer, shareAmount, usdcOut);
    }

    /* --------------- view helpers --------------- */

    function plinthSharesHeld(bytes32 vaultId) external view returns (uint256) {
        return plinth.sharesOf(vaultId, address(this));
    }
}
