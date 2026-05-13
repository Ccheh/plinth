/**
 * Verifies the Aster API credentials in D:\桌面\arc\.env.
 *
 * Does 3 checks (no orders placed):
 *   1. Public ping       — confirms baseUrl is reachable
 *   2. Public price      — fetches BTCUSDT price (informational)
 *   3. Signed /balance   — confirms the API wallet is registered to the master
 *                          and reads back the USDT balance available for trading
 */
import { config } from "dotenv";
import { resolve } from "node:path";
import { AsterClient } from "./client.js";
import type { Hex } from "viem";

config({ path: resolve("D:\\桌面\\arc\\.env") });

function need(name: string): string {
  const v = process.env[name];
  if (!v || v.startsWith("0x_PASTE")) {
    throw new Error(`Missing env var: ${name} (or still has the placeholder)`);
  }
  return v;
}

async function main() {
  const cfg = {
    baseUrl: need("ASTER_BASE_URL"),
    user: process.env.ASTER_USER as Hex | undefined,
    signer: need("ASTER_SIGNER") as Hex,
    privateKey: need("ASTER_PRIVATE_KEY") as Hex,
  };

  console.log("=".repeat(60));
  console.log("Plinth ↔ Aster Mainnet (Aster L1) credential verification");
  console.log("=".repeat(60));
  console.log("baseUrl :", cfg.baseUrl);
  console.log("user    :", cfg.user, "(master — kept for verification, not sent in API)");
  console.log("signer  :", cfg.signer, "(API wallet — does the actual signing)");
  console.log();

  const client = new AsterClient(cfg);
  console.log("✓ privateKey → signer mapping verified");
  console.log();

  // 1. Public ping
  console.log("[1/3] Public reachability check");
  try {
    const t = await client.serverTime();
    const drift = Date.now() - t.serverTime;
    console.log(`     serverTime = ${t.serverTime}  (drift ${drift}ms)`);
  } catch (e: any) {
    console.error("     FAIL:", e.message);
    process.exit(1);
  }
  console.log();

  // 2. BTC price snapshot
  console.log("[2/3] BTCUSDT market price");
  try {
    const p = await client.price("BTCUSDT");
    console.log(`     BTCUSDT = ${p.price} USDT`);
  } catch (e: any) {
    console.error("     FAIL:", e.message);
  }
  console.log();

  // 3. Signed read — the real credential test
  console.log("[3/3] Signed /fapi/v3/balance");
  try {
    const balances = await client.getBalance();
    if (!Array.isArray(balances)) {
      console.log("     unexpected shape:", JSON.stringify(balances).slice(0, 200));
      process.exit(1);
    }
    if (balances.length === 0) {
      console.log("     ⚠ wallet has no asset records — testnet faucet not yet credited?");
    }
    for (const b of balances) {
      const bal = parseFloat(b.balance);
      const free = parseFloat(b.availableBalance);
      console.log(`     ${b.asset.padEnd(6)} balance=${bal.toFixed(4)}  available=${free.toFixed(4)}`);
    }
    const usdt = balances.find((b) => b.asset === "USDT");
    if (usdt && parseFloat(usdt.availableBalance) >= 5) {
      console.log();
      console.log("     ✓ ≥5 USDT available — enough for one 0.001 BTC perp demo trade");
    } else if (usdt) {
      console.log();
      console.log(
        `     ⚠ available USDT (${usdt.availableBalance}) is below 5 USDT minimum position size`,
      );
      console.log("       fund the master account from https://www.asterdex-testnet.com/en/faucet");
    }
  } catch (e: any) {
    console.error("     FAIL:", e.message);
    console.error();
    console.error("Common causes:");
    console.error("  - ASTER_SIGNER is not authorized for ASTER_USER on Aster");
    console.error("    → re-create at https://www.asterdex-testnet.com/en/api-wallet");
    console.error("  - clock drift > 10s between local and Aster server");
    console.error("  - master account never connected to Aster testnet UI");
    process.exit(1);
  }

  console.log();
  console.log("=".repeat(60));
  console.log("All checks passed. Credentials are wired up.");
  console.log("Next: `npx tsx demo-trade.ts` to open + close one real BTC perp.");
  console.log("=".repeat(60));
}

main().catch((e) => {
  console.error("Unhandled error:", e);
  process.exit(1);
});
