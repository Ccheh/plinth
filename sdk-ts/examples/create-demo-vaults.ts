/**
 * Generates a small population of demonstration vaults on Arc Testnet so the
 * public Plinth web UI has interesting content for hackathon judges and
 * curious visitors. All activity is real on-chain — the multiple "agents"
 * are different vaults under the same MAIN wallet, but with distinctive
 * strategy descriptors so the gallery looks diverse.
 *
 * Demo vaults created here:
 *   1. "ETH/USDC mean reversion, 1x cash, slow rebalance"   (low risk demo)
 *   2. "SOL perp grid bot, 2x leverage, ±5% bands"            (medium risk)
 *   3. "Multi-asset arbitrage agent (CCTP routes)"            (no PnL yet)
 *
 * Plus a second SERVICE-wallet investor deposit into the existing vault so
 * traction numbers are slightly more interesting.
 *
 * Run: npx tsx examples/create-demo-vaults.ts
 */

import { parseEther, type Hex } from "viem";
import "./_load-env.js";  // portable .env loader (looks in cwd / sdk-ts / repo root)
import {
  AgentClient, InvestorClient,
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
const V1 = PLINTH_ARC_TESTNET.mockVenue1;
const V2 = PLINTH_ARC_TESTNET.mockVenue2;
const EXPLORER = ARC_TESTNET.explorer;

const agent = new AgentClient({ privateKey: AGENT_PK, plinthAddress: PLINTH });
const investor = new InvestorClient({ privateKey: INVESTOR_PK, plinthAddress: PLINTH });

console.log(`AGENT:    ${agent.address}`);
console.log(`INVESTOR: ${investor.address}\n`);

// Vault 2 — low risk mean reversion
console.log(`Creating vault 2: ETH/USDC mean reversion`);
const v2 = await agent.createVault({
  approvedVenues: [V1, V2],
  strategyDescriptor: "ETH/USDC mean reversion, 1x cash, slow weekly rebalance, max 20% drawdown",
  initialDepositWei: parseEther("0.005"),
});
console.log(`  tx: ${EXPLORER}/tx/${v2.txHash}`);
console.log(`  id: ${v2.vaultId}\n`);

// Vault 3 — medium risk perp grid
console.log(`Creating vault 3: SOL perp grid bot`);
const v3 = await agent.createVault({
  approvedVenues: [V1],
  strategyDescriptor: "SOL perp grid bot, 2x leverage, ±5% bands, kill switch on -15% daily drawdown",
  initialDepositWei: parseEther("0.003"),
});
console.log(`  tx: ${EXPLORER}/tx/${v3.txHash}`);
console.log(`  id: ${v3.vaultId}\n`);

// Vault 4 — multi-asset arb
console.log(`Creating vault 4: Multi-asset arb (CCTP routes)`);
const v4 = await agent.createVault({
  approvedVenues: [V1, V2],
  strategyDescriptor: "Multi-asset cross-chain arbitrage via Circle CCTP. Conservative position sizing, fee-aware.",
  initialDepositWei: parseEther("0.002"),
});
console.log(`  tx: ${EXPLORER}/tx/${v4.txHash}`);
console.log(`  id: ${v4.vaultId}\n`);

// Add an additional investor deposit into vault 2 for traction visibility
console.log(`Investor adds 0.002 USDC to vault 2 (mean reversion)`);
const dep = await investor.deposit(v2.vaultId, parseEther("0.002"));
console.log(`  tx: ${EXPLORER}/tx/${dep.txHash}`);
console.log(`  shares minted: ${formatUsdc(dep.sharesMinted)}\n`);

// Have vault 3 (SOL grid) deploy + report some PnL so NAV moves
console.log(`Vault 3 deploys 0.002 to venue1 + reports +0.001 PnL`);
const dep3 = await agent.deployToVenue(v3.vaultId, V1, parseEther("0.002"));
console.log(`  deploy tx:    ${EXPLORER}/tx/${dep3}`);
const pnl3 = await agent.reportPnL(v3.vaultId, parseEther("0.001"));
console.log(`  reportPnL tx: ${EXPLORER}/tx/${pnl3}\n`);

console.log(`================== SUMMARY ==================`);
console.log(`4 vaults now live on Plinth at ${PLINTH}:`);
console.log(`  Vault 1 (existing): BTC perp momentum`);
console.log(`  Vault 2 (new):      ETH/USDC mean reversion          ${v2.vaultId}`);
console.log(`  Vault 3 (new):      SOL perp grid bot (deployed+PnL) ${v3.vaultId}`);
console.log(`  Vault 4 (new):      Multi-asset arbitrage             ${v4.vaultId}`);
console.log(`\nBrowsable at: https://ccheh.github.io/plinth/`);
