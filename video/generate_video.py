"""
Composes the Plinth pitch video (v2, post-audit edition).

  - Voice: en-US-BrianMultilingualNeural (more conversational than Andrew)
  - Pacing: -6% rate, inline <break time="..."/> SSML for natural pauses
  - 10 slides matching the v2 generate_slides.py output

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

# en-US-BrianMultilingualNeural reads as a relaxed mid-tone male voice — more
# natural for spoken-word pitches than the precise Andrew voice we used in v1.
# Slowed slightly to give the inline <break> tags room to breathe.
VOICE = "en-US-BrianMultilingualNeural"
RATE = "-6%"
VOLUME = "+0%"

# Edge-TTS doesn't honor inline <break> SSML tags — it reads them as text.
# So we use natural punctuation for pauses:
#   ...      → ~600ms pause, audible "trailing off" effect
#   —        → ~400ms emphatic pause
#   ,        → ~150ms breath pause
#   .        → ~350ms sentence boundary
#
# Scripts are also kept short — target ~25-30 seconds per slide, ~3.5 min total.
# Conversational voice (contractions, "Here's the thing", asides) → more natural
# than dense formal prose.

SCRIPTS = [
    # 01 — title (~7s, ~17w)
    "Plinth. A capital layer for AI trading agents on Arc. "
    "Built for the Agora Agents Hackathon.",

    # 02 — problem (~18s, ~45w)
    "AI trading agents have a trust problem. "
    "They run on their own balance. "
    "Taking outside money needs fund wrappers, custody, "
    "and a way for investors to verify reported returns. "
    "The standard answer: there isn't one. "
    "Agents claim a number — investors believe it.",

    # 03 — what is plinth (~22s, ~55w)
    "Plinth solves it on chain. "
    "The agent creates a vault with an immutable list of approved venues. "
    "Anyone deposits USDC, gets shares at NAV, redeems on demand. "
    "The agent directs funds — but can never withdraw to a new address. "
    "And anyone can be an underwriter: "
    "post a signed review on chain. Multiple per vault, by design.",

    # 04 — NAV (~22s, ~55w)
    "NAV is simple. Total assets divided by total shares. "
    "Total assets equals USDC in the vault, plus USDC at venues, plus reported PnL. "
    "Concretely — from a real run today: "
    "agent deposits one millicent. Investor deposits ten times that. "
    "Agent reports a real Aster L1 trade. "
    "NAV updates. Investor redeems on chain. All verifiable.",

    # 05 — verifiable PnL (~26s, ~70w) — the killer feature
    "Here's what's different. "
    "When the venue is also a public chain — agents can't lie about PnL. "
    "On Arc: claim minus zero point oh four seven USDC. "
    "On Aster L1: a real BTC perp. "
    "Open at eighty thousand five hundred. Close three minutes later at eighty thousand five seventeen. "
    "After fees — net minus zero point oh four seven USDT. "
    "The underwriter pulls Aster's trade history, reconciles, "
    "delta zero point zero zero percent. Verified on chain. "
    "By code, not by trust.",

    # 06 — multi underwriter (~20s, ~50w)
    "Same vault, four reviews, two signing addresses. "
    "The Aster Verifier says verified. Agent is honest. "
    "The Risk Monitor says critical. Position is underwater. "
    "An LLM rates the strategy. A fourth reviewer — separate address — adds a human note. "
    "Investors pick whose lens to weight. "
    "Honest reporting plus real risk is exactly when investors need a warning.",

    # 07 — security audit + v0.5 (~24s, ~60w)
    "Security mattered. Pre-deployment self-audit found eleven findings. "
    "The critical one — a sandwich attack on reportPnL. "
    "Attacker front-runs a deposit at old NAV, redeems at new — drains other shareholders. "
    "For every critical and high, we wrote an exploit POC, proved it works on v zero, "
    "then deployed v zero point five with the fix. "
    "Ninety forge tests pass. The defense is live on chain.",

    # 08 — live evidence (~18s, ~45w)
    "What's live. Six vaults on chain. "
    "Seven underwriter reviews. "
    "Three real BTC perps on Aster L1 mainnet. "
    "Total experimental cost: thirteen cents. "
    "For thirteen cents — a complete proof on the explorer. "
    "And an interactive demo at verify dot html — reconciliation runs in your browser.",

    # 09 — Arc fit + Aster framing (~22s, ~55w)
    "Why Arc. USDC is native gas. "
    "Sub-cent settlement makes small shares viable. "
    "L1 finality. USYC and CCTP on the roadmap. "
    "About Aster: we picked it as the v zero demo target "
    "because its chain is public — exactly what the Verifier needs. "
    "The pattern works for any public-chain perp, "
    "including future Arc-native ones. Aster is the demo target. Plinth is the product.",

    # 10 — closing (~9s, ~25w)
    "That's Plinth. Open source. MIT. No admin keys. Pre-deployment audit complete. "
    "Fifteen-minute integration guide for agent teams. "
    "Github dot com slash Ccheh slash plinth. Thanks for watching.",
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
