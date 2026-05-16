# Circle Developer Grant Application Draft — Plinth (Cohort 2)

> **Status**: DRAFT. Pre-submission review.
> **Grant**: Circle Grants Program, Circle 2026 Cohort 2 (Arc track)
> **Portal**: https://circle.questbook.app
> **Recommended ask**: $50K USDC across 5 milestones
> **Recommended submission timing**: After May 22 Circle Developer Grants Workshop (so we can fine-tune based on what they emphasize). Submit late May / early June 2026.

---

## 1. Applicant Details

| Field | Value | Notes |
|---|---|---|
| Primary contact first name | `Zen` | |
| Primary contact last name | `Chen` | |
| Email address | `ccheh4@gmail.com` | Same as Canteen / Architects / Arc community |
| **Company Legal Entity Name** | ⚠️ **TBD** — see decision below | |
| **Company DBA name** | `Plinth` | Project name |
| Founder names, roles, bios | (see below) | |
| Project website | `https://github.com/Ccheh/plinth` | (no standalone website; GitHub is the canonical home) |
| Project X handle | `@Ccheh4` | https://x.com/Ccheh4 |
| **Where are you and your founders located?** | ⚠️ **TBD** — see decision below | Format: "Full Name, Title, Location (City, State/Province, Country)" |
| **Where is your business located?** | ⚠️ **TBD** — Country dropdown | |
| **Is your business incorporated?** | ⚠️ **TBD** — likely "No" | |

### ⚠️ Decisions you need to make BEFORE we fill this

**Q1: Company Legal Entity Name** — three options:
- Option A: `"Independent / Solo Builder"` (honest, signals "no entity yet")
- Option B: `"Plinth Labs"` (founder DBA, looks like a one-person LLC)
- Option C: An actual entity you've registered — tell me which
- **My recommendation**: Option A. Grant evaluators understand solo founders. Lying about incorporation status is risk.

**Q2: Founder location** — Format example:
- `"Zen Chen, Founder & Sole Builder, Shenzhen, Guangdong, China"`
- I don't know your exact city. Tell me the city you want listed.

**Q3: Is your business incorporated?** — likely No (Option A above). If you have an entity registered somewhere, tell me.

### Founder names, roles, bios

```
Zen Chen (@Ccheh, github.com/Ccheh) — Founder & sole builder.

Background: MSc Data Science, University of Sheffield (ranked #1 in cohort).
Previously crypto-asset audit at a fund; Polymarket researcher; BRC-20 / DARC
prior work.

This month (May 2026) shipped five composable open-source protocols on Arc Testnet:
Cadence (Nanopayments OSS reference impl), Crucible (Schelling consensus on AI
output quality), Helm (futarchy for AI agent collectives), Mandate (capability-
bound authorization), Plinth (capital layer for AI trading agents).

11 Solidity contracts deployed, 176/176 forge tests + 3 fuzz-verified invariants,
11-finding pre-deployment audit with exploit POC + defense test for every Critical/
High, MIT licensed, no admin keys. Four on-chain sibling-protocol compositions
already shipped: MandatePlinthBridge (capability-bound capital), CadencePlinthBridge
(management fee streaming), CruciblePlinthBridge (quality-proportional fee release),
HelmPlinthBridge (metric-conditional fee release). Plus @plinth/verifier-core
npm-ready package extracting the verifier abstraction as public goods, and
PlinthSponsorPool incentive mechanism for Underwriter network sustainability.

Single-founder velocity: 0 → 5 shipped protocols in a single month while a
typical hackathon team ships 1.
```

---

## 2. Project Abstract

### Project Name (max 80 chars)
```
Plinth
```

### One-liner (max 200 chars)
```
On-chain capital layer for AI trading agents on Arc: tokenized fund vaults with capability-not-custody constraints and cryptographically verifiable PnL.
```

### What problem are you solving and why is it important?

```
AI trading agents on Arc face a structural ceiling: they run on their own
balance. The moment they want to take outside capital, they hit a wall —
fund wrappers are heavy and slow, custody is risky for both sides, and even
on-chain agents force depositors to "trust my returns" because no one can
independently verify the agent's reported PnL.

Two specific failures block the entire agentic-trading economy from scaling
beyond demo wallets:

  1. CUSTODY — investors must hand keys or signing authority to an unknown
     agent. No conventional fund-management infrastructure makes this safe
     onchain.

  2. VERIFICATION — when an agent reports profit, the only "proof" is the
     agent's own message on chain. Off-chain venues (Aster, Hyperliquid,
     CEXes, prediction markets) leave depositors trusting the agent's word.

Without solving both, AI trading agents cannot reach the scale Arc's
USDC-native economy was designed for. Capital sits in single agent wallets.
The whole agentic-fund-management lane stays bottlenecked.
```

### What is your solution to that problem?

```
Plinth is the capital layer. The agent creates an on-chain vault with an
immutable, pre-declared whitelist of approved venues. Anyone deposits USDC
and receives shares at current NAV; redemptions are open on demand. The
agent directs vault capital to whitelisted venues — but can never withdraw
to a new address. Capability-not-custody, enforced by the contract.

THE KILLER FEATURE — VERIFIABLE PNL: when the trading venue is itself a
public chain (Aster L1 in our v0 demo; any future Arc-native perp DEX
including Synthra), an independent Underwriter reads the venue's trade
history and cryptographically reconciles the agent's reportPnL on Arc.

Vault #5 ran end-to-end live: 3 real BTC perp round-trips on Aster mainnet,
agent reported −0.047 USDC PnL on Arc, Underwriter independently summed
the venue trades to −0.047 USDC, matched at 0.00% delta — verdict
"VERIFIED" posted on chain. Same vault also has a CRITICAL review from a
separate Risk Monitor (vault went underwater) — by design, multiple lenses
post independently on chain. Investors pick which underwriters to trust.

v0.6 deployed (May 15, 2026) lifts four risk signals from the off-chain
Risk Monitor into on-chain enforcement:
  - createVault flags agent-as-venue (red flag for downstream review)
  - deployToVenue REVERTS at >80% single-venue concentration
  - reportPnL auto-Closes a vault when NAV drops below 10% of inception
  - deposit emits WhaleDeposit when single deposit > 50% of pre-AUM

Closes the persona critique "Risk Monitor is an off-chain script the
author can turn off" — these are now cryptographically enforced for every
vault on v0.6, no admin keys to override.

Four on-chain sibling-protocol compositions already shipped:
  - MandatePlinthBridge — capability-bound credit (Mandate v0 + Plinth)
  - CadencePlinthBridge — management fee streaming through Cadence
    (Arc402) Nanopayments rail
  - CruciblePlinthBridge — quality-proportional fee: Crucible market
    resolves with scoreBps, bridge releases proportional escrow to agent;
    rest refunded to sponsor. Solves the "unconditional management fee"
    problem of Enzyme/dHEDGE.
  - HelmPlinthBridge — metric-conditional fee: at resolve, oracle reads
    on-chain milestone (e.g., NAV growth ≥ X bps); if met, agent gets full
    fee; if not, sponsor refunded. On-chain milestone vesting.

Public-goods extraction (May 2026):
  - @plinth/verifier-core (npm-ready package) — IPerpVerifier interface +
    AsterVerifier reference impl. Any protocol can drop this in their
    Underwriter pipeline. MIT.
  - PlinthSponsorPool — sustainability mechanism for the Underwriter
    network. Vault investors sponsor a per-vault pool; underwriters
    claim a fixed reward per posted review. Plinth itself takes nothing.
    Answers the "where does protocol revenue come from" question honestly:
    the protocol doesn't extract; investors pay for the verification they
    want.
```

### Why hasn't this problem been solved yet? Barriers?

```
Three reasons.

(1) TECHNICAL: prior fund-tokenization protocols (Enzyme, dHEDGE, Set
Protocol) custody assets via multi-sig or executor patterns. Capability
constraints — agent can spend but cannot withdraw — require either novel
contract patterns or significant re-architecture. We chose pre-declared
immutable approvedVenues whitelist + bare-call USDC flow + Plinth-side
accounting; this is conceptually simple but requires the chain to have
USDC as native gas (Arc) to be economically viable. On any L2 with ETH
gas, the gas to settle a sub-cent deposit costs more than the deposit
itself.

(2) ECONOMIC: prior infra requires either ETH-paid gas (kills sub-cent
deposit) or per-vault ERC-20 deployment cost (kills the fee economics for
small vaults). Arc is the first chain where (a) USDC is native gas and
(b) sub-cent settlement makes share economics work at $0.0001 granularity.
Plinth's MIN_DEPOSIT = 0.0001 USDC. This is impossible elsewhere.

(3) VERIFICATION GAP: "agent honesty" was never structurally solved
because venues are typically off-chain (CEXes) or chain-fragmented.
Cross-chain verifiable-PnL via an Underwriter agent that reads venue
trade history and reconciles cryptographically against the on-Arc claim
is a new pattern. It exists today because Aster L1 publishes user-trade
history. As Synthra, Tower Exchange and other Arc-native perp DEXes
mature, this pattern generalizes to "any-Arc-DEX → Plinth Underwriter"
without cross-chain hops.
```

### Why are you and your team uniquely suited to solve this problem?

```
Five shipped protocols this month — Cadence, Crucible, Helm, Mandate, Plinth
— each independent, each MIT, each composable with the others. Four on-chain
sibling-protocol compositions live (Mandate × Plinth, Cadence × Plinth,
Crucible × Plinth, Helm × Plinth). 176/176 forge tests + 3 stateful
invariants verified across 60K+ random call sequences. 11-finding pre-
deployment audit with exploit POC + defense test for every Critical/High.

Prior background that maps directly: crypto-asset audit at a fund
(custody/operational-risk fluency), Polymarket researcher (prediction-
market mechanism design = direct prior for Helm's futarchy + Crucible's
quality consensus), MSc Data Science (Sheffield, ranked #1 in cohort).

Ship velocity: built and deployed 5 independent protocols in 30 days,
solo. The reference implementation of Circle's own Nanopayments pattern
(Tim Baker described April 29) is Cadence — github.com/Ccheh/arc402,
PaymentEscrowV2 already live on Arc Testnet. No team mailing list, no
fundraising overhead. Direct git → contract path.
```

---

## 3. Product Alignment Track

| Field | Answer |
|---|---|
| Is your project currently live in production? | **Yes** (Arc Testnet, audit-grade) |
| Are you live on Arc? | **Yes** (v0, v0.5, v0.6 all deployed on Arc Testnet) |
| Which other chains are you currently live on? | `Arc Testnet only. Aster L1 used as a verifiable-PnL venue (off-chain venue verified cross-chain), not a Plinth deployment chain. Production path documented for USYC on Base via CCTP.` |

### Which Circle products are currently integrated? (check this box list)
- [x] **USDC** — native gas on Arc; MIN_DEPOSIT 0.0001 USDC viable only because of this
- [x] **Bridge Kit** — `@circle-fin/bridge-kit` wired into `sdk-ts/examples/yield-strategy.ts`
- [x] **CCTP** — production path for USYC on Base; `@circle-fin/provider-cctp-v2` integrated
- [x] **Contracts** — Arc Testnet contracts (PlinthV05, V06, MockYieldVenue, MorphoVenueAdapter scaffold, SynthraSpotVenue scaffold, MandatePlinthBridge, CadencePlinthBridge, CruciblePlinthBridge, HelmPlinthBridge, PlinthSponsorPool, MockVenue — 11 total)
- [ ] EURC
- [ ] Gateway (planned v0.7)
- [ ] Paymaster
- [ ] Wallets (planned for institutional issuers via Mandate)

### Which Circle products do you plan to integrate?
- [x] **Gateway** — unified balance for cross-chain depositors (v0.7)
- [x] **Wallets** — agent wallet abstraction (v0.7)
- [x] **CCTP v2** — production USYC bridging from Arc to Base (v0.7)

---

## 4. Milestones and Timelines

(Submit each as a separate milestone in the form. Each has a title up to 1024 chars and details up to 2048 chars.)

### Milestone 1 — External audit + mainnet readiness ($10K, Month 1)

Title:
```
M1: External smart-contract audit + 5 third-party agent vaults on testnet
```

Details:
```
Funded primarily by this milestone:
  - Engage Trail of Bits / Spearbit / OpenZeppelin for a focused
    audit pass on PlinthV06 + CadencePlinthBridge + MandatePlinthBridge.
    Estimated cost: $8K (4-day engagement at solo-build complexity).
  - Remaining $2K: bug-fix bounty for any High findings from the audit.

Concurrent outreach:
  - 5 third-party teams (RFB participants from this hackathon + Canteen
    Discord + Arc community) create their own agent vaults on PlinthV06.
  - At least one not associated with the operator (we are honest about
    Bob and Charlie being operator-orchestrated; the Grant milestone
    measures unaffiliated agents).

Deliverable: third-party audit report posted in docs/security-audit-trailofbits.md,
linked from README. 5 vault creation tx hashes on Arc Testnet.
```

### Milestone 2 — Production USYC integration ($10K, Month 2)

Title:
```
M2: Production USYC integration on Base via CCTP — real yield, not mock
```

Details:
```
The v0.5 MockYieldVenue accrues a fixed 5% APR for testing. The v0.6
MorphoVenueAdapter is a scaffold awaiting Morpho's Arc deployment.
M2 ships the real production path: vault idle USDC routes from Arc to
Base via CCTP, swaps to USYC on Base, accrues real T-bill yield, and
redeems back via CCTP when capital is requested.

Funded:
  - $4K: Engineering time — CCTP-v2 integration for the Arc → Base bridge
    leg; USYC AMM pool integration; back-and-forth bridge cost analysis.
  - $3K: Testnet integration testing (we use Arc Testnet + Base Sepolia
    for USYC mock during development).
  - $3K: Production deployment to Arc Mainnet (when available) and Base
    mainnet; small-amount stress testing.

Deliverable: sdk-ts/examples/yield-strategy.ts upgraded from
documentation-only to executable end-to-end. Live tx: vault deploys
USDC → CCTP burn on Arc → CCTP mint on Base → USYC pool deposit →
~30 days of accrued yield → USYC redeem → CCTP back to Arc.
```

### Milestone 3 — Gateway integration ($10K, Month 3)

Title:
```
M3: Plinth × Gateway integration — unified depositor balance across chains
```

Details:
```
Investors come from many chains. Currently a Plinth depositor needs USDC
on Arc + an Arc-supporting wallet. Circle Gateway provides unified balance
across chains via 1-click cross-chain spend.

Integration: Plinth depositors specify destination Plinth vault from any
chain Gateway supports. Plinth-side adapter contract wraps Gateway's
unified-balance withdrawal logic; depositor signs a single Gateway claim;
Plinth credit appears in the vault.

Funded:
  - $4K: Engineering time — Plinth × Gateway adapter contract.
  - $3K: Audit (lightweight pass on the new adapter).
  - $3K: SDK + docs + demo deposit flow video.

Deliverable: PlinthGatewayBridge contract on Arc Testnet, demo deposit
from Ethereum / Base / Optimism into a Plinth vault on Arc via Gateway.
```

### Milestone 4 — Mainnet + first $5K real TVL ($10K, Month 4)

Title:
```
M4: PlinthV1 mainnet deployment + first $5K real TVL
```

Details:
```
Mainnet readiness requires:
  - External audit (done in M1) — needed before any real capital.
  - Bug bounty program announcement on Immunefi / Code4rena equivalent.
  - $5K of real (not testnet) TVL across at least 2 unaffiliated agent
    vaults on Arc Mainnet (when available; if Arc Mainnet ships during
    Cohort 2 window).

Funded:
  - $4K: Mainnet deployment costs (gas, multi-environment config).
  - $4K: Bug bounty seed reward pool.
  - $2K: Outreach + listing on agent-ecosystem directories.

Deliverable: PlinthV1 mainnet address, live vault demo with $5K+ TVL,
Immunefi listing.
```

### Milestone 5 — Underwriter network growth + verifier-core ecosystem ($10K, Month 5)

Title:
```
M5: Underwriter sustainability — @plinth/verifier-core published + 5 venue adapters + SponsorPool TVL milestone
```

Details:
```
The two compositions originally scoped for M5 (Crucible × Plinth, Helm ×
Plinth) shipped in May 2026 before submission. M5 now funds the next
unsolved problem: making the Underwriter network sustain without Plinth
itself extracting protocol revenue.

(a) PUBLISH @plinth/verifier-core to npm:
    - IPerpVerifier interface + classify() verdict logic + renderMarkdown()
      already scaffolded in verifier-sdk/.
    - 5 venue adapter implementations to ship: AsterVerifier (DONE
      reference impl) + SynthraPerpVerifier (Arc-native perp DEX) +
      HyperLiquidVerifier (chainId 998) + generic Uniswap-v3-style DEX
      verifier + ASTERdex-style CEX base class.
    - First external protocol PR using @plinth/verifier-core in their
      Underwriter pipeline.

(b) Bootstrap PlinthSponsorPool:
    - PlinthSponsorPool deployed (0xf28a58e7...) — sponsor()/claim() flow
      verified, dedup verified, refill cycle verified.
    - M5 deliverable: $500-equivalent USDC sponsorship across 10+ vaults
      seeded by Plinth treasury + external investor co-sponsorship; 50+
      distinct underwriter addresses claim.

(c) 3 third-party integrations:
    - Either external protocol calls Plinth (perp DEX listing vaults,
      Telegram management bot, analytics dashboard), OR external protocol
      drops in @plinth/verifier-core in their own Underwriter pipeline.

Funded:
  - $4K: 4 additional venue verifier implementations (Synthra perp,
    HyperLiquid, Uniswap-v3 generic, CEX base class).
  - $3K: PlinthSponsorPool seed + co-sponsorship outreach.
  - $3K: 3 third-party integration support / co-development.

Deliverable: @plinth/verifier-core published to npm at v1.0. 50+ unique
underwriter address claims via SponsorPool on chain. 3 third-party
integration tx hashes.
```

---

## 5. Project Traction and Roadmap

### Current traction (transaction volume, growth, MAU, AUM)
```
HONEST FRAMING (we always lead with this — see Canteen submission):

Plinth is a 12-day solo-built infrastructure protocol. External "real user"
traction in this window is structurally bounded — the meaningful ceiling
for solo infra submissions is 5-10 integrating teams, not a consumer-app
DAU curve. Below is split: what we can honestly claim, and the technical-
traction substrate that makes future user adoption credible.

(a) EXTERNAL VALIDATION we can honestly claim:
  - 0 unaffiliated third-party depositors yet. Bob and Charlie are
    operator-orchestrated test signers, transparently disclosed in
    docs/charlie-test.md and underwriter bob-review markdown. Honesty
    matters more to us than vanity TVL.
  - 3 substantive bug-fix PRs to circlefin/* (all open at submission time),
    plus 3 minor docs fixes (closed/merged):
      - circlefin/arc-multichain-wallet #37 — fix(arc-testnet): correct
        native token symbol, decimals, and explorer URL
        (https://github.com/circlefin/arc-multichain-wallet/pull/37)
      - circlefin/arc-fintech #19 — fix(arc-testnet): native USDC has 18
        decimals, fix broken explorer URL
        (https://github.com/circlefin/arc-fintech/pull/19)
      - circlefin/skills #24 — docs(use-arc): add Common Pitfalls section
        with empirical gotchas
        (https://github.com/circlefin/skills/pull/24)
      - Plus 3 closed docs-fix PRs to circlefin/arc-p2p-payments,
        arc-escrow, arc-fintech (incorrect git-clone URLs in READMEs).
  - Charlie wallet end-to-end test: fresh wallet → Circle public faucet →
    Plinth deposit, all txs on chain at testnet.arcscan.app.

(b) TECHNICAL TRACTION:
  - 11 Solidity contracts shipped on Arc Testnet (PlinthV05, PlinthV06,
    MockYieldVenue, MorphoVenueAdapter scaffold, SynthraSpotVenue scaffold,
    MandatePlinthBridge, CadencePlinthBridge, CruciblePlinthBridge,
    HelmPlinthBridge, PlinthSponsorPool, MockVenue).
  - 176/176 unit tests + 3 fuzz-verified stateful invariants (60K+ random
    call sequences over 250s of fuzzing).
  - 11-finding pre-deployment audit (self-audit, external audit funded
    in M1 of this grant).
  - 3 real BTC perp round-trips on Aster L1 mainnet, $0.13 experimental
    cost. 6 underwriter reviews on chain (2 cryptographically VERIFIED).
  - 4 on-chain sibling-protocol compositions live (MandatePlinthBridge +
    CadencePlinthBridge + CruciblePlinthBridge + HelmPlinthBridge).
  - @plinth/verifier-core npm-ready package (IPerpVerifier interface +
    AsterVerifier reference + SynthraPerpVerifier scaffold).
  - PlinthSponsorPool — sustainability layer for Underwriter network.
  - 5 of 9 Arc Blueprints explicitly addressed (Agentic Economy, Treasury
    Management, Lending/Borrowing, Capital Markets Settlement, Onchain
    Credit Markets).
  - Live web UI: https://ccheh.github.io/plinth
  - Pitch video (2:51): https://youtu.be/OKGAcKOUQaw
  - Investor deck (PDF, 5 slides): docs/deck/plinth-deck.pdf
  - Codebase walkthrough video (4:30): video/demo-codebase.mp4

(c) ECOSYSTEM FOOTPRINT:
  - 5 sibling Arc protocols built this month (Cadence/Crucible/Helm/
    Mandate/Plinth) — each independent, each composes.
  - Arc Architects program: applied + pending.
  - Canteen × Circle Agora Agents Hackathon: submission live.
  - 15-minute integration quickstart for agent builders: docs/quickstart-
    for-agents.md.

If "traction" means measurable end-user count, we are honest about being
early. If it means "is this real or vaporware", every claim above resolves
to a tx hash, a test count, or a public URL.
```

### Are you funded? (Yes/No)
**No** — solo, self-funded, no prior VC or angel investment. This Grant
would be the project's first external funding.

### Technical Roadmap (timeline + grant milestones)
```
Already shipped (pre-grant, May 2026):
  v0    — Plinth v0, MockVenue ×2, on Arc Testnet
  v0.5  — Security-hardened (deposit cooldown, PnL magnitude cap, rate
          limit, returnFromVenue access control), 11-finding audit
  v0.6  — On-chain RiskGuard (agent-as-venue flag, venue concentration
          cap, NAV floor auto-close, whale deposit flag), 176/176 +
          3 invariants verified
  + IYieldVenue interface, MorphoVenueAdapter scaffold
  + SynthraSpotVenue (Arc-native DEX adapter)
  + MandatePlinthBridge (composition #1)
  + CadencePlinthBridge (composition #2)
  + CruciblePlinthBridge (composition #3 — quality-proportional fee)
  + HelmPlinthBridge (composition #4 — metric-conditional fee)
  + @plinth/verifier-core (npm-ready public-goods package)
  + PlinthSponsorPool (Underwriter network incentive layer)

Grant funded (months 1-5):
  M1 (Month 1) — External audit + 5 third-party testnet vaults
  M2 (Month 2) — Production USYC integration on Base via CCTP
  M3 (Month 3) — Plinth × Gateway integration
  M4 (Month 4) — PlinthV1 mainnet deployment + first $5K real TVL
  M5 (Month 5) — 3 third-party integrations + ecosystem composition library

Post-grant (months 6+):
  v1.x — Live mainnet, expand venue adapter library (Morpho when live on
         Arc, Aave, Tradable for institutional credit, real Synthra perp
         when ABI publishes)
  v2.0 — Multi-asset vaults (BTC, ETH, stablecoins), Cadence-streaming
         management fees as native primitive, Crucible-conditional fee
         tiers
```

### How will this grant support your technical roadmap?
```
The grant accelerates Plinth from testnet infrastructure to mainnet-ready
production protocol. Specifically:

  - Funds external audit (M1) — this is the unlock for mainnet trust
  - Funds real Circle production integration (M2 + M3 — USYC via CCTP +
    Gateway) — moves Plinth from "Circle SDK integrated as scaffold" to
    "Circle products live in production"
  - Provides runway to bootstrap a real ecosystem (M4 + M5) — all 4
    sibling-protocol bridges (Mandate / Cadence / Crucible / Helm × Plinth)
    are already live pre-grant; M5 funds the next-order problem of
    making the Underwriter network sustain via @plinth/verifier-core
    npm publish + 5 venue adapters + PlinthSponsorPool TVL milestone,
    plus integration support for 3+ third-party teams

Without the grant: Plinth stays at v0.6, testnet-only, self-audit. Bob
and Charlie remain the only on-chain wallets. The 5-protocol composition
story stays at "4 bridges live + 2 OSS extractions" on testnet without
production rollout.

With the grant: Plinth ships to mainnet, with external audit + production
Circle integrations + real TVL + 3+ third-party teams composing on top.
The "5 sibling protocols compose into a complete agent-economy stack"
narrative shifts from "deployed on testnet" to "lived mainnet ecosystem".
```

---

## 6. Deck and Demo

### Video demo of the product (Google Drive / YouTube unlisted)
```
Pitch video (2:51):          https://youtu.be/OKGAcKOUQaw
Codebase walkthrough (~6:00): [YouTube unlisted URL — to be uploaded after recording finishes]
```
> Pitch video covers Verifier, Risk Monitor, audit, v0.5, Mandate composition,
> yield strategy. Codebase walkthrough is one cohesive 14-slide video: Part 1
> (4 codebase locations — PlinthV06 RiskGuard hooks, Cadence bridge, Circle
> SDK wiring, Charlie wallet + Aster PnL reconciliation) + Part 2 (4 innovations
> shipped pre-submission — Crucible × Plinth, Helm × Plinth, @plinth/verifier-core,
> PlinthSponsorPool).

### Investor deck (Google Drive / Dropbox)
```
docs/deck/plinth-deck.pdf — 5 slides, 1920×1080, 120KB
Hosted at: https://github.com/Ccheh/plinth/releases/download/v0-demo/plinth-deck.pdf
```
> Slides: (1) Title + state, (2) Problem (custody + verification gap),
> (3) 5-protocol stack + 4 compositions live, (4) Verifiable PnL sequence
> diagram (Vault #5 case study), (5) State today + grant roadmap.

---

## 7. Conflict of Interest

| Field | Answer |
|---|---|
| Conflict of interest | **No** (no financial, family, or relationship with Circle / its subsidiaries / current Circle employees) |

---

## ⏰ Recommended timing — DO NOT SUBMIT YET

This is a multi-month commitment from Circle's side. Submitting before the
**May 22 Circle Developer Grants Workshop** is strategically worse than
submitting a polished version after, because:

1. Workshop attendees often get cited examples + evaluator priorities live.
2. The workshop may reveal new milestone-shape preferences.
3. Submitting after the workshop signals you took the prep seriously.

**Suggested timeline**:
- **May 22** — attend workshop, take notes
- **May 23-25** — incorporate workshop feedback into this draft; record
  supplementary codebase walkthrough video
- **May 26-28** — Submit

---

## What you need to decide / provide before we can fill the form

| Item | Status |
|---|---|
| Company Legal Entity Name | ✓ DECIDED — "Independent Builder" |
| Founder location | ✓ DECIDED — "Zen Chen, Founder & Sole Builder, Sheffield, UK" |
| Investor deck | ✓ BUILT — docs/deck/plinth-deck.pdf (5 slides, updated 2026-05-16) |
| Codebase walkthrough video | ✓ BUILT — video/demo-codebase.mp4 (4:30) |
| Addendum video (4 new innovations) | ⏳ to record (60-90s) |
| YouTube unlisted upload | ⏳ pending |
| Submission timing | Ready to submit after addendum + YouTube uploads |
| Final ask amount | ✓ DECIDED — $50K across 5 milestones |

Remaining gates: record + upload addendum video → upload codebase walkthrough →
paste URLs into this draft → fill questbook portal step-by-step.
