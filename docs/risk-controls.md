# Risk Controls — current state and v0.5 roadmap

This document inventories the safety mechanisms in Plinth v0, identifies the gaps, and sketches the on-chain `RiskGuard` interface that v0.5 will add.

## What v0 already enforces on-chain

These constraints are written into `Plinth.sol` and cannot be bypassed by the agent:

| Constraint | Mechanism | Why it matters |
|---|---|---|
| **Capital can never leave to an arbitrary address** | `approvedVenues` array set at vault creation, never mutable | Eliminates the obvious rug — agent can't drain to a fresh attacker wallet |
| **Agent cannot mint shares for itself** | `deposit()` mints proportionally to `msg.value`; there is no agent-side mint function | Eliminates the inflation rug |
| **Agent cannot directly withdraw USDC** | No `withdraw()` function exists for the agent role at all | Agent has spending authority but never custody |
| **Underwater protection** | If `totalAUM ≤ 0`, `deposit()` and `redeem()` revert | New depositors can't get diluted to 0; existing investors can't claim a negative pool |
| **Liquidity guarantee** | `redeem()` reverts if `inVault < usdcOut` | Investor can't claim deployedAUM that's still at a venue |
| **Status gating** | `paused`/`closed` vaults reject new deposits | Lifecycle controls let an agent freeze a vault without losing investor claims |

These are *capability constraints* — Mandate-style. They're sufficient to prevent the most direct attacks but leave economic / behavioral risks open.

## What v0 mitigates off-chain (via Underwriter Reviews)

Three independent Underwriter agents now scan vaults and post structured reviews on chain. None is privileged — anyone can run them and anyone can read the review hashes.

| Reviewer | Detects | Cost to fool |
|---|---|---|
| **LLM Underwriter** (`underwriter/review.ts`) | Suspicious strategy descriptors, agent listed as own venue, missing diversification, guarantee claims | Requires deceiving an LLM with structured prompt; possible but high-effort |
| **Risk Monitor** (`underwriter/risk-monitor.ts`) | Underwater NAV, outsized PnL claims vs AUM (>50%), single-venue concentration, review staleness, self-venue | Requires off-chain attestation forgery (impossible) |
| **Verifiable-PnL Reconciler** (`aster/verifier.ts`) | Mismatch between agent's `reportedPnL` and venue's on-chain trade history | **Cryptographically impossible if venue is a public chain** (Aster L1, future Arc-native perp DEXes) |

## Known gaps (v0 admits)

These risks are NOT enforced today and the contract doesn't try to. Some are off-chain detectable (Underwriter catches them), others are economic risks the contract design accepts:

| Gap | Current state | Why deferred |
|---|---|---|
| **No per-call deployToVenue size cap** | Agent can move 100% of TVL to a single venue in one tx | Caps need to be vault-parameter so agent picks; not v0 priority |
| **No NAV-drop circuit breaker** | NAV can drop 50% in one `reportPnL` call without auto-pausing | Watermark tracking needs new storage + careful invariants |
| **No PnL update rate limit** | Agent can `reportPnL(+1000%)` then immediately accept deposits at inflated NAV | Time-delay = new state machine; v0.5 design problem |
| **No investor concentration cap** | Single depositor can own 99% of shares | Cap is policy not protocol; can be off-chain warning instead |
| **No agent-key compromise recovery** | Single private key controls the vault permanently | Multi-sig or social recovery = scope creep for v0 |
| **No slippage / front-running protection on deposit-at-NAV** | Front-runners can deposit *before* a known +PnL is reported | NAV-update mempool race; needs commit-reveal or time-delayed PnL |
| **No on-chain enforcement of disclosed strategy** | `strategyDescriptor` is free text | Strategy adherence isn't formalizable without strong oracles |

## v0.5 design — `RiskGuard` interface

The next milestone introduces an optional plug-in contract that intercepts the gated actions before they execute. Vaults can opt-in at creation time.

```solidity
interface IRiskGuard {
    /// Returns true if the deployToVenue call should proceed.
    /// Reverts (with reason) if the action should be blocked entirely.
    function checkDeploy(
        bytes32 vaultId,
        address venue,
        uint256 amount,
        uint256 currentInVault,
        uint256 currentDeployedAUM
    ) external view returns (bool);

    /// Returns true if the reportPnL call should be allowed to update NAV
    /// immediately. May return false to force a time-locked queue.
    function checkReportPnL(
        bytes32 vaultId,
        int256 oldPnL,
        int256 newPnL,
        uint256 totalAUM
    ) external view returns (bool);

    /// Returns true if the deposit should be accepted at current NAV.
    /// May return false to require investor-side acknowledgment (high NAV,
    /// concentration cap exceeded, etc.).
    function checkDeposit(
        bytes32 vaultId,
        address depositor,
        uint256 amount,
        uint256 currentShares
    ) external view returns (bool);
}
```

Plinth.sol modifications (additive, ~30 LOC):

```solidity
// In Vault struct:
address riskGuard;        // 0x0 = no guard (default, backward compatible)

// In createVault: accept optional riskGuard parameter, default 0x0

// Before each gated action:
if (v.riskGuard != address(0)) {
    require(IRiskGuard(v.riskGuard).checkDeploy(vaultId, venue, amount, v.inVault, v.deployedAUM), "guard blocked");
}
```

Two reference `RiskGuard` implementations ship with v0.5:

### `ConservativeRiskGuard.sol`

| Rule | Default | Configurable per-vault |
|---|---|---|
| Max single `deployToVenue` | 25% of total AUM | yes |
| Max PnL change per 24h | ±20% of inVault+deployedAUM | yes |
| Max deposit per address | 50% of post-deposit totalShares | yes |
| Auto-pause if NAV drops >30% from HWM | enabled | toggle |

### `PermissiveRiskGuard.sol`

| Rule | Default |
|---|---|
| Max single `deployToVenue` | 75% of total AUM |
| Max PnL change per 24h | ±100% |
| Max deposit per address | 95% |
| Auto-pause threshold | NAV drop > 80% |

Investors choose which guard they trust by picking which vaults they fund. Agents choose their guard at vault creation — a more conservative guard signals "I'm OK being constrained" and earns investor trust at the cost of operational flexibility.

## Test plan for v0.5

The existing 52 forge tests for `Plinth.sol` continue to pass unchanged (RiskGuard hook is no-op when guard address is 0x0). New tests:

1. `test_deployToVenue_reverts_when_guard_blocks` — guard returns false → revert
2. `test_reportPnL_queued_when_guard_returns_false` — verifies time-lock queue insertion
3. `test_conservative_guard_caps_per_call_deploy_at_25pct`
4. `test_conservative_guard_caps_24h_pnl_change`
5. `test_conservative_guard_blocks_whale_deposit`
6. `test_riskGuard_can_be_address_zero_default` — backward compat: existing v0 vault behavior unchanged
7. `test_riskGuard_field_immutable_after_creation` — agent can't swap guard mid-flight
8. `test_NAV_drop_autoPause_works` — paused vault rejects new deposits, allows redemption
9. Plus 3 e2e tests covering the full lifecycle with each guard variant

## Why we shipped v0 without these

The Plinth thesis is: **capability constraints + verifiable Underwriter attestations are necessary, sufficient is harder**. Adding economic safety rules has subtle interactions with NAV math, share dilution, and concurrent action ordering — getting them wrong is worse than not having them.

v0 was scoped to prove the capability-constraint design works on chain, that real agents can integrate, and that the Underwriter layer can be cryptographically backed. v0.5 closes the economic-safety gap with a clean interface that agents and investors can both reason about.

## Off-chain risk surface (already shipped)

Until v0.5 lands, the Risk Monitor (`underwriter/risk-monitor.ts`) does all of the above checks *off chain* and writes structured `RiskAlert` reviews on chain when threshold scores are exceeded. Investors who care about safety can:

1. Subscribe to `UnderwriterReviewPosted` events from the Risk Monitor's address
2. Refuse to deposit into vaults with active `HIGH` or `CRITICAL` alerts
3. Build their own monitors and post additional reviews — multiple underwriters per vault is the design

The on-chain v0.5 design moves these from "investor must opt-in" to "agent must opt-in" — both are valid, complementary.
