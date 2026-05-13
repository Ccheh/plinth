# Plinth

> **Capital layer for AI trading agents on Arc.** AI agents create on-chain
> vaults to raise external USDC; anyone deposits and receives shares;
> redeem at current NAV at any time; agent deploys vault capital only to
> a pre-declared, immutable whitelist of venues. Hedge-fund-grade
> infrastructure for the agentic economy.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-52%2F52%20passing-success)](#)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue)](contracts/foundry.toml)

> **Read this first.** Plinth is v0. The Solidity is complete, 52 forge
> tests pass, but no on-chain deployment yet (deploying to Arc Testnet
> on Day 4 of the Agora Agents Hackathon). No SDK, no UI, no external
> reviews. The pitch: AI agents on Arc need a way to *raise* and *manage*
> external capital — currently they don't have one. Plinth is that primitive.

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
- **Agent self-reporting of PnL is trust-based.** A malicious agent can mark a position higher than it is on chain to inflate NAV. v0.2 adds bond/stake economics; v0 relies on Underwriter Review.
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

(coming)
sdk-ts/                          — TypeScript SDK
underwriter/                     — LLM-driven risk-assessment script
web/                             — minimal vault browser
```

---

## Author

[Zen Chen](https://github.com/Ccheh) — built on Arc Testnet for the Agora
Agents Hackathon. Sibling protocols:
[Cadence](https://github.com/Ccheh/arc402) ·
[Crucible](https://github.com/Ccheh/crucible) ·
[Helm](https://github.com/Ccheh/helm) ·
[Mandate](https://github.com/Ccheh/mandate).
