# Plinth

> **Capital layer for AI trading agents on Arc.** AI agents create on-chain
> vaults to raise external USDC; anyone deposits and receives shares;
> redeem at current NAV at any time; agent deploys vault capital only to
> a pre-declared, immutable whitelist of venues. Hedge-fund-grade
> infrastructure for the agentic economy.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-158%2F158%20%2B%203%20invariants-success)](#)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue)](contracts/foundry.toml)
[![Audit](https://img.shields.io/badge/security--audit-11%20findings%20documented-orange)](docs/security-audit.md)
[![Arc Testnet](https://img.shields.io/badge/Arc%20Testnet-v0.6%20live-brightgreen)](https://testnet.arcscan.app/address/0x17B7B30d324Add96c5dC5d3259746695e94c92C9)

### Aligned with Arc Blueprints

Plinth is infrastructure that hits **5 of Circle's 9 official [Arc Blueprints](https://www.arc.io/blog)** (use-case briefs Arc published May 2026). Each row maps a blueprint to the specific Plinth primitive that addresses it:

| Arc Blueprint | How Plinth addresses it |
|---|---|
| **[Agentic Economy](https://www.arc.io/blog/how-arc-supports-the-agentic-economy-arc-blueprints)** | Plinth IS the capital layer for AI agents — vault creation, NAV accounting, capability-not-custody constraints. Five sibling protocols (Cadence/Crucible/Helm/Mandate/Plinth) compose into an agent-economy stack |
| **[Treasury Management](https://www.arc.io/blog/how-arc-supports-treasury-management-arc-blueprints)** | A Plinth vault IS the AI agent's on-chain treasury: idle USDC sweeps to yield via `IYieldVenue` adapters (Morpho-ready), trading capital routes via approved-venue whitelist, redemptions open at NAV |
| **[Lending and Borrowing](https://www.arc.io/blog/how-arc-supports-lending-and-borrowing-arc-blueprints)** | `MorphoVenueAdapter` (ERC-4626 scaffold) plugs Plinth vaults into Morpho on Arc when live. Capability constraints on the borrower side: agent can route to approved lending venues but never withdraw to arbitrary addresses |
| **[Capital Markets Settlement](https://www.arc.io/blog/how-arc-supports-capital-markets-settlement-arc-blueprints)** | Verifiable PnL = settlement primitive: when the trading venue is itself a public chain (Aster L1, Synthra perp on Arc), an independent Underwriter reconciles agent-reported PnL cryptographically. Vault #5: matched to 0.00% delta on chain |
| **[Onchain Credit Markets](https://www.arc.io/blog/how-arc-supports-onchain-credit-markets-arc-blueprints)** | `MandatePlinthBridge` is the first on-chain sibling-protocol composition: institutional issuers authorize agent-mediated deposits with cryptographic capability constraints across both protocols — capability-bound credit. [`Live tx`](https://testnet.arcscan.app/tx/0x4bdb577e6c4698cae3f2f3a8cc010e0cb9d95cb6e06ba83a5580e3bf72fec4ea) |

### v0.6 on Arc Testnet (recommended — RiskGuard + Cadence composition)

| Contract | Address | Deploy tx |
|---|---|---|
| **PlinthV06** ⭐ | [`0x17B7B30d324Add96c5dC5d3259746695e94c92C9`](https://testnet.arcscan.app/address/0x17B7B30d324Add96c5dC5d3259746695e94c92C9) | [`0x183557ce...`](https://testnet.arcscan.app/tx/0x183557ce3a5ec5ab40ca72d1176fc9deb2be6ea2291d5a3e9b69a695cc0c23e4) |
| **CadencePlinthBridge** ⭐ (2nd cross-protocol composition) | [`0x9E3c322c19b13317C662af39994573de6daB5347`](https://testnet.arcscan.app/address/0x9E3c322c19b13317C662af39994573de6daB5347) | [`0xf5cb23cf...`](https://testnet.arcscan.app/tx/0xf5cb23cf4d7e81dc370f66cd53da05296b7ac69fb0b4159b0c524af3e0e15538) |
| **CruciblePlinthBridge** ⭐ (3rd cross-protocol composition) | [`0xa948e26546c3634da03df8b078b1c8d79ba54a78`](https://testnet.arcscan.app/address/0xa948e26546c3634da03df8b078b1c8d79ba54a78) | [`0xf8a346dd...`](https://testnet.arcscan.app/tx/0xf8a346dd49c8399d20527a185352571a779afcf610fbda7bda19dd0ef27253e5) |

v0.6 adds on-chain enforcement of 4 risk signals previously off-chain (agent-as-venue flag, 80% venue concentration cap, NAV floor auto-close at 10%, whale deposit flag) plus **3 sibling-protocol compositions live** (Mandate × Plinth · Cadence × Plinth · Crucible × Plinth). The 3rd composition — `CruciblePlinthBridge` — implements **quality-conditional management fees**: vault investors escrow a fee budget tied to a Crucible quality market; on resolution, the agent receives a fraction proportional to the scoreBps (0-10000). First on-chain quality-conditional management-fee mechanism in the Arc ecosystem.

### v0.5 on Arc Testnet (security-hardened, still live as historical reference)

| Contract | Address | Deploy tx |
|---|---|---|
| **PlinthV05** | [`0xba1b087b0ac77b398c250a9fd7e298f3f96addc7`](https://testnet.arcscan.app/address/0xba1b087b0ac77b398c250a9fd7e298f3f96addc7) | [`0x55bd1dce...`](https://testnet.arcscan.app/tx/0x55bd1dced631429fa86357d54030004feafc91e687863cddd0cddbb489f2a91d) |
| **MockYieldVenue** (T-bill cash-sweep) | [`0xe5cceca53ccb15affc58016e1757e1a138ef3144`](https://testnet.arcscan.app/address/0xe5cceca53ccb15affc58016e1757e1a138ef3144) | [`0x8714eb2d...`](https://testnet.arcscan.app/tx/0x8714eb2d72daf7e7d49a1db95a80a78f94f6214669448c841817ca432cb837b9) |
| **MandatePlinthBridge** (1st Plinth × Mandate compose) | [`0x0b92b6e4fa26e6c2b10a5c668d8313a1bf8c3f50`](https://testnet.arcscan.app/address/0x0b92b6e4fa26e6c2b10a5c668d8313a1bf8c3f50) | [`0x9a7c9f97...`](https://testnet.arcscan.app/tx/0x9a7c9f97ef67167d9c2114002da220ec548cb18b524fbe9af221122a48a32057) |

Closes **6 audit findings** vs v0 ([full report](docs/security-audit.md)): sandwich-on-reportPnL, returnFromVenue griefing, reportPnL inflation rug, reportPnL on Closed vault, reportPnL magnitude overflow, strategyDescriptor unbounded length. **145/145 unit tests + 3 stateful invariants** (5 exploit POCs + 18 v0.5 defense + 14 v0.6 RiskGuard + 12 Cadence×Plinth bridge + 8 yield-strategy + 10 Morpho adapter + 11 Synthra spot + 67 other + 3 fuzz-verified invariants: solvency, deployedAUM ledger consistency, shares conservation — verified across 60K+ random call sequences over 250s of fuzzing).

**v0.6 RiskGuard (just shipped)**: four risk signals previously enforced only by the off-chain `risk-monitor.ts` script are now **on-chain primitives** in [`PlinthV06.sol`](contracts/src/PlinthV06.sol) — no admin key, no off-chain dependency:

| # | Signal | v0.5 | v0.6 |
|---|---|---|---|
| 1 | Agent listed as own venue | Risk Monitor flag (off-chain) | `createVault` emits `AgentAsVenueFlag` |
| 2 | Single-venue > 80% concentration | Risk Monitor flag | `deployToVenue` **REVERTS** with `VenueConcentrationExceeded` |
| 3 | NAV < 10% of inception | Risk Monitor flag | `reportPnL` **auto-Closes** the vault, investors retain redemption |
| 4 | Whale deposit > 50% of AUM | Risk Monitor flag | `deposit` emits `WhaleDeposit` for Underwriter pipeline |

This closes the persona-8 critique of v0.5 ("Risk Monitor is a script the author can turn off") — those four protections are now cryptographically enforced for every vault on v0.6, with no recourse to admin keys.

First v0.5 vault on chain ([explorer](https://testnet.arcscan.app/tx/0x5d3fc733eb32502f601741874333abde69c2940b5e071bd92b182116100b4e28)) with deposit cooldown firing as expected: investor deposit `0x2dc4b91c...` → simulated immediate redeem reverts with `SharesPendingVesting (0x6ba41e7c)`.

### v0 on Arc Testnet (historical / demo artifact)

| Contract | Address | Deploy tx |
|---|---|---|
| **Plinth v0** | [`0xc2994ce3df612ebd2f898244a992a0bbfef86627`](https://testnet.arcscan.app/address/0xc2994ce3df612ebd2f898244a992a0bbfef86627) | [`0xe10e704a...`](https://testnet.arcscan.app/tx/0xe10e704a6b7240095b74518da5e94ae3086237dd71ff05f2fbc52cfd615fe583) |
| **MockVenue #1** | [`0x50bf887e4957261e7ca0c6b4eeb61ab83ad6ddcd`](https://testnet.arcscan.app/address/0x50bf887e4957261e7ca0c6b4eeb61ab83ad6ddcd) | [`0x62e48b43...`](https://testnet.arcscan.app/tx/0x62e48b43311e339e2193b138e5e4a71cb65e97d725b0b89d4b3900fd16964bca) |
| **MockVenue #2** | [`0xc0f8d26cbf7123b0f5148b9feae6c3234cccda35`](https://testnet.arcscan.app/address/0xc0f8d26cbf7123b0f5148b9feae6c3234cccda35) | [`0x85b612e2...`](https://testnet.arcscan.app/tx/0x85b612e25177985922e546366c67bd63b64c944c50c9226238c71d93b2574e4d) |

v0 is preserved on chain as the historical/demo artifact (5 vaults with full lifecycles, 3 Aster L1 round-trips, 6 underwriter reviews including 2 verifiable-PnL reviews and 2 risk alerts). MockVenue contracts are reused by v0.5.

Combined deployed gas (v0 + v0.5): ~4M (~0.16 USDC at 40 gwei).

- **Web UI**: https://ccheh.github.io/plinth/
- **Verifiable-PnL Demo (interactive)**: https://ccheh.github.io/plinth/verify.html — reconciliation runs in your browser
- **Pitch video**: [demo.mp4 (~3 min, v0.5 + composition + yield)](https://github.com/Ccheh/plinth/releases/download/v0-demo/demo.mp4) — covers Verifier, Risk Monitor, security audit, v0.5, Mandate composition, yield strategy
- **Submission one-pager**: [docs/submission.md](docs/submission.md)
- **Quickstart for agent builders** (15 min integration): [docs/quickstart-for-agents.md](docs/quickstart-for-agents.md)
- **Security audit**: [docs/security-audit.md](docs/security-audit.md) — 11 findings, 6 closed in v0.5

### Live vaults (as of submission)

| Vault | Strategy descriptor | Status | NAV |
|---|---|---|---|
| #1 `0xc4c82a67...` | BTC perp momentum, max 3x leverage, daily rebalance | full lifecycle ran (deposit, deploy, +PnL, redeem) | 1.375 USDC/share |
| #2 `0xd33068c5...` | ETH/USDC mean reversion, 1x cash, slow weekly rebalance | 2 depositors, 0.007 USDC TVL | 1.0 |
| #3 `0x5c7eebdb...` | SOL perp grid bot, 2x leverage, ±5% bands | deployed 0.002 to venue, +0.001 PnL reported | 1.333 |
| #4 `0x71002b00...` | Multi-asset cross-chain arbitrage via CCTP | fresh, awaiting depositors | 1.0 |
| #5 `0xefb495a0...` | **BTC perp via Aster L1 — verifiable PnL demo** | **3 real Aster round-trips ran, Underwriter posted `VERIFIED` + `CRITICAL` (independent reviewers)** | underwater (correctly flagged) |

Plus **6 underwriter reviews** on chain — 1 LLM-generated, 1 3rd-party, **2 cryptographically verified** against Aster L1 trade history (vault #5, Phase 3 + Phase 5), and **2 risk alerts** auto-generated by an off-chain Risk Monitor (vault #5 `CRITICAL` + vault #1 `HIGH`).

### Security — pre-deployment audit + 6 findings closed in v0.5

[`docs/security-audit.md`](docs/security-audit.md) is the full in-team audit of Plinth v0 (290 LOC), conducted before any production deployment. **11 findings total**: 1 Critical, 2 High, 3 Medium, 2 Low, 3 already-safe-by-design.

Every Critical/High finding has both an **exploit POC test** in [`Plinth.t.sol`](contracts/test/Plinth.t.sol) (proving the v0 vulnerability is real) and a **defense test** in [`PlinthV05.t.sol`](contracts/test/PlinthV05.t.sol) (proving v0.5 closes it):

| Finding | Severity | v0 status | v0.5 fix |
|---|---|---|---|
| #1 `reportPnL` sandwich extraction | 🔴 Critical | exploitable (POC: attacker exits with profit) | deposit cooldown — `SharesPendingVesting` revert |
| #2 `returnFromVenue` open access griefing | 🟠 High | exploitable (POC: 3rd party redirects venue funds) | caller must be `venue` or `agent` |
| #3 `reportPnL` magnitude / rate unbounded | 🟠 High | exploitable (POC: NAV inflation rug) | 10× capital cap + 25%/hr rate limit |
| #4 `reportPnL` allowed on Closed vault | 🟡 Medium | exploitable (POC: exit-NAV manipulation) | rejected on Closed |
| #6 `reportPnL` near INT256 bounds | 🟡 Medium | theoretical | bounded by #3 fix |
| #8 `strategyDescriptor` unbounded length | 🟢 Low | griefing via gas | `MAX_STRATEGY_LEN = 1024` |

Two findings deferred to v0.6 (#5 funds stuck at venue post-close; #7 createVault spam — both have documented mitigations). Three findings are already safe-by-design (reentrancy via OZ `ReentrancyGuard` + CEI; donation attack neutralized by per-vault accounting; first-depositor inflation prevented by NAV reading storage not balance).

A v0.5 vault is live on chain with deposit cooldown firing correctly: see [`Plinth.t.sol`](contracts/test/Plinth.t.sol) exploit tests and [`docs/security-audit.md`](docs/security-audit.md) for the full report.

### Yield Strategy — vault cash-sweep into T-bill yield (testnet mock, real USYC in production)

A real AI-trading fund leaves significant capital idle most of the time. Plinth's capability-constraint model makes "cash sweep into a yield venue" a clean, in-architecture pattern: deploy idle USDC to a yield venue exactly the same way capital flows to a trading venue.

Live on Arc Testnet:
- **MockYieldVenue** at `0xe5cceca53ccb15affc58016e1757e1a138ef3144` accrues continuous 5% APR on principal, with pre-funded reserve backing payouts.
- Demo lifecycle ([sdk-ts/examples/yield-strategy.ts](sdk-ts/examples/yield-strategy.ts)) ran end-to-end: agent creates vault → investor deposits 0.005 USDC → agent sweeps 0.004 to yield venue → 180s passes → yield accrues exactly `1.218 × 10^-9 USDC` (matches `5% × 0.004 × 180/(365×24×3600)` to 12 decimals) → agent reports as PnL → NAV moves from `1.0` to `1.000000202943`.
- On-chain evidence: [vault page](https://testnet.arcscan.app/tx/0xe1d50bb3259be427bc14f1b124e6ec1ea0fe4b7ba085f46ba055069beebc4be7) · [deploy-to-venue tx](https://testnet.arcscan.app/tx/0xba87e4a011bbe03ea83d1676147cf693d0494210c1ad3d93b8cd475c37f98320) · [reportPnL tx](https://testnet.arcscan.app/tx/0x598d2d8ce6b4b19846fcadcfdb5decf640963588f80f1b7c96bc09977bd52884)

The Verifier pattern from Aster L1 applies identically: any third party can read `MockYieldVenue.accruedYield()` on chain and reconcile it against the agent's `reportPnL` value. Same architecture, different yield source.

**Pluggable yield-venue architecture (v0.6)**: All yield venues now implement a common [`IYieldVenue`](contracts/src/interfaces/IYieldVenue.sol) interface, making the production swap drop-in. Shipped adapters:

| Adapter | Status | Underlying |
|---|---|---|
| [`MockYieldVenue`](contracts/src/MockYieldVenue.sol) | ✅ Live on Arc Testnet | Fixed 5% APR simple-interest mock |
| [`MorphoVenueAdapter`](contracts/src/MorphoVenueAdapter.sol) | 🟡 Scaffold (placeholder mode) — production-ready, awaiting Morpho's Arc deployment | Morpho Vault V2 (ERC-4626) |
| [`SynthraSpotVenue`](contracts/src/SynthraSpotVenue.sol) | 🟡 Scaffold (placeholder mode) — production-ready, deploy with Synthra's verified SwapRouter address | Synthra v3 spot AMM (Uniswap v3 fork on Arc) |

All adapter contracts are fully unit-tested against canonical mock counterparties (21 new tests covering placeholder + production modes, full lifecycle, slippage protection, agent-only access control). When Morpho lands on Arc, `MorphoVenueAdapter` constructor takes the real vault address and the placeholder gate flips off — zero changes to Plinth. Same pattern for Synthra spot.

**Verifier abstraction (v0.6)**: The Underwriter pipeline now operates against a venue-agnostic [`IPerpVerifier`](aster/perp-verifier.ts) interface. `AsterVerifier` (cross-chain via Aster L1) and `SynthraPerpVerifier` (Arc-native scaffold) both implement it, so a single Underwriter codebase reconciles agent reportPnL against any registered venue.

**Production wiring path** (documented end-to-end in [`yield-strategy.ts`](sdk-ts/examples/yield-strategy.ts)): the real **USYC** token on Base (Circle's tokenized US Treasury Bills), bridge Arc USDC↔Base via **CCTP** using `@circle-fin` SDKs. The Plinth contract itself is unchanged — USYC just slots in as another approvedVenue under the same `IYieldVenue` abstraction.

### Sibling protocol composition — three on-chain compositions shipped

Five protocols (Cadence, Crucible, Helm, Mandate, Plinth) ship as independent contracts. The README has long described how they compose architecturally; v0.5 + v0.6 ship **three actual on-chain compositions** — each one a different mechanism:

| # | Bridge | What it composes | Mechanism |
|---|---|---|---|
| 1 | [`MandatePlinthBridge`](contracts/src/MandatePlinthBridge.sol) | Mandate v0 + PlinthV05 | **Capability-bound capital authorization** — institutional issuer authorizes agent-mediated deposits with cryptographic constraints across both protocols |
| 2 | [`CadencePlinthBridge`](contracts/src/CadencePlinthBridge.sol) | Plinth + Cadence (Arc402) PaymentEscrowV2 | **Management-fee streaming** — vault depositors route fees to the vault's agent via Cadence's Nanopayments rail. Bridge reads agent from Plinth (no spoofing), forwards funds via `depositFor`. Agent then has full Nanopayments downstream: signed claims, batched settlement, session keys. |
| 3 | [`CruciblePlinthBridge`](contracts/src/CruciblePlinthBridge.sol) | Plinth + CrucibleMarketV6 | **Quality-conditional management fees** — investor escrows fee budget tied to a Crucible quality market. When the market resolves with `scoreBps`, the bridge releases a proportional fraction to the agent and refunds the remainder to the investor. Below a minimum score: full refund. First on-chain implementation of quality-conditional management fees (to the author's knowledge). |

The CadencePlinthBridge is the second-shipped composition. 12 tests cover: end-to-end credit flow, agent-spoofing resistance, per-vault accumulation, multi-vault tracking, sponsorship pattern (funder ≠ agent), zero-value / non-existent-vault / cadence-failure reverts. Deployment: bridge takes `(PlinthV05/V06 address, PaymentEscrowV2 address)` at construction.

Below: the original Mandate × Plinth composition still ships unchanged.

### Mandate × Plinth on chain (first composition)

The original Mandate composition: Mandate authorizes Plinth-vault deposits via a bridge contract.

The story it enables: an institutional issuer (bank, fund, corporate treasury — typically a multi-sig) creates a Mandate authorizing an AI agent to deposit USDC into a specific Plinth Vault, bounded by spend ceiling + counterparty whitelist + purpose whitelist + time window. The agent calls [`MandatePlinthBridge.depositViaMandate`](contracts/src/MandatePlinthBridge.sol) which atomically pulls capital out of the mandate (Mandate.execute) and deposits it into the vault (Plinth.deposit), with shares recorded under the mandate's issuer. Even if the agent's private key is compromised, the agent cannot redeem the shares — capability constraint preserved across both protocols.

Live on Arc Testnet:
- **MandatePlinthBridge** at `0x0b92b6e4fa26e6c2b10a5c668d8313a1bf8c3f50` wires [`Mandate`](https://testnet.arcscan.app/address/0xfBBDAeC05E0061ADeb955896DFF183fdd412E6E4) to [`PlinthV05`](https://testnet.arcscan.app/address/0xba1b087b0ac77b398c250a9fd7e298f3f96addc7).
- Demo lifecycle ([sdk-ts/examples/mandate-plinth-composition.ts](sdk-ts/examples/mandate-plinth-composition.ts)) ran end-to-end on chain:
  1. Vault created on Plinth v0.5 with bridge as approved-venue ([create tx](https://testnet.arcscan.app/tx/0x9f21316e30da7436b7ef4941edd0bd91480ff1a99858c796f85da8b8ce9f77fa))
  2. Mandate issued — principal = bridge, ceiling = 0.01 USDC, counterparty whitelist = single Merkle leaf for bridge, purpose = `keccak256("plinth_invest_v0")`, funded with 0.005 USDC ([issue tx](https://testnet.arcscan.app/tx/0x1b65d3544a18ac75e096d0399d242c29356ef075b246b16f7431bb84a29f984b))
  3. Bridge.depositViaMandate triggered: atomic Mandate.execute → Plinth.deposit ([composed tx](https://testnet.arcscan.app/tx/0x4bdb577e6c4698cae3f2f3a8cc010e0cb9d95cb6e06ba83a5580e3bf72fec4ea))
  - Final state on chain: Mandate.spent = 0.005 USDC ✓, Bridge.sharesOfMandate[mandate][vault] = 0.005 ✓, Plinth.inVault on vault += 0.005 ✓

This is the first **real architectural compose** of sibling protocols, not just README cross-references. Cadence + Plinth (per-call fees on vault redeem), Crucible + Plinth (vault performance scored as agent quality), and Helm + Plinth (agent DAO voting on vault parameters) follow the same bridge pattern.

### Verifiable PnL — agent's claim matched against Aster L1 trade history

Vault #5 demonstrates the architectural payoff of Plinth's Underwriter Review layer when the off-chain venue is itself a public chain:

| Side | What happened | On-chain evidence |
|---|---|---|
| Plinth (Arc Testnet) | Agent created vault, investor deposited 0.01 USDC, agent deployed 0.005 to MockVenue | [vault page](https://testnet.arcscan.app/tx/0x7b4d547a1c66819a3fdb8892b9dc07add2a32f5def647f2132031f2515df1726) |
| Aster L1 (chainId 1666) | Agent opened BUY 0.001 BTC @ 80,500.7, closed SELL @ 80,517.9 after 3 min | Aster orders `31402248641` open / `31402286923` close, fills id 134970761 + 134970911 |
| Plinth (Arc Testnet) | Agent reported realized `−0.047207 USDC` PnL | [reportPnL tx](https://testnet.arcscan.app/tx/0x0f15c4e1e0583aa14fc28ce1f0c1cb680efee5f5f2147d18bdf915d148d41002) |
| **Underwriter** | Independently pulled Aster `userTrades`, summed gross `+0.0172 USDT` − commissions `0.0644` = `−0.0472 USDT`, **matched agent's claim within 0.00%** delta | [`UnderwriterReviewPosted` tx](https://testnet.arcscan.app/tx/0x7ee06f9c18faf6e9c05fee9136ec3b8bc6ce06f7a934d7735342480ba5bad8e5) — verdict `VERIFIED` |

3 round-trips were executed cumulatively (1 long, 1 long, 1 short). All 3 had positive directional moves; fees ate the gross profit. Net realized: `−0.135 USDT` across 6 fills, matched to 0.00% delta on chain ([second verifier review tx](https://testnet.arcscan.app/tx/0xf6c6b142bbbd415e5e6facab36301540be00fd03c97615f56bdc5e3352f9939c)). Total experimental cost: $0.13 USDT.

The same architecture works against any public-chain venue, including future Arc-native perp DEXes. Aster L1 was picked for v0 because it was readily available; the integration code lives in [`aster/`](aster/).

### Wallet diversity in the demo

Plinth's multi-underwriter + multi-depositor design supports any number of independent identities, each acting from their own key. The demos exercise this with **three distinct on-chain wallets**:

| Wallet | Role | Funded by | Disclosure |
|---|---|---|---|
| `0x...` (main agent/operator key) | Runs Aster Verifier + Risk Monitor + LLM Underwriter | Original USDC | The project author's primary key |
| `0xA4Fe6D03…` ("Bob") | Deposited 0.003 USDC into Vault #1 + posted qualitative review of Vault #5 | Operator-transferred USDC | [bob review markdown footer](https://ccheh.github.io/plinth/reviews/0xefb495a02c14af970104d62e9623d83eea8d0b725dea9ffd6b7aa479284430fc-bob-1778679308638.md) |
| `0xAbc9c5cE…` ("Charlie") | Deposited 0.0001 USDC into Vault #4 v0.5 via **public Circle faucet** path | [Circle's public Arc Testnet faucet](https://faucet.circle.com) | [docs/charlie-test.md](docs/charlie-test.md) — full disclosure + reproducibility script |

All three are operator-orchestrated; **Plinth makes no claim of unaffiliated third-party traction**. Their value is technical: they prove the cryptographic multi-signer design works end-to-end at the wallet level, not just at the contract level. Charlie additionally proves the fresh-wallet onboarding journey (faucet → deposit) works as documented in `docs/quickstart-for-agents.md`.

### Risk Monitor — second independent Underwriter, complementary to verifiable-PnL

A separate off-chain agent ([`underwriter/risk-monitor.ts`](underwriter/risk-monitor.ts)) scans every vault on the deployment and writes structured `RiskAlert` reviews on chain when any of these signals trigger: underwater NAV, outsized PnL claims vs AUM, agent-as-venue, single-venue concentration, liquidity gap, review staleness.

Two alerts went live during the submission window:
- Vault #5 ([`CRITICAL` review](https://testnet.arcscan.app/tx/0xe8593402606010742c15a91f1c4ab00539bfeba73fefcbb66b3ccebae0948c4e)) — vault is underwater after the Aster round-trips, reportedPnL is 1224% of AUM
- Vault #1 ([`HIGH` review](https://testnet.arcscan.app/tx/0x8d802e4dddf7732a1232c4f633c420441fd3be171a330741b7e215ec4047b2ca)) — reportedPnL is 50% of AUM and no recent underwriter review

Notably: **Vault #5 has TWO reviews from independent underwriters that disagree on what to do.** The Aster Verifier says `VERIFIED` (the agent is honest about PnL). The Risk Monitor says `CRITICAL` (the position is dangerous). Both are correct and useful — an honest agent reporting a real loss is exactly when investors should be warned about the size of the loss, not when they should be reassured by the verification. This is by design — multiple lenses, each posting independently on chain.

For the gaps the v0 contract intentionally does NOT enforce (per-call size caps, NAV-drop circuit breakers, PnL rate limits, etc.), see [`docs/risk-controls.md`](docs/risk-controls.md) for the v0.5 `RiskGuard` interface and implementation roadmap.

> **Read this first.** Plinth v0 is live on Arc Testnet, 1 real third-party-venue lifecycle ran successfully (Aster L1, 3 round-trips, $0.13 experimental cost), 52 forge tests pass, audit pending. The pitch: AI agents on Arc need a way to *raise* and *manage* external capital with cryptographically verifiable PnL — currently they don't have one. Plinth is that primitive.

---

## What it does

A **Plinth Vault** is a tokenized USDC pool with:

- One **agent** (AI or human) authorized to deploy the pool's capital and report PnL.
- N **shareholders** who deposited USDC and received internal shares.
- An **immutable whitelist of approved venues** (perp DEXes, prediction markets, AMMs).
  The agent can ONLY transfer pool funds to addresses on this list.
- A **NAV** (net asset value per share) updated continuously from agent PnL reports.
- An optional **Underwriter Review** layer: any 3rd party can post a signed
  risk assessment of the vault on chain.

### Core flows

```
1. Agent creates vault:
     createVault(approvedVenues[], strategyDescriptor)
     - approvedVenues is fixed at creation; agent cannot drain to arbitrary addresses
     - msg.value is agent's "skin in the game" — they get 1 share per USDC at inception

2. Investor deposits:
     deposit(vaultId)
     - msg.value is the USDC amount
     - sharesMinted = msg.value * 1e18 / currentNAV

3. Agent deploys to venue:
     deployToVenue(vaultId, venue, amount)
     - venue must be in approvedVenues
     - inVault decreases, deployedAUM increases
     - USDC flows to venue contract

4. Agent reports PnL:
     reportPnL(vaultId, newPnL)
     - signed int (can be negative)
     - NAV = (inVault + deployedAUM + reportedPnL) / totalShares

5. Investor redeems:
     redeem(vaultId, shareAmount)
     - usdcOut = shareAmount * currentNAV / 1e18
     - reverts if not enough liquid (inVault < usdcOut)

6. Underwriter posts review:
     postUnderwriterReview(vaultId, reviewHash, reviewUri)
     - hash on chain, full review off-chain at reviewUri
     - any address can post; consumers pick which signer to trust
```

### NAV math

```
totalAUM = inVault + deployedAUM + reportedPnL          (signed int)
NAV      = totalShares == 0 ? 1e18 : (totalAUM * 1e18) / totalShares
```

Inception NAV is **1 USDC/share** (1e18 wei). NAV moves with reportedPnL.

If totalAUM ≤ 0, the vault is "underwater" — deposits and redemptions revert
to protect surviving share value. Only the agent unwinding positions and
returning funds (or closing the vault) can unlock further action.

### Agent safety constraints (Mandate-style)

The agent's authority is hard-capped by the contract:

- Can only call `deployToVenue` to addresses in `approvedVenues` (immutable).
- Cannot withdraw USDC for personal use — there is no "agent withdraw" function.
- Cannot mint new shares for themselves outside the deposit flow.
- Can revoke their own access via `closeVault` but cannot revoke shareholder
  claims to their pro-rata of remaining liquidity.

What the agent CAN do badly (documented openly):

- List themselves (or a sock-puppet venue) as an approvedVenue at creation,
  then deploy to themselves. This is detectable off-chain by the Underwriter.
- Report fraudulent PnL. NAV moves on the agent's say-so in v0. v0.2 will
  add stake/bond economics for honesty enforcement.

---

## Why this fits the agentic economy on Arc

The 4 protocols already shipped form a stack:

| Protocol | Solves |
|---|---|
| [Cadence](https://github.com/Ccheh/arc402) | How agents *pay* (per-call USDC) |
| [Crucible](https://github.com/Ccheh/crucible) | How agents are *scored* on output quality |
| [Helm](https://github.com/Ccheh/helm) | How agent *groups decide* (futarchy) |
| [Mandate](https://github.com/Ccheh/mandate) | How institutions *authorize* agents |
| **Plinth** (this) | How agents *raise capital* from external investors |

Plinth is the missing capital layer. Without it, an AI agent can run a great
strategy but only on its own funds. With it, the same agent can attract
external USDC, scale strategy size, and share returns with its investors.

---

## On Arc specifically

- **USDC as native gas** means a deposit/redeem flow is one tx with no separate gas token.
- **Sub-cent settlement** makes small-share economics work — you can redeem
  $0.50 worth of shares without losing the value to gas.
- **L1 finality** matters for NAV: a deposit at NAV 1.50 is final, no chain
  reorg can rewrite the share count.

These properties are what make a "tokenized AI fund" viable here vs on
Ethereum mainnet ($5+ gas per deposit kills sub-thousand-dollar vaults).

---

## Reproducing the tests

```sh
cd contracts
forge test
```

Expected: `52 passed; 0 failed`. Covers:

- 6 createVault tests (happy path + 5 revert cases including event emission)
- 6 deposit tests (NAV-based share calculation in 3 regimes: inception, profit, loss)
- 7 redeem tests (incl. revert on insufficient liquidity, paused vault, closed vault, underwater)
- 7 deployToVenue tests (incl. an *intentional* adversarial test showing the agent-as-venue attack)
- 4 returnFromVenue tests
- 4 reportPnL tests (positive, negative, overwrite, not-agent)
- 5 pause/close tests
- 3 underwriter review tests
- 3 multi-vault / multi-investor isolation tests
- 3 view function tests
- 1 end-to-end lifecycle test (agent + investor + venue + PnL + redeem)

---

## What's deferred to v0.2+

- **TypeScript SDK** (in progress for the hackathon)
- **LLM Underwriter agent** that auto-reviews `strategyDescriptor` (in progress)
- **Web UI** (in progress)
- **Management + performance fees** — v0 has no fees
- **ERC-20 wrapping** of internal shares so they're tradable on AMMs
- **NAV oracle integration** — replace agent self-reporting with verifiable feeds
- **Multi-asset vaults** — v0 is USDC-only
- **Insurance / first-loss tranche** — investor protection from agent fraud
- **USYC auto-yield** — sweep idle inVault into Circle's tokenized T-bills

---

## Honest limits

- **v0, pre-audit, pre-deployment, no production adopters.** Treat this as research code shipped for the Agora Agents Hackathon (May 11–25, 2026).
- **Agent self-reporting of PnL is trust-based — *unless the venue is also a public chain*.** A malicious agent on an opaque (CEX-style) venue can mark a position higher than reality to inflate NAV; v0 relies on Underwriter Review to catch it. When the venue is itself a public chain — like Aster L1, or future Arc-native perp DEXes — the Underwriter can independently reconcile the agent's claim against the venue's trade history (see Vault #5 above). v0.2 adds bond/stake economics on top.
- **Agent can list themselves as an approved venue.** This is the intended *Underwriter-detectable* failure mode — flagged by off-chain review, not blocked on chain. Trade-off: simplicity now, reputation layer later.
- **No on-chain enforcement of disclosed strategy.** The `strategyDescriptor` is free text. Agents may operate differently than they advertise. Investors must trust the Underwriter and the agent's track record.
- **Native USDC only.** Plinth assumes 18-decimal native USDC (Arc Testnet semantics). Mainnet adaptation will require IERC-20 + approve/transferFrom semantics.

---

## Repo layout

```
contracts/src/
├── Plinth.sol                   — core vault + share + NAV contract (≈ 240 LOC)
├── MockVenue.sol                — placeholder venue for tests and demo
└── interfaces/
    └── IPlinth.sol              — interface + events + errors

contracts/test/
└── Plinth.t.sol                 — 52 forge tests

sdk-ts/                          — TypeScript SDK
underwriter/                     — LLM-driven risk-assessment script
aster/                           — Aster L1 venue adapter + verifiable-PnL Underwriter
docs/                            — web UI + verifier review artifacts (gh-pages)
video/                           — pitch video build pipeline
```

---

## Author

[Zen Chen](https://github.com/Ccheh) — built on Arc Testnet for the Agora
Agents Hackathon. Sibling protocols:
[Cadence](https://github.com/Ccheh/arc402) ·
[Crucible](https://github.com/Ccheh/crucible) ·
[Helm](https://github.com/Ccheh/helm) ·
[Mandate](https://github.com/Ccheh/mandate).
