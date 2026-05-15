/**
 * Plinth + Mandate composition demo — first on-chain compose of two sibling
 * protocols. Demonstrates: an institutional issuer (modeled by the operator)
 * issues a Mandate authorizing an agent (also operator wallet here for solo
 * demo simplicity, but conceptually a different party) to deposit USDC into a
 * specific Plinth vault, bounded by capability + spend ceiling + counterparty
 * + purpose whitelist.
 *
 * Flow:
 *   1. Operator deploys a fresh Plinth vault with MandatePlinthBridge in
 *      approvedVenues (so the agent can later redeploy capital).
 *   2. Operator (acting as institutional issuer) issues a Mandate to itself
 *      (acting as agent), authorizing up to 0.01 USDC of spend to the bridge
 *      contract for purposeCode = "plinth_invest_v0".
 *   3. Operator funds the mandate with 0.005 USDC.
 *   4. Agent calls MandatePlinthBridge.depositViaMandate — the bridge:
 *      a. Calls Mandate.execute to pull 0.005 USDC from the mandate pool
 *      b. Calls Plinth.deposit on that USDC, minting shares to the bridge
 *      c. Records shares as belonging to the mandate's issuer
 *   5. Verify: bridge holds shares, mandate.spent == 0.005, plinth vault has
 *      0.005 inVault.
 *
 * This is the first time on chain that Plinth and Mandate compose into a
 * single capital flow. The structured event chain enables audit-trail
 * attribution: which mandate funded which vault, on whose authorization.
 */
import {
  createPublicClient, createWalletClient, http, defineChain, parseEther, keccak256,
  encodeAbiParameters, parseAbi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ARC_TESTNET, PLINTH_V05_ARC_TESTNET, PLINTH_ABI } from "../src/index.js";
import type { Hex } from "viem";

process.loadEnvFile("D:\\桌面\\arc\\.env");

const ARC_CHAIN = defineChain({
  id: ARC_TESTNET.chainId,
  name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [ARC_TESTNET.rpc] } },
});

// All three protocol contracts on Arc Testnet
const MANDATE = "0xfBBDAeC05E0061ADeb955896DFF183fdd412E6E4" as Hex;
const PLINTH  = PLINTH_V05_ARC_TESTNET.plinth;
const BRIDGE  = "0x0b92b6e4fa26e6c2b10a5c668d8313a1bf8c3f50" as Hex;

const MANDATE_ABI = parseAbi([
  "function issue(address principal, uint32 capabilityBitmap, uint256 spendCeiling, bytes32 counterpartyMerkleRoot, bytes32 purposeMerkleRoot, uint64 validFrom, uint64 validUntil, address auditViewKeyHolder) external payable returns (bytes32 mandateId)",
  "function topUp(bytes32 mandateId) external payable",
  "function mandates(bytes32 mandateId) external view returns (address issuer, address principal, uint32 capabilityBitmap, uint256 spendCeiling, uint256 spent, uint256 funded, bytes32 counterpartyMerkleRoot, bytes32 purposeMerkleRoot, uint64 validFrom, uint64 validUntil, address auditViewKeyHolder, uint8 status)",
  "function issueCount() external view returns (uint256)",
]);

const BRIDGE_ABI = parseAbi([
  "function depositViaMandate(bytes32 mandateId, bytes32 vaultId, uint256 amount, bytes32 purposeCode, bytes32 counterpartyTag, bytes32[] counterpartyProof, bytes32[] purposeProof, bytes encryptedMetadata) external returns (uint256 sharesMinted)",
  "function sharesOfMandate(bytes32 mandateId, bytes32 vaultId) external view returns (uint256)",
  "function totalDepositedViaMandate(bytes32 mandateId) external view returns (uint256)",
]);

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function pollReceipt(pub: any, hash: Hex, label: string) {
  for (let i = 0; i < 30; i++) {
    await sleep(6_000);
    try {
      const r = await pub.getTransactionReceipt({ hash });
      if (r.status === "success") {
        console.log(`    ✓ ${label} (block ${r.blockNumber})`);
        return r;
      }
      if (r.status === "reverted") throw new Error(`${label} reverted`);
    } catch (e: any) {
      if (!e.message?.includes("could not be found")) throw e;
    }
  }
  throw new Error(`${label} timeout`);
}

async function main() {
  const op = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
  const pub = createPublicClient({ chain: ARC_CHAIN, transport: http(ARC_TESTNET.rpc, { timeout: 60_000, retryCount: 2 }) });
  const opWallet = createWalletClient({ account: op, chain: ARC_CHAIN, transport: http(ARC_TESTNET.rpc, { timeout: 60_000 }) });

  console.log("─".repeat(70));
  console.log("Plinth + Mandate composition demo");
  console.log("─".repeat(70));
  console.log(`Operator (issuer + principal)  : ${op.address}`);
  console.log(`Mandate contract                : ${MANDATE}`);
  console.log(`Plinth v0.5                     : ${PLINTH}`);
  console.log(`MandatePlinthBridge             : ${BRIDGE}`);
  console.log();

  // ─── 1. Create a fresh Plinth vault with the bridge as one approved venue ──
  console.log("[1/4] Create Plinth vault with bridge in approvedVenues...");
  const createTx = await opWallet.writeContract({
    address: PLINTH, abi: PLINTH_ABI, functionName: "createVault",
    args: [
      [BRIDGE],
      "Institutional-mandate-funded vault — capital deposited via MandatePlinthBridge under a bounded on-chain authorization. First Plinth+Mandate compose.",
    ],
    value: parseEther("0.001"),
  });
  console.log(`    create tx: ${createTx}`);
  await pollReceipt(pub, createTx, "create");

  const vaultCount = await pub.readContract({
    address: PLINTH, abi: PLINTH_ABI, functionName: "vaultCount", args: [op.address],
  }) as bigint;
  const vaultId = keccak256(
    encodeAbiParameters(
      [{ type: "address" }, { type: "uint256" }, { type: "uint256" }],
      [op.address, vaultCount, BigInt(ARC_TESTNET.chainId)],
    ),
  );
  console.log(`    vaultId  : ${vaultId}`);

  // ─── 2. Issue a Mandate authorizing operator (as agent) to spend up to
  //         0.01 USDC, only to the bridge contract, for the
  //         "plinth_invest_v0" purpose ────────────────────────────────────
  console.log("\n[2/4] Issuer issues Mandate (principal=self, counterparty=bridge)...");

  // Mandate's leaf encoding (per execute() logic):
  //   counterpartyLeaf = keccak256(abi.encode(counterpartyTag, to))   ← tag FIRST
  //   purposeLeaf      = keccak256(abi.encode(purposeCode))
  // For a single-leaf tree, the root equals the leaf (empty proof verifies).
  const counterpartyTag = ("0x" + "00".repeat(32)) as Hex;
  const purposeCode = keccak256(new TextEncoder().encode("plinth_invest_v0")) as Hex;

  const counterpartyLeaf = keccak256(
    encodeAbiParameters([{ type: "bytes32" }, { type: "address" }], [counterpartyTag, BRIDGE]),
  );
  const purposeLeaf = keccak256(encodeAbiParameters([{ type: "bytes32" }], [purposeCode]));
  const counterpartyRoot = counterpartyLeaf;
  const purposeRoot = purposeLeaf;

  const now = Math.floor(Date.now() / 1000);
  // Note: principal is the BRIDGE contract, not the operator wallet — the
  // bridge is what actually invokes Mandate.execute(), so msg.sender on the
  // mandate-side will be the bridge. Conceptually the agent (operator) drives
  // the action; the bridge is the on-chain principal because it's the one
  // calling Mandate.execute. This keeps Mandate's principal-check intact
  // while allowing the bridge to compose with Plinth.deposit atomically.
  const issueTx = await opWallet.writeContract({
    address: MANDATE, abi: MANDATE_ABI, functionName: "issue",
    args: [
      BRIDGE,                                      // principal = bridge contract
      1,                                           // capabilityBitmap = BIT_TRANSFER
      parseEther("0.01"),                          // spendCeiling
      counterpartyRoot,
      purposeRoot,
      BigInt(now - 60),                            // validFrom
      BigInt(now + 24 * 60 * 60),                  // validUntil = 24h
      op.address,                                  // auditViewKeyHolder
    ],
    value: parseEther("0.005"),                    // initial funding
  });
  console.log(`    issue tx: ${issueTx}`);
  await pollReceipt(pub, issueTx, "issue");

  // Reconstruct mandateId deterministically: keccak256(abi.encode(issuer, count, chainId))
  const issueCount = await pub.readContract({
    address: MANDATE, abi: MANDATE_ABI, functionName: "issueCount",
  }) as bigint;
  const mandateId = keccak256(
    encodeAbiParameters(
      [{ type: "address" }, { type: "uint256" }, { type: "uint256" }],
      [op.address, issueCount, BigInt(ARC_TESTNET.chainId)],
    ),
  );
  console.log(`    mandateId: ${mandateId}`);

  const mandateRow = await pub.readContract({
    address: MANDATE, abi: MANDATE_ABI, functionName: "mandates", args: [mandateId],
  }) as readonly any[];
  console.log(`    funded: ${Number(mandateRow[5]) / 1e18} USDC, ceiling: ${Number(mandateRow[3]) / 1e18}`);

  // ─── 3. Agent calls bridge.depositViaMandate → composes the chain ─────
  console.log("\n[3/4] Agent calls bridge.depositViaMandate (Mandate.execute → Plinth.deposit)...");
  const depositAmount = parseEther("0.005");

  const depositTx = await opWallet.writeContract({
    address: BRIDGE, abi: BRIDGE_ABI, functionName: "depositViaMandate",
    args: [
      mandateId,
      vaultId,
      depositAmount,
      purposeCode,
      counterpartyTag,
      [],          // single-leaf tree, no proof needed (leaf == root)
      [],          // single-leaf tree, no proof needed
      "0x" as Hex, // no encrypted metadata for this demo
    ],
  });
  console.log(`    deposit tx: ${depositTx}`);
  await pollReceipt(pub, depositTx, "depositViaMandate");

  // ─── 4. Verify on-chain state composition succeeded ────────────────────
  console.log("\n[4/4] Verify composed state on chain...");
  const sharesHeld = await pub.readContract({
    address: BRIDGE, abi: BRIDGE_ABI, functionName: "sharesOfMandate",
    args: [mandateId, vaultId],
  }) as bigint;
  const totalDeposited = await pub.readContract({
    address: BRIDGE, abi: BRIDGE_ABI, functionName: "totalDepositedViaMandate",
    args: [mandateId],
  }) as bigint;
  const mandateAfter = await pub.readContract({
    address: MANDATE, abi: MANDATE_ABI, functionName: "mandates", args: [mandateId],
  }) as readonly any[];

  console.log(`    Bridge sharesOfMandate          : ${Number(sharesHeld) / 1e18}`);
  console.log(`    Bridge totalDepositedViaMandate : ${Number(totalDeposited) / 1e18} USDC`);
  console.log(`    Mandate.spent                   : ${Number(mandateAfter[4]) / 1e18} USDC`);
  console.log(`    Mandate.funded                  : ${Number(mandateAfter[5]) / 1e18} USDC`);

  console.log();
  console.log("─".repeat(70));
  console.log("✅ Plinth + Mandate composition succeeded on chain");
  console.log("─".repeat(70));
  console.log(`Vault           : ${vaultId}`);
  console.log(`Mandate         : ${mandateId}`);
  console.log(`Vault create tx : ${createTx}`);
  console.log(`Mandate issue tx: ${issueTx}`);
  console.log(`Deposit tx      : ${depositTx}`);
}

main().catch((e) => { console.error("FATAL:", e); process.exit(1); });
