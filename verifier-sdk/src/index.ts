/**
 * @plinth/verifier-core
 *
 * Generic IPerpVerifier interface + shared types for any protocol that needs
 * to cryptographically reconcile a trader's on-chain reported PnL against a
 * venue's trade history.
 *
 * This package is extracted from Plinth's Underwriter pipeline (which
 * implements this for Aster L1 today and Synthra Perp on Arc tomorrow) and
 * published as public-goods infrastructure so other on-chain fund-management
 * protocols don't have to re-invent the verifier abstraction.
 *
 * Quick start:
 *
 *   import { IPerpVerifier, classify } from "@plinth/verifier-core";
 *   import { AsterVerifier } from "@plinth/verifier-core/aster";
 *
 *   const verifier: IPerpVerifier = new AsterVerifier({
 *       baseUrl: "https://fapi.asterdex.com",
 *       privateKey: process.env.ASTER_PRIVATE_KEY,
 *   });
 *
 *   const report = await verifier.verifyReport({
 *       vaultId: "0x...",
 *       symbol: "BTCUSDT",
 *       reportedPnlWei: -47207000000000000n,  // -0.047207 USDC
 *       windowStartMs: Date.now() - 3600_000,
 *   });
 *
 *   if (report.verdict === "VERIFIED") {
 *       // post on-chain review via Plinth.postUnderwriterReview(...)
 *   }
 *
 * Extend with your own venue by implementing IPerpVerifier and calling
 * the centralized `classify(reported, venueNet, eventCount, tolerancePct)`
 * helper for consistent verdict logic.
 */

export type VerificationVerdict =
  | "VERIFIED"
  | "OVERSTATED"
  | "UNDERSTATED"
  | "NO_VENUE_ACTIVITY"
  | "INCONCLUSIVE";

export type VenueIdentity = {
  name: string;
  chain: string;
  chainId: number;
  explorerNote: string;
};

export type VenueSummary = {
  eventCount: number;
  realizedPnlGrossUsdc: number;
  totalFeesUsdc: number;
  netRealizedUsdc: number;
};

export type VerificationReport = {
  verdict: VerificationVerdict;
  vaultId: string;
  symbol: string;
  windowStart: number;
  windowEnd: number;
  claim: {
    reportedPnlWei: string;
    reportedPnlUsdc: number;
  };
  venue: VenueIdentity & VenueSummary;
  delta: {
    absUsdc: number;
    pct: number;
  };
  generatedAt: number;
  notes: string[];
  venueSpecific?: Record<string, unknown>;
};

export type VerifyReportArgs = {
  vaultId: string;
  symbol: string;
  reportedPnlWei: bigint;
  windowStartMs: number;
  windowEndMs?: number;
};

export interface IPerpVerifier {
  readonly identity: VenueIdentity;
  readonly tolerancePct: number;
  verifyReport(args: VerifyReportArgs): Promise<VerificationReport>;
}

/**
 * Centralized verdict classification.
 *
 * Encapsulates the rule that "VERIFIED" requires |claim − venue-net| / max(|claim|, |venue-net|) ≤ tolerance.
 * All verifiers should call this rather than re-inventing the rule, so
 * verdicts are comparable across venues.
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

/**
 * Render a VerificationReport as a human-readable markdown block suitable
 * for posting as a Plinth UnderwriterReview reviewUri target.
 */
export function renderMarkdown(r: VerificationReport): string {
  const lines: string[] = [];
  lines.push(`# Underwriter Review — ${r.venue.name}`);
  lines.push("");
  lines.push(`**Verdict**: \`${r.verdict}\``);
  lines.push(`**Vault**: \`${r.vaultId}\``);
  lines.push(`**Symbol**: ${r.symbol}`);
  lines.push(`**Window**: ${new Date(r.windowStart).toISOString()} → ${new Date(r.windowEnd).toISOString()}`);
  lines.push("");
  lines.push(`## Agent's claim (on-chain)`);
  lines.push(`- Reported PnL: **${r.claim.reportedPnlUsdc.toFixed(6)} USDC**`);
  lines.push(`- Raw wei: \`${r.claim.reportedPnlWei}\``);
  lines.push("");
  lines.push(`## Venue evidence (${r.venue.name}, chainId ${r.venue.chainId})`);
  lines.push(`- Event count: ${r.venue.eventCount}`);
  lines.push(`- Gross realized: ${r.venue.realizedPnlGrossUsdc.toFixed(6)} USDC`);
  lines.push(`- Total fees: ${r.venue.totalFeesUsdc.toFixed(6)} USDC`);
  lines.push(`- **Net realized**: ${r.venue.netRealizedUsdc.toFixed(6)} USDC`);
  lines.push("");
  lines.push(`## Delta`);
  lines.push(`- Absolute: ${r.delta.absUsdc.toFixed(6)} USDC`);
  lines.push(`- Percent: ${r.delta.pct.toFixed(2)}%`);
  lines.push("");
  lines.push(`## Notes`);
  for (const n of r.notes) lines.push(`- ${n}`);
  lines.push("");
  lines.push(`Generated at ${new Date(r.generatedAt).toISOString()} by @plinth/verifier-core v0.1.0.`);
  return lines.join("\n");
}
