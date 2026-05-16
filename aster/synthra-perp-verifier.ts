/**
 * SynthraPerpVerifier — scaffold for verifying agent reportedPnL against
 * Synthra Perp trade history on Arc.
 *
 * Synthra Perp is an Arc-native hybrid AMM+orderbook perpetuals venue
 * (subgraph: https://subgraph.synthra.org/subgraphs/name/arc-testnet/synthra-perps/,
 * backend: https://perps-backend.synthra.org, WS events: wss://perps-backend.synthra.org/ws/events).
 *
 * Status (May 2026): Synthra Perp is DEPLOYED on Arc Testnet — 15 hybrid* contracts
 * are live (hybridOrderBook, hybridPositionBook, hybridMarginVault, etc., addresses
 * documented in synthra-front/src/constants/perps.ts). The Synthra Perp ABI for
 * external integrators is not yet stabilized / publicly documented at the level
 * of "what events do I parse to know a trader's realized PnL". The verifier sits
 * as a SCAFFOLD that implements IPerpVerifier and returns INCONCLUSIVE until the
 * real query layer is wired.
 *
 * The advantage of Synthra-on-Arc vs Aster-cross-chain (which the AsterVerifier
 * targets today): no cross-chain hop. The verifier queries Arc-native subgraph
 * / position book directly. When Synthra publishes a stable event schema or
 * documents the subgraph types, fill in `_querySynthraPnL` below.
 */
import { type PublicClient } from "viem";
import {
  IPerpVerifier,
  VerificationReport,
  VerifyReportArgs,
  VenueIdentity,
  classify,
} from "./perp-verifier.js";

const SYNTHRA_PERP_IDENTITY: VenueIdentity = {
  name: "Synthra Perp on Arc",
  chain: "Arc Testnet",
  chainId: 5042002,
  explorerNote:
    "Synthra Perp trades are recorded on Arc and indexed at subgraph.synthra.org/subgraphs/name/arc-testnet/synthra-perps/; positions live in hybridPositionBook at 0x705c3374730b502084f46d6790cdca327ea1a577.",
};

/** Configurable endpoint + chain config — defaults wired to Synthra's prod testnet stack. */
export type SynthraVerifierConfig = {
  subgraphUrl?: string;
  backendUrl?: string;
  rpcClient?: PublicClient;
  /** Override the default 5% delta-tolerance for VERIFIED. */
  tolerancePct?: number;
};

const DEFAULT_SUBGRAPH_URL =
  "https://subgraph.synthra.org/subgraphs/name/arc-testnet/synthra-perps/";

export class SynthraPerpVerifier implements IPerpVerifier {
  readonly identity: VenueIdentity = SYNTHRA_PERP_IDENTITY;
  readonly tolerancePct: number;

  constructor(private cfg: SynthraVerifierConfig = {}) {
    this.tolerancePct = cfg.tolerancePct ?? 5;
  }

  async verifyReport(args: VerifyReportArgs): Promise<VerificationReport> {
    const end = args.windowEndMs ?? Date.now();
    const start = args.windowStartMs;
    const reportedUsdc = Number(args.reportedPnlWei) / 1e18;

    // Query Synthra for trade history. Returns null in scaffold mode.
    const synthraPnL = await this._querySynthraPnL(args.symbol, start, end);

    const notes: string[] = [];

    if (synthraPnL === null) {
      // Scaffold mode: emit INCONCLUSIVE with a clear note. Underwriter pipeline
      // can either skip or fall back to LLM/risk-monitor review.
      notes.push(
        "SynthraPerpVerifier is in scaffold mode — subgraph schema for trader PnL not yet wired. Once Synthra publishes the trader-side subgraph types, implement `_querySynthraPnL` to return { realizedPnlGrossUsdc, totalFeesUsdc, eventCount }.",
      );
      return {
        verdict: "INCONCLUSIVE",
        vaultId: args.vaultId,
        symbol: args.symbol,
        windowStart: start,
        windowEnd: end,
        claim: {
          reportedPnlWei: args.reportedPnlWei.toString(),
          reportedPnlUsdc: reportedUsdc,
        },
        venue: {
          ...SYNTHRA_PERP_IDENTITY,
          eventCount: 0,
          realizedPnlGrossUsdc: 0,
          totalFeesUsdc: 0,
          netRealizedUsdc: 0,
        },
        delta: { absUsdc: Math.abs(reportedUsdc), pct: 100 },
        generatedAt: Date.now(),
        notes,
        venueSpecific: { stub: true, subgraphUrl: this.cfg.subgraphUrl ?? DEFAULT_SUBGRAPH_URL },
      };
    }

    const netRealizedUsdc = synthraPnL.realizedPnlGrossUsdc - synthraPnL.totalFeesUsdc;
    const { verdict, deltaAbs, deltaPct } = classify(
      reportedUsdc,
      netRealizedUsdc,
      synthraPnL.eventCount,
      this.tolerancePct,
    );

    notes.push(
      `${synthraPnL.eventCount} position events on Synthra ${args.symbol}. Net realized ${netRealizedUsdc.toFixed(6)} USDC vs claim ${reportedUsdc.toFixed(6)} USDC (delta ${deltaPct.toFixed(2)}%).`,
    );

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
        ...SYNTHRA_PERP_IDENTITY,
        eventCount: synthraPnL.eventCount,
        realizedPnlGrossUsdc: synthraPnL.realizedPnlGrossUsdc,
        totalFeesUsdc: synthraPnL.totalFeesUsdc,
        netRealizedUsdc,
      },
      delta: { absUsdc: deltaAbs, pct: deltaPct },
      generatedAt: Date.now(),
      notes,
      venueSpecific: { source: "synthra-subgraph", events: synthraPnL.events ?? [] },
    };
  }

  /**
   * Query Synthra for trader PnL. Returns null in scaffold mode.
   *
   * When implementing for real: query the Synthra perps subgraph for
   * PositionDecrease events (or equivalent) by trader address (or by
   * Plinth-vault adapter address) in the time window, sum realized PnL
   * minus fees. Use `cfg.subgraphUrl` (default = Synthra's testnet subgraph).
   */
  private async _querySynthraPnL(
    _symbol: string,
    _windowStartMs: number,
    _windowEndMs: number,
  ): Promise<{
    eventCount: number;
    realizedPnlGrossUsdc: number;
    totalFeesUsdc: number;
    events?: unknown[];
  } | null> {
    // TODO: Implement once Synthra publishes a stable trader-side schema.
    //
    // Reference query shape (to be confirmed against Synthra's subgraph):
    //
    //   query TraderEvents($trader: String!, $start: BigInt!, $end: BigInt!) {
    //     positionDecreaseEvents(
    //       where: { trader: $trader, timestamp_gte: $start, timestamp_lte: $end }
    //     ) {
    //       id timestamp realizedPnl size feeAmount
    //     }
    //   }
    //
    return null;
  }
}
