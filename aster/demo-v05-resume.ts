/**
 * Resume demo-v05 after Arc RPC dropped the deposit tx.
 * The vault was already created on chain — retry deposit + cooldown check.
 */
import { createPublicClient, createWalletClient, http, defineChain, parseEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ARC_TESTNET, PLINTH_V05_ARC_TESTNET, PLINTH_ABI } from "../sdk-ts/src/index.js";
import type { Hex } from "viem";

const ARC_CHAIN = defineChain({
  id: ARC_TESTNET.chainId,
  name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [ARC_TESTNET.rpc] } },
});

const PLINTH = PLINTH_V05_ARC_TESTNET.plinth;
const VAULT_ID = "0xc003ec854ac99d1054541f6160568b13bff6f4e443bbaa25422ff3392eb29d46" as Hex;

async function main() {
  const { config } = await import("dotenv");
  const { resolve } = await import("node:path");
  config({ path: resolve("D:\\桌面\\arc\\.env") });

  const investorAcc = privateKeyToAccount(process.env.SERVICE_PRIVATE_KEY as Hex);
  const pub = createPublicClient({ chain: ARC_CHAIN, transport: http(ARC_TESTNET.rpc, { timeout: 60_000, retryCount: 3 }) });
  const investorWallet = createWalletClient({ account: investorAcc, chain: ARC_CHAIN, transport: http(ARC_TESTNET.rpc, { timeout: 60_000 }) });

  console.log(`Vault: ${VAULT_ID}`);
  console.log(`Investor: ${investorAcc.address}`);

  // Check if investor already has shares from a prior attempt
  const sharesBefore = (await pub.readContract({
    address: PLINTH,
    abi: PLINTH_ABI,
    functionName: "sharesOf",
    args: [VAULT_ID, investorAcc.address],
  })) as bigint;
  console.log(`Investor shares before: ${sharesBefore}`);

  let depositTx: Hex | undefined;
  if (sharesBefore === 0n) {
    console.log("\nSubmitting deposit (0.005 USDC)…");
    depositTx = await investorWallet.writeContract({
      address: PLINTH,
      abi: PLINTH_ABI,
      functionName: "deposit",
      args: [VAULT_ID],
      value: parseEther("0.005"),
    });
    console.log(`  deposit tx: ${depositTx}`);

    // Poll for receipt; tolerate timeouts
    let landed = false;
    for (let i = 0; i < 30; i++) {
      await new Promise((r) => setTimeout(r, 6_000));
      try {
        const r = await pub.getTransactionReceipt({ hash: depositTx });
        if (r.status === "success") { landed = true; break; }
      } catch { /* not mined yet */ }
      process.stdout.write(".");
    }
    console.log();
    if (!landed) {
      console.log("  ⚠ Receipt didn't land in 3 min — tx may still be pending. Check explorer.");
      return;
    }
  } else {
    console.log("  ✓ Investor already has shares from earlier attempt — skipping deposit");
  }

  // Read unlocksAt
  const unlocksAt = (await pub.readContract({
    address: PLINTH,
    abi: [
      { type: "function", name: "unlocksAt", stateMutability: "view",
        inputs: [{ type: "bytes32" }, { type: "address" }],
        outputs: [{ type: "uint256" }] },
    ],
    functionName: "unlocksAt",
    args: [VAULT_ID, investorAcc.address],
  })) as bigint;
  const now = Math.floor(Date.now() / 1000);
  const lockEndISO = new Date(Number(unlocksAt) * 1000).toISOString();
  console.log(`\nCooldown info:`);
  console.log(`  unlocksAt: ${unlocksAt} (${lockEndISO})`);
  console.log(`  time until unlock: ${Number(unlocksAt) - now}s (${((Number(unlocksAt) - now) / 60).toFixed(1)} min)`);

  // Simulate the redeem to prove it reverts
  console.log(`\nSimulating redeem (expecting SharesPendingVesting revert)…`);
  try {
    await pub.simulateContract({
      address: PLINTH,
      abi: PLINTH_ABI,
      functionName: "redeem",
      args: [VAULT_ID, parseEther("0.005")],
      account: investorAcc.address,
    });
    console.log(`  ✗ Unexpected — simulation did NOT revert`);
  } catch (e: any) {
    const msg = e.shortMessage ?? e.message ?? String(e);
    const isCooldown = msg.includes("SharesPendingVesting") || msg.includes("0xb6d3da1f");
    if (isCooldown) {
      console.log(`  ✓ Defense fired: SharesPendingVesting (v0.5 sandwich protection)`);
    } else {
      console.log(`  ? Revert: ${msg.slice(0, 200)}`);
    }
  }

  console.log();
  console.log(`Demo complete — v0.5 deposit cooldown is live on chain.`);
  if (depositTx) console.log(`deposit tx: ${depositTx}`);
}

main().catch((e) => { console.error("FATAL:", e); process.exit(1); });
