/**
 * @plinth/verifier-core/aster — Aster L1 reference implementation of IPerpVerifier.
 *
 * Aster L1 is a public-chain perp DEX (chainId 1666) used as the v0 demo
 * venue in Plinth. This verifier queries the Aster userTrades REST endpoint
 * to independently compute realized PnL across an agent's fills in a time
 * window, and reconciles that against the agent's reported PnL on Plinth
 * (Arc Testnet).
 *
 * The pattern generalizes: implement the same `verifyReport(...)` shape
 * against any public-chain venue, and any protocol building Plinth-style
 * verifiable funds can reuse the Underwriter pipeline unchanged.
 */
import {
  type IPerpVerifier,
  type VerificationReport,
  type VerifyReportArgs,
  type VenueIdentity,
  classify,
} from "../index.js";

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

export type AsterVenueSpecific = {
  openTrades: Trade[];
  closeTrades: Trade[];
  realizedPnlUsdtRaw: number;
  totalCommissionUsdtRaw: number;
};

/// Minimal Aster client surface — the verifier only needs read-side userTrades.
export interface AsterClientLike {
  getUserTrades(symbol: string, limit?: number): Promise<Trade[]>;
}

export type AsterVerifierConfig = {
  client: AsterClientLike;
  tolerancePct?: number;
};

const ASTER_IDENTITY: VenueIdentity = {
  name: "Aster L1",
  chain: "Aster L1",
  chainId: 1666,
  explorerNote:
    "Aster L1 trades are accessible via /fapi/v3/userTrades and reflect on-chain fills.",
};

export class AsterVerifier implements IPerpVerifier {
  readonly identity: VenueIdentity = ASTER_IDENTITY;
  readonly tolerancePct: number;

  constructor(private cfg: AsterVerifierConfig) {
    this.tolerancePct = cfg.tolerancePct ?? 5;
  }

  async verifyReport(args: VerifyReportArgs): Promise<VerificationReport> {
    const end = args.windowEndMs ?? Date.now();
    const start = args.windowStartMs;
    const reportedUsdc = Number(args.reportedPnlWei) / 1e18;

    let trades: Trade[] = [];
    let fetchNote = "";
    try {
      trades = await this.cfg.client.getUserTrades(args.symbol, 1000);
      trades = trades.filter((t) => t.time >= start && t.time <= end);
    } catch (e: any) {
      fetchNote = `Aster userTrades fetch failed: ${e.message}`;
    }

    const openTrades = trades.filter((t) => parseFloat(t.realizedPnl) === 0);
    const closeTrades = trades.filter((t) => parseFloat(t.realizedPnl) !== 0);

    const realizedPnlUsdt = closeTrades.reduce(
      (sum, t) => sum + parseFloat(t.realizedPnl), 0
    );
    const totalCommissionUsdt = trades.reduce(
      (sum, t) => sum + Math.abs(parseFloat(t.commission)), 0
    );
    const netRealizedUsdc = realizedPnlUsdt - totalCommissionUsdt;

    const { verdict, deltaAbs, deltaPct } = classify(
      reportedUsdc,
      netRealizedUsdc,
      trades.length,
      this.tolerancePct,
    );

    const notes: string[] = [];
    if (fetchNote) notes.push(fetchNote);
    if (trades.length === 0 && Math.abs(reportedUsdc) >= 1e-6) {
      notes.push(
        `Agent reported ${reportedUsdc.toFixed(6)} USDC PnL but no Aster trades found in window ${new Date(start).toISOString()} → ${new Date(end).toISOString()}.`,
      );
    } else if (trades.length > 0 && verdict === "VERIFIED") {
      notes.push(
        `${trades.length} trades on Aster ${args.symbol}. Net realized ${netRealizedUsdc.toFixed(6)} USDC vs claim ${reportedUsdc.toFixed(6)} USDC (delta ${deltaPct.toFixed(2)}%) within ${this.tolerancePct}% tolerance.`,
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
      delta: { absUsdc: deltaAbs, pct: deltaPct },
      generatedAt: Date.now(),
      notes,
      venueSpecific,
    };
  }
}
