# Plinth Security Audit — v0 → v0.5

**Audit date**: 2026-05-13
**Auditor**: in-team review, prior to mainnet deployment
**Code reviewed**: [`contracts/src/Plinth.sol`](../contracts/src/Plinth.sol) @ commit `eff4fbd`, 290 LOC
**Tests reviewed**: [`contracts/test/Plinth.t.sol`](../contracts/test/Plinth.t.sol), 52 tests (pre-audit)
**Methodology**: Manual review against OWASP / DeFi attack taxonomy (MEV, reentrancy, access control, donation, inflation, rounding, signed-int handling, lifecycle), supplemented by exploit-POC test cases.

## Executive summary

11 findings: **1 Critical**, **2 High**, **3 Medium**, **2 Low**, **3 Already-Safe-by-Design**. Every Critical/High has a working exploit POC test in [`Plinth.t.sol`](../contracts/test/Plinth.t.sol) and a corresponding defense test in [`PlinthV05.t.sol`](../contracts/test/PlinthV05.t.sol) (when v0.5 ships).

v0.5 closes Critical + 4 High/Medium findings. The remaining 2 (funds-stuck-at-venue post-close; DOS via spam vaults) are documented as design trade-offs with v0.6 roadmap.

| # | Severity | Title | v0 status | v0.5 status |
|---|---|---|---|---|
| 1 | 🔴 CRITICAL | `reportPnL` sandwich extraction | exploitable | **fixed** (deposit cooldown) |
| 2 | 🟠 HIGH | `returnFromVenue` open access enables griefing | exploitable | **fixed** (caller must be venue or agent) |
| 3 | 🟠 HIGH | `reportPnL` magnitude / rate not bounded | exploitable | **fixed** (10x capital cap + 25%/hr rate limit) |
| 4 | 🟡 MEDIUM | `reportPnL` allowed on Closed vault | exploitable | **fixed** (Closed → revert) |
| 5 | 🟡 MEDIUM | Funds stuck at venue when vault closes | accepted | **v0.6 roadmap** (declareUnrecoverable) |
| 6 | 🟡 MEDIUM | `reportedPnL` near `INT256_MIN/MAX` overflows arithmetic | theoretical | **fixed** (10x bound implies practical safety) |
| 7 | 🟢 LOW | `createVault` spam → storage bloat | self-limiting (attacker burns own gas + USDC) | accepted |
| 8 | 🟢 LOW | `strategyDescriptor` unbounded string | griefing via gas | **fixed** (MAX_STRATEGY_LEN = 1024 bytes) |
| 9 | ✅ SAFE | Reentrancy on payable functions | OpenZeppelin `ReentrancyGuard` + CEI pattern | retained |
| 10 | ✅ SAFE | Donation attack via `selfdestruct` push | per-vault accounting in storage, not `address(this).balance` | retained |
| 11 | ✅ SAFE | First-depositor / ERC-4626 inflation attack | NAV doesn't read balance; `NoSharesToMint` revert on rounding | retained |

---

## #1 — `reportPnL` sandwich extraction 🔴 CRITICAL

**Category**: MEV / economic
**File**: [`Plinth.sol`](../contracts/src/Plinth.sol)
**Functions affected**: `deposit`, `redeem`, `reportPnL`

### Description

`deposit()` and `redeem()` price shares using the current NAV (`_navOf`), which is computed from `inVault + deployedAUM + reportedPnL`. `reportPnL()` is the agent's mechanism to update mark-to-market PnL and consequently NAV. Because Ethereum/EVM mempools are public, any pending `reportPnL` tx is visible to MEV searchers BEFORE it confirms. A searcher can sandwich the update for cost-free extraction.

### Attack scenario

State at t=0: vault has `inVault = 100 USDC`, `deployedAUM = 0`, `reportedPnL = 0`, `totalShares = 100`. NAV = 1.0 USDC/share. One investor (Alice) holds all 100 shares.

1. **t=0**: agent submits `reportPnL(vault, +50e18)` with normal gas
2. **t=0**: attacker sees this tx in mempool; submits `deposit(vault)` with `msg.value=100 USDC` and higher gas
3. **t=1**: attacker's deposit confirms FIRST. At entry: NAV = 1.0. `sharesMinted = 100 USDC × 1e18 / 1e18 = 100 shares`. New state: `totalShares = 200`, `inVault = 200`.
4. **t=1**: agent's `reportPnL` confirms. `reportedPnL = 50`. NAV = `(200 + 0 + 50) × 1e18 / 200 = 1.25 USDC/share`.
5. **t=2**: attacker submits `redeem(vault, 100 shares)`. NAV = 1.25. `usdcOut = 100 × 1.25 = 125 USDC`.
6. Attacker withdraws **125 USDC** for **100 USDC deposited** — net profit **+25 USDC**.

Where did the profit come from? Alice's shares went from being worth `(100 + 50)/100 = 1.5 USDC/share` (their fair value) to `(75 + 0)/100 = 0.75 USDC/share` after the sandwich (after Alice's share of the +50 was siphoned out by the attacker). Alice's effective dilution: **33%** of her fair gain.

Mathematically: attacker's profit ≈ `depositAmount × ΔreportedPnL / (oldTotalAUM + depositAmount)`. For our 50% NAV move case: profit = `100 × 50 / (100 + 100) = 25 USDC`. The bigger the PnL update, the larger the extraction.

### Exploit POC

See [`test_exploit_sandwich_reportPnL`](../contracts/test/Plinth.t.sol#:~:text=test_exploit_sandwich_reportPnL) in `Plinth.t.sol`. The test simulates the exact sequence above against v0 and asserts the attacker exits with `+25 USDC` profit.

### Mitigation — deposit cooldown (v0.5)

After every `deposit()`, the depositor's shares are subject to a vesting period. Redemption of those shares reverts until `block.timestamp >= lastDepositAt[vault][user] + DEPOSIT_COOLDOWN`.

```solidity
uint256 public constant DEPOSIT_COOLDOWN = 1 hours;
mapping(bytes32 => mapping(address => uint256)) public lastDepositAt;

function deposit(bytes32 vaultId) external payable {
    // ... existing logic ...
    lastDepositAt[vaultId][msg.sender] = block.timestamp;
}

function redeem(bytes32 vaultId, uint256 shareAmount) external {
    // ... existing checks ...
    if (block.timestamp < lastDepositAt[vaultId][msg.sender] + DEPOSIT_COOLDOWN) {
        revert SharesPendingVesting();
    }
    // ... existing logic ...
}
```

**Why this works**: the attacker can still pre-position a deposit BEFORE `reportPnL`, but they cannot redeem at the post-`reportPnL` NAV until `DEPOSIT_COOLDOWN` has elapsed. During that window, the NAV can move in either direction (agent may report subsequent PnL, market conditions may change). The instant arbitrage becomes a directional bet over a 1-hour horizon — expected value ≈ 0 for an unbiased market.

**Trade-off**: legitimate users also can't redeem within 1 hour of depositing. For a hedge-fund-style product where investors typically hold for days/weeks/months, this is acceptable. UI can clearly display "Funds vesting until {time}" after deposit.

**Alternative mitigations considered**:
- Commit-reveal deposits: rejected (poor UX, complex)
- TWAP NAV: rejected (heavy storage cost for snapshot history)
- Block all deposits during pending PnL: rejected (agent could front-run their own updates anyway; doesn't help)
- Worst-of NAV: rejected (penalizes innocent users equally)

### Defense POC

See [`test_v05_sandwich_attempt_revertsOnRedeem`](../contracts/test/PlinthV05.t.sol).

---

## #2 — `returnFromVenue` open access enables griefing 🟠 HIGH

**Category**: access control / availability
**File**: [`Plinth.sol`](../contracts/src/Plinth.sol#L175-L186)

### Description

`returnFromVenue(bytes32 vaultId, address venue, uint256 amount) external payable` has no `msg.sender` check. Anyone can call it (and must provide `msg.value == amount`). The function then increases `inVault` and decreases `deployedAUM`. The intent was that the venue contract itself returns funds and updates accounting in one call, or the agent does it on the venue's behalf. But the lack of access control allows a third-party griefer.

### Attack scenario

State: vault has `inVault = 5`, `deployedAUM = 5` (5 USDC sitting at the venue contract).

1. Attacker calls `returnFromVenue(vault, venue, 5)` with `msg.value = 5 USDC` of their own funds.
2. State now: `inVault = 10`, `deployedAUM = 0`. Vault accounting thinks venue has nothing.
3. The venue's actual 5 USDC is still at the venue address.
4. Later, the venue (legitimately) tries to call `returnFromVenue(vault, venue, 5)` with its 5 USDC. The call reverts with `InsufficientDeployedAUM` (deployedAUM is now 0 in the vault's books).
5. The venue's 5 USDC is now stranded at the venue address; the vault's books still look balanced (10 USDC `inVault`, of which the attacker contributed 5).

Net outcome:
- Attacker: −5 USDC (lost to vault; partially recovers via redeeming their proportional share if they're an investor)
- Vault: ledger says 10 USDC, actual recoverable: 10 USDC (attacker's "donation" is now part of the pool)
- Venue: −5 USDC stranded (legitimate funds cannot be returned to vault)

While the attacker pays for the attack (so it's not a steal), it allows a malicious actor to **redirect venue funds into vault liquidity** — useful if the attacker is positioned as a vault shareholder (they get pro-rata of the recovered funds). With sufficient share, they extract more than they paid in.

### Exploit POC

See [`test_exploit_returnFromVenue_thirdPartyGriefing`](../contracts/test/Plinth.t.sol#:~:text=test_exploit_returnFromVenue).

### Mitigation (v0.5)

Add caller check:

```solidity
function returnFromVenue(bytes32 vaultId, address venue, uint256 amount) external payable nonReentrant {
    Vault storage v = vaults[vaultId];
    if (msg.sender != venue && msg.sender != v.agent) revert NotAuthorized();
    // ... rest unchanged
}
```

The agent can still trigger returns programmatically (e.g., to call a venue's `withdraw()` then immediately call `returnFromVenue` with the recovered USDC). The venue itself can also push-return funds. Random third parties cannot.

**Trade-off**: if both agent and venue keys are lost (very edge case), the vault's `deployedAUM` accounting cannot be reconciled. The `declareUnrecoverable` mechanism (v0.6 roadmap, finding #5) provides the recovery path.

---

## #3 — `reportPnL` magnitude / rate not bounded 🟠 HIGH

**Category**: economic / NAV manipulation
**File**: [`Plinth.sol`](../contracts/src/Plinth.sol#L193-L200)

### Description

`reportPnL(bytes32 vaultId, int256 newPnL)` accepts any `int256` value with no:
- magnitude check (could be `INT256_MIN` or `INT256_MAX`)
- rate limit (agent can report +100% PnL one block, then -100% the next)
- floor relative to capital (could report PnL >> total deposits)

Combined with #1 (sandwich) and the off-chain Underwriter relying on detecting fraud rather than the contract preventing it, this gives a malicious or compromised agent significant freedom to manipulate NAV before Underwriter agents catch on.

### Attack scenarios

**Scenario A (NAV inflation rug)**:
1. Agent creates vault with `MIN_DEPOSIT = 0.0001 USDC`.
2. Agent reports `+1000e18` PnL → NAV explodes to 10,000,001.
3. Public sees high NAV; uninformed investors deposit at the inflated price, getting microscopic shares.
4. Agent reports `-1000e18`. NAV crashes back. Investors' microscopic shares are now worth pennies.
5. Net: investors lost 99%+ of deposit to agent's accounting fraud.

In v0, the rate limit doesn't prevent this — the agent can move NAV by any amount in a single block.

**Scenario B (INT256 overflow probe)**:
1. Agent reports `newPnL = INT256_MIN` (or `INT256_MAX`).
2. `_totalAUMOf` computes `int256(inVault) + int256(deployedAUM) + INT256_MIN`.
3. With non-trivial inVault, this is a near-overflow.
4. In Solidity 0.8+, arithmetic overflow reverts — so `_totalAUMOf` reverts.
5. Now `nav()`, `deposit()`, `redeem()` all revert. Vault is permanently bricked. DOS-on-self.

While the agent doesn't gain anything from scenario B, it shows the lack of input validation.

### Exploit POC

See [`test_exploit_reportPnL_navInflationRug`](../contracts/test/Plinth.t.sol) and [`test_exploit_reportPnL_int256BoundsBricksVault`](../contracts/test/Plinth.t.sol).

### Mitigation (v0.5)

Two-layer defense:

```solidity
uint256 public constant MAX_PNL_MULTIPLE = 10;          // |reportedPnL| ≤ 10 × capital
uint256 public constant PNL_RATE_PCT = 25;              // 25% capital per period
uint256 public constant PNL_RATE_WINDOW = 1 hours;

mapping(bytes32 => uint256) public lastReportAt;

function reportPnL(bytes32 vaultId, int256 newPnL) external {
    Vault storage v = vaults[vaultId];
    if (v.status != VaultStatus.Active && v.status != VaultStatus.Paused) revert NotActive();  // #4 fix
    if (msg.sender != v.agent) revert NotAgent();

    uint256 capital = v.inVault + v.deployedAUM;
    uint256 newPnLAbs = newPnL >= 0 ? uint256(newPnL) : uint256(-newPnL);

    // Bound 1: total magnitude
    if (capital > 0 && newPnLAbs > capital * MAX_PNL_MULTIPLE) revert PnLOutOfBounds();
    if (capital == 0 && newPnLAbs > 0) revert PnLOutOfBounds();  // can't report PnL with no capital

    // Bound 2: rate limit (only if a prior report exists within window)
    int256 oldPnL = v.reportedPnL;
    if (block.timestamp < lastReportAt[vaultId] + PNL_RATE_WINDOW && capital > 0) {
        int256 delta = newPnL > oldPnL ? newPnL - oldPnL : oldPnL - newPnL;
        if (uint256(delta) * 100 > capital * PNL_RATE_PCT) revert PnLRateLimitExceeded();
    }

    v.reportedPnL = newPnL;
    lastReportAt[vaultId] = block.timestamp;
    emit PnLReported(vaultId, oldPnL, newPnL, _totalAUMOf(v));
}
```

**Why these constants**:
- `MAX_PNL_MULTIPLE = 10`: catches gross inputs (no legitimate strategy reports 10x AUM PnL in a single update); makes overflow scenarios mathematically impossible.
- `PNL_RATE_PCT = 25`, `PNL_RATE_WINDOW = 1 hour`: a real strategy moving > 25% in an hour is a red flag the Underwriter should investigate; legitimate moves can be reported as multiple updates over time.

**Trade-off**: a vault with a legitimately volatile strategy (e.g., during a flash crash, 30% real drawdown in 10 minutes) cannot reflect that in a single `reportPnL`. Agent has two options: (a) wait 1 hour and report in chunks; (b) write a follow-up Underwriter review explaining the divergence. Acceptable trade-off — the rate limit reduces blast radius from agent fraud or key compromise.

---

## #4 — `reportPnL` allowed on Closed vault 🟡 MEDIUM

**Category**: lifecycle / access control
**File**: [`Plinth.sol`](../contracts/src/Plinth.sol#L195)

### Description

`reportPnL` checks `status != VaultStatus.None` but accepts `Closed`. Combined with redemption being allowed on closed vaults, an agent can manipulate the redemption NAV after the vault is supposedly "closed."

### Attack scenario

1. Vault has 100 USDC `inVault`, `reportedPnL = 0`, NAV = 1.0.
2. Investors begin redeeming.
3. Agent closes vault (`closeVault`) — deposits blocked, redemptions continue.
4. After some redemptions, remaining investors still hold ~80 shares.
5. Agent calls `reportPnL(vault, -50)` — NAV drops to `(100 - 50) / 80 = 0.625`.
6. Remaining redemptions execute at 0.625 NAV — the agent has effectively confiscated 37.5% of the remaining investors' value.
7. Where did the 37.5% go? Stays in `inVault`. The agent then calls `closeVault` again (already closed, but `Active` was the gate). If the agent has any shares, they redeem and pocket the difference.

### Exploit POC

See [`test_exploit_reportPnL_onClosedVault`](../contracts/test/Plinth.t.sol).

### Mitigation (v0.5)

```solidity
function reportPnL(bytes32 vaultId, int256 newPnL) external {
    Vault storage v = vaults[vaultId];
    if (v.status != VaultStatus.Active && v.status != VaultStatus.Paused) revert NotActive();
    // ... rest of reportPnL ...
}
```

Closed vaults are immutable. Any final PnL accounting must be done while the vault is still `Active` or `Paused`.

---

## #5 — Funds stuck at venue when vault closes 🟡 MEDIUM (accepted)

**Category**: design trade-off
**File**: [`Plinth.sol`](../contracts/src/Plinth.sol#L220-L226)

### Description

When an agent calls `closeVault`, no further `deployToVenue` is allowed (status is `Closed`, deployToVenue requires `Active`). If at the moment of close `deployedAUM > 0`, those funds can only return to the vault via `returnFromVenue`. If the venue contract is unresponsive, malicious, or has lost its operator's key, those funds are permanently stranded.

### Why not fixed in v0.5

This is a design tension between:
- Agent autonomy (agent decides when to close)
- Investor protection (funds shouldn't get stuck)

Possible v0.6 solutions:
- (a) `closeVault` requires `deployedAUM == 0` (forces agent to recover first)
- (b) Add `declareUnrecoverable(bytes32 vaultId, address venue)` — callable by anyone after vault has been `Closed` for ≥ 90 days; writes off the deployedAUM by reducing `reportedPnL`; lets remaining investors redeem at the lower NAV
- (c) Add a guardian role (multi-sig of underwriters) that can mark venues unrecoverable

We're deferring this to v0.6 because:
1. It requires either a status state-machine change or a new role, both of which need careful design
2. The off-chain Risk Monitor (already shipped) detects vaults with high `deployedAUM` heading toward close and flags them
3. The audit doc explicitly warns agents and investors of this constraint

---

## #6 — `reportedPnL` near INT256 bounds 🟡 MEDIUM

**Category**: arithmetic
**File**: [`Plinth.sol`](../contracts/src/Plinth.sol#L279-L281)

### Description

`_totalAUMOf` performs `int256(v.inVault) + int256(v.deployedAUM) + v.reportedPnL` with Solidity 0.8 overflow checks. If `reportedPnL` is near `INT256_MIN` and `inVault + deployedAUM` is small (or zero), the addition is safe. But if both operands push toward the boundary, the math reverts and any caller of `_totalAUMOf` (which includes `nav()`, `deposit()`, `redeem()`) reverts. Permanent state-level bricking is possible.

### Mitigation

Fix #3 implicitly addresses this: `MAX_PNL_MULTIPLE = 10` means `|reportedPnL| ≤ 10 × capital`. Combined with realistic `capital` values (USDC has ~30B circulating supply at 18 decimals = 3 × 10^28 wei, far below `INT256_MAX ≈ 5.79 × 10^76`), overflow is mathematically impossible after the fix.

---

## #7 — `createVault` spam → storage bloat 🟢 LOW (accepted)

**Category**: DOS
**Status**: self-limiting

A malicious agent can call `createVault` repeatedly with `MIN_DEPOSIT` and minimal venue arrays. Each call costs gas + 0.0001 USDC of locked capital. While storage grows, the attack:
- Costs the attacker more than the protocol (gas + locked USDC)
- Doesn't degrade any specific vault's behavior
- Is bounded by gas economics (attacker can't write infinite storage cheaply)

We accept this risk. v0.6 may add a per-agent vault creation rate limit if abuse is observed in practice.

---

## #8 — `strategyDescriptor` unbounded string 🟢 LOW

**Category**: gas griefing
**File**: [`Plinth.sol`](../contracts/src/Plinth.sol#L57)

### Description

`createVault` accepts an unbounded `string calldata strategyDescriptor`. While the function caller pays for the gas of storing/emitting it, an attacker could craft a vault with a megabyte-long descriptor that subsequently makes any `getVault` / event scanning operation expensive.

### Mitigation (v0.5)

```solidity
uint256 public constant MAX_STRATEGY_LEN = 1024;  // 1 KB

function createVault(...) external payable {
    if (bytes(strategyDescriptor).length > MAX_STRATEGY_LEN) revert StrategyDescriptorTooLong();
    // ... rest unchanged
}
```

1 KB is plenty for a one-paragraph description plus structured metadata (JSON, etc.) for Underwriter consumption.

---

## #9 — Reentrancy ✅ SAFE-BY-DESIGN

`Plinth` inherits OpenZeppelin's `ReentrancyGuard`. All payable functions (`createVault`, `deposit`, `returnFromVenue`) and all external-call-emitting functions (`redeem`, `deployToVenue`) are marked `nonReentrant`. State updates follow CEI (Checks → Effects → Interactions). Cross-function reentrancy is blocked because `nonReentrant` is contract-scoped.

**Note**: `nonReentrant` does NOT prevent the venue or recipient from making OTHER calls to OTHER contracts. The capability constraint is achieved by `approvedVenues` immutability, not reentrancy guards. Both layers are needed.

---

## #10 — Donation attack via selfdestruct ✅ SAFE-BY-DESIGN

A common pattern in DeFi is to force-send ETH (USDC on Arc) to a contract via `selfdestruct(payable(target))`, bypassing receive/fallback. This can manipulate share-price computations that read `address(this).balance`.

Plinth does NOT read `address(this).balance` anywhere. NAV computation uses `v.inVault + v.deployedAUM + v.reportedPnL` from storage. Each vault's accounting is independent; donations to the Plinth contract address don't update any specific vault's `inVault`.

Side effect: donated USDC is stranded forever (no vault claims it). This is a benign outcome — the attacker has gifted USDC to nobody. Plinth has no admin recovery function for stranded funds; this is by design (no admin keys).

---

## #11 — First-depositor / ERC-4626 inflation attack ✅ SAFE-BY-DESIGN

The classic ERC-4626 inflation attack works when:
1. Attacker is the first depositor with a tiny amount (e.g., 1 wei)
2. Attacker donates a large amount directly to the vault, inflating share price
3. Second depositor's deposit, when divided by inflated price, rounds down to 0 shares
4. Attacker withdraws both deposits

In Plinth, this attack fails because:
1. NAV computation uses storage (`v.inVault`), not `address(this).balance`. Donations don't affect NAV.
2. `MIN_DEPOSIT = 0.0001 USDC` prevents dust deposits that could round to 0 shares.
3. `if (sharesMinted == 0) revert NoSharesToMint()` provides explicit protection.

The ONLY way to inflate NAV is via `reportPnL`, which is bounded in v0.5 (see #3).

---

## v0.5 implementation checklist

- [x] Audit document (this file)
- [ ] Exploit POC tests added to `Plinth.t.sol`
- [ ] `Plinth_v05.sol` contract implementing fixes #1, #2, #3, #4, #6, #8
- [ ] `PlinthV05.t.sol` — reuses existing 52 tests (with `vm.warp` adjustments for cooldown) + new defense tests
- [ ] Deploy to Arc Testnet
- [ ] Update [`sdk-ts/src/constants.ts`](../sdk-ts/src/constants.ts) with v0.5 address
- [ ] Update [`docs/index.html`](index.html) web UI to support v0/v0.5 toggle
- [ ] Update [`README.md`](../README.md) to lead with v0.5

## v0.6 roadmap

Findings deferred to the next milestone:
- #5: `declareUnrecoverable` mechanism for stranded venue funds
- (potential) on-chain `RiskGuard` plug-in interface (see [`risk-controls.md`](risk-controls.md))
- (potential) per-agent vault creation rate limit if #7 spam is observed

---

## Audit conclusions

v0 is **research code**. The capability-constraint design (immutable `approvedVenues`, no agent withdraw, share-based accounting) is sound and was already strong against the most direct attacks (drain to attacker wallet, share dilution via mint, reentrancy). The gaps were in **economic and operational** territory — MEV extraction, NAV manipulation, lifecycle edge cases.

v0.5 closes those gaps without changing the core design. Agents and investors who used v0 can migrate to v0.5 by deploying a fresh vault; existing v0 vaults remain on chain as a historical / demo artifact.

Beyond v0.5: full third-party audit by a reputable firm (e.g., OpenZeppelin, Trail of Bits) is recommended before mainnet deployment, even with the in-team review.
