/**
 * Aster L1 trade-history verifier for the Plinth Underwriter.
 *
 * Given a vault on Plinth (Arc) whose agent claims +X USDC realized PnL from
 * trading on Aster, this module independently queries Aster's userTrades
 * endpoint, sums the realized PnL across all fills in the time window, and
 * compares to the on-Arc claim.
 *
 * Output is a structured verdict that the Underwriter posts on chain via
 * postUnderwriterReview(vaultId, reviewHash, reviewUri).
 */
import { AsterClient } from "./client.js";

export type Trade = {
  id: number;
  orderId: number;
  symbol: string;
  side: "BUY" | "SELL";
  price: string;
  qty: string;
  quoteQty: string;
  realizedPnl: string;
  commission: string;
  commissionAsset: string;
  time: number;
  buyer: boolean;
  maker: boolean;
};

export type VerificationVerdict =
  | "VERIFIED"          // claim matches venue history within tolerance
  | "OVERSTATED"        // claim higher than venue history
  | "UNDERSTATED"       // claim lower than venue history (less concerning but suspicious)
  | "NO_VENUE_ACTIVITY" // claim made but zero trades found on Aster
  | "INCONCLUSIVE";     // partial data, can't decide

export type VerificationReport = {
  verdict: VerificationVerdict;
  vaultId: string;
  symbol: string;
  windowStart: number;
  windowEnd: number;
  claim: {
    reportedPnlWei: string;      // raw on-chain reportedPnL (18 dec)
    reportedPnlUsdc: number;     // human-readable
  };
  venue: {
    chain: "Aster L1";
    chainId: 1666;
    explorerNote: string;
    tradeCount: number;
    openTrades: Trade[];
    closeTrades: Trade[];
    realizedPnlUsdt: number;
    totalCommissionUsdt: number;
    netRealizedUsdt: number;      // realized - commissions
  };
  delta: {
    absUsdc: number;              // |reported - venue net|
    pct: number;                  // delta / max(|reported|, |venue|) * 100
  };
  generatedAt: number;
  notes: string[];
};

const TOLERANCE_PCT = 5;  // 5% delta accepted as "VERIFIED" (covers slippage + 18→6 decimal rounding)

export class AsterVerifier {
  constructor(private aster: AsterClient) {}

  async verifyReport(args: {
    vaultId: string;
    symbol: string;
    reportedPnlWei: bigint;      // signed
    windowStartMs: number;
    windowEndMs?: number;
  }): Promise<VerificationReport> {
    const end = args.windowEndMs ?? Date.now();
    const start = args.windowStartMs;

    const reportedUsdc = Number(args.reportedPnlWei) / 1e18;

    let trades: Trade[] = [];
    let fetchNote = "";
    try {
      trades = await this.aster.getUserTrades(args.symbol, 1000);
      // Filter to time window. Aster returns most recent 500-1000 by default;
      // we request 1000 and filter in code (per Aster docs, no startTime/endTime
      // filter is available when fromId is used; we use neither and just slice).
      trades = trades.filter((t) => t.time >= start && t.time <= end);
    } catch (e: any) {
      fetchNote = `Aster userTrades fetch failed: ${e.message}`;
    }

    // Split fills by closing vs opening. On Aster perps:
    //   realizedPnl != 0  → this fill was (at least partially) closing a position
    //   realizedPnl == 0  → opening (or adding to) a position
    const openTrades = trades.filter((t) => parseFloat(t.realizedPnl) === 0);
    const closeTrades = trades.filter((t) => parseFloat(t.realizedPnl) !== 0);

    const realizedPnlUsdt = closeTrades.reduce(
      (sum, t) => sum + parseFloat(t.realizedPnl),
      0,
    );
    const totalCommissionUsdt = trades.reduce(
      (sum, t) => sum + Math.abs(parseFloat(t.commission)),
      0,
    );
    const netRealizedUsdt = realizedPnlUsdt - totalCommissionUsdt;

    // Compute delta against reported (treating USDT ≈ USDC 1:1 for purposes of this demo;
    // both are dollar-pegged, and the agent's reportedPnL is denominated in vault USDC).
    const absDelta = Math.abs(reportedUsdc - netRealizedUsdt);
    const denom = Math.max(Math.abs(reportedUsdc), Math.abs(netRealizedUsdt), 1e-9);
    const pct = (absDelta / denom) * 100;

    let verdict: VerificationVerdict;
    const notes: string[] = [];

    if (fetchNote) notes.push(fetchNote);

    if (trades.length === 0) {
      if (Math.abs(reportedUsdc) < 1e-6) {
        verdict = "VERIFIED";
        notes.push("Zero claim + zero venue activity — vacuously consistent.");
      } else {
        verdict = "NO_VENUE_ACTIVITY";
        notes.push(
          `Agent reported ${reportedUsdc.toFixed(6)} USDC PnL but no Aster trades found in window ${new Date(start).toISOString()} → ${new Date(end).toISOString()}.`,
        );
      }
    } else if (pct <= TOLERANCE_PCT) {
      verdict = "VERIFIED";
      notes.push(
        `${trades.length} trades on Aster ${args.symbol} between window. Net realized ${netRealizedUsdt.toFixed(6)} USDT vs claim ${reportedUsdc.toFixed(6)} USDC (delta ${pct.toFixed(2)}%) within ${TOLERANCE_PCT}% tolerance.`,
      );
    } else if (reportedUsdc > netRealizedUsdt) {
      verdict = "OVERSTATED";
      notes.push(
        `Agent claims +${reportedUsdc.toFixed(6)} USDC but venue shows only ${netRealizedUsdt.toFixed(6)} USDT (delta ${pct.toFixed(2)}%). Possible NAV inflation.`,
      );
    } else {
      verdict = "UNDERSTATED";
      notes.push(
        `Agent claims +${reportedUsdc.toFixed(6)} USDC but venue shows ${netRealizedUsdt.toFixed(6)} USDT (delta ${pct.toFixed(2)}%). Less concerning but inconsistent.`,
      );
    }

    return {
      verdict,
      vaultId: args.vaultId,
      symbol: args.symbol,
      windowStart: start,
      windowEnd: end,
      claim: {
        reportedPnlWei: args.reportedPnlWei.toString(),
        reportedPnlUsdc: reportedUsdc,
      },
      venue: {
        chain: "Aster L1",
        chainId: 1666,
        explorerNote: "Aster L1 trades are accessible via /fapi/v3/userTrades and reflect on-chain fills.",
        tradeCount: trades.length,
        openTrades,
        closeTrades,
        realizedPnlUsdt,
        totalCommissionUsdt,
        netRealizedUsdt,
      },
      delta: {
        absUsdc: absDelta,
        pct,
      },
      generatedAt: Date.now(),
      notes,
    };
  }

  /**
   * Renders the verdict as a human-readable summary suitable for posting as
   * reviewUri content (or pasting into a GitHub release note / submission).
   */
  static renderMarkdown(r: VerificationReport): string {
    const lines: string[] = [];
    lines.push(`# Underwriter Review — Aster L1 PnL Verification`);
    lines.push("");
    lines.push(`**Verdict**: \`${r.verdict}\``);
    lines.push(`**Vault**: \`${r.vaultId}\``);
    lines.push(`**Symbol**: ${r.symbol}`);
    lines.push(
      `**Window**: ${new Date(r.windowStart).toISOString()} → ${new Date(r.windowEnd).toISOString()}`,
    );
    lines.push("");
    lines.push(`## Agent's claim (on-chain, Arc)`);
    lines.push(`- Reported PnL: **${r.claim.reportedPnlUsdc.toFixed(6)} USDC**`);
    lines.push(`- Raw wei: \`${r.claim.reportedPnlWei}\``);
    lines.push("");
    lines.push(`## Venue evidence (Aster L1, chainId 1666)`);
    lines.push(`- Trade count: ${r.venue.tradeCount} fills`);
    lines.push(`- Opens: ${r.venue.openTrades.length}, Closes: ${r.venue.closeTrades.length}`);
    lines.push(`- Sum realizedPnl: **${r.venue.realizedPnlUsdt.toFixed(6)} USDT**`);
    lines.push(`- Sum commissions: ${r.venue.totalCommissionUsdt.toFixed(6)} USDT`);
    lines.push(`- **Net realized**: ${r.venue.netRealizedUsdt.toFixed(6)} USDT`);
    lines.push("");
    if (r.venue.closeTrades.length > 0) {
      lines.push(`### Closing fills`);
      for (const t of r.venue.closeTrades) {
        lines.push(
          `- id ${t.id} | ${t.side} ${t.qty} @ ${t.price} → realizedPnl ${t.realizedPnl} (${new Date(t.time).toISOString()})`,
        );
      }
      lines.push("");
    }
    lines.push(`## Delta`);
    lines.push(`- Absolute: ${r.delta.absUsdc.toFixed(6)} USDC`);
    lines.push(`- Percent : ${r.delta.pct.toFixed(2)}%`);
    lines.push(`- Tolerance: ${TOLERANCE_PCT}%`);
    lines.push("");
    lines.push(`## Notes`);
    for (const n of r.notes) lines.push(`- ${n}`);
    lines.push("");
    lines.push(`Generated at ${new Date(r.generatedAt).toISOString()} by Plinth Underwriter Aster Verifier v0.`);
    return lines.join("\n");
  }
}
