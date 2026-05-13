# @plinth/sdk

TypeScript SDK for [Plinth](https://github.com/Ccheh/plinth) — capital
layer for AI trading agents on Arc.

[![tests](https://img.shields.io/badge/vitest-29%2F29%20passing-success)](#)
[![Arc Testnet](https://img.shields.io/badge/Arc%20Testnet-v0%20live-blue)](https://testnet.arcscan.app/address/0xc2994ce3df612ebd2f898244a992a0bbfef86627)

## Install

```sh
pnpm add @plinth/sdk        # once published
# or, for now:
git clone https://github.com/Ccheh/plinth
cd plinth/sdk-ts
npm install
```

## Quickstart — agent integrating Plinth (5 minutes)

```typescript
import {
  AgentClient,
  PLINTH_ARC_TESTNET,
} from "@plinth/sdk";
import { parseEther } from "viem";

const agent = new AgentClient({
  privateKey: process.env.AGENT_PRIVATE_KEY as `0x${string}`,
  plinthAddress: PLINTH_ARC_TESTNET.plinth,
});

// 1. Create a vault. msg.value is the agent's "skin in the game".
const { vaultId } = await agent.createVault({
  approvedVenues: [HYPERLIQUID_VAULT_ADDR, ASTER_PERP_ADDR],
  strategyDescriptor: "BTC perp momentum, max 3x leverage, daily rebalance",
  initialDepositWei: parseEther("0.01"),  // 0.01 USDC
});
console.log("Vault ID:", vaultId);

// 2. After investors deposit (via InvestorClient), agent deploys to a venue
await agent.deployToVenue(vaultId, HYPERLIQUID_VAULT_ADDR, parseEther("0.05"));

// 3. After trading, agent reports mark-to-market PnL (signed int)
await agent.reportPnL(vaultId, parseEther("0.012"));   // +0.012 USDC PnL

// 4. When position closes and USDC returns to the venue → return to vault
await agent.returnFromVenue(vaultId, HYPERLIQUID_VAULT_ADDR, parseEther("0.062"));

// 5. Lifecycle controls
await agent.setPaused(vaultId, true);   // stop accepting new deposits
await agent.closeVault(vaultId);        // permanent — existing investors can still redeem
```

## Quickstart — investor depositing into a vault

```typescript
import { InvestorClient, PLINTH_ARC_TESTNET, formatUsdc } from "@plinth/sdk";
import { parseEther } from "viem";

const investor = new InvestorClient({
  privateKey: process.env.INVESTOR_PRIVATE_KEY as `0x${string}`,
  plinthAddress: PLINTH_ARC_TESTNET.plinth,
});

// 1. Browse vault state
const v = await investor.getVault(vaultId);
console.log(`Strategy: "${v.strategyDescriptor}"`);
console.log(`NAV: ${formatUsdc(await investor.getNAV(vaultId))} USDC/share`);

// 2. Deposit at current NAV
const dep = await investor.deposit(vaultId, parseEther("0.005"));
console.log(`Got ${formatUsdc(dep.sharesMinted)} shares at NAV ${formatUsdc(dep.navAtDeposit)}`);

// 3. Redeem at any time (assuming vault has liquid)
const red = await investor.redeem(vaultId, dep.sharesMinted);
console.log(`Redeemed for ${formatUsdc(red.usdcOut)} USDC`);
```

## Quickstart — browsing all vaults (read-only, no key)

```typescript
import { BrowseClient, PLINTH_ARC_TESTNET, formatUsdc } from "@plinth/sdk";

const browser = new BrowseClient({ plinthAddress: PLINTH_ARC_TESTNET.plinth });

const latestBlock = await browser.publicClient.getBlockNumber();
const vaults = await browser.listAllVaults(latestBlock - 9_000n, "latest", true);

for (const v of vaults) {
  console.log(`${v.vaultId.slice(0,10)} ${v.agent.slice(0,8)} ${formatUsdc(v.nav!)} ${v.strategyDescriptor.slice(0,40)}`);
}

const reviews = await browser.listReviews(vaultId, latestBlock - 9_000n);
console.log(`${reviews.length} underwriter review(s) for vault ${vaultId.slice(0,10)}`);
```

## API surface

### `AgentClient` (agent-side)

```typescript
class AgentClient {
  constructor({ privateKey, plinthAddress, chain? });

  // create + control
  createVault({ approvedVenues, strategyDescriptor, initialDepositWei }) → { txHash, vaultId }
  setPaused(vaultId, paused) → txHash
  closeVault(vaultId) → txHash

  // operations
  deployToVenue(vaultId, venue, amountWei) → txHash
  returnFromVenue(vaultId, venue, amountWei) → txHash    // msg.value = amount
  reportPnL(vaultId, newPnL: bigint /* signed */) → txHash

  // reads
  getVault(vaultId) → VaultState
}
```

### `InvestorClient` (investor-side)

```typescript
class InvestorClient {
  constructor({ privateKey, plinthAddress, chain? });

  // write
  deposit(vaultId, usdcWei) → { txHash, sharesMinted, predictedShares, navAtDeposit }
  redeem(vaultId, shareAmount) → { txHash, usdcOut, predictedUsdcOut, navAtRedeem }
  postUnderwriterReview(vaultId, reviewHash, reviewUri) → txHash

  // reads
  getVault(vaultId) → VaultState
  getNAV(vaultId) → bigint
  getNAVRecomputed(vaultId) → bigint   // off-chain re-compute, sanity check
  sharesOf(vaultId, user?) → bigint
  getApprovedVenues(vaultId) → Hex[]
}
```

### `BrowseClient` (read-only, no key)

```typescript
class BrowseClient {
  constructor({ plinthAddress, chain? });

  listAllVaults(fromBlock?, toBlock?, withState?) → VaultListing[]
  listReviews(vaultId, fromBlock?) → UnderwriterReview[]
}
```

### Math + utilities

```typescript
deriveVaultId(agent, vaultCount, chainId) → vaultId
computeNav(inVault, deployedAUM, reportedPnL, totalShares) → bigint
sharesForDeposit(usdcWei, navWei) → bigint
usdcForRedeem(shares, navWei) → bigint
formatUsdc(wei, decimals=6) → string

// constants
ARC_TESTNET          // { chainId: 5042002, rpc, explorer }
PLINTH_ARC_TESTNET   // { plinth, mockVenue1, mockVenue2, deployTx }
INCEPTION_NAV        // 10n ** 18n
VaultStatus          // { None: 0, Active: 1, Paused: 2, Closed: 3 }
```

## Robustness notes

- All write calls wait for receipt with **5-minute timeout + 4s polling** (Arc Testnet's RPC frequently lags). `AgentClient.createVault` pre-computes the deterministic `vaultId` and returns it even if receipt confirmation times out, so callers always have a usable id.
- `eth_getLogs` on Arc Testnet is capped at **10,000-block ranges**. `BrowseClient` doesn't auto-chunk yet (v0); pass an explicit `fromBlock` within that window.

## Tests

```sh
npm test
# 29 vitest tests passing — utils math + constants + ABI surface
```

## Example: full lifecycle on Arc Testnet

```sh
# requires PRIVATE_KEY + SERVICE_PRIVATE_KEY in D:\桌面\arc\.env
npx tsx examples/full-lifecycle.ts
```

Walks through: create vault → investor deposit → deploy to venue → +PnL → return from venue → redeem → underwriter review. ~7 on-chain txs, ~2 min wall clock, total cost ~0.01 USDC of gas.

See `examples/create-demo-vaults.ts` for the script that seeded the 4 demo vaults currently live on Arc Testnet.

## License

MIT.
