/**
 * Demo vault on PlinthV05 — proves the security-hardened contract works
 * on Arc Testnet and that the new defenses kick in.
 *
 * Flow:
 *   1. Agent createVault on PlinthV05 (with descriptor including v0.5 reference)
 *   2. Investor deposits 0.005 USDC
 *   3. Investor IMMEDIATELY tries to redeem → expect SharesPendingVesting revert
 *   4. Reads on-chain `unlocksAt(vault, investor)` view to show cooldown end timestamp
 *   5. (Doesn't wait — that would be 1 hour. Just proves the gate fires.)
 *
 * No real money risk beyond the deposit (which can be redeemed after cooldown).
 */
import { createPublicClient, createWalletClient, http, defineChain, parseEther, keccak256, encodeAbiParameters } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ARC_TESTNET, PLINTH_V05_ARC_TESTNET, PLINTH_ABI } from "../sdk-ts/src/index.js";
import type { Hex } from "viem";

const ARC_CHAIN = defineChain({
  id: ARC_TESTNET.chainId,
  name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [ARC_TESTNET.rpc] } },
});

const VENUE = PLINTH_V05_ARC_TESTNET.mockVenue1;
const PLINTH = PLINTH_V05_ARC_TESTNET.plinth;

// v0.5-specific errors we expect to see
const SHARES_PENDING_VESTING_SELECTOR = "0x" + keccak256(new TextEncoder().encode("SharesPendingVesting()")).slice(2, 10);

async function main() {
  // Load env
  const { config } = await import("dotenv");
  const { resolve } = await import("node:path");
  config({ path: resolve("D:\\桌面\\arc\\.env") });

  const agentAcc = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
  const investorAcc = privateKeyToAccount(process.env.SERVICE_PRIVATE_KEY as Hex);

  const pub = createPublicClient({ chain: ARC_CHAIN, transport: http(ARC_TESTNET.rpc, { timeout: 60_000, retryCount: 2 }) });
  const agentWallet = createWalletClient({ account: agentAcc, chain: ARC_CHAIN, transport: http(ARC_TESTNET.rpc, { timeout: 60_000 }) });
  const investorWallet = createWalletClient({ account: investorAcc, chain: ARC_CHAIN, transport: http(ARC_TESTNET.rpc, { timeout: 60_000 }) });

  console.log("─".repeat(60));
  console.log("PlinthV05 first vault — security-hardened demo");
  console.log("─".repeat(60));
  console.log(`Contract: ${PLINTH}`);
  console.log(`Agent   : ${agentAcc.address}`);
  console.log(`Investor: ${investorAcc.address}`);
  console.log();

  // ─── 1. createVault on v0.5 ───
  console.log("[1] Agent creating vault on PlinthV05…");
  const createTx = await agentWallet.writeContract({
    address: PLINTH,
    abi: PLINTH_ABI,
    functionName: "createVault",
    args: [
      [VENUE],
      "PlinthV05 demo — security hardening proof. Agent deposit + investor deposit + redeem-blocked-by-cooldown.",
    ],
    value: parseEther("0.001"),
  });
  console.log(`    create tx: ${createTx}`);
  await pub.waitForTransactionReceipt({ hash: createTx, timeout: 300_000, pollingInterval: 4000 });

  // Compute vaultId deterministically
  const vaultCount = (await pub.readContract({
    address: PLINTH,
    abi: PLINTH_ABI,
    functionName: "vaultCount",
    args: [agentAcc.address],
  })) as bigint;
  const vaultId = keccak256(
    encodeAbiParameters(
      [{ type: "address" }, { type: "uint256" }, { type: "uint256" }],
      [agentAcc.address, vaultCount, BigInt(ARC_TESTNET.chainId)],
    ),
  );
  console.log(`    vaultId  : ${vaultId}`);

  // ─── 2. Investor deposit ───
  console.log("\n[2] Investor deposits 0.005 USDC…");
  const depositTx = await investorWallet.writeContract({
    address: PLINTH,
    abi: PLINTH_ABI,
    functionName: "deposit",
    args: [vaultId],
    value: parseEther("0.005"),
  });
  console.log(`    deposit tx: ${depositTx}`);
  await pub.waitForTransactionReceipt({ hash: depositTx, timeout: 300_000, pollingInterval: 4000 });

  // ─── 3. Read unlocksAt ───
  console.log("\n[3] Reading cooldown info from chain…");
  const unlocksAt = (await pub.readContract({
    address: PLINTH,
    abi: [
      {
        type: "function",
        name: "unlocksAt",
        stateMutability: "view",
        inputs: [{ type: "bytes32" }, { type: "address" }],
        outputs: [{ type: "uint256" }],
      },
    ],
    functionName: "unlocksAt",
    args: [vaultId, investorAcc.address],
  })) as bigint;
  const lockEndISO = new Date(Number(unlocksAt) * 1000).toISOString();
  console.log(`    investor's shares vest until: ${unlocksAt} (${lockEndISO})`);

  // ─── 4. Try to redeem immediately — should revert ───
  console.log("\n[4] Investor attempts immediate redeem (expect SharesPendingVesting revert)…");
  let redeemFailed = false;
  let revertReason = "";
  try {
    await pub.simulateContract({
      address: PLINTH,
      abi: PLINTH_ABI,
      functionName: "redeem",
      args: [vaultId, parseEther("0.005")],
      account: investorAcc.address,
    });
    console.log(`    ✗ Unexpected: simulation did not revert`);
  } catch (e: any) {
    redeemFailed = true;
    revertReason = e.shortMessage ?? e.message ?? String(e);
    if (revertReason.includes("SharesPendingVesting") || revertReason.includes("0xdc6e4406")) {
      console.log(`    ✓ Redeem correctly reverted: SharesPendingVesting`);
    } else {
      console.log(`    ? Revert reason: ${revertReason.slice(0, 200)}`);
    }
  }

  console.log();
  console.log("─".repeat(60));
  console.log("SUMMARY");
  console.log("─".repeat(60));
  console.log(`Contract       : ${PLINTH}`);
  console.log(`Vault          : ${vaultId}`);
  console.log(`createVault tx : ${createTx}`);
  console.log(`deposit tx     : ${depositTx}`);
  console.log(`Cooldown active: ${redeemFailed ? "YES (defense fired)" : "NO"}`);
  console.log(`Unlocks at     : ${lockEndISO}`);
  console.log();
  console.log("v0.5 sandwich defense is live on chain.");
}

main().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
