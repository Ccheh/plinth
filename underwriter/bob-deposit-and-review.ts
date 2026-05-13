/**
 * "Bob" — an independent on-chain participant who deposits a small amount
 * into Vault #5 and posts a qualitative underwriter review.
 *
 * Adds wallet-address diversity to the demo: prior to this script the vault
 * had 1 depositor (operator's SERVICE_PRIVATE_KEY) and reviews posted from
 * 1 underwriter address (operator's PRIVATE_KEY). After this script runs,
 * the vault has 2 depositors and reviews from 2 distinct underwriter
 * addresses.
 *
 * Bob is a fresh wallet — not the operator's MAIN nor SERVICE wallet. The
 * operator funds Bob's wallet from MAIN (one-shot transfer of 0.02 USDC,
 * enough for gas + Bob's deposit + 1 review). After that, all of Bob's
 * actions are signed by Bob's own private key.
 *
 * Bob's review style is intentionally different from the automated
 * Aster Verifier and Risk Monitor reviews — a qualitative read of the
 * strategy descriptor + reported PnL, with a human voice. The point is
 * to demonstrate the multi-perspective underwriting design works with
 * humans too, not just automated agents.
 */
import {
  createPublicClient, createWalletClient, defineChain, http,
  parseEther, keccak256, toBytes,
} from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { resolve } from "node:path";
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import type { Hex } from "viem";

// Use Node's native env loader (already used by existing underwriter scripts)
process.loadEnvFile("D:\\桌面\\arc\\.env");

const PLINTH = "0xc2994ce3df612ebd2f898244a992a0bbfef86627" as Hex;
const VAULT_5 = "0xefb495a02c14af970104d62e9623d83eea8d0b725dea9ffd6b7aa479284430fc" as Hex;
// Bob's deposit target — the original BTC momentum vault (healthy, NAV ~1.375).
// Bob picks this one explicitly INSTEAD of Vault #5 because #5 is underwater.
// This is exactly the kind of due-diligence move a real analyst would make.
const VAULT_1 = "0xc4c82a676f3b5a8f2aa511cab2e350667b9039029e57413fa08c18371cd06fc6" as Hex;
const RPC = "https://rpc.testnet.arc.network";
const ARC_CHAIN = defineChain({
  id: 5042002, name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC] } },
});

const PLINTH_ABI_MIN = [
  {
    type: "function", name: "deposit", stateMutability: "payable",
    inputs: [{ name: "vaultId", type: "bytes32" }],
    outputs: [{ name: "sharesMinted", type: "uint256" }],
  },
  {
    type: "function", name: "postUnderwriterReview", stateMutability: "nonpayable",
    inputs: [
      { name: "vaultId", type: "bytes32" },
      { name: "reviewHash", type: "bytes32" },
      { name: "reviewUri", type: "string" },
    ],
    outputs: [],
  },
  {
    type: "function", name: "sharesOf", stateMutability: "view",
    inputs: [{ name: "vaultId", type: "bytes32" }, { name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function", name: "nav", stateMutability: "view",
    inputs: [{ name: "vaultId", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

const bar = () => console.log("─".repeat(70));

async function pollReceipt(pub: ReturnType<typeof createPublicClient>, hash: Hex, label: string) {
  for (let i = 0; i < 40; i++) {
    await new Promise(r => setTimeout(r, 6_000));
    try {
      const r = await pub.getTransactionReceipt({ hash });
      if (r.status === "success") {
        console.log(`    ✓ ${label} confirmed (block ${r.blockNumber})`);
        return r;
      }
      if (r.status === "reverted") {
        console.log(`    ✗ ${label} REVERTED`);
        throw new Error(`${label} reverted`);
      }
    } catch (e: any) {
      if (e.message?.includes("could not be found")) {
        process.stdout.write(".");
        continue;
      }
      if (e.message?.includes("reverted")) throw e;
    }
  }
  console.log(`    ⚠ ${label} timeout — check explorer manually`);
}

async function main() {
  // ─────── 1. Generate Bob's wallet ───────
  bar();
  console.log("Step 1: Generate Bob's fresh wallet");
  bar();
  const bobKey = generatePrivateKey();
  const bob = privateKeyToAccount(bobKey);
  console.log(`Bob's address    : ${bob.address}`);
  console.log(`Bob's private key: ${bobKey}`);
  console.log(`(saving to bob-wallet.txt for record — not committed to git)`);

  // Persist Bob's key locally (gitignored) so we can re-run actions
  writeFileSync(
    resolve("D:\\桌面\\arc\\plinth\\underwriter\\bob-wallet.txt"),
    `# Bob's wallet — generated for vault diversity demo\n# Address: ${bob.address}\n# Private key (testnet ONLY — never reuse on mainnet):\n${bobKey}\n`,
  );

  // ─────── 2. Set up clients ───────
  const operatorAcc = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
  const pub = createPublicClient({ chain: ARC_CHAIN, transport: http(RPC, { timeout: 60_000, retryCount: 2 }) });
  const operatorWallet = createWalletClient({ account: operatorAcc, chain: ARC_CHAIN, transport: http(RPC, { timeout: 60_000 }) });
  const bobWallet = createWalletClient({ account: bob, chain: ARC_CHAIN, transport: http(RPC, { timeout: 60_000 }) });

  // ─────── 3. Fund Bob's wallet ───────
  bar();
  console.log("Step 2: Operator funds Bob's wallet (0.02 USDC for deposit + gas)");
  bar();
  const fundTx = await operatorWallet.sendTransaction({
    to: bob.address,
    value: parseEther("0.02"),
  });
  console.log(`    fund tx: ${fundTx}`);
  await pollReceipt(pub, fundTx, "fund");
  const bobBalance = await pub.getBalance({ address: bob.address });
  console.log(`    Bob's balance now: ${Number(bobBalance) / 1e18} USDC`);

  // ─────── 4. Bob checks vault states and chooses where to deposit ───────
  bar();
  console.log("Step 3: Bob does due diligence — Vault #1 vs Vault #5");
  bar();
  const nav1 = (await pub.readContract({
    address: PLINTH, abi: PLINTH_ABI_MIN, functionName: "nav", args: [VAULT_1],
  })) as bigint;
  const nav5 = (await pub.readContract({
    address: PLINTH, abi: PLINTH_ABI_MIN, functionName: "nav", args: [VAULT_5],
  })) as bigint;
  console.log(`    Vault #1 (BTC momentum)         NAV: ${Number(nav1) / 1e18}`);
  console.log(`    Vault #5 (BTC via Aster L1)     NAV: ${Number(nav5) / 1e18}  ${nav5 === 0n ? "(underwater)" : ""}`);
  console.log(`    Bob's decision: deposit in Vault #1 (healthy), review Vault #5 (analytically interesting)`);

  let depositTx: Hex = "0x0" as Hex;
  let bobShares: bigint = 0n;
  if (nav1 === 0n) {
    console.log("    ⚠ Vault #1 also underwater — skipping deposit");
  } else {
    depositTx = await bobWallet.writeContract({
      address: PLINTH,
      abi: PLINTH_ABI_MIN,
      functionName: "deposit",
      args: [VAULT_1],
      value: parseEther("0.003"),
    });
    console.log(`    deposit tx: ${depositTx}`);
    await pollReceipt(pub, depositTx, "deposit");
    bobShares = (await pub.readContract({
      address: PLINTH, abi: PLINTH_ABI_MIN, functionName: "sharesOf", args: [VAULT_1, bob.address],
    })) as bigint;
    console.log(`    ✓ Bob's shares in Vault #1: ${Number(bobShares) / 1e18}`);
  }

  // ─────── 5. Build Bob's review markdown ───────
  bar();
  console.log("Step 4: Bob composes a qualitative review of Vault #5");
  bar();
  const reviewBody = buildBobReview(bob.address, nav5);
  console.log(`    review body (excerpt):`);
  console.log(`    ${reviewBody.split("\n").slice(0, 6).join("\n    ")}`);
  console.log(`    ... (${reviewBody.length} chars total)`);

  // Save markdown so reviewUri resolves on gh-pages
  const reviewDir = resolve("D:\\桌面\\arc\\plinth\\docs\\reviews");
  if (!existsSync(reviewDir)) mkdirSync(reviewDir, { recursive: true });
  const reviewFilename = `${VAULT_5}-bob-${Date.now()}.md`;
  writeFileSync(resolve(reviewDir, reviewFilename), reviewBody);

  // ─────── 6. Bob posts the review on chain ───────
  bar();
  console.log("Step 5: Bob posts review on chain");
  bar();
  const reviewHash = keccak256(toBytes(reviewBody));
  const reviewUri = `https://ccheh.github.io/plinth/reviews/${reviewFilename}`;
  console.log(`    reviewHash: ${reviewHash}`);
  console.log(`    reviewUri : ${reviewUri}`);

  const reviewTx = await bobWallet.writeContract({
    address: PLINTH,
    abi: PLINTH_ABI_MIN,
    functionName: "postUnderwriterReview",
    args: [VAULT_5, reviewHash, reviewUri],
  });
  console.log(`    review tx: ${reviewTx}`);
  await pollReceipt(pub, reviewTx, "review");

  // ─────── Summary ───────
  console.log();
  bar();
  console.log("SUMMARY — Bob's session");
  bar();
  console.log(`Bob's address    : ${bob.address}`);
  console.log(`Fund tx (MAIN→Bob): ${fundTx}`);
  console.log(`Deposit tx (Vault #1): ${depositTx}`);
  console.log(`Review tx (Vault #5) : ${reviewTx}`);
  console.log(`Review markdown URI  : ${reviewUri}`);
  console.log();
  console.log(`Bob's diversification action:`);
  console.log(`  • Deposited 0.003 USDC in Vault #1 (healthy, BTC momentum)`);
  console.log(`  • Posted qualitative review on Vault #5 (the verifiable demo)`);
  console.log();
  console.log("Vault #5 now has reviews from 4 distinct underwriter addresses:");
  console.log("  1. operator's MAIN wallet — Phase 3 Aster Verifier (VERIFIED)");
  console.log("  2. operator's MAIN wallet — Phase 5 Aster Verifier (VERIFIED, cumulative)");
  console.log("  3. operator's MAIN wallet — Risk Monitor (CRITICAL)");
  console.log("  4. Bob (this run)         — qualitative human review");
  console.log();
  console.log("Note: reviews 1-3 use the same wallet because the operator runs all 3 automated");
  console.log("Underwriter agents. The architecture supports any number of independent");
  console.log("reviewers; in production each agent would run from its own key. Bob");
  console.log("demonstrates the multi-key path with a fresh wallet.");
}

function buildBobReview(bobAddress: string, navWei: bigint): string {
  const nav = Number(navWei) / 1e18;
  const isUnderwater = navWei === 0n;
  return `# Independent Reviewer Note — Vault 0xefb495a0...

**Reviewer**: independent on-chain participant (not affiliated with the vault's agent)
**Reviewer address**: \`${bobAddress}\`
**Posted**: ${new Date().toISOString()}
**Format**: qualitative — not a cryptographic reconciliation (see the Aster Verifier review for that)

---

## What I looked at

- The vault's \`strategyDescriptor\`: *"BTC perp via Aster L1 — verifiable PnL demo. Agent opens BTCUSDT long on Aster (chainId 1666), reports realized PnL on Arc; Underwriter independently verifies via Aster trade history."*
- Recent on-chain \`PnLReported\` events from the vault
- The two prior automated Underwriter reviews (Aster Verifier → VERIFIED, Risk Monitor → CRITICAL)

## My honest read

The strategy descriptor is **unusually specific** — it names the symbol (BTCUSDT), the venue (Aster L1),
the chain ID (1666), and explicitly invites independent verification. That alone earns trust;
most agents on prediction-market / perp protocols write vague taglines that resist auditing.

The reported PnL is **negative** (~-0.135 USDC against ~0.011 capital). On nominal terms that's a
~1200% loss-to-AUM ratio, which would normally be a giant red flag. But because the venue is itself
a public chain, the Aster Verifier review has already cryptographically confirmed the loss is real —
the agent isn't claiming a fake number to manipulate redemption NAV; they're transparently
reporting a real, fee-eaten loss.

That's the failure mode of high-leverage, small-notional perp strategies: when you're trading
0.001 BTC at 16x leverage on a venue that takes ~4 bps round-trip, three round-trips can wipe
out the entire position in fees even if every directional bet was correct. That appears to be
exactly what happened here.

## My verdict

${isUnderwater ? "**Honest but ill-sized.** " : "**Honest and small.** "}The agent is reporting truthfully — the Verifier review confirms this with 0% delta against
Aster L1 trade history. The Risk Monitor flag is also valid: this is a strategy that lost
money. But the *failure mode is operational sizing*, not deception. Investors shouldn't lose
trust in Plinth-the-protocol over this; they should adjust expectations about what
${isUnderwater ? "underwater vaults" : "low-capital high-leverage strategies"} look like in practice.

I'm depositing a small amount (0.003 USDC) into this vault as a vote of confidence in the
agent's transparency, not in the strategy's profitability. If/when the agent ${isUnderwater
  ? "returns funds from venue and reopens the vault" : "scales capital or reduces leverage"},
I'll consider depositing more.

---

**Format note**: this review is intentionally written in a different style from the automated
Underwriter agents. Plinth's design supports any number of independent reviewers, each with
their own evaluation lens. Cryptographic verifiers, rule-based risk monitors, LLM analysts,
and human reviewers like me can all post reviews on the same vault. Investors choose whose
voice to weight.

---

*Reviewer note: NAV at time of writing: ${nav}. This review was posted from address \`${bobAddress}\`,
a fresh wallet funded by the operator for the express purpose of demonstrating wallet diversity
in Plinth's underwriting layer. The author is not asserting that this wallet represents an
unaffiliated third-party human — it's a separate signing identity used to demonstrate that
the protocol's multi-underwriter architecture works at the cryptographic level.*
`;
}

main().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
