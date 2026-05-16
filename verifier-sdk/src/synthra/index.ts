/**
 * @plinth/verifier-core/synthra — Synthra Perp on Arc Testnet implementation.
 *
 * Status: SCAFFOLD. Synthra Perp is deployed on Arc Testnet (15 hybrid*
 * contracts live as of May 2026), and the perps subgraph URL is published
 * at https://subgraph.synthra.org/subgraphs/name/arc-testnet/synthra-perps/.
 * The trader-side subgraph schema has not yet been documented; this verifier
 * implements the IPerpVerifier interface but returns INCONCLUSIVE until
 * `_querySynthraPnL` is wired against the real schema.
 *
 * The advantage of Synthra-on-Arc vs Aster cross-chain: no cross-chain
 * hop. Underwriter queries Arc-native subgraph directly.
 */
import {
  type IPerpVerifier,
  type VerificationReport,
  type VerifyReportArgs,
  type VenueIdentity,
  classify,
} from "../index.js";

const SYNTHRA_PERP_IDENTITY: VenueIdentity = {
  name: "Synthra Perp on Arc",
  chain: "Arc Testnet",
  chainId: 5042002,
  explorerNote:
    "Synthra Perp trades are recorded on Arc and indexed at subgraph.synthra.org/subgraphs/name/arc-testnet/synthra-perps/; positions live in hybridPositionBook at 0x705c3374730b502084f46d6790cdca327ea1a577.",
};

export type SynthraVerifierConfig = {
  subgraphUrl?: string;
  backendUrl?: string;
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

    const synthraPnL = await this._querySynthraPnL(args.symbol, start, end);

    const notes: string[] = [];

    if (synthraPnL === null) {
      notes.push(
        "SynthraPerpVerifier is in scaffold mode — subgraph schema for trader PnL not yet wired. Implement `_querySynthraPnL` to enable verification.",
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
    // TODO: implement against Synthra's trader-side subgraph schema once published.
    return null;
  }
}
