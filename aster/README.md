# @plinth/aster-bridge

Aster L1 venue adapter for [Plinth](https://github.com/Ccheh/plinth). Lets a Plinth agent run a real trading strategy on Aster Pro V3 (Aster L1, chainId 1666) and produces a **cryptographically reconcilable** PnL claim that Plinth's Underwriter can verify on chain.

```
Plinth Vault (Arc)                  Aster L1 (venue, chainId 1666)
  │                                   │
  │ deployToVenue                     │ open BUY 0.001 BTC
  ▼                                   ▼
MockVenue (Arc)                     real perp position
  │  ↑                                │
  │  │                                ▼ close (3-5 min later)
  │  │                              realized PnL ±$0.05
  │  │ reportPnL ←─── agent ────── (same wallet identity)
  ▼  │
   Plinth NAV updates                 │
                                      │
   Underwriter ─── reads venue ───────┘
   trade history via Aster /fapi/v3/userTrades
                                          │
                                          ▼
   verdict { VERIFIED | OVERSTATED | NO_VENUE_ACTIVITY }
   posted on Arc as UnderwriterReviewPosted event
```

## Why this is interesting

The standard concern with on-chain hedge funds is "agent self-reports PnL — investors must trust it." Plinth's v0 mitigates this with off-chain Underwriter reviews (LLM + rule-based) that anyone can post. But when the *venue itself is a public chain*, the Underwriter doesn't need to trust the agent at all — it can recompute the realized PnL from the venue's public trade history and post a cryptographically backed verdict on Plinth.

Aster L1 is the v0 demo target because it ships today. The same code pattern applies unchanged to any future Arc-native perp DEX.

## What's in this folder

| File | Purpose |
|---|---|
| `client.ts` | EIP-712 signed-request client for Aster Pro V3 (`chainId 1666`, domain `AsterSignTransaction`). HTTP transport via `curl` to bypass Node's TLS rejection by Aster's edge. |
| `verifier.ts` | Reconciles agent's on-Arc `reportedPnL` against Aster `userTrades`. Output: `VERIFIED` / `OVERSTATED` / `UNDERSTATED` / `NO_VENUE_ACTIVITY` with structured evidence. |
| `verify.ts` | Pre-flight credential check: confirms signer authorization, USDT balance, network reachability. |
| `demo-phase2.ts` | Dry-run: applies verifier to all existing Plinth vaults. Demonstrates fraud detection (correctly flags `NO_VENUE_ACTIVITY` on vaults whose `reportedPnL` was generated against MockVenue). |
| `demo-phase3.ts` | End-to-end real trade: creates Plinth vault → opens 0.001 BTC long on Aster → closes after 3 min → reports realized PnL on Plinth → Underwriter verifies → posts review on chain. |

## Run

```sh
cd plinth/aster
npm install

# 1. Credential pre-flight
npx tsx verify.ts

# 2. Apply verifier to existing vaults (no real money)
npx tsx demo-phase2.ts

# 3. End-to-end real trade (~5 USDT margin, isolated)
#    Add ASTER_USER / ASTER_SIGNER / ASTER_PRIVATE_KEY / ASTER_BASE_URL to ../../.env first.
#    To resume after a partial run: PHASE3_VAULT_ID=0x... npx tsx demo-phase3.ts
npx tsx demo-phase3.ts
```

## Result on submission day

Vault #5 (`0xefb495a0…`) on Arc Testnet:
- Aster L1 open `0.001 BTC` @ 80,500.7 — order `31402248641`
- Aster L1 close @ 80,517.9 — order `31402286923`
- Gross realized: `+0.0172 USDT`; commissions `0.0644`; **net `−0.0472 USDT`**
- [`reportPnL` on Plinth](https://testnet.arcscan.app/tx/0x0f15c4e1e0583aa14fc28ce1f0c1cb680efee5f5f2147d18bdf915d148d41002): `−0.047207 USDC`
- [`UnderwriterReviewPosted`](https://testnet.arcscan.app/tx/0x7ee06f9c18faf6e9c05fee9136ec3b8bc6ce06f7a934d7735342480ba5bad8e5): verdict `VERIFIED`, delta 0.00%

Total experimental cost: ~$0.05 USDT.

## Notes on the docs

The Aster V3 testnet docs claim `chainId 714` and require a `user` field in signed payloads. **Both are wrong for mainnet.** The reference implementation that actually works (drawn from a community v17 trading script) uses `chainId 1666` and omits `user` — only `signer` + `nonce` + `signature` are needed. The mainnet endpoint is `https://fapi.asterdex.com` (not `…-testnet`). This client matches the working pattern.
