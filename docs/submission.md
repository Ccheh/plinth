# Plinth — Agora Agents Hackathon Submission

> One-pager for hackathon judges. The full architecture is in [README.md](../README.md); honest limits at the bottom.

## TL;DR

**Plinth is the capital layer that lets AI trading agents on Arc raise external USDC from investors and manage it under hard on-chain constraints.** It turns a single-wallet agent demo into a tokenized fund: agent creates a vault, anyone deposits USDC at NAV, agent deploys to a pre-declared immutable whitelist of venues, NAV moves on reported PnL, investors redeem on demand.

**v0 ships with a cross-chain verifiable-PnL Underwriter.** When an agent's strategy executes on a public-chain venue (Aster L1 in our demo; future Arc-native perp DEXes by the same pattern), Plinth's Underwriter reads the venue's trade history and cryptographically reconciles it against the agent's reported PnL on Arc. Vault #5 ran end-to-end on Aster mainnet: agent opened 0.001 BTC long → closed 3 min later → realized PnL `−0.047207 USDT` → reported same value on Arc → Underwriter matched to 0.00% delta → posted `VERIFIED` review on chain. This turns the honest-limit "agent self-reports PnL → trust required" into "PnL is recomputable from venue chain."

## How this addresses the RFB themes

The Agora brief covered 6 RFBs around trading agents (RFB 1: perp futures, RFB 2: prediction markets, RFB 4: portfolio management, RFB 5: arbitrage, RFB 6: social trading). **Plinth is orthogonal-but-essential infrastructure for all of them.** Every trading agent on Arc has the same structural ceiling: they run on their own balance. Plinth removes that ceiling by giving the agent a way to safely take on external capital.

Concretely, an RFB 2 prediction-market team using Plinth gets:
- A vault that 3-5 friends can deposit testnet USDC into
- "Real" traction numbers (TVL, depositors, NAV PnL) for their submission
- Cryptographic guarantees that protect the depositors — agent can never drain to arbitrary addresses

## Submission scorecard

| Criterion | Weight | Plinth's claim |
|---|---|---|
| **Agentic Sophistication** | 30% | Two distinct Underwriter agents: (a) LLM-based risk reviewer reads vault metadata + on-chain history and outputs structured risk assessments; (b) **Verifiable-PnL Underwriter** independently reconciles the agent's reported PnL against the venue's own on-chain trade history. Vault #5 ran end-to-end: a real BTC perp on Aster L1, agent reports realized PnL on Arc, Underwriter matches to 0.00% delta and posts `VERIFIED` review on chain. |
| **Traction** | 30% | **5 vaults live on Arc Testnet, 16+ lifecycle transactions on chain, 3 underwriter reviews on chain (1 cryptographically verified against a real Aster L1 trade)**. Web UI at ccheh.github.io/plinth lets anyone browse + verify. Outreach kit ready for Canteen Discord — hackathon teams can integrate in ~15 minutes. |
| **Circle Tool Usage** | 20% | Built on **Arc Testnet with USDC as native gas**. MIN_DEPOSIT is 0.0001 USDC (only viable on Arc's economics). v0.2 will integrate **USYC** (Circle's tokenized T-bills) for idle USDC yield, and **Cadence** (the OSS Nanopayments reference) for management fee streaming. |
| **Innovation** | 20% | (a) **Verifiable-PnL Underwriter** — when the off-chain venue is itself a public chain, the Underwriter cryptographically reconciles agent claims against venue trade history (live demo on Aster L1, same pattern applies to any future Arc-native perp DEX). (b) Capability-not-custody constraint: agent never holds keys but directs funds. (c) Sub-cent share economics — retail-sized capital diversifying across AI strategies, only possible on Arc. (d) Composes with 4 sibling protocols (Mandate, Cadence, Crucible, Helm) into a complete agent-economy stack. |

## Deliverables (matching submission checklist)

| Required | Provided |
|---|---|
| Product demo (live working product) | https://ccheh.github.io/plinth · contract on testnet.arcscan.app |
| Founder pitch video | `video/demo.mp4` in this repo (~2.5 min, TTS-narrated slides) |
| Public GitHub repo | https://github.com/Ccheh/plinth (MIT) |
| Traction questions | See above + the "Live vaults" table in [README.md](../README.md) |

## Sibling protocols (the broader stack)

I've been building agent-economy infrastructure on Arc this month. Plinth is the 5th and most recent:

| Protocol | Layer | Repo |
|---|---|---|
| **Cadence** | Per-call USDC payments | github.com/Ccheh/arc402 |
| **Crucible** | Quality-conditional settlement | github.com/Ccheh/crucible |
| **Helm** | Group decisions (futarchy) | github.com/Ccheh/helm |
| **Mandate** | Institutional authorization | github.com/Ccheh/mandate |
| **Plinth** | **Capital raising + management** | **github.com/Ccheh/plinth** ← this |

Each is independent. Each composes with the others. Plinth uses the same design patterns from Mandate (capability whitelist) and Crucible (quality reputation events).

## Honest framing (for judging clarity)

- **What this IS**: an open-source infrastructure protocol. Not a trading agent itself.
- **What this is NOT**: a fund I'm running, a custody service, or audited production code.
- **Traction reality**: in-hackathon traction comes from helping other RFB teams tokenize their agents. We have 4 demo vaults at submission; the outreach kit invites more. The realistic 12-day ceiling for solo-built infrastructure submissions of this type is 5-10 integrators.
- **What we want from judges**: hard questions about the capability-constraint model and the Underwriter trust assumptions. The "agent-as-venue" attack surface is intentionally on-contract (off-chain reviewer detectable) rather than blocked in code — this is a defensibility trade-off documented in honest limits.

## Author

[Zen Chen](https://github.com/Ccheh) — MSc Data Science (Sheffield). Previously: crypto-asset audit at a fund. Email: ccheh4@gmail.com. Available for follow-up conversation.
