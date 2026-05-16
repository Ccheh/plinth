# @plinth/verifier-core

[![npm version](https://img.shields.io/badge/npm-not%20yet%20published-orange)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Tests](https://img.shields.io/badge/sourced%20from-Plinth%20main%20test%20suite-success)](#)

**Public-goods extraction of [Plinth](https://github.com/Ccheh/plinth)'s Underwriter verifier abstraction.** Generic interface + reference implementations for cryptographically reconciling a trader's on-chain reported PnL against a venue's trade history.

> Built so other on-chain fund-management protocols don't have to re-invent the verifier abstraction. MIT licensed.

## Why this exists

When a trading agent on Arc (or anywhere) reports PnL on chain, downstream investors trust that number unless someone independently verifies it. Plinth introduced an Underwriter agent that reads the venue's trade history and cryptographically reconciles it against the agent's claim — verdict posted on chain.

That pattern is now public goods: any protocol can `npm install @plinth/verifier-core` and get the verifier interface + reference implementations (Aster L1, Synthra Perp on Arc).

## What's in this package

```
@plinth/verifier-core              IPerpVerifier interface + shared types + classify() + renderMarkdown()
@plinth/verifier-core/aster        AsterVerifier — reads Aster L1 userTrades, reconciles PnL
@plinth/verifier-core/synthra      SynthraPerpVerifier — scaffold for Arc-native Synthra Perp (subgraph schema TBD)
```

## Quick start

```typescript
import {
    IPerpVerifier,
    type VerificationReport,
    classify,
    renderMarkdown,
} from "@plinth/verifier-core";
import { AsterVerifier, AsterClientLike } from "@plinth/verifier-core/aster";

// You provide the venue API client. Minimal interface = `getUserTrades(symbol, limit)`.
const client: AsterClientLike = makeYourAsterClient(/* api keys etc */);

const verifier: IPerpVerifier = new AsterVerifier({
    client,
    tolerancePct: 5,  // 5% delta accepted as VERIFIED
});

const report: VerificationReport = await verifier.verifyReport({
    vaultId: "0xc003ec854ac99d10...",
    symbol: "BTCUSDT",
    reportedPnlWei: -47_207_000_000_000_000n,  // -0.047207 USDC (18 decimals on Arc)
    windowStartMs: Date.now() - 3600_000,
});

if (report.verdict === "VERIFIED") {
    const markdown = renderMarkdown(report);
    // post on-chain via Plinth.postUnderwriterReview(...) or any equivalent
}
```

## Adding a new venue

Implement `IPerpVerifier`:

```typescript
import { IPerpVerifier, VerificationReport, VerifyReportArgs, VenueIdentity, classify } from "@plinth/verifier-core";

const MY_VENUE: VenueIdentity = {
    name: "My Perp DEX",
    chain: "Arc",
    chainId: 5042002,
    explorerNote: "Trades indexed at my-subgraph.example/...",
};

export class MyVenueVerifier implements IPerpVerifier {
    readonly identity = MY_VENUE;
    readonly tolerancePct = 5;

    async verifyReport(args: VerifyReportArgs): Promise<VerificationReport> {
        const reportedUsdc = Number(args.reportedPnlWei) / 1e18;

        // Read trade history from your venue (subgraph / REST / on-chain logs)
        const trades = await yourVenueClient.tradesFor(args.symbol, args.windowStartMs, args.windowEndMs);
        const netRealizedUsdc = trades.reduce((sum, t) => sum + t.realizedPnL - t.fee, 0);

        // Use the centralized verdict logic so your reviews compare against other venues
        const { verdict, deltaAbs, deltaPct } = classify(reportedUsdc, netRealizedUsdc, trades.length, this.tolerancePct);

        return {
            verdict,
            vaultId: args.vaultId,
            symbol: args.symbol,
            windowStart: args.windowStartMs,
            windowEnd: args.windowEndMs ?? Date.now(),
            claim: { reportedPnlWei: args.reportedPnlWei.toString(), reportedPnlUsdc: reportedUsdc },
            venue: {
                ...this.identity,
                eventCount: trades.length,
                realizedPnlGrossUsdc: trades.reduce((s, t) => s + t.realizedPnL, 0),
                totalFeesUsdc: trades.reduce((s, t) => s + t.fee, 0),
                netRealizedUsdc,
            },
            delta: { absUsdc: deltaAbs, pct: deltaPct },
            generatedAt: Date.now(),
            notes: [`Reconciled ${trades.length} trades from ${this.identity.name}.`],
        };
    }
}
```

That's it. Any protocol can drop your verifier into their Underwriter pipeline.

## Real-world deployments using this pattern

- **[Plinth](https://github.com/Ccheh/plinth)** — Capital layer for AI trading agents on Arc. Vault #5 demonstrates the pattern end-to-end: 3 real BTC perp round-trips on Aster L1 mainnet, agent reported −0.047 USDC PnL on Arc, Underwriter matched to 0.00% delta, VERIFIED review posted on chain.

If you ship a verifier using this package, open a PR adding your project here.

## Roadmap

- [ ] Real Synthra Perp implementation once the trader-side subgraph schema is finalized
- [ ] HyperLiquid verifier (chainId 998)
- [ ] Generic on-chain DEX verifier reading Uniswap v3 `Swap` events (works for Synthra spot + any v3 fork)
- [ ] CEX verifier base class for ASTERdex-style REST APIs (Binance, OKX, ByBit shapes)

## License

MIT. Same as parent [Plinth](https://github.com/Ccheh/plinth) repository.

## Acknowledgements

Extracted from Plinth's `aster/perp-verifier.ts` (the file that proved this pattern works) for the [Circle Developer Grant 2026 — Arc track](https://www.circle.com/grant) submission.
