/**
 * Plinth Risk Monitor — off-chain risk scanner that auto-posts alerts.
 *
 * Scans every vault on the Plinth deployment, computes a structured risk
 * signal vector (drawdown, PnL spikes, investor concentration, self-venue,
 * review staleness, underwater status), and writes a `RiskAlert` underwriter
 * review on chain for any vault scoring above a threshold.
 *
 * Designed to be run periodically (cron / GitHub Action) so that risk
 * deviations get on-chain attestation without depending on a single
 * trusted reviewer.
 *
 * Run:
 *   npx tsx risk-monitor.ts             # scan all, print verdicts, no posting
 *   npx tsx risk-monitor.ts --post      # also post on-chain reviews for high risk
 *   npx tsx risk-monitor.ts --vault 0x  # scan a single vault
 */
import { keccak256, toBytes } from "viem";
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  BrowseClient,
  InvestorClient,
  PLINTH_ARC_TESTNET,
  formatUsdc,
} from "../sdk-ts/src/index.js";
import type { Hex } from "viem";

process.loadEnvFile("D:\\桌面\\arc\\.env");

const argv = process.argv.slice(2);
const POST_ON_CHAIN = argv.includes("--post");
const SCAN_ONE = argv.indexOf("--vault") >= 0 ? argv[argv.indexOf("--vault") + 1] as Hex : null;
const THRESHOLD = 30; // score >= 30 triggers an on-chain alert

const PLINTH = PLINTH_ARC_TESTNET.plinth;
const DEPLOY_BLOCK = 41_977_066n;
const REVIEW_DIR = resolve("D:\\桌面\\arc\\plinth\\docs\\reviews");

type Signal = {
  level: "ok" | "low" | "medium" | "high" | "critical";
  score: number;
  reason: string;
  evidence?: Record<string, string | number>;
};

type VaultRiskReport = {
  vaultId: Hex;
  agent: Hex;
  strategyDescriptor: string;
  nav: bigint;
  inVault: bigint;
  deployedAUM: bigint;
  reportedPnL: bigint;
  totalShares: bigint;
  signals: Signal[];
  totalScore: number;
  verdict: "OK" | "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
  generatedAt: number;
};

const INCEPTION = 10n ** 18n;

async function scan() {
  const browser = new BrowseClient({ plinthAddress: PLINTH });
  const investor = new InvestorClient({
    privateKey: process.env.PRIVATE_KEY as Hex,
    plinthAddress: PLINTH,
  });

  console.log("═".repeat(70));
  console.log("Plinth Risk Monitor — scanning vaults");
  console.log("═".repeat(70));

  // Enumerate vaults (Arc Testnet eth_getLogs cap = 10k blocks, chunk it)
  const latest = await browser.publicClient.getBlockNumber();
  const CHUNK = 9_000n;
  let allVaults: Awaited<ReturnType<typeof browser.listAllVaults>> = [];
  let to: bigint = latest;
  while (to >= DEPLOY_BLOCK) {
    const from = to > CHUNK ? to - CHUNK : 0n;
    const slice = await browser.listAllVaults(
      from < DEPLOY_BLOCK ? DEPLOY_BLOCK : from,
      to,
      true,
    );
    allVaults.push(...slice);
    if (from <= DEPLOY_BLOCK) break;
    to = from - 1n;
  }
  if (SCAN_ONE) allVaults = allVaults.filter((v) => v.vaultId.toLowerCase() === SCAN_ONE.toLowerCase());

  console.log(`Scanning ${allVaults.length} vault(s)…\n`);

  const reports: VaultRiskReport[] = [];

  for (const v of allVaults) {
    if (!v.state) continue;
    const signals: Signal[] = [];

    const inVault = v.state.inVault;
    const deployedAUM = v.state.deployedAUM;
    const reportedPnL = v.state.reportedPnL;  // signed bigint
    const totalShares = v.state.totalShares;
    const nav = v.nav ?? INCEPTION;
    const agent = v.agent.toLowerCase();

    // ─── Signal 1: Underwater (NAV below inception) ───
    if (nav < INCEPTION) {
      const dropPct = Number(((INCEPTION - nav) * 10000n) / INCEPTION) / 100;
      signals.push({
        level: dropPct > 20 ? "critical" : dropPct > 10 ? "high" : "medium",
        score: dropPct > 20 ? 30 : dropPct > 10 ? 20 : 12,
        reason: `Vault NAV is ${dropPct.toFixed(2)}% below inception`,
        evidence: { nav: formatUsdc(nav), dropPct: `${dropPct.toFixed(2)}%` },
      });
    }

    // ─── Signal 2: Outsized PnL claim vs deployed capital ───
    if (reportedPnL !== 0n && deployedAUM > 0n) {
      const pnlAbs = reportedPnL < 0n ? -reportedPnL : reportedPnL;
      const totalAUM = inVault + deployedAUM;
      if (totalAUM > 0n) {
        const ratioBps = Number((pnlAbs * 10000n) / totalAUM);
        if (ratioBps > 5000) {  // PnL > 50% of AUM
          signals.push({
            level: ratioBps > 10000 ? "high" : "medium",
            score: ratioBps > 10000 ? 25 : 15,
            reason: `Reported PnL is ${(ratioBps / 100).toFixed(1)}% of AUM — extreme ratio invites scrutiny`,
            evidence: { reportedPnL: formatUsdc(reportedPnL), totalAUM: formatUsdc(totalAUM) },
          });
        }
      }
    }

    // ─── Signal 3: Agent is on its own approvedVenues list (self-venue) ───
    const venues = v.approvedVenues.map((a) => a.toLowerCase());
    if (venues.includes(agent)) {
      signals.push({
        level: "critical",
        score: 40,
        reason: "Agent address appears on its own approvedVenues list — capability constraint defeated",
        evidence: { agent: v.agent },
      });
    }

    // ─── Signal 4: Single venue concentration (only 1 approved venue) ───
    if (venues.length === 1) {
      signals.push({
        level: "low",
        score: 5,
        reason: "Only 1 approved venue — no operational diversification",
        evidence: { venues: venues.length.toString() },
      });
    }

    // ─── Signal 5: Review staleness (within recent ~9k blocks; Arc cap) ───
    const recentFromBlock = latest > CHUNK ? latest - CHUNK : 0n;
    const reviews = await browser.listReviews(v.vaultId, recentFromBlock);
    if (reviews.length === 0 && reportedPnL !== 0n) {
      signals.push({
        level: "medium",
        score: 15,
        reason: `Vault reports PnL but has no underwriter reviews in last ~${CHUNK} blocks`,
        evidence: { reviewCount: "0", reportedPnL: formatUsdc(reportedPnL) },
      });
    }

    // ─── Signal 6: Negative deployedAUM math — would indicate corruption (defensive) ───
    if (deployedAUM < 0n) {
      signals.push({
        level: "critical",
        score: 50,
        reason: "Negative deployedAUM detected (state corruption)",
      });
    }

    // ─── Signal 7: Liquidity gap (inVault much smaller than totalShares × inception) ───
    // If a redemption-at-NAV would need to draw from deployedAUM beyond what's idle,
    // the vault reverts. Flag if inVault < 5% of total assets.
    if (totalShares > 0n && (inVault + deployedAUM) > 0n) {
      const liquidityBps = Number((inVault * 10000n) / (inVault + deployedAUM));
      if (liquidityBps < 500 && deployedAUM > 0n) {
        signals.push({
          level: "medium",
          score: 12,
          reason: `Only ${(liquidityBps / 100).toFixed(1)}% of AUM is liquid in vault — redemptions may revert until agent returns funds`,
          evidence: { liquidityPct: `${(liquidityBps / 100).toFixed(1)}%` },
        });
      }
    }

    const totalScore = signals.reduce((s, x) => s + x.score, 0);
    const verdict: VaultRiskReport["verdict"] =
      totalScore >= 60 ? "CRITICAL" :
      totalScore >= 30 ? "HIGH" :
      totalScore >= 15 ? "MEDIUM" :
      totalScore >= 5 ? "LOW" : "OK";

    reports.push({
      vaultId: v.vaultId,
      agent: v.agent,
      strategyDescriptor: v.strategyDescriptor,
      nav,
      inVault,
      deployedAUM,
      reportedPnL,
      totalShares,
      signals,
      totalScore,
      verdict,
      generatedAt: Date.now(),
    });
  }

  // Print summary
  console.log("Verdict  Score  Vault          Strategy");
  console.log("─".repeat(70));
  for (const r of reports.sort((a, b) => b.totalScore - a.totalScore)) {
    const verdictDecor = {
      CRITICAL: "🔴 CRITICAL",
      HIGH:     "🟠 HIGH    ",
      MEDIUM:   "🟡 MEDIUM  ",
      LOW:      "🟢 LOW     ",
      OK:       "⚪ OK      ",
    }[r.verdict];
    console.log(
      `${verdictDecor}  ${String(r.totalScore).padStart(3)}    ${r.vaultId.slice(0, 12)}…  ${r.strategyDescriptor.slice(0, 40)}`,
    );
  }
  console.log();

  // Print detailed signals for non-OK
  for (const r of reports.filter((r) => r.verdict !== "OK")) {
    console.log("─".repeat(70));
    console.log(`Vault ${r.vaultId}`);
    console.log(`Agent: ${r.agent}  |  NAV: ${formatUsdc(r.nav)}  |  Score: ${r.totalScore} → ${r.verdict}`);
    console.log(`Strategy: ${r.strategyDescriptor}`);
    console.log();
    for (const s of r.signals) {
      console.log(`  [${s.level.toUpperCase().padEnd(8)}] +${s.score}  ${s.reason}`);
      if (s.evidence) {
        for (const [k, v] of Object.entries(s.evidence)) {
          console.log(`              ${k}: ${v}`);
        }
      }
    }
    console.log();
  }

  // Post on-chain reviews for HIGH+ vaults
  if (POST_ON_CHAIN) {
    console.log("─".repeat(70));
    console.log("Posting on-chain RiskAlert reviews…");
    console.log("─".repeat(70));
    for (const r of reports.filter((r) => r.totalScore >= THRESHOLD)) {
      const markdown = renderMarkdown(r);
      const path = `${REVIEW_DIR}/${r.vaultId}-riskmonitor-${Date.now()}.md`;
      writeFileSync(path, markdown);
      const reviewHash = keccak256(toBytes(markdown));
      const filename = path.split(/[\\/]/).pop();
      const reviewUri = `https://ccheh.github.io/plinth/reviews/${filename}`;
      try {
        const tx = await investor.postUnderwriterReview(r.vaultId, reviewHash, reviewUri);
        console.log(`  ✓ ${r.vaultId.slice(0, 12)}…  →  ${r.verdict} alert posted  tx ${tx}`);
      } catch (e: any) {
        console.error(`  ✗ ${r.vaultId.slice(0, 12)}…  →  failed: ${e.message.slice(0, 100)}`);
      }
    }
  } else {
    console.log("(Run with --post to post on-chain RiskAlert reviews for HIGH+ vaults.)");
  }
}

function renderMarkdown(r: VaultRiskReport): string {
  const lines: string[] = [];
  lines.push(`# Underwriter Review — Risk Monitor Alert`);
  lines.push("");
  lines.push(`**Verdict**: \`${r.verdict}\`  (score ${r.totalScore})`);
  lines.push(`**Vault**: \`${r.vaultId}\``);
  lines.push(`**Agent**: \`${r.agent}\``);
  lines.push(`**Strategy**: ${r.strategyDescriptor}`);
  lines.push("");
  lines.push(`## State snapshot`);
  lines.push(`- NAV: ${formatUsdc(r.nav)} USDC/share`);
  lines.push(`- inVault: ${formatUsdc(r.inVault)} USDC`);
  lines.push(`- deployedAUM: ${formatUsdc(r.deployedAUM)} USDC`);
  lines.push(`- reportedPnL: ${formatUsdc(r.reportedPnL)} USDC`);
  lines.push(`- totalShares: ${formatUsdc(r.totalShares)}`);
  lines.push("");
  lines.push(`## Risk signals`);
  for (const s of r.signals) {
    lines.push(`- **[${s.level.toUpperCase()}] +${s.score}** — ${s.reason}`);
    if (s.evidence) {
      for (const [k, v] of Object.entries(s.evidence)) {
        lines.push(`    - ${k}: \`${v}\``);
      }
    }
  }
  lines.push("");
  lines.push(`Generated at ${new Date(r.generatedAt).toISOString()} by Plinth Risk Monitor v0.`);
  lines.push("");
  lines.push(`---`);
  lines.push(`This review was produced by an automated off-chain monitor. It does not constitute investment advice. The Risk Monitor is one of multiple complementary Underwriter reviewers — others include the LLM-driven risk reviewer (\`underwriter/review.ts\`) and the verifiable-PnL Aster reconciler (\`aster/verifier.ts\`).`);
  return lines.join("\n");
}

scan().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
