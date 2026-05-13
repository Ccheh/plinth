/**
 * PHASE 5 — Cumulative verifier demonstration on Vault #5.
 *
 * Opens an additional 1-2 BTC perp round-trips on Aster L1, reports the
 * cumulative realized PnL on Plinth, and re-runs the Underwriter verifier
 * against the full trade history. Strengthens the v0 demo from "1 data
 * point" to "3 round-trips, mix of long+short, mix of win+loss".
 *
 * Each round-trip ~5 USDT margin / $80 notional, ~$0.05 fees.
 * Total experimental cost budget: ~$0.15 USDT.
 */
import { config } from "dotenv";
import { resolve } from "node:path";
import { writeFileSync } from "node:fs";
import { keccak256, toBytes } from "viem";
import { AsterClient } from "./client.js";
import { AsterVerifier } from "./verifier.js";
import { AgentClient, InvestorClient, PLINTH_ARC_TESTNET } from "../sdk-ts/src/index.js";
import type { Hex } from "viem";

config({ path: resolve("D:\\桌面\\arc\\.env") });

const VAULT_ID = "0xefb495a02c14af970104d62e9623d83eea8d0b725dea9ffd6b7aa479284430fc" as Hex;
const SYMBOL = "BTCUSDT";
const QUANTITY = "0.001";
const HOLD_SECONDS = 120;

// Plan: 1 long + 1 short, each held ~2 min. Combined with the original
// long from Phase 3, the vault will have 3 round-trips visible to the verifier.
const ROUND_TRIPS: Array<{ side: "BUY" | "SELL"; positionSide: "LONG" | "SHORT"; label: string }> = [
  { side: "BUY",  positionSide: "LONG",  label: "Round 2 — LONG" },
  { side: "SELL", positionSide: "SHORT", label: "Round 3 — SHORT" },
];

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const bar = () => console.log("─".repeat(70));

async function main() {
  bar();
  console.log(`Phase 5 — Cumulative verifier demo @ ${new Date().toISOString()}`);
  bar();

  const aster = new AsterClient({
    baseUrl: process.env.ASTER_BASE_URL!,
    signer: process.env.ASTER_SIGNER as Hex,
    privateKey: process.env.ASTER_PRIVATE_KEY as Hex,
  });
  const verifier = new AsterVerifier(aster);
  const agent = new AgentClient({
    privateKey: process.env.PRIVATE_KEY as Hex,
    plinthAddress: PLINTH_ARC_TESTNET.plinth,
  });
  const investor = new InvestorClient({
    privateKey: process.env.SERVICE_PRIVATE_KEY as Hex,
    plinthAddress: PLINTH_ARC_TESTNET.plinth,
  });

  const windowStart = Date.parse("2026-05-13T12:00:00Z"); // before Phase 3 trade
  console.log(`Vault     : ${VAULT_ID}`);
  console.log(`Symbol    : ${SYMBOL}`);
  console.log(`Window    : since 2026-05-13T12:00:00Z`);
  console.log();

  for (const trip of ROUND_TRIPS) {
    bar();
    console.log(trip.label);
    bar();

    // OPEN
    console.log(`OPEN ${trip.side} ${QUANTITY} ${SYMBOL} (positionSide=${trip.positionSide})`);
    const open = await aster.placeMarketOrder({
      symbol: SYMBOL,
      side: trip.side,
      quantity: QUANTITY,
      positionSide: trip.positionSide,
    });
    console.log(`  ✓ orderId ${open.orderId}, status ${open.status}`);

    // HOLD
    for (let i = HOLD_SECONDS; i > 0; i -= 30) {
      await sleep(30_000);
      const t = await aster.price(SYMBOL);
      console.log(`  t-${i}s | ${SYMBOL} = ${t.price}`);
    }

    // CLOSE (opposite side on same positionSide bucket)
    const closeSide: "BUY" | "SELL" = trip.side === "BUY" ? "SELL" : "BUY";
    console.log(`CLOSE ${closeSide} ${QUANTITY} (positionSide=${trip.positionSide})`);
    const close = await aster.placeMarketOrder({
      symbol: SYMBOL,
      side: closeSide,
      quantity: QUANTITY,
      positionSide: trip.positionSide,
    });
    console.log(`  ✓ orderId ${close.orderId}`);
    await sleep(5_000); // let Aster settle attribution
    console.log();
  }

  // ============== Pull cumulative trades + compute total realized ==============
  bar();
  console.log("Aggregating trades from Aster…");
  bar();
  const trades = await aster.getUserTrades(SYMBOL, 100);
  const inWindow = trades.filter((t: any) => t.time >= windowStart);
  console.log(`Total fills since ${new Date(windowStart).toISOString()}: ${inWindow.length}`);
  for (const t of inWindow) {
    const ts = new Date(t.time).toISOString().slice(11, 19);
    console.log(
      `  ${ts}  ${t.side.padEnd(4)} ${t.qty} @ ${t.price.toString().padEnd(10)} | realizedPnl=${parseFloat(t.realizedPnl).toFixed(6)} | fee=${parseFloat(t.commission).toFixed(6)}`,
    );
  }

  const grossRealized = inWindow.reduce((s: number, t: any) => s + parseFloat(t.realizedPnl), 0);
  const totalCommission = inWindow.reduce((s: number, t: any) => s + Math.abs(parseFloat(t.commission)), 0);
  const netRealized = grossRealized - totalCommission;
  console.log();
  console.log(`Σ gross realizedPnl : ${grossRealized.toFixed(6)} USDT`);
  console.log(`Σ commissions       : ${totalCommission.toFixed(6)} USDT`);
  console.log(`Net realized        : ${netRealized.toFixed(6)} USDT`);
  console.log();

  // ============== reportPnL on Plinth (cumulative) ==============
  bar();
  console.log("Reporting cumulative PnL on Plinth…");
  bar();
  const pnlScaled = BigInt(Math.round(netRealized * 1e18));
  const pnlTx = await agent.reportPnL(VAULT_ID, pnlScaled);
  console.log(`  ✓ reportPnL tx: ${pnlTx}`);
  console.log(`  ✓ new reportedPnL (wei): ${pnlScaled.toString()}`);

  // ============== Run verifier ==============
  bar();
  console.log("Running Underwriter Aster verifier…");
  bar();
  const report = await verifier.verifyReport({
    vaultId: VAULT_ID,
    symbol: SYMBOL,
    reportedPnlWei: pnlScaled,
    windowStartMs: windowStart,
  });
  const markdown = AsterVerifier.renderMarkdown(report);

  // Persist to docs/reviews so reviewUri resolves
  writeFileSync(
    resolve(`D:\\桌面\\arc\\plinth\\docs\\reviews\\${VAULT_ID}-phase5.md`),
    markdown,
  );

  console.log();
  console.log(`Verdict: ${report.verdict}`);
  console.log(`Delta:   ${report.delta.absUsdc.toFixed(6)} USDC (${report.delta.pct.toFixed(2)}%)`);
  console.log();

  // ============== Post review on chain ==============
  const reviewHash = keccak256(toBytes(markdown));
  const reviewUri = `https://ccheh.github.io/plinth/reviews/${VAULT_ID}-phase5.md`;
  const reviewTx = await investor.postUnderwriterReview(VAULT_ID, reviewHash, reviewUri);

  bar();
  console.log("SUMMARY");
  bar();
  console.log(`Round-trips      : ${inWindow.length / 2}`);
  console.log(`Net realized PnL : ${netRealized.toFixed(6)} USDT`);
  console.log(`Verdict          : ${report.verdict} (delta ${report.delta.pct.toFixed(2)}%)`);
  console.log(`reportPnL tx     : ${pnlTx}`);
  console.log(`Underwriter tx   : ${reviewTx}`);
  bar();
}

main().catch((e) => {
  console.error("FATAL:", e.message);
  process.exit(1);
});
