/**
 * Aster L1 trade-history verifier for the Plinth Underwriter.
 *
 * Given a vault on Plinth (Arc) whose agent claims +X USDC realized PnL from
 * trading on Aster, this module independently queries Aster's userTrades
 * endpoint, sums the realized PnL across all fills in the time window, and
 * compares to the on-Arc claim.
 *
 * Output is a structured verdict (`VerificationReport`) that the Underwriter
 * posts on chain via `postUnderwriterReview(vaultId, reviewHash, reviewUri)`.
 *
 * As of v0.6, `AsterVerifier` implements the `IPerpVerifier` interface
 * (see `perp-verifier.ts`) so the Underwriter pipeline is venue-agnostic.
 * Future verifiers — `SynthraPerpVerifier`, etc. — plug into the same
 * pipeline by implementing the same interface.
 */
import { AsterClient } from "./client.js";
import {
  IPerpVerifier,
  VerificationReport,
  VerifyReportArgs,
  VenueIdentity,
  classify,
} from "./perp-verifier.js";

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

/** Aster-specific raw data attached to `VerificationReport.venueSpecific`. */
export type AsterVenueSpecific = {
  openTrades: Trade[];
  closeTrades: Trade[];
  /** Original Aster-native values, before USDC-equivalent conversion (kept for audit). */
  realizedPnlUsdtRaw: number;
  totalCommissionUsdtRaw: number;
};

const TOLERANCE_PCT = 5;  // 5% delta accepted as "VERIFIED" (covers slippage + 18→6 decimal rounding)

const ASTER_IDENTITY: VenueIdentity = {
  name: "Aster L1",
  chain: "Aster L1",
  chainId: 1666,
  explorerNote: "Aster L1 trades are accessible via /fapi/v3/userTrades and reflect on-chain fills.",
};

export class AsterVerifier implements IPerpVerifier {
  constructor(private aster: AsterClient) {}

  readonly identity: VenueIdentity = ASTER_IDENTITY;
  readonly tolerancePct: number = TOLERANCE_PCT;

  async verifyReport(args: VerifyReportArgs): Promise<VerificationReport> {
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

    // Treat USDT ≈ USDC 1:1 for purposes of this demo; both are dollar-pegged,
    // and the agent's reportedPnL is denominated in vault USDC.
    const netRealizedUsdc = netRealizedUsdt;

    // Centralized verdict classification (shared with other verifiers).
    const { verdict, deltaAbs, deltaPct } = classify(
      reportedUsdc,
      netRealizedUsdc,
      trades.length,
      TOLERANCE_PCT,
    );

    const notes: string[] = [];
    if (fetchNote) notes.push(fetchNote);

    if (trades.length === 0 && Math.abs(reportedUsdc) >= 1e-6) {
      notes.push(
        `Agent reported ${reportedUsdc.toFixed(6)} USDC PnL but no Aster trades found in window ${new Date(start).toISOString()} → ${new Date(end).toISOString()}.`,
      );
    } else if (trades.length === 0) {
      notes.push("Zero claim + zero venue activity — vacuously consistent.");
    } else if (verdict === "VERIFIED") {
      notes.push(
        `${trades.length} trades on Aster ${args.symbol} between window. Net realized ${netRealizedUsdt.toFixed(6)} USDT vs claim ${reportedUsdc.toFixed(6)} USDC (delta ${deltaPct.toFixed(2)}%) within ${TOLERANCE_PCT}% tolerance.`,
      );
    } else if (verdict === "OVERSTATED") {
      notes.push(
        `Agent claims +${reportedUsdc.toFixed(6)} USDC but venue shows only ${netRealizedUsdt.toFixed(6)} USDT (delta ${deltaPct.toFixed(2)}%). Possible NAV inflation.`,
      );
    } else if (verdict === "UNDERSTATED") {
      notes.push(
        `Agent claims +${reportedUsdc.toFixed(6)} USDC but venue shows ${netRealizedUsdt.toFixed(6)} USDT (delta ${deltaPct.toFixed(2)}%). Less concerning but inconsistent.`,
      );
    }

    const venueSpecific: AsterVenueSpecific = {
      openTrades,
      closeTrades,
      realizedPnlUsdtRaw: realizedPnlUsdt,
      totalCommissionUsdtRaw: totalCommissionUsdt,
    };

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
        ...ASTER_IDENTITY,
        eventCount: trades.length,
        realizedPnlGrossUsdc: realizedPnlUsdt,
        totalFeesUsdc: totalCommissionUsdt,
        netRealizedUsdc,
      },
      delta: {
        absUsdc: deltaAbs,
        pct: deltaPct,
      },
      generatedAt: Date.now(),
      notes,
      venueSpecific,
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
    lines.push(`## Venue evidence (${r.venue.name}, chainId ${r.venue.chainId})`);
    lines.push(`- Event count: ${r.venue.eventCount} fills`);

    // Aster-specific detail, if present
    const av = r.venueSpecific as AsterVenueSpecific | undefined;
    if (av) {
      lines.push(`- Opens: ${av.openTrades.length}, Closes: ${av.closeTrades.length}`);
      lines.push(`- Sum realizedPnl: **${av.realizedPnlUsdtRaw.toFixed(6)} USDT**`);
      lines.push(`- Sum commissions: ${av.totalCommissionUsdtRaw.toFixed(6)} USDT`);
    } else {
      lines.push(`- Gross realized: ${r.venue.realizedPnlGrossUsdc.toFixed(6)} USDC`);
      lines.push(`- Total fees: ${r.venue.totalFeesUsdc.toFixed(6)} USDC`);
    }
    lines.push(`- **Net realized**: ${r.venue.netRealizedUsdc.toFixed(6)} USDC`);
    lines.push("");
    if (av && av.closeTrades.length > 0) {
      lines.push(`### Closing fills`);
      for (const t of av.closeTrades) {
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

// Re-export common types so existing consumers don't have to change imports.
export type { VerificationReport, VerificationVerdict } from "./perp-verifier.js";
