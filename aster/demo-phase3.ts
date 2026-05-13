/**
 * PHASE 3 — End-to-end verifiable-PnL demo on Plinth + Aster L1.
 *
 *  1. Create a new Plinth vault on Arc Testnet: "BTC perp via Aster L1 — verifiable demo"
 *  2. Configure Aster: ISOLATED margin, 16x leverage
 *  3. Open 0.001 BTC long market order on Aster (real money, ~5 USDT margin)
 *  4. Wait 180 seconds
 *  5. Close position (0.001 BTC sell, reduceOnly)
 *  6. Pull userTrades from Aster → compute realized PnL
 *  7. agent.reportPnL(vaultId, realizedPnL) on Plinth
 *  8. Run AsterVerifier → expected verdict: VERIFIED
 *  9. Post UnderwriterReviewPosted on Plinth with the verdict + tx hashes
 * 10. Print a summary that can be pasted into submission.md
 */
import { config } from "dotenv";
import { resolve } from "node:path";
import { writeFileSync } from "node:fs";
import { keccak256, toBytes, parseEther } from "viem";
import { AsterClient } from "./client.js";
import { AsterVerifier } from "./verifier.js";
import {
  AgentClient,
  InvestorClient,
  PLINTH_ARC_TESTNET,
  formatUsdc,
} from "../sdk-ts/src/index.js";
import type { Hex } from "viem";

config({ path: resolve("D:\\桌面\\arc\\.env") });

const SYMBOL = "BTCUSDT";
const QUANTITY = "0.001";
const LEVERAGE = 16;
const HOLD_SECONDS = 180;
const INITIAL_VAULT_DEPOSIT_USDC = parseEther("0.01");

function nowIso() { return new Date().toISOString(); }
function sleep(ms: number) { return new Promise((r) => setTimeout(r, ms)); }
function bar() { console.log("─".repeat(70)); }

async function main() {
  bar();
  console.log(`Plinth ↔ Aster L1 — Phase 3 (real trade) @ ${nowIso()}`);
  bar();

  // ============== Setup clients ==============
  const aster = new AsterClient({
    baseUrl: process.env.ASTER_BASE_URL!,
    signer: process.env.ASTER_SIGNER as Hex,
    privateKey: process.env.ASTER_PRIVATE_KEY as Hex,
    user: process.env.ASTER_USER as Hex,
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

  // ============== Pre-flight checks ==============
  console.log("\n[Pre-flight]");
  const balances = await aster.getBalance();
  const usdt = balances.find((b) => b.asset === "USDT");
  if (!usdt) throw new Error("USDT row missing from Aster balance");
  const available = parseFloat(usdt.availableBalance);
  console.log(`  Aster USDT available: ${available.toFixed(4)}`);
  if (available < 5.0) {
    throw new Error(`Aborting: available ${available} < 5 USDT required for ${SYMBOL} min notional`);
  }
  const tickStart = await aster.price(SYMBOL);
  console.log(`  ${SYMBOL} market price: ${tickStart.price}`);
  const windowStart = Date.now();

  // ============== Step 1+2: Create or resume Plinth vault ==============
  const resumeVaultId = process.env.PHASE3_VAULT_ID as Hex | undefined;
  let vaultId: Hex;
  let createTxHash: Hex = "0x0" as Hex;
  let depositTxHash: Hex = "0x0" as Hex;
  let deployTxHash: Hex = "0x0" as Hex;
  if (resumeVaultId) {
    console.log("\n[1+2/9] Resuming with existing vault…");
    vaultId = resumeVaultId;
    console.log(`     ✓ resume vaultId: ${vaultId}`);
  } else {
    console.log("\n[1/9] Creating Plinth vault on Arc Testnet…");
    const created = await agent.createVault({
      approvedVenues: [PLINTH_ARC_TESTNET.mockVenue1],
      strategyDescriptor:
        "BTC perp via Aster L1 — verifiable PnL demo. Agent opens BTCUSDT long on Aster (chainId 1666), reports realized PnL on Arc; Underwriter independently verifies via Aster trade history.",
      initialDepositWei: parseEther("0.001"),
    });
    vaultId = created.vaultId;
    createTxHash = created.txHash;
    console.log(`     ✓ vaultId : ${vaultId}`);
    console.log(`     ✓ createTx: ${created.txHash}`);

    console.log("\n[2/9] Investor deposit + agent deploy…");
    const dep = await investor.deposit(vaultId, INITIAL_VAULT_DEPOSIT_USDC);
    depositTxHash = dep.txHash;
    console.log(`     ✓ deposit tx: ${dep.txHash}  shares=${formatUsdc(dep.sharesMinted)}`);
    const deployAmount = parseEther("0.005");
    deployTxHash = await agent.deployToVenue(vaultId, PLINTH_ARC_TESTNET.mockVenue1, deployAmount);
    console.log(`     ✓ deploy  tx: ${deployTxHash}`);
  }

  // ============== Step 3: Configure Aster (margin + leverage) ==============
  console.log("\n[3/9] Configuring Aster (ISOLATED, ${LEVERAGE}x)…");
  try {
    const mt = await aster.setMarginType(SYMBOL, "ISOLATED");
    console.log(`     marginType:  ${JSON.stringify(mt).slice(0, 80)}`);
  } catch (e: any) {
    // Aster returns an error if already isolated; treat as non-fatal
    console.log(`     marginType (already set?): ${e.message.slice(0, 100)}`);
  }
  const lev = await aster.setLeverage(SYMBOL, LEVERAGE);
  console.log(`     leverage:    ${JSON.stringify(lev)}`);

  // ============== Step 4: Open Aster BTC long ==============
  console.log(`\n[4/9] OPENING ${QUANTITY} ${SYMBOL} LONG (market order, hedge mode)…`);
  const openOrder = await aster.placeMarketOrder({
    symbol: SYMBOL,
    side: "BUY",
    quantity: QUANTITY,
    positionSide: "LONG",
  });
  console.log(`     ✓ orderId: ${openOrder.orderId}  status: ${openOrder.status}`);
  console.log(`     ✓ avgPrice: ${openOrder.avgPrice ?? "(pending)"}  qty: ${openOrder.executedQty ?? openOrder.origQty}`);

  // ============== Step 5: Wait ==============
  console.log(`\n[5/9] Holding position for ${HOLD_SECONDS}s …`);
  for (let i = HOLD_SECONDS; i > 0; i -= 30) {
    await sleep(30_000);
    const tick = await aster.price(SYMBOL);
    console.log(`     t-${i}s | ${SYMBOL} = ${tick.price}`);
  }

  // ============== Step 6: Close Aster position ==============
  console.log(`\n[6/9] CLOSING position (SELL ${QUANTITY} positionSide=LONG)…`);
  const closeOrder = await aster.placeMarketOrder({
    symbol: SYMBOL,
    side: "SELL",
    quantity: QUANTITY,
    positionSide: "LONG",   // close LONG bucket: SELL same positionSide
  });
  console.log(`     ✓ orderId: ${closeOrder.orderId}  status: ${closeOrder.status}`);
  console.log(`     ✓ avgPrice: ${closeOrder.avgPrice ?? "(pending)"}`);
  const windowEnd = Date.now();

  // Give Aster a few seconds to finalize trade attribution
  await sleep(5_000);

  // ============== Step 7: Pull trades + compute realized PnL ==============
  console.log(`\n[7/9] Fetching userTrades from Aster…`);
  const trades = await aster.getUserTrades(SYMBOL, 50);
  const inWindow = trades.filter((t: any) => t.time >= windowStart && t.time <= windowEnd + 60_000);
  console.log(`     ${inWindow.length} fills in window`);
  for (const t of inWindow) {
    console.log(
      `       id=${t.id} ${t.side} ${t.qty} @ ${t.price} | realizedPnl=${t.realizedPnl} | commission=${t.commission} ${t.commissionAsset}`,
    );
  }
  const realizedPnL = inWindow.reduce((s: number, t: any) => s + parseFloat(t.realizedPnl), 0);
  const commission = inWindow.reduce((s: number, t: any) => s + Math.abs(parseFloat(t.commission)), 0);
  const netRealized = realizedPnL - commission;
  console.log(`     Σ realizedPnl: ${realizedPnL.toFixed(6)} USDT`);
  console.log(`     Σ commission:  ${commission.toFixed(6)} USDT`);
  console.log(`     net realized:  ${netRealized.toFixed(6)} USDT`);

  // ============== Step 8: reportPnL on Plinth ==============
  console.log(`\n[8/9] Calling reportPnL on Plinth…`);
  // Convert USDT → USDC at 1:1; scale to 18 decimals. Round to nearest 0.000001
  // to keep numbers tidy.
  const pnlScaled = BigInt(Math.round(netRealized * 1e18));
  const pnlTx = await agent.reportPnL(vaultId, pnlScaled);
  console.log(`     ✓ reportPnL tx: ${pnlTx}`);
  console.log(`     ✓ scaled PnL wei: ${pnlScaled.toString()}`);

  // ============== Step 9: Run verifier + post review ==============
  console.log(`\n[9/9] Running Underwriter verifier + posting review…`);
  const report = await verifier.verifyReport({
    vaultId,
    symbol: SYMBOL,
    reportedPnlWei: pnlScaled,
    windowStartMs: windowStart,
    windowEndMs: windowEnd + 60_000,
  });
  const markdown = AsterVerifier.renderMarkdown(report);

  // Persist the review locally so it can be pushed to gh-pages and used as
  // reviewUri (or referenced directly via the GitHub release asset URL).
  const reviewDir = resolve("D:\\桌面\\arc\\plinth\\docs\\reviews");
  try { writeFileSync(`${reviewDir}/${vaultId}.md`, markdown); } catch { /* dir may not exist yet */ }

  console.log(`\n--- Underwriter verdict: ${report.verdict} ---`);
  console.log(markdown);
  console.log(`---\n`);

  const reviewHash = keccak256(toBytes(markdown));
  const reviewUri = `https://ccheh.github.io/plinth/reviews/${vaultId}.md`;

  const reviewTx = await investor.postUnderwriterReview(vaultId, reviewHash, reviewUri);
  console.log(`     ✓ underwriter review tx: ${reviewTx}`);

  // ============== Summary ==============
  console.log();
  bar();
  console.log("SUMMARY — paste into submission.md:");
  bar();
  console.log(`Vault             : ${vaultId}`);
  console.log(`Plinth create tx  : ${createTxHash}`);
  console.log(`Plinth deposit tx : ${depositTxHash}`);
  console.log(`Plinth deploy tx  : ${deployTxHash}`);
  console.log(`Plinth reportPnL  : ${pnlTx}`);
  console.log(`Plinth review tx  : ${reviewTx}`);
  console.log();
  console.log(`Aster open order  : ${openOrder.orderId}`);
  console.log(`Aster close order : ${closeOrder.orderId}`);
  console.log(`Aster trade fills : ${inWindow.length}`);
  console.log(`Realized PnL      : ${netRealized.toFixed(6)} USDT`);
  console.log(`Reported on Plinth: ${(Number(pnlScaled) / 1e18).toFixed(6)} USDC`);
  console.log(`Underwriter verdict: ${report.verdict}`);
  bar();
}

main().catch((e) => {
  console.error("\nFATAL:", e.message);
  console.error("\nIf an Aster position is still OPEN, close manually at https://www.asterdex.com");
  process.exit(1);
});
