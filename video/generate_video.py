"""
Composes the final Plinth pitch video: TTS narration + slide images.
Same pattern as the previous Ignyte hackathon submission, retuned for Plinth.

Output: D:\\桌面\\arc\\plinth\\video\\demo.mp4
"""

import asyncio
from pathlib import Path

import edge_tts
from moviepy import AudioFileClip, ImageClip, concatenate_videoclips

OUT_DIR = Path(r"D:\桌面\arc\plinth\video")
SLIDE_DIR = OUT_DIR / "slides"
AUDIO_DIR = OUT_DIR / "audio"
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

VOICE = "en-US-AndrewMultilingualNeural"
RATE = "-3%"
VOLUME = "+0%"

# Conversational scripts — em-dashes for natural pauses, contractions,
# pronouncing addresses as digits is awful so we paraphrase.
SCRIPTS = [
    # 01 — title (~7s)
    "So... let me show you Plinth. "
    "A capital layer for AI trading agents on Arc, "
    "submitted to the Agora Agents Hackathon.",

    # 02 — problem (~16s)
    "Here's the problem. AI trading agents have a structural ceiling. "
    "They run on the agent's own balance — maybe a hundred USDC of testnet money. "
    "There's no on-chain primitive to raise capital, manage shares, "
    "or constrain the agent's authority over investor funds. "
    "Result: most agent demos can't scale past their seed budget. "
    "Real capital won't trust them.",

    # 03 — what is plinth (~20s)
    "So... what Plinth is. It's hedge fund infrastructure for AI trading agents on Arc. "
    "Agent creates a vault with an immutable whitelist of approved venues. "
    "Anyone deposits USDC, receives shares at the current NAV. "
    "Agent deploys vault capital — but only to the whitelisted venues. "
    "Agent reports PnL, the share price updates, "
    "investors can redeem at the new NAV at any time. "
    "The key constraint: the agent can never transfer pool funds to addresses outside the approved list.",

    # 04 — mechanism (~22s)
    "Here's how NAV works. Total AUM equals USDC in the vault, plus USDC deployed to venues, plus the agent's reported PnL. "
    "NAV is total AUM divided by outstanding shares. "
    "Walk through an example. "
    "Day one — agent deposits five tenths of a USDC, gets five tenths of a share. NAV starts at one. "
    "Day two — investor deposits zero point oh oh three USDC at NAV one. Investor gets zero point oh oh three shares. "
    "Day three — agent reports plus three tenths of a USDC PnL. NAV jumps to one point three seven five. "
    "Day four — investor redeems half their shares. They get back zero point oh oh two zero six USDC. "
    "All of this actually ran on Arc Testnet earlier today.",

    # 05 — live evidence (~22s)
    "Live on Arc Testnet right now. Plinth contract deployed, four vaults active, "
    "eight lifecycle transactions on chain. "
    "Vault one is the full lifecycle — BTC perp momentum strategy, NAV moved from one to one point three seven five. "
    "Vault two — ETH mean reversion, two depositors, seven thousandths of a USDC of TVL. "
    "Vault three — SOL perp grid bot, deployed two thousandths, agent reported plus one thousandth of a USDC PnL. "
    "Vault four — multi-asset arbitrage, fresh, awaiting depositors. "
    "Plus... two underwriter reviews on chain — auditable risk attestations. "
    "Everything is verifiable on testnet.arcscan.app. "
    "And there's a live web UI at ccheh.github.io slash plinth.",

    # 06 — circle / arc fit (~18s)
    "Why this fits Arc specifically. "
    "USDC as native gas means a single transaction does deposit and redeem. "
    "Sub-cent settlement means small-share economics actually work — "
    "a fifty cent redeem isn't eaten by gas fees. "
    "L1 finality means a deposit at NAV one point five is final — "
    "no chain reorg can rewrite the share count. "
    "And the compliance interfaces Circle is building at L1 — "
    "they're exactly what institutional vault adoption will need next.",

    # 07 — innovation (~22s)
    "What's different about Plinth. "
    "It's a capability constraint, not a custody constraint. The agent never holds the keys — "
    "but does direct the funds. The whitelist is immutable. "
    "There's an Underwriter Agent — an LLM that reads each vault's strategy descriptor "
    "plus on-chain state, outputs a structured risk review, "
    "and commits the review hash on chain. "
    "Sub-cent shares — MIN_DEPOSIT is one ten-thousandth of a USDC. "
    "Retail-sized capital can diversify across AI strategies. "
    "And it composes with the existing agent economy stack — "
    "Mandate, Cadence, Crucible, Helm. Plinth is the capital layer.",

    # 08 — honest limits (~18s)
    "Honest limits. Plinth is version zero — pre-audit, pre-mainnet. "
    "Fifty two forge tests pass and Slither shows no high or medium findings. "
    "But no external review yet. "
    "No production adopters — the bet is that trading agent teams need this primitive. "
    "Agent-reported PnL is trust-based in version zero. "
    "Version zero point two will add stake-slashing for honesty. "
    "And the agent could list themselves as an approved venue — "
    "that's an intentionally Underwriter-detectable failure mode, "
    "flagged off-chain as a critical risk by the LLM reviewer.",

    # 09 — closing (~8s)
    "That's Plinth. Open source, MIT licensed, no admin keys. "
    "Github dot com slash Ccheh slash plinth. "
    "Try it, push back, integrate it. Thanks for watching.",
]


async def synth_one(text, out_path):
    communicate = edge_tts.Communicate(text, VOICE, rate=RATE, volume=VOLUME)
    await communicate.save(str(out_path))


async def synth_all():
    for i, text in enumerate(SCRIPTS, start=1):
        path = AUDIO_DIR / f"narration_{i:02d}.mp3"
        print(f"  [{i}/{len(SCRIPTS)}] {path.name}  ({len(text)} chars)")
        await synth_one(text, path)


print(f"Synthesizing {len(SCRIPTS)} narrations via {VOICE}...")
asyncio.run(synth_all())

print("\nComposing video with audio...")
slide_paths = sorted(SLIDE_DIR.glob("slide_*.png"))
assert len(slide_paths) == len(SCRIPTS), f"slides={len(slide_paths)} scripts={len(SCRIPTS)}"

clips = []
total = 0.0
for i, slide in enumerate(slide_paths, start=1):
    audio_path = AUDIO_DIR / f"narration_{i:02d}.mp3"
    audio_clip = AudioFileClip(str(audio_path))
    dur = audio_clip.duration
    img_clip = ImageClip(str(slide)).with_duration(dur).with_audio(audio_clip)
    clips.append(img_clip)
    print(f"  slide {i}: {dur:.1f}s")
    total += dur

print(f"\nTotal duration: {total:.1f}s = {total/60:.1f}min")

final = concatenate_videoclips(clips, method="compose")
out_path = OUT_DIR / "demo.mp4"
final.write_videofile(
    str(out_path), fps=30, codec="libx264", audio_codec="aac",
    audio_bitrate="128k", preset="medium", threads=4,
)
print(f"\nDone. Wrote {out_path}")
