# 你今晚需要做的 (10 分钟)

视频 + 代码 + 部署 + 文档 + Aster L1 真实交易 + Risk Monitor 全部我已经搞定。**剩下需要你身份的事**:

## 1. 加 Canteen Discord (3 分钟)

打开: https://discord.gg/TGnyfKh23V
进入需要的 passphrase: `SITEx1313` (Luma 给的)

## 2. 同时加 Arc Builder Discord

打开: https://discord.com/invite/buildonarc
随便进 `#general`,说一句 "Joining for Canteen + Agora hackathon" 让他们识别。

## 3. Canteen Discord 找到合适频道,发这条 (5 分钟)

频道优先级: `#showcase` > `#showcase-projects` > `#general`

```
Hey builders 👋 shipping something that might be the missing piece for the trading-agent RFBs.

I just published **Plinth** — open-source capital layer for AI trading agents on Arc. TL;DR: your agent gets a tokenized vault, anyone deposits USDC at NAV, you deploy capital only to a pre-declared whitelist of venues, you report PnL → NAV updates, investors redeem at NAV.

**The trick**: when your strategy executes on a public-chain venue (Aster L1, future Arc-native perps), Plinth's Underwriter Agent **cryptographically reconciles your reported PnL against the venue's trade history**. No "trust me" required.

**Live demo on Arc Testnet** — Vault #5 ran end-to-end yesterday:
- Agent opened 0.001 BTC long on Aster L1
- Closed 3 min later, realized −0.047 USDT (fees > gains, real trading reality)
- Agent reported same value on Plinth/Arc
- Underwriter auto-verified to 0.00% delta — review hash on chain

Total experimental cost: $0.05 USDT.

**Why I'm sharing in Canteen**: if you're building for RFB 1/2/4/5/6, traction usually bottlenecks at "I'm running on my own testnet USDC, the demo looks small". With Plinth you can put your agent in a vault, have 3-5 friends deposit USDC, run real strategy, **and the Underwriter cross-checks you** — TVL + verified PnL + concrete on-chain story for your submission.

I'm offering to **wire any RFB team into Plinth for free in ~15 min**:
- you give me your agent wallet + 1-line strategy + venue address
- I create the vault + deposit-flow + Underwriter integration

Stack:
- Repo (MIT): https://github.com/Ccheh/plinth
- Live vault browser: https://ccheh.github.io/plinth/
- SDK `@plinth/sdk`: TypeScript, 52 forge + 29 vitest tests
- Contracts: `0xc2994ce3df612ebd2f898244a992a0bbfef86627` on Arc Testnet
- 6 vaults live, 6 underwriter reviews (4 verified-PnL, 2 risk-alert)

DM me or react 👀 if you want to integrate.
```

## 4. (可选) Twitter 同步一份 (2 分钟)

```
Shipped Plinth for the @Agora Agents Hackathon ⚓ — capital layer for AI trading agents on @circle's Arc.

Vault #5 went live yesterday with the first cryptographically verifiable PnL claim I'm aware of:

→ agent opens 0.001 BTC perp on Aster L1
→ realized −$0.05 (fees ate it, real trading)
→ agent reports same value on Arc/Plinth
→ Underwriter recomputes from Aster L1 trade history → matches to 0.00% delta
→ VERIFIED review hash posted on chain

The "agent self-reports PnL → trust required" problem is solved when the venue is also a public chain. Works for Aster L1 today; works for any future Arc-native perp DEX.

6 vaults live, MIT, full lifecycle on chain 👇
https://github.com/Ccheh/plinth
```

## 5. 然后等回复

回复来了 (Discord 提示 / Twitter mention),**截图发给我**,我帮你回每一条。

不要承诺做不到的事 — 我们的 offer 范围: 帮 createVault + 集成 SDK + Underwriter 接入 + Canteen Discord 帮你拉 3-5 个 deposit。

---

## 提交时 (Day 12) 你要做的

我会准备好提交模板。但**提交按钮你按**。在 Canteen 平台或者他们的 submission portal 上。

提交需要的:
- ✅ GitHub: https://github.com/Ccheh/plinth (已 push)
- ✅ Demo: https://ccheh.github.io/plinth/ (Pages 上线)
- ✅ Video: `D:\桌面\arc\plinth\video\demo.mp4`
- ⏳ Video 更新: 加 30 秒 Aster L1 真实成交 + Risk Monitor 输出画面 (Phase 9,需要你帮录屏)
- ✅ Founder pitch: 视频内已包含
- ✅ Traction numbers:
  - 6 vaults on chain
  - 1 vault with real third-party-venue trade (Aster L1)
  - 6 underwriter reviews on chain (4 verifiable-PnL, 2 risk-alert)
  - 3 round-trip BTC perps executed end-to-end with $0.13 USDT experimental cost

---

**就这些。** 其他全 by me。
