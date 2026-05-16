/**
 * IPerpVerifier — generic interface for perpetual-trading venue verifiers.
 *
 * Plinth's Underwriter pattern: an off-chain agent reads trade history from a
 * venue (Aster L1, Synthra perp on Arc, any future Arc-native perp DEX),
 * computes realized PnL, and reconciles it against the agent's reportedPnL
 * on Plinth. This file factors that contract out so multiple venues can plug
 * into the same Underwriter pipeline.
 *
 * Concrete implementations:
 *   - AsterVerifier (verifier.ts)           → cross-chain via Aster L1 userTrades REST API
 *   - SynthraPerpVerifier (stub, this dir)  → Arc-native via Synthra subgraph + position-book
 *
 * The interface is intentionally venue-agnostic at the call site; venue-specific
 * details (trade schema, chain id, API endpoints) live in the implementation.
 */

/** Top-level verdict produced by any verifier. Venue-agnostic. */
export type VerificationVerdict =
  | "VERIFIED"          // claim matches venue history within tolerance
  | "OVERSTATED"        // claim higher than venue history (red flag)
  | "UNDERSTATED"       // claim lower than venue history (less concerning but suspicious)
  | "NO_VENUE_ACTIVITY" // claim made but zero activity found on venue
  | "INCONCLUSIVE";     // partial data, can't decide

/** Generic venue identity. All implementations must populate this. */
export type VenueIdentity = {
  /** Human-readable venue name, e.g. "Aster L1", "Synthra Perp on Arc". */
  name: string;
  /** Settlement chain name where trades are recorded. */
  chain: string;
  /** EVM chainId. -1 if non-EVM (e.g. Solana). */
  chainId: number;
  /** Where a reviewer can independently audit the same source. */
  explorerNote: string;
};

/** Generic venue-side summary. Implementations augment with `venueSpecific`. */
export type VenueSummary = {
  /** Number of distinct events used in the reconciliation (trades, fills, position updates). */
  eventCount: number;
  /** Gross realized PnL according to the venue, before any fees, in USDC-equivalent. */
  realizedPnlGrossUsdc: number;
  /** Total trading fees / commissions paid in USDC-equivalent. */
  totalFeesUsdc: number;
  /** Net realized PnL (gross - fees). This is what gets compared against the agent's claim. */
  netRealizedUsdc: number;
};

/** Common report shape. Implementations may attach venue-specific raw data via `venueSpecific`. */
export type VerificationReport = {
  verdict: VerificationVerdict;
  vaultId: string;
  symbol: string;
  windowStart: number;
  windowEnd: number;
  claim: {
    /** Raw on-chain reportedPnL, 18 decimals (Arc native USDC). */
    reportedPnlWei: string;
    /** Human-readable USDC amount. */
    reportedPnlUsdc: number;
  };
  venue: VenueIdentity & VenueSummary;
  delta: {
    /** Absolute difference between claim and venue-net, in USDC. */
    absUsdc: number;
    /** Percentage: |delta| / max(|claim|, |venue|) × 100. */
    pct: number;
  };
  generatedAt: number;
  notes: string[];
  /** Implementation-specific raw data (trades array, position snapshots, etc.). */
  venueSpecific?: Record<string, unknown>;
};

/** Common args every verifier accepts. */
export type VerifyReportArgs = {
  vaultId: string;
  /** Asset/market identifier in venue-native form, e.g. "BTCUSDT" for Aster, "btc-perp" for Synthra. */
  symbol: string;
  /** Signed PnL claimed by the agent on Plinth, 18 decimals. */
  reportedPnlWei: bigint;
  /** Time window start (ms since epoch). */
  windowStartMs: number;
  /** Optional time window end. Default = now. */
  windowEndMs?: number;
};

/**
 * IPerpVerifier — contract that every venue-specific verifier implements.
 * Plinth's Underwriter pipeline depends only on this interface, not on any
 * particular venue's API.
 */
export interface IPerpVerifier {
  /** Static venue identity. Cheap to read; no network calls. */
  readonly identity: VenueIdentity;

  /** Tolerance (in percent) within which a delta is treated as VERIFIED. */
  readonly tolerancePct: number;

  /**
   * Reconcile the agent's reportedPnL against the venue's trade history for
   * the given vault + symbol + time window. Must produce a `VerificationReport`.
   */
  verifyReport(args: VerifyReportArgs): Promise<VerificationReport>;
}

/* ====================================================================== */
/*       Shared utilities: verdict classification + delta math             */
/*       Implementations can call into these to keep logic consistent.     */
/* ====================================================================== */

/**
 * Compute verdict from a (claim, venue-net) pair using a tolerance.
 * Centralizes the rule so all verifiers agree on what "VERIFIED" means.
 */
export function classify(
  reportedUsdc: number,
  netRealizedUsdc: number,
  eventCount: number,
  tolerancePct: number,
): { verdict: VerificationVerdict; deltaAbs: number; deltaPct: number } {
  const absDelta = Math.abs(reportedUsdc - netRealizedUsdc);
  const denom = Math.max(Math.abs(reportedUsdc), Math.abs(netRealizedUsdc), 1e-9);
  const pct = (absDelta / denom) * 100;

  let verdict: VerificationVerdict;
  if (eventCount === 0) {
    verdict = Math.abs(reportedUsdc) < 1e-6 ? "VERIFIED" : "NO_VENUE_ACTIVITY";
  } else if (pct <= tolerancePct) {
    verdict = "VERIFIED";
  } else if (reportedUsdc > netRealizedUsdc) {
    verdict = "OVERSTATED";
  } else {
    verdict = "UNDERSTATED";
  }

  return { verdict, deltaAbs: absDelta, deltaPct: pct };
}
