/**
 * Plinth LLM Underwriter — analyze a vault's strategy descriptor + on-chain
 * history, output a structured risk review, and post the review hash on chain.
 *
 * Flow:
 *   1. Read vault state from Plinth (agent address, approvedVenues, strategy
 *      descriptor, current AUM / PnL state).
 *   2. Read agent's recent on-chain activity (last N transactions, including
 *      any prior Plinth events from the same agent address).
 *   3. Build a structured prompt for Claude. Ask for:
 *        - riskLevel: low | medium | high | critical
 *        - confidence: 0..1
 *        - redFlags: string[] (each concrete + evidence-grounded)
 *        - summary: 2-3 sentence plain English review
 *        - recommendedActions: array of caveats to investors
 *   4. Serialize the review JSON, compute keccak256(content), call
 *      Plinth.postUnderwriterReview(vaultId, hash, uri) with the review URI
 *      pointing to where the full JSON lives (in this demo we just embed in
 *      logs; in production this is IPFS / HTTPS).
 *   5. Caller picks which underwriter address(es) to trust — multiple
 *      reviewers can co-exist for the same vault.
 *
 * Run:
 *   ANTHROPIC_API_KEY=sk-ant-... npx tsx review.ts --vault 0xc4c82a... [--no-post]
 *
 * `--no-post` skips the on-chain posting (useful for dry runs).
 */

import { keccak256, toBytes, type Hex } from "viem";
import Anthropic from "@anthropic-ai/sdk";
import {
  AgentClient, InvestorClient, BrowseClient,
  PLINTH_ARC_TESTNET, ARC_TESTNET, formatUsdc,
} from "../sdk-ts/src/index.js";

// ---------- args + env ----------

process.loadEnvFile("D:\\桌面\\arc\\.env");

const argv = process.argv.slice(2);
const vaultArg = argv.indexOf("--vault");
const noPost = argv.includes("--no-post");
if (vaultArg < 0 || !argv[vaultArg + 1]) {
  console.error("Usage: tsx review.ts --vault <0x...> [--no-post]");
  process.exit(2);
}
const vaultId = argv[vaultArg + 1] as Hex;

const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY;
const UNDERWRITER_PK = process.env.PRIVATE_KEY as Hex;
if (!UNDERWRITER_PK) throw new Error("Missing PRIVATE_KEY in .env (underwriter signer)");

const PLINTH = PLINTH_ARC_TESTNET.plinth;
const EXPLORER = ARC_TESTNET.explorer;

// ---------- read vault state ----------

const investor = new InvestorClient({ privateKey: UNDERWRITER_PK, plinthAddress: PLINTH });
const browser = new BrowseClient({ plinthAddress: PLINTH });

console.log(`Reading vault ${vaultId} from ${PLINTH}...`);
const vault = await investor.getVault(vaultId);
const navNow = await investor.getNAV(vaultId);
const venues = await investor.getApprovedVenues(vaultId);

console.log(`  agent:              ${vault.agent}`);
console.log(`  status:             ${vault.status} (1=Active 2=Paused 3=Closed)`);
console.log(`  strategyDescriptor: "${vault.strategyDescriptor}"`);
console.log(`  approvedVenues:     ${venues.join(", ")}`);
console.log(`  totalShares:        ${formatUsdc(vault.totalShares)}`);
console.log(`  inVault:            ${formatUsdc(vault.inVault)} USDC`);
console.log(`  deployedAUM:        ${formatUsdc(vault.deployedAUM)} USDC`);
console.log(`  reportedPnL:        ${formatUsdc(vault.reportedPnL)} USDC`);
console.log(`  current NAV:        ${formatUsdc(navNow)} USDC/share`);

// ---------- read agent history (Plinth-only events from this agent) ----------

// Arc Testnet caps eth_getLogs at 10,000 block range. Stay under that.
const currentBlock = await investor.publicClient.getBlockNumber();
const fromBlock = currentBlock > 9_900n ? currentBlock - 9_900n : 0n;
const agentVaults = await browser.listAllVaults(fromBlock, "latest", true);
const agentPriorVaults = agentVaults.filter(v =>
  v.agent.toLowerCase() === vault.agent.toLowerCase() && v.vaultId.toLowerCase() !== vaultId.toLowerCase()
);
console.log(`  agent's other vaults: ${agentPriorVaults.length}`);

// ---------- build LLM prompt ----------

const systemPrompt = `You are an Underwriter for the Plinth Protocol, a capital layer for AI trading agents on Arc Testnet. Your job is to review a vault's strategy and produce a risk rating for prospective investors.

Be SKEPTICAL but FAIR. Look for:
- Red flags: vague strategy, unrealistic claims, agent-as-venue setups (where the agent could drain to themselves), excessive leverage promises, missing risk caveats.
- Green flags: specific strategy with clear constraints, multiple distinct venues, conservative position sizing.

Output JSON ONLY, matching this schema:
{
  "riskLevel": "low" | "medium" | "high" | "critical",
  "confidence": 0.0-1.0,
  "redFlags": ["..."],
  "greenFlags": ["..."],
  "summary": "2-3 sentence plain English",
  "recommendedActionsForInvestors": ["..."]
}

Be CONCRETE. Cite specific evidence from the strategy descriptor / on-chain state. No filler text.`;

const userPrompt = `Vault ID: ${vaultId}
Agent address: ${vault.agent}
Status: ${vault.status === 1 ? "Active" : vault.status === 2 ? "Paused" : "Closed"}
Strategy Descriptor (verbatim, agent-supplied): "${vault.strategyDescriptor}"

Approved Venues (immutable, set at creation): ${venues.join(", ")}
Note: if any approvedVenue equals the agent's own EOA, that's a DRAIN risk.

Current State:
- Total shares outstanding: ${formatUsdc(vault.totalShares)}
- USDC liquid in vault: ${formatUsdc(vault.inVault)}
- USDC deployed to venues: ${formatUsdc(vault.deployedAUM)}
- Agent's reported (mark-to-market) PnL: ${formatUsdc(vault.reportedPnL)}
- Current NAV: ${formatUsdc(navNow)} USDC/share

Agent has ${agentPriorVaults.length} other vault(s) under this Plinth deployment.

Produce your JSON review now.`;

// ---------- call LLM ----------

let reviewJSON: string;
if (ANTHROPIC_KEY) {
  console.log(`\nCalling Claude (Anthropic) for risk review...`);
  const anthropic = new Anthropic({ apiKey: ANTHROPIC_KEY });
  const msg = await anthropic.messages.create({
    model: "claude-3-5-haiku-latest",
    max_tokens: 1024,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });
  // Extract text content
  const text = msg.content
    .filter((c): c is { type: "text"; text: string } => c.type === "text")
    .map(c => c.text)
    .join("\n");
  // Strip markdown fence if present
  reviewJSON = text.replace(/^```(json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  console.log(`  Claude responded (${reviewJSON.length} chars)`);
} else {
  console.log(`\nNo ANTHROPIC_API_KEY in env → using rule-based fallback review`);
  // Simple rule-based review for demo when no API key set
  const redFlags: string[] = [];
  const greenFlags: string[] = [];
  // Check for agent-as-venue
  if (venues.some(v => v.toLowerCase() === vault.agent.toLowerCase())) {
    redFlags.push("CRITICAL: agent listed their own address as an approvedVenue → can drain to themselves");
  }
  if (vault.strategyDescriptor.length < 20) {
    redFlags.push("Strategy descriptor is very short — insufficient detail to assess risk");
  }
  if (vault.strategyDescriptor.toLowerCase().includes("guaranteed") || vault.strategyDescriptor.toLowerCase().includes("100%")) {
    redFlags.push("Strategy claims guarantees that are not credible in crypto trading");
  }
  if (vault.deployedAUM > 0n && vault.reportedPnL > vault.deployedAUM / 2n) {
    redFlags.push("Reported PnL > 50% of deployed AUM in a short time — verify claim or treat as unrealized");
  }
  if (venues.length >= 2) {
    greenFlags.push(`Diversified across ${venues.length} approved venues`);
  }
  if (vault.strategyDescriptor.toLowerCase().includes("max") || vault.strategyDescriptor.toLowerCase().includes("leverage")) {
    greenFlags.push("Strategy descriptor mentions explicit risk constraints (e.g. max leverage)");
  }
  const riskLevel = redFlags.some(f => f.startsWith("CRITICAL")) ? "critical"
                  : redFlags.length >= 2 ? "high"
                  : redFlags.length === 1 ? "medium" : "low";
  reviewJSON = JSON.stringify({
    riskLevel, confidence: 0.6, redFlags, greenFlags,
    summary: `Rule-based review (no LLM key). ${redFlags.length} red flag(s), ${greenFlags.length} green flag(s). Risk level: ${riskLevel}.`,
    recommendedActionsForInvestors: redFlags.length > 0
      ? ["Wait for an LLM-backed review.", "Verify the agent's prior track record off-chain."]
      : ["Standard caveats apply: small initial position, monitor NAV changes."],
  }, null, 2);
}

console.log(`\n========== REVIEW ==========`);
console.log(reviewJSON);
console.log(`============================\n`);

// ---------- compute hash + post on chain ----------

const reviewHash = keccak256(toBytes(reviewJSON));
const reviewUri = `data:application/json;base64,${Buffer.from(reviewJSON).toString("base64")}`;
console.log(`Review hash: ${reviewHash}`);
console.log(`Review URI:  ${reviewUri.slice(0, 80)}... (${reviewUri.length} chars total)`);

if (noPost) {
  console.log(`\n--no-post specified → skipping on-chain post.`);
} else {
  console.log(`\nPosting review on chain...`);
  const tx = await investor.postUnderwriterReview(vaultId, reviewHash, reviewUri);
  console.log(`  tx: ${EXPLORER}/tx/${tx}`);
}

// ---------- verify the review is queryable via BrowseClient ----------

console.log(`\nFetching all reviews for this vault via BrowseClient:`);
const latest = await investor.publicClient.getBlockNumber();
const reviewsFrom = latest > 9_900n ? latest - 9_900n : 0n;
const reviews = await browser.listReviews(vaultId, reviewsFrom);
for (const r of reviews) {
  console.log(`  by ${r.underwriter.slice(0, 10)}... hash=${r.reviewHash.slice(0, 10)}... block=${r.blockNumber}`);
  console.log(`    uri: ${r.reviewUri.slice(0, 80)}...`);
}

console.log(`\nDone. Review can be cross-verified by anyone: recompute keccak256(reviewJSON) must match on-chain reviewHash.`);
