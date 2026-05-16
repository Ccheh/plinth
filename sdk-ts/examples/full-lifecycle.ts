/**
 * End-to-end Plinth v0 lifecycle on Arc Testnet via @plinth/sdk.
 *
 * Scenario: agent (MAIN wallet) creates a vault for "BTC perp momentum"
 * strategy. Investor (SERVICE wallet) deposits. Agent deploys to
 * MockVenue, reports +50% PnL, investor redeems at the new NAV. Auditor
 * (no key) browses the entire vault history via BrowseClient.
 *
 * ~7 on-chain txs, all costs in fractional USDC of gas.
 */

import "./_load-env.js";  // portable .env loader (looks in cwd / sdk-ts / repo root)
import { parseEther, formatEther, type Hex } from "viem";
import {
  AgentClient, InvestorClient, BrowseClient,
  PLINTH_ARC_TESTNET, ARC_TESTNET,
  formatUsdc,
} from "../src/index.js";

const AGENT_PK = process.env.PRIVATE_KEY as Hex;
const INVESTOR_PK = process.env.SERVICE_PRIVATE_KEY as Hex;
if (!AGENT_PK || !INVESTOR_PK) {
  throw new Error(
    "Missing PRIVATE_KEY / SERVICE_PRIVATE_KEY. Copy .env.example to .env at the repo root and fill in your testnet keys."
  );
}

const PLINTH = PLINTH_ARC_TESTNET.plinth;
const VENUE = PLINTH_ARC_TESTNET.mockVenue1;
const EXPLORER = ARC_TESTNET.explorer;

const agent    = new AgentClient({    privateKey: AGENT_PK,    plinthAddress: PLINTH });
const investor = new InvestorClient({ privateKey: INVESTOR_PK, plinthAddress: PLINTH });
const browser  = new BrowseClient({                            plinthAddress: PLINTH });

console.log(`AGENT    : ${agent.address}`);
console.log(`INVESTOR : ${investor.address}`);
console.log(`PLINTH   : ${PLINTH}`);
console.log(`VENUE    : ${VENUE}\n`);

// ---------- step 1: agent creates vault ----------
console.log(`Step 1: agent creates a vault (initial 0.005 USDC, 1 venue, BTC perp momentum)`);
const { txHash: createTx, vaultId } = await agent.createVault({
  approvedVenues: [VENUE],
  strategyDescriptor: "BTC perp momentum, max 3x leverage, daily rebalance",
  initialDepositWei: parseEther("0.005"),
});
console.log(`  create tx: ${EXPLORER}/tx/${createTx}`);
console.log(`  vaultId:   ${vaultId}\n`);

// ---------- step 2: investor deposits at inception NAV ----------
console.log(`Step 2: investor deposits 0.003 USDC at current NAV`);
const dep = await investor.deposit(vaultId, parseEther("0.003"));
console.log(`  deposit tx:      ${EXPLORER}/tx/${dep.txHash}`);
console.log(`  shares minted:   ${formatUsdc(dep.sharesMinted)} (predicted: ${formatUsdc(dep.predictedShares)})`);
console.log(`  NAV at deposit:  ${formatUsdc(dep.navAtDeposit)} USDC/share\n`);

// ---------- step 3: agent deploys capital to venue ----------
console.log(`Step 3: agent deploys 0.006 USDC to venue`);
const depTx = await agent.deployToVenue(vaultId, VENUE, parseEther("0.006"));
console.log(`  deploy tx: ${EXPLORER}/tx/${depTx}\n`);

// ---------- step 4: agent reports +PnL ----------
console.log(`Step 4: agent reports +0.003 USDC PnL (~50% gain on deployed AUM)`);
const pnlTx = await agent.reportPnL(vaultId, parseEther("0.003"));
console.log(`  reportPnL tx: ${EXPLORER}/tx/${pnlTx}\n`);

// ---------- step 5: check NAV ----------
const navNow = await investor.getNAV(vaultId);
console.log(`Step 5: vault NAV now = ${formatUsdc(navNow)} USDC/share (was 1.0 at inception)`);
const recomputed = await investor.getNAVRecomputed(vaultId);
console.log(`        re-computed NAV: ${formatUsdc(recomputed)} (sanity check)\n`);

// ---------- step 6: investor redeems half of their shares ----------
console.log(`Step 6: investor redeems half of their shares`);
const halfShares = dep.sharesMinted / 2n;
// Need vault to have enough liquid USDC. inVault is currently 0.002 (8 - 6 deployed).
// Redeem half of 0.003 worth at 1.something NAV → ~0.002 USDC. Might be tight.
// Agent first returns some funds to make sure redemption works.
console.log(`        (first: agent returns 0.003 from venue to ensure liquidity)`);
// Note: MockVenue holds the deployed funds. We can simulate the venue
// returning capital by sending it back to Plinth via returnFromVenue.
// In this demo we have the agent do it (could be anyone if we control the venue).
//
// For the actual MockVenue we deployed, anyone can call its returnFunds.
// But we need to first SEND msg.value to Plinth. The cleanest path: agent
// transfers from their own wallet to simulate it, then calls returnFromVenue.
const returnTx = await agent.returnFromVenue(vaultId, VENUE, parseEther("0.003"));
console.log(`        returnFromVenue tx: ${EXPLORER}/tx/${returnTx}`);

const red = await investor.redeem(vaultId, halfShares);
console.log(`  redeem tx:       ${EXPLORER}/tx/${red.txHash}`);
console.log(`  USDC out:        ${formatUsdc(red.usdcOut)} (predicted: ${formatUsdc(red.predictedUsdcOut)})`);
console.log(`  NAV at redeem:   ${formatUsdc(red.navAtRedeem)} USDC/share\n`);

// ---------- step 7: investor posts an underwriter review (acts as a 3rd-party here) ----------
console.log(`Step 7: 3rd-party posts an underwriter review for this vault`);
const fakeReviewHash = "0x" + "ab".repeat(32) as Hex;
const reviewUri = "ipfs://demo-review-Qm123abc";
const reviewTx = await investor.postUnderwriterReview(vaultId, fakeReviewHash, reviewUri);
console.log(`  review tx: ${EXPLORER}/tx/${reviewTx}\n`);

// ---------- step 8: browser enumerates vaults + reviews ----------
console.log(`Step 8: BrowseClient enumerates the protocol state`);
// Start from a recent block to keep getLogs cheap on Arc Testnet
const fromBlock = await investor.publicClient.getBlockNumber();
const vaultsList = await browser.listAllVaults(fromBlock - 5000n, "latest", true);
console.log(`  ${vaultsList.length} vault(s) found in the last 5000 blocks:`);
for (const v of vaultsList) {
  console.log(`    [${v.vaultId.slice(0, 10)}...] agent=${v.agent.slice(0, 10)}...`);
  console.log(`      strategy: "${v.strategyDescriptor.slice(0, 60)}..."`);
  if (v.state) {
    console.log(`      totalShares=${formatUsdc(v.state.totalShares)} inVault=${formatUsdc(v.state.inVault)} deployedAUM=${formatUsdc(v.state.deployedAUM)} reportedPnL=${formatUsdc(v.state.reportedPnL)}`);
  }
  if (v.nav !== undefined) console.log(`      current NAV: ${formatUsdc(v.nav)} USDC/share`);
}

const reviews = await browser.listReviews(vaultId, fromBlock - 5000n);
console.log(`\n  ${reviews.length} underwriter review(s) for our vault:`);
for (const r of reviews) {
  console.log(`    by ${r.underwriter} → ${r.reviewUri} (block ${r.blockNumber})`);
}

// ---------- summary ----------
console.log(`\n================== SUMMARY ==================`);
console.log(`Plinth v0 lifecycle ran end-to-end on Arc Testnet via @plinth/sdk:`);
console.log(`  - createVault:    ${createTx}`);
console.log(`  - deposit:        ${dep.txHash}`);
console.log(`  - deployToVenue:  ${depTx}`);
console.log(`  - reportPnL:      ${pnlTx}`);
console.log(`  - returnFromVenue:${returnTx}`);
console.log(`  - redeem:         ${red.txHash}`);
console.log(`  - postReview:     ${reviewTx}`);
console.log(`\nFinal state of vault ${vaultId}:`);
const finalV = await investor.getVault(vaultId);
console.log(`  totalShares:    ${formatUsdc(finalV.totalShares)}`);
console.log(`  inVault:        ${formatUsdc(finalV.inVault)} USDC`);
console.log(`  deployedAUM:    ${formatUsdc(finalV.deployedAUM)} USDC`);
console.log(`  reportedPnL:    ${formatUsdc(finalV.reportedPnL)} USDC`);
console.log(`  current NAV:    ${formatUsdc(await investor.getNAV(vaultId))} USDC/share`);
console.log(`  investor shares:${formatUsdc(await investor.sharesOf(vaultId))}`);
console.log(`\nVerifiable: ${EXPLORER}/address/${PLINTH}#events`);
