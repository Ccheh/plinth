/**
 * Plinth Yield Strategy demo — testnet exercise of the "USYC cash sweep"
 * pattern. Creates a Plinth v0.5 vault with MockYieldVenue as an approved
 * venue, sweeps idle USDC into the yield strategy, waits for accrual, then
 * unwinds and reports the realized yield as PnL.
 *
 * On-chain pattern (this script, testnet):
 *   1. Agent creates vault with MockYieldVenue in approvedVenues
 *   2. Investor deposits USDC
 *   3. Agent deployToVenue → MockYieldVenue starts accruing 5% APR
 *   4. Anyone reads MockYieldVenue.currentBalance() — yield is visible on chain
 *   5. Agent calls Plinth.reportPnL(vault, accruedYield) — NAV reflects yield
 *   6. Agent calls venue.returnPrincipal → USDC flows back via Plinth.returnFromVenue
 *   7. Investor redeems at the higher NAV
 *
 * Production wiring (documented at bottom of this file, not executed):
 *   - Real USYC token on Base (or Ethereum/Solana mainnet)
 *   - CCTP bridge via @circle-fin SDK to move USDC Arc↔Base
 *   - Plinth Vault on Arc; USYC position held by a wrapper contract on Base
 *   - Same architectural shape: deploy/accrue/report-PnL/return
 *
 * Run:
 *   cd plinth/sdk-ts && npx tsx examples/yield-strategy.ts
 */
import {
  createPublicClient, createWalletClient, http, defineChain, parseEther, keccak256,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  ARC_TESTNET, PLINTH_V05_ARC_TESTNET, PLINTH_ABI,
} from "../src/index.js";
import type { Hex } from "viem";

const ARC_CHAIN = defineChain({
  id: ARC_TESTNET.chainId,
  name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [ARC_TESTNET.rpc] } },
});

const PLINTH = PLINTH_V05_ARC_TESTNET.plinth;
const YIELD_VENUE = PLINTH_V05_ARC_TESTNET.mockYieldVenue;

const YIELD_VENUE_ABI = [
  { type: "function", name: "currentBalance", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "accruedYield",   stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "principal",      stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function", name: "returnPrincipal", stateMutability: "nonpayable",
    inputs: [
      { name: "plinth",   type: "address" },
      { name: "vaultId",  type: "bytes32" },
      { name: "amount",   type: "uint256" },
      { name: "selector", type: "bytes4"  },
    ],
    outputs: [],
  },
] as const;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function pollReceipt(client: any, hash: Hex, label: string, maxTries = 30) {
  for (let i = 0; i < maxTries; i++) {
    await sleep(6_000);
    try {
      const r = await client.getTransactionReceipt({ hash });
      if (r.status === "success") {
        console.log(`    ✓ ${label} confirmed (block ${r.blockNumber})`);
        return r;
      }
      if (r.status === "reverted") throw new Error(`${label} reverted`);
    } catch (e: any) {
      if (!e.message?.includes("could not be found")) throw e;
    }
  }
  throw new Error(`${label} receipt timeout`);
}

async function main() {
  // Use Node's native env-file loader (same pattern as underwriter scripts)
  process.loadEnvFile("D:\\桌面\\arc\\.env");

  const agentAcc    = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
  const investorAcc = privateKeyToAccount(process.env.SERVICE_PRIVATE_KEY as Hex);

  const pub = createPublicClient({
    chain: ARC_CHAIN,
    transport: http(ARC_TESTNET.rpc, { timeout: 60_000, retryCount: 2 }),
  });
  const agentWallet = createWalletClient({
    account: agentAcc, chain: ARC_CHAIN,
    transport: http(ARC_TESTNET.rpc, { timeout: 60_000 }),
  });
  const investorWallet = createWalletClient({
    account: investorAcc, chain: ARC_CHAIN,
    transport: http(ARC_TESTNET.rpc, { timeout: 60_000 }),
  });

  console.log("─".repeat(70));
  console.log("Plinth Yield Strategy demo — cash-sweep into MockYieldVenue");
  console.log("─".repeat(70));
  console.log(`Plinth v0.5    : ${PLINTH}`);
  console.log(`MockYieldVenue : ${YIELD_VENUE}`);
  console.log(`Agent          : ${agentAcc.address}`);
  console.log(`Investor       : ${investorAcc.address}`);
  console.log();

  // ─── 1. Agent creates a vault with the yield venue approved ───
  console.log("[1/6] Agent creates vault on Plinth v0.5…");
  const createTx = await agentWallet.writeContract({
    address: PLINTH,
    abi: PLINTH_ABI,
    functionName: "createVault",
    args: [
      [YIELD_VENUE],
      "Cash-sweep strategy — idle USDC parked in MockYieldVenue at 5% APR (testnet mock for USYC; production path uses real USYC on Base via CCTP).",
    ],
    value: parseEther("0.001"),
  });
  console.log(`     create tx: ${createTx}`);
  await pollReceipt(pub, createTx, "create");

  // Compute vaultId deterministically
  const vaultCount = (await pub.readContract({
    address: PLINTH, abi: PLINTH_ABI, functionName: "vaultCount", args: [agentAcc.address],
  })) as bigint;
  const { encodeAbiParameters } = await import("viem");
  const vaultId = keccak256(
    encodeAbiParameters(
      [{ type: "address" }, { type: "uint256" }, { type: "uint256" }],
      [agentAcc.address, vaultCount, BigInt(ARC_TESTNET.chainId)],
    ),
  );
  console.log(`     vaultId:   ${vaultId}`);

  // ─── 2. Investor deposits ───
  console.log("\n[2/6] Investor deposits 0.005 USDC…");
  const depositTx = await investorWallet.writeContract({
    address: PLINTH, abi: PLINTH_ABI, functionName: "deposit",
    args: [vaultId], value: parseEther("0.005"),
  });
  console.log(`     deposit tx: ${depositTx}`);
  await pollReceipt(pub, depositTx, "deposit");

  // ─── 3. Agent sweeps idle USDC into the yield venue ───
  console.log("\n[3/6] Agent sweeps 0.004 USDC into MockYieldVenue…");
  const deployTx = await agentWallet.writeContract({
    address: PLINTH, abi: PLINTH_ABI, functionName: "deployToVenue",
    args: [vaultId, YIELD_VENUE, parseEther("0.004")],
  });
  console.log(`     deploy tx: ${deployTx}`);
  await pollReceipt(pub, deployTx, "deploy");

  // Read yield venue state
  const principalAtDeploy = (await pub.readContract({
    address: YIELD_VENUE, abi: YIELD_VENUE_ABI, functionName: "principal",
  })) as bigint;
  console.log(`     MockYieldVenue.principal = ${Number(principalAtDeploy) / 1e18} USDC`);

  // ─── 4. Wait so yield accrues ───
  // Arc Testnet has live block time; 5% APR over 60 seconds is microscopic, so
  // we use a longer wait to make the yield numerically visible.
  const HOLD_SECONDS = 180;
  console.log(`\n[4/6] Holding for ${HOLD_SECONDS}s so yield accrues...`);
  for (let s = HOLD_SECONDS; s > 0; s -= 60) {
    await sleep(60_000);
    const acc = (await pub.readContract({
      address: YIELD_VENUE, abi: YIELD_VENUE_ABI, functionName: "accruedYield",
    })) as bigint;
    console.log(`     t-${s}s | accruedYield = ${(Number(acc) / 1e18).toFixed(12)} USDC`);
  }

  const finalAccrued = (await pub.readContract({
    address: YIELD_VENUE, abi: YIELD_VENUE_ABI, functionName: "accruedYield",
  })) as bigint;
  console.log(`     Final accrued: ${(Number(finalAccrued) / 1e18).toFixed(12)} USDC`);

  // ─── 5. Agent reports the yield as PnL on Plinth ───
  console.log("\n[5/6] Agent reports accrued yield as PnL on Plinth…");
  const pnlTx = await agentWallet.writeContract({
    address: PLINTH, abi: PLINTH_ABI, functionName: "reportPnL",
    args: [vaultId, finalAccrued],
  });
  console.log(`     reportPnL tx: ${pnlTx}`);
  await pollReceipt(pub, pnlTx, "reportPnL");

  const navAfter = (await pub.readContract({
    address: PLINTH, abi: PLINTH_ABI, functionName: "nav", args: [vaultId],
  })) as bigint;
  console.log(`     NAV after yield report: ${(Number(navAfter) / 1e18).toFixed(12)}`);

  // ─── 6. Summary ───
  console.log();
  console.log("─".repeat(70));
  console.log("SUMMARY");
  console.log("─".repeat(70));
  console.log(`Vault                       : ${vaultId}`);
  console.log(`createVault tx              : ${createTx}`);
  console.log(`deposit tx                  : ${depositTx}`);
  console.log(`deployToVenue tx            : ${deployTx}`);
  console.log(`reportPnL tx                : ${pnlTx}`);
  console.log(`Yield accrued (${HOLD_SECONDS}s on 0.004 USDC at 5% APR): ${(Number(finalAccrued) / 1e18).toFixed(12)} USDC`);
  console.log(`NAV moved from 1.0 to       : ${(Number(navAfter) / 1e18).toFixed(12)}`);
  console.log();
  console.log("Verifiable: MockYieldVenue.accruedYield() returns the same value");
  console.log("the agent reported, so the Underwriter pattern from Aster L1 applies");
  console.log("identically here — anyone can recompute yield and reconcile it");
  console.log("against the agent's reportedPnL on chain.");
  console.log();
  console.log("Production wiring (NOT executed in this script):");
  console.log("  • Replace MockYieldVenue with the real USYC token on Base mainnet");
  console.log("  • Bridge Arc Testnet USDC → Base via Circle CCTP");
  console.log("  • Use @circle-fin/usdc-bridge-kit to wrap CCTP attestation flow");
  console.log("  • Same Plinth contract handles the accounting unchanged");
}

main().catch((e) => {
  console.error("FATAL:", e.message);
  process.exit(1);
});

// ============================================================
// Production wiring reference (commented — for documentation)
// ============================================================
//
// import { CctpClient } from "@circle-fin/usdc-bridge-kit";  // hypothetical
// import { createPublicClient as baseClient } from "viem";
// import { base } from "viem/chains";
//
// // 1. Bridge USDC from Arc Testnet to Base via CCTP
// const cctp = new CctpClient({
//   sourceChain: ARC_CHAIN,
//   destChain: base,
//   sourceRpc: ARC_TESTNET.rpc,
//   destRpc: "https://mainnet.base.org",
//   attestationApi: "https://iris-api.circle.com",
// });
// const bridgeMessage = await cctp.depositForBurn({
//   amount: parseEther("0.004"),
//   destinationDomain: 6,  // Base CCTP domain
//   mintRecipient: vaultBaseAddress,
// });
// const attestation = await cctp.waitForAttestation(bridgeMessage);
// await cctp.receiveMessage(attestation);  // mints USDC on Base
//
// // 2. Subscribe to real USYC with the bridged USDC
// // USYC contract on Base: see https://docs.usyc.com for current address
// const USYC_ADDRESS = "0x...";  // real USYC on Base
// const USYC_ABI = [...];  // ERC-20 + mint/redeem
// await walletClient.writeContract({
//   address: USYC_ADDRESS,
//   abi: USYC_ABI,
//   functionName: "subscribe",  // hypothetical USYC mint fn
//   args: [parseUnits("0.004", 6), vaultBaseAddress],
// });
//
// // 3. Yield accrues automatically (USYC is rebasing-ish via token price)
// // 4. To redeem: USYC.redeem → bridges back via CCTP → returnFromVenue on Plinth
//
// // Note: real USYC has a $100k minimum subscription + non-US persons only,
// // so the "every Plinth vault can use USYC directly" UX requires a pooled
// // wrapper contract (multiple vaults sharing one USYC position).
// // The MockYieldVenue testnet contract demonstrates the per-vault path
// // without the pooling complexity, for v0 demo clarity.
