# Wrap your agent in Plinth in 15 minutes

This guide is for AI agent developers who already have a working trading bot (perps, prediction markets, AMMs, prediction markets — anything) and want to turn it into a **tokenized fund**: real depositors, real shares, real on-chain PnL, all without touching custody.

If you're building for any of the Canteen × Arc Agora RFBs (1, 2, 4, 5, 6), this gives you:

- Real **TVL** numbers for your submission (depositors instead of "trading my own $100")
- **Verifiable PnL** if your venue is itself a public chain (Aster L1 today, Hyperliquid, future Arc-native perps)
- An **Underwriter Review** posted on chain that audits your honesty — boosts trust without you needing a brand
- Composable with the rest of the Agora stack (Mandate, Crucible, Helm, Cadence)

Plinth doesn't do strategy. It's the capital + accounting layer below your strategy.

---

## What you need before starting

- Node.js ≥ 20 and `npm`
- Your agent's existing wallet (private key) — the wallet you use to sign trade txs
- That wallet funded with at least **0.005 USDC** on Arc Testnet (for vault creation + 2 gas-priced txs). [Faucet here](https://faucet.testnet.arc.network) or ask in the Canteen Discord
- The **address(es)** of the venue(s) you trade on. For an Arc-native venue this is a contract address. For an off-chain venue (CEX, Aster, Hyperliquid) you'll either use a bridge contract or a `MockVenue` placeholder + off-chain PnL reporting (we'll cover both)

---

## Step 1 — Install the SDK

```sh
git clone https://github.com/Ccheh/plinth
cd plinth/sdk-ts
npm install
```

The SDK is also npm-installable once published: `npm i @plinth/sdk` (TBD).

Make a fresh file `agent-integration.ts`:

```typescript
import { AgentClient, PLINTH_V05_ARC_TESTNET, formatUsdc } from "../sdk-ts/src/index.js";
import { parseEther } from "viem";
import type { Hex } from "viem";

const agent = new AgentClient({
  privateKey: process.env.AGENT_PRIVATE_KEY as Hex,
  plinthAddress: PLINTH_V05_ARC_TESTNET.plinth,  // use v0.5 (security-hardened)
});
```

Replace `AGENT_PRIVATE_KEY` with your agent's existing trading wallet — same key you use to sign your trade orders. No need for a separate "fund operator" key.

---

## Step 2 — Create your vault (3 minutes)

```typescript
const APPROVED_VENUES = [
  // For an Arc-native perp DEX, put its contract address.
  // For an off-chain venue (Aster L1, Hyperliquid, Polymarket), use a MockVenue
  // address as the on-chain accounting placeholder — your agent makes the real
  // trade off-chain, and Plinth tracks the deployed capital via deployToVenue / returnFromVenue.
  PLINTH_V05_ARC_TESTNET.mockVenue1,
] as Hex[];

const { txHash, vaultId } = await agent.createVault({
  approvedVenues: APPROVED_VENUES,
  strategyDescriptor:
    "BTC perp momentum on Aster L1, max 4× leverage. " +
    "Strategy: hold long when funding < 0, hold short when funding > 0.05%, flat otherwise. " +
    "Daily rebalance. Source: github.com/yourname/your-agent.",
  initialDepositWei: parseEther("0.001"),  // 0.001 USDC skin-in-the-game
});

console.log("Vault created:", vaultId);
console.log("Tx:", txHash);
```

**About `strategyDescriptor`**: Write it like a human will read it. Specific is better than vague. Include venue, leverage limits, rebalance frequency, kill-switch conditions if any. The Plinth LLM Underwriter reads this and grades it; vague descriptors get flagged ("missing leverage spec," "no kill switch," etc.). Max 1024 bytes.

**About `initialDepositWei`**: This is the agent's own first deposit. Earns shares at 1 USDC = 1 share inception NAV. Minimum is `0.0001 USDC` but most teams use `0.001` or higher to signal commitment.

**About `approvedVenues`**: This list is **immutable for the vault's lifetime**. Pick carefully. You can list up to 16 venues (e.g., your primary perp DEX + a stablecoin parking spot + a backup). You CAN list yourself as a venue if your agent does some local accounting, but the LLM Underwriter will flag this as the classic "agent-as-venue" red flag — be ready to defend why.

---

## Step 3 — Wire your trading loop (5 minutes)

Inside your agent's existing trading loop, you now need three Plinth calls:

### When you open a position (deploy capital to the venue)

```typescript
async function openPosition(notionalWei: bigint) {
  // 1. Move USDC from the vault to the venue
  await agent.deployToVenue(vaultId, APPROVED_VENUES[0], notionalWei);

  // 2. Your existing trade-opening code, unchanged
  await yourAgentClient.placeMarketOrder({ symbol: "BTCUSDT", side: "BUY", size: ... });
}
```

`deployToVenue` decreases `inVault`, increases `deployedAUM`. It also transfers the USDC to the venue contract address. If your venue is on-chain, the USDC arrives at the venue immediately. If your venue is off-chain (Aster L1, Hyperliquid), the funds sit at a MockVenue contract address as the on-chain accounting twin of your off-chain venue balance.

### When you close a position (return capital + record PnL)

```typescript
async function closePosition(notionalWei: bigint, realizedPnLWei: bigint) {
  // 1. Your existing trade-closing code, unchanged
  const closeResult = await yourAgentClient.closeOrder(...);

  // 2. Tell Plinth what was realized
  await agent.reportPnL(vaultId, realizedPnLWei);  // signed; negative for losses

  // 3. (For off-chain venues) Move the venue's recovered USDC back to the vault.
  //    Your code is responsible for actually getting the USDC into the contract;
  //    Plinth just updates the accounting.
  await agent.returnFromVenue(vaultId, APPROVED_VENUES[0], notionalWei + realizedPnLWei);
}
```

**`reportPnL` is signed (`int256`)**, so positive = profit, negative = loss. v0.5 caps it at 10× capital (to catch typos) and rate-limits to 25%/hour (to prevent NAV manipulation rugs).

### Periodic mark-to-market (optional but recommended)

If your strategy holds positions for days/weeks, investors won't be able to read a fair NAV from `inVault` alone. Run a periodic mark-to-market job:

```typescript
async function markToMarket() {
  const venueState = await yourAgentClient.queryAccountState();
  const currentMtmWei = computeUnrealizedPnL(venueState);

  // reportPnL accepts the CURRENT total PnL, not deltas. So if your position
  // is up $1 unrealized + $2 realized historically, send $3.
  const totalPnL = currentMtmWei + (await getCachedRealizedPnL());
  await agent.reportPnL(vaultId, totalPnL);
}
```

Schedule this every ~1-6 hours depending on strategy volatility. The Plinth Risk Monitor will flag a vault with stale PnL after 7 days of silence.

---

## Step 4 — Get your first review (2 minutes)

The fastest way: run the bundled LLM Underwriter against your own vault.

```sh
cd plinth/underwriter
npm install
ANTHROPIC_API_KEY=sk-ant-... npx tsx review.ts --vault 0x_your_vault_id
```

This reads your strategy descriptor, scans your agent's on-chain activity, and posts a structured risk review. You'll get one of `low / medium / high / critical` plus a list of flagged concerns.

The review is now on chain and visible at https://ccheh.github.io/plinth/ — anyone considering depositing into your vault will see it.

For the **verifiable-PnL** path (only works if your venue is itself a public chain), see [`aster/verifier.ts`](../aster/verifier.ts) for the reference implementation. The pattern:

1. Pull your trade history from the venue's public API (or scan the venue chain's events)
2. Sum `realizedPnL - commissions` over the relevant window
3. Compare to the agent's on-chain `reportedPnL`
4. Post the verdict on chain via `investor.postUnderwriterReview(vaultId, reviewHash, reviewUri)`

For Aster L1, the verifier is already written and runs against any vault that trades on Aster. For new venues (Arc-native perp DEX, Hyperliquid, Polymarket), the verifier is ~150 LOC and you can adapt `aster/verifier.ts` as a template.

---

## Step 5 — Bootstrap your first depositors (2 minutes)

You don't need real third parties on day 1 — the architecture supports demonstration depositors transparently. See [`underwriter/bob-deposit-and-review.ts`](../underwriter/bob-deposit-and-review.ts) for the reference pattern: generate a fresh wallet, fund it with a small amount, sign deposit + review txs from that wallet.

**Important**: do NOT claim demonstration wallets are unaffiliated humans in your submission text. The fix is to be transparent — in your README, write:

> *"Demo wallets `0xA4Fe…` and `0xB7C2…` are operator-funded for the launch period to exercise multi-signer flows on chain. Production launch will rely on third-party depositors."*

Once you have real interest (Canteen Discord teams, friends, Twitter responses), point them at your vault's page on https://ccheh.github.io/plinth/, give them the vault ID, and they can deposit via the Plinth UI (forthcoming) or via the SDK:

```typescript
import { InvestorClient, PLINTH_V05_ARC_TESTNET } from "@plinth/sdk";
import { parseEther } from "viem";

const investor = new InvestorClient({
  privateKey: process.env.INVESTOR_PRIVATE_KEY,
  plinthAddress: PLINTH_V05_ARC_TESTNET.plinth,
});

const result = await investor.deposit("0x_your_vault_id", parseEther("0.005"));
console.log("Got", result.sharesMinted, "shares at NAV", result.navAtDeposit);
```

---

## Common patterns

### "My agent uses Python, not TypeScript"

The Plinth ABI works from any language. Use `web3.py` with the ABI exported from `sdk-ts/src/constants.ts`:

```python
from web3 import Web3
import json

w3 = Web3(Web3.HTTPProvider("https://rpc.testnet.arc.network"))
plinth_abi = json.loads(open("plinth_abi.json").read())
plinth = w3.eth.contract(address="0xba1b087b0ac77b398c250a9fd7e298f3f96addc7", abi=plinth_abi)

# Call deployToVenue
tx = plinth.functions.deployToVenue(vault_id, venue, amount).build_transaction({
    "from": agent_address,
    "nonce": w3.eth.get_transaction_count(agent_address),
})
signed = w3.eth.account.sign_transaction(tx, private_key=agent_pk)
w3.eth.send_raw_transaction(signed.rawTransaction)
```

### "My venue isn't on Arc — how does the cross-chain accounting work?"

For v0, the pattern is **Agent-as-Oracle**:

```
Plinth Vault (Arc) ─── 持有 USDC
       │
       │ deployToVenue(MockVenue, X)  ← accounting only
       ▼
   MockVenue (Arc) ─── "X USDC is at Aster L1"
       │
       │ same agent identity, off-chain trade
       ▼
   Aster L1 (real venue) ─── opens real BTC perp
       │
       │ realizes PnL
       ▼
   agent.reportPnL(realized)  ← back to Arc
```

Capital doesn't actually cross chains. The vault books say "X USDC is deployed"; the agent's actual cross-chain trading uses separate, parallel capital. Many real strategies work this way already (the agent has a Hyperliquid sub-account, a CEX sub-account, etc.). Plinth is the on-Arc tokenized fund pool that mirrors the consolidated PnL.

When CCTP-bridged stablecoins flow back to Arc, `returnFromVenue` reconciles the accounting.

### "How do investors redeem if `inVault < usdcOut`?"

`redeem()` reverts with `InsufficientLiquidity`. The agent must `returnFromVenue` first to make liquidity available. This is by design — agents can't be forced to instantly unwind a position.

If an agent is unresponsive and investors are stuck, v0.5 ships with no automatic resolution. v0.6 will add a `declareUnrecoverable` mechanism that lets investors write off frozen deployedAUM after a configurable lockup period.

### "Can I add fees later?"

Not in v0/v0.5 — no fee mechanism is built. The protocol takes no cut; the agent takes no cut. v0.2 will add an ERC-4626-style management + performance fee config that agents can opt into per-vault.

---

## Gotchas

| Gotcha | Fix |
|---|---|
| **My deposit reverts with `SharesPendingVesting`** when I try to redeem | v0.5 adds a 1-hour cooldown after every deposit. Wait. This is the **#1 security fix vs v0** (sandwich-on-reportPnL defense). For testing, advance EVM time. |
| **`reportPnL` reverts with `PnLRateLimitExceeded`** | You tried to change NAV by > 25% within 1 hour of the last report. Either wait, or split the move into smaller chunks over time. |
| **`reportPnL` reverts with `PnLOutOfBounds`** | Your absolute `|reportedPnL|` exceeds 10× your capital (`inVault + deployedAUM`). Sanity-check your value; you probably have a typo. |
| **`returnFromVenue` reverts with `NotAuthorized`** | v0.5 requires `msg.sender` to be the venue OR the agent. A random caller can no longer push USDC into the vault (security fix vs v0). |
| **My Underwriter review post fails on a closed vault** | v0.5 rejects `reportPnL` on Closed vaults but allows `postUnderwriterReview`. Make sure you're calling the right function. |
| **My viem `waitForTransactionReceipt` times out on Arc Testnet** | Arc Testnet's RPC frequently drops connections for ~30 seconds at a time. Set `timeout: 60_000, retryCount: 2` and poll manually for receipts if needed. |

---

## Submitting to Canteen with Plinth

When you write your Canteen submission:

1. **List your Plinth vault ID prominently** in the traction section
2. **Show the on-chain numbers**: TVL, depositor count, NAV trajectory, realized PnL
3. **Link the Plinth UI page** for your vault: `https://ccheh.github.io/plinth/?vault=0x_your_id`
4. **Note any Underwriter reviews** you've earned, with tx hashes
5. **If your venue is a public chain**, the Verifiable-PnL pattern is your strongest differentiator — make sure it's in your pitch

Example traction paragraph for your submission:

> *"Our agent trades [strategy] on [venue]. Capital is managed through a Plinth Vault (vault id `0x...`) on Arc Testnet — 4 third-party depositors, $X TVL, NAV moved from 1.0 → Y over the testing period. Reported PnL of $X is cryptographically reconcilable against [venue]'s on-chain trade history (see Underwriter Review tx `0x...`). 2 independent Underwriters posted reviews on chain."*

---

## What to do if you get stuck

- Read the [Plinth README](../README.md) for the protocol architecture
- Read [`docs/security-audit.md`](security-audit.md) if you have security questions
- Browse other live vaults at https://ccheh.github.io/plinth/ for reference patterns
- Open an issue at https://github.com/Ccheh/plinth/issues
- DM the operator in the Canteen Discord

The fastest path: copy [`underwriter/bob-deposit-and-review.ts`](../underwriter/bob-deposit-and-review.ts) as a template and modify it for your agent's specific actions. Most teams find this faster than writing from scratch.

---

## Time budget recap

| Task | Time |
|---|---|
| Install SDK + write `agent-integration.ts` | 2 min |
| Create your vault | 3 min |
| Wire trading loop with `deployToVenue` / `reportPnL` / `returnFromVenue` | 5 min |
| Run LLM Underwriter against your vault | 2 min |
| Bootstrap demonstration depositors (Bob pattern) | 3 min |
| **Total** | **15 min** |

The agent code you already have is the 80%. Plinth is the 20% of glue that turns it into a tokenized fund. The architecture is intentionally thin so you can keep iterating on what's actually hard — your strategy.
