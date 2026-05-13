# Plinth — Canteen Discord Outreach Kit

> All copy below is ready to paste into Canteen Discord / Arc Builder
> Discord / Twitter / DMs. You drive the conversations; this kit gives you
> the words.

---

## 📌 Use this kit in 3 stages

1. **Day 8 (Sunday afternoon)** — post the intro in Canteen Discord (`#general` or `#showcase`). Use Variant A.
2. **Day 9 (Monday)** — DM each RFB 1/2/4/5/6 team that's looking active. Use the per-RFB pitch.
3. **Day 10 (Tuesday)** — follow up with anyone who showed interest. Use the integration walkthrough.

---

## Variant A — Canteen Discord #showcase post (250 words)

```
Hey builders 👋 dropping a tool that might be useful if you're building any of the trading-agent RFBs.

I just shipped **Plinth** — an open-source capital layer for AI trading agents on Arc Testnet. Think of it as "hedge fund infrastructure for your agent": your agent creates a vault, anyone can deposit USDC and get shares at NAV, your agent deploys vault capital to pre-approved venues, reports PnL → NAV updates → investors redeem at the new NAV.

**Why I'm sharing**: if you're building for RFB 1/2/4/5/6, the bottleneck for traction is usually "I'm running on my own $100 of testnet USDC and the demo PnL looks small". With Plinth, you can put your agent in a vault, ask 3-5 friends or other Canteen builders to deposit testnet USDC for the demo, and now your traction numbers (TVL, depositors, NAV changes) are real.

I'm offering to **help any RFB team tokenize their agent into a Plinth vault for free**. Takes ~15 minutes:
- you give me your agent's wallet address + a 1-line strategy description + the venue address(es) you trade on
- I help you create the vault and wire your existing agent code to use Plinth-deployed USDC

Live + deployed:
- Contract: `0xc2994ce3df612ebd2f898244a992a0bbfef86627` on Arc Testnet
- Repo (MIT): github.com/Ccheh/plinth
- SDK: `@plinth/sdk` TypeScript, 29 vitest tests, full lifecycle ran on chain
- Web browser: (link if you put it on netlify/vercel)

DM me or react with 👀 if you want to integrate.
```

### Adjustments

- If the channel is more formal, change "Hey builders 👋" to "Hi all,"
- If they have a `#showcase-projects` channel, post there. Otherwise `#general`.
- DON'T post twice. One channel, one post. Lurk and DM teams that respond.

---

## Variant B — Twitter / X post (shorter, public reach)

```
Just shipped Plinth for the Agora Agents Hackathon ⚓

It's hedge fund infrastructure for AI trading agents on @circle's Arc:
- agent creates a vault
- anyone deposits USDC, gets shares at NAV
- agent deploys to whitelisted venues, reports PnL
- investors redeem at NAV anytime

Live on Arc Testnet 👇
github.com/Ccheh/plinth

If you're building a trading agent and want to tokenize it (turn your demo into a real fund with investor shares), I'll wire it up for free this week. DM me.
```

- Tag `@circle`, `@buildonarc`, `@thecanteenapp`
- Pin if you have followers

---

## Per-RFB pitches (use in DMs after they respond)

### RFB 1 — Perp Futures Trading Agent

```
Hey [name], saw you're working on the perp futures RFB. If you're trading
on Hyperliquid / Aster / etc., Plinth could be the wrapper that makes your
demo more credible.

Quick framing: your agent currently runs on whatever you funded it with.
With Plinth, your agent IS a hedge fund — friends and Canteen builders
can deposit testnet USDC, watch your agent's PnL roll in, redeem when
they want. Now your "traction" answer for the submission isn't "I traded
my own $100" — it's "$X TVL across N depositors".

Plinth takes 15 min to integrate:
- I help you createVault with your agent's address + Hyperliquid/Aster
  contract addresses as approvedVenues
- Your existing perp-trade code calls Plinth.deployToVenue → pulls from
  vault instead of your own balance
- After each trade you call Plinth.reportPnL with your realized PnL

Want me to scaffold it together with you? Send me your agent's repo if
public, I can do a PR.
```

### RFB 2 — Prediction Market Trader Intelligence

```
Hey [name], for the prediction-market trader RFB — Plinth could be useful.

Your AI picks contracts and bets. Right now if the demo shows "AI made
12% PnL on $50 of testnet bets" — judges have to take your word. With
Plinth, the AI's bets come from a vault that 5 people deposited testnet
USDC into. Now PnL is provably across N investors' capital.

The integration: register the prediction market platform's contract as
an approved venue, have your agent call deployToVenue to move USDC out
when placing bets, then returnFromVenue on resolution.

Want me to help wire this up?
```

### RFB 4 — Adaptive Portfolio Manager

```
Hey [name], adaptive-portfolio-manager RFB looks fun. Plinth probably
fits cleanly here.

Your agent manages allocation across N assets. With Plinth, depositors
give your agent capital to manage. The "regime detection + rebalancing"
becomes a real fund. Bonus: idle USDC in inVault is sitting there —
you could auto-stake into USYC (Circle's RWA token) for yield while
not deployed, makes the demo even richer.

I can help you wire up the vault + USYC sweep if you want.
```

### RFB 5 — Cross-Platform Arbitrage Agent

```
Hey [name], arbitrage agent — interesting. Plinth might be a good fit if
you want the "fund" angle.

Arbitrage strategies have predictable Sharpe and consistent small wins,
so they're ideal candidates for an external-capital wrapper: invest in
the strategy, get a steady drip of NAV gains.

If you're game, I can help set up a vault that lets others deposit USDC,
and your existing arb agent just calls Plinth.deployToVenue → trade →
Plinth.returnFromVenue + reportPnL.
```

### RFB 6 — Social Trading Intelligence

```
Hey [name], social-trading RFB. Plinth could complement well.

Your AI picks which traders to copy. Currently the demo shows your AI's
performance on your funds. With Plinth, you wrap the AI itself in a
vault — others deposit, your AI's copy decisions deploy capital to the
followed traders' venues. Now the "social trading" pitch is concrete:
investors deposit, AI copy-trades on their behalf, NAV reflects the
results.

Want me to help wire it up?
```

---

## FAQ — anticipated questions

### "Is this Solidity audited?"

```
No external audit. 52 forge tests pass including adversarial scenarios.
Self-run Slither would happen in v0.2. For the hackathon demo with
testnet USDC the audit risk is moot.
```

### "What stops the agent from rugging?"

```
The approvedVenues whitelist is immutable at vault creation. Agent can
ONLY call deployToVenue to addresses in that list. They CANNOT add new
addresses later. The check is hard-coded in the contract.

What the agent CAN do is list themselves (or a sock-puppet contract
they control) as an approvedVenue at creation. This is detectable
off-chain — the Plinth Underwriter Agent reviews the approvedVenues
list and flags this as a CRITICAL red flag. That review is posted on
chain (UnderwriterReviewPosted event) so prospective investors see it
before depositing.

It's a "defense in depth" approach: contract layer makes drain to
arbitrary addresses impossible; off-chain reviewer makes drain to
self-listed addresses visible.
```

### "Does the agent earn fees?"

```
v0: no fees. Agent's incentive in v0 is to demo their strategy with
external capital. v0.2 will add management + performance fee with
high-water-mark accounting.
```

### "Can I use a real Hyperliquid / Aster / GMX contract as the venue?"

```
Yes — that's the intended pattern. The venue just needs to be a
contract that can receive USDC. Some venues might require additional
setup (deposit functions, position management), so for v0 demo we
provide MockVenue.sol as a placeholder. v0.2 will add ready-made
adapters for the top 3 Arc venues.

If you have a Hyperliquid integration working in your agent already,
add Hyperliquid's USDC vault contract as an approvedVenue at vault
creation. Then your agent calls deployToVenue → Plinth transfers USDC
to Hyperliquid → your agent trades.
```

### "How do I report PnL? Is it trusted?"

```
v0: agent reports PnL via reportPnL(vaultId, newPnL). It's trusted in
v0 — meaning a malicious agent could lie about PnL to inflate NAV.

In production:
- Real venues (Hyperliquid, Aster) have on-chain position state that
  can be verified. An oracle or anyone can audit.
- v0.2 will add stake/bond economics for honesty enforcement.

For the hackathon demo, agents report PnL honestly because the
audit trail is public.
```

### "How small a deposit can I make for testing?"

```
0.0001 USDC minimum (the MIN_DEPOSIT constant). Plinth is designed
for sub-cent flows from the start.
```

### "Why use Plinth instead of just deploying my agent?"

```
Three reasons:
1. Traction signal in the hackathon submission — N depositors and
   $X TVL are real numbers.
2. Realistic demo — the agent isn't trading its own funds, it's
   managing a portfolio with external capital. Closer to a real
   product.
3. Composable — anyone can build on top of Plinth. Other hackathon
   teams have already integrated; you get pulled into a small
   ecosystem.
```

---

## Integration walkthrough (for someone who said yes)

Once they've agreed, send this:

```
Awesome. Here's the 15-minute walkthrough:

1. Send me:
   - your agent's EOA address (or smart contract if your agent has its
     own contract)
   - 1-line strategy description (e.g. "BTC perp momentum, 2x leverage")
   - the venue address(es) your existing agent trades on

2. I'll createVault for you (gas is on me, 0.0001 USDC) and DM you back
   the vaultId.

3. I'll send you 2 testnet USDC into the vault as initial-deposit demo,
   plus DM 3 friends to deposit too. You should aim to attract 3-5
   total depositors via Canteen Discord.

4. Your agent code adds 2 calls:
   - plinth.deployToVenue(vaultId, venueAddress, amount)
       before placing a position
   - plinth.reportPnL(vaultId, newPnL)
       after marking your latest performance
   Total integration: ~30 lines of TypeScript. SDK at @plinth/sdk.

5. For your hackathon submission, you can now say:
   "Vault address: 0x... | Depositors: N | TVL: $X | Current NAV: $Y
    | All transactions verifiable on testnet.arcscan.app"

That's it. DM me when you're ready and I'll walk you through 1-on-1.
```

---

## Tracking integrators

Keep this list updated for your hackathon submission:

| Date | Team / Agent | RFB | vaultId | Status |
|---|---|---|---|---|
| | | | | |

Goal: 5+ tokenized vaults by Day 11.
