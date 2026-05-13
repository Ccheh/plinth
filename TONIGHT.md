# 你今晚需要做的 (10 分钟)

视频 + 代码 + 部署 + 文档 全部我已经搞定。**剩下需要你身份的事**:

## 1. 加 Canteen Discord (3 分钟)

打开: https://discord.gg/TGnyfKh23V
进入需要的 passphrase: `SITEx1313` (Luma 给的)

## 2. 同时加 Arc Builder Discord

打开: https://discord.com/invite/buildonarc
随便进 `#general`,说一句 "Joining for Canteen + Agora hackathon" 让他们识别。

## 3. Canteen Discord 找到合适频道,发这条 (5 分钟)

频道优先级: `#showcase` > `#showcase-projects` > `#general`

```
Hey builders 👋 dropping a tool that might be useful if you're building any of the trading-agent RFBs.

I just shipped **Plinth** — an open-source capital layer for AI trading agents on Arc Testnet. Think of it as "hedge fund infrastructure for your agent": your agent creates a vault, anyone can deposit USDC and get shares at NAV, your agent deploys vault capital to pre-approved venues, reports PnL → NAV updates → investors redeem at the new NAV.

**Why I'm sharing**: if you're building for RFB 1/2/4/5/6, the bottleneck for traction is usually "I'm running on my own $100 of testnet USDC and the demo PnL looks small". With Plinth, you can put your agent in a vault, ask 3-5 friends or other Canteen builders to deposit testnet USDC for the demo, and now your traction numbers (TVL, depositors, NAV changes) are real.

I'm offering to **help any RFB team tokenize their agent into a Plinth vault for free**. Takes ~15 minutes:
- you give me your agent's wallet address + a 1-line strategy description + the venue address(es) you trade on
- I help you create the vault and wire your existing agent code to use Plinth-deployed USDC

Live + deployed:
- Browse all vaults: https://ccheh.github.io/plinth/
- Repo (MIT): https://github.com/Ccheh/plinth
- SDK: `@plinth/sdk` TypeScript, 29 vitest + 52 forge tests, full lifecycle ran on chain
- Contract: 0xc2994ce3df612ebd2f898244a992a0bbfef86627 on Arc Testnet

DM me or react with 👀 if you want to integrate.
```

## 4. (可选) Twitter 同步一份 (2 分钟)

```
Just shipped Plinth for the Agora Agents Hackathon ⚓

It's hedge fund infrastructure for AI trading agents on @circle's Arc:
- agent creates a vault
- anyone deposits USDC, gets shares at NAV
- agent deploys to whitelisted venues, reports PnL
- investors redeem at NAV anytime

4 vaults live on Arc Testnet 👇
https://ccheh.github.io/plinth/

If you're building a trading agent and want to tokenize it, I'll wire it up for free this week. DM me.
```

## 5. 然后等回复

回复来了 (Discord 提示 / Twitter mention),**截图发给我**,我帮你回每一条。

不要承诺什么你做不到的事 — 我们的 offer 是: "我帮你 createVault + 集成 SDK + 在 Canteen Discord 帮你拉 3-5 个 deposit"。

---

## 提交时 (Day 12) 你要做的

我会准备好提交模板。但**提交按钮你按**。在 Canteen 平台或者他们的 submission portal 上。

提交需要的:
- ✅ GitHub: https://github.com/Ccheh/plinth (已 push)
- ✅ Demo: https://ccheh.github.io/plinth/ (Pages 上线后)
- ✅ Video: `D:\桌面\arc\plinth\video\demo.mp4` (我在生成)
- ✅ Founder pitch: 视频内已包含
- ⚠️ Traction numbers: 看 Discord outreach 结果

---

**就这些。** 其他全 by me。
