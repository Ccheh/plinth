/**
 * PHASE 2 of Plinth's verifiable-oracle architecture (Option C):
 *
 * Run the Aster verifier against the EXISTING Vault #1 on Arc Testnet.
 * That vault has a reported PnL of +0.375 USDC but ZERO trades on Aster
 * (because it was a MockVenue lifecycle demo). The expected verdict is
 * `NO_VENUE_ACTIVITY` — proving the verifier can catch agents who claim
 * PnL without backing trades.
 *
 * No real money moves in this script. It's pure read-only.
 */
import { config } from "dotenv";
import { resolve } from "node:path";
import { AsterClient } from "./client.js";
import { AsterVerifier } from "./verifier.js";
import {
  PLINTH_ARC_TESTNET,
  BrowseClient,
} from "../sdk-ts/src/index.js";
import type { Hex } from "viem";

config({ path: resolve("D:\\桌面\\arc\\.env") });

async function main() {
  const aster = new AsterClient({
    baseUrl: process.env.ASTER_BASE_URL!,
    signer: process.env.ASTER_SIGNER as Hex,
    privateKey: process.env.ASTER_PRIVATE_KEY as Hex,
    user: process.env.ASTER_USER as Hex,
  });
  const verifier = new AsterVerifier(aster);

  console.log("Phase 2 — Verifier dry-run against existing vaults");
  console.log("=".repeat(60));

  // Enumerate vaults via BrowseClient. Arc Testnet eth_getLogs is capped at
  // 10k blocks; Plinth deploy is ~14k blocks back, so chunk manually.
  const browser = new BrowseClient({ plinthAddress: PLINTH_ARC_TESTNET.plinth });
  const latest = await browser.publicClient.getBlockNumber();
  const DEPLOY_BLOCK = 41_977_066n;
  const CHUNK = 9_000n;
  const allVaults: Awaited<ReturnType<typeof browser.listAllVaults>> = [];
  let to: bigint = latest;
  while (to >= DEPLOY_BLOCK) {
    const from = to > CHUNK ? to - CHUNK : 0n;
    const slice = await browser.listAllVaults(
      from < DEPLOY_BLOCK ? DEPLOY_BLOCK : from,
      to,
      true,
    );
    allVaults.push(...slice);
    if (from <= DEPLOY_BLOCK) break;
    to = from - 1n;
  }

  if (allVaults.length === 0) {
    console.log("No vaults found. Aborting.");
    return;
  }

  console.log(`Found ${allVaults.length} vault(s) on chain.\n`);

  for (const v of allVaults) {
    const vaultId = v.vaultId;
    const agent = v.agent;
    const descriptor = v.strategyDescriptor;
    const reportedPnL = v.state?.reportedPnL ?? 0n;
    const inVault = v.state?.inVault ?? 0n;
    const deployedAUM = v.state?.deployedAUM ?? 0n;

    console.log(`Vault ${vaultId.slice(0, 10)}…`);
    console.log(`  agent       : ${agent.slice(0, 10)}…`);
    console.log(`  descriptor  : ${descriptor.slice(0, 60)}${descriptor.length > 60 ? "…" : ""}`);
    console.log(`  inVault     : ${(Number(inVault) / 1e18).toFixed(6)} USDC`);
    console.log(`  deployedAUM : ${(Number(deployedAUM) / 1e18).toFixed(6)} USDC`);
    console.log(`  reportedPnL : ${(Number(reportedPnL) / 1e18).toFixed(6)} USDC`);

    // Only meaningful to verify vaults with non-zero reportedPnL
    if (reportedPnL === 0n) {
      console.log(`  → no claim to verify (reportedPnL == 0), skip`);
      console.log();
      continue;
    }

    // Time window: last 30 days (Aster userTrades is capped at 7 days per call,
    // but in this dry-run we just need to demonstrate the "no activity" case).
    const windowStart = Date.now() - 30 * 24 * 60 * 60 * 1000;

    // Guess the symbol from the strategy descriptor
    let symbol = "BTCUSDT";
    const upperDesc = descriptor.toUpperCase();
    if (upperDesc.includes("ETH")) symbol = "ETHUSDT";
    else if (upperDesc.includes("SOL")) symbol = "SOLUSDT";
    else if (upperDesc.includes("BTC")) symbol = "BTCUSDT";

    console.log(`  → running Aster verifier on ${symbol} (window: last 30d)`);
    const report = await verifier.verifyReport({
      vaultId,
      symbol,
      reportedPnlWei: reportedPnL,
      windowStartMs: windowStart,
    });

    const verdictDecoration = {
      VERIFIED: "✓",
      OVERSTATED: "⚠ ",
      UNDERSTATED: "⚠ ",
      NO_VENUE_ACTIVITY: "✗",
      INCONCLUSIVE: "?",
    }[report.verdict];

    console.log(`  ${verdictDecoration} Verdict: ${report.verdict}`);
    console.log(`     claim   : ${report.claim.reportedPnlUsdc.toFixed(6)} USDC`);
    console.log(`     venue   : ${report.venue.netRealizedUsdc.toFixed(6)} USDC (${report.venue.eventCount} fills)`);
    console.log(`     delta   : ${report.delta.absUsdc.toFixed(6)} USDC (${report.delta.pct.toFixed(2)}%)`);
    if (report.notes.length > 0) {
      console.log(`     note    : ${report.notes[0]}`);
    }
    console.log();
  }

  console.log("=".repeat(60));
  console.log("Dry-run complete.");
  console.log();
  console.log("Expected outcome: every vault with reportedPnL > 0 shows");
  console.log("`NO_VENUE_ACTIVITY` — because the demo lifecycles used");
  console.log("MockVenue, not Aster. This *correctly* identifies that those");
  console.log("PnL claims aren't backed by venue activity → in a real");
  console.log("deployment, the Underwriter would flag them as suspicious.");
  console.log();
  console.log("Phase 3 (real trade) will produce a vault that VERIFIES.");
}

main().catch((e) => {
  console.error("FATAL:", e.message);
  process.exit(1);
});
