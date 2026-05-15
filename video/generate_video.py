"""
Composes the Plinth pitch video (v4 — natural-pacing edition).

Key change vs v3: each script slide is split into individual sentences, each
sentence is synthesized separately, then concatenated with controlled-duration
silence between them. This gives the audio a more human cadence than a single
TTS call per slide.

Per-sentence pause durations:
  short (~250ms): comma-level breath between closely-related clauses
  mid   (~450ms): standard sentence boundary
  long  (~700ms): paragraph break / dramatic emphasis
  beat  (~900ms): slide transition / setup-payoff

Voice: en-US-AndrewMultilingualNeural — multilingual voice with good prosody
for English narration. Slowed -4% for clarity without sounding mechanical.

Output: D:\\桌面\\arc\\plinth\\video\\demo.mp4 (target ~3 min)
"""

import asyncio
import subprocess
from pathlib import Path

import edge_tts
import imageio_ffmpeg
from moviepy import AudioFileClip, ImageClip, concatenate_videoclips

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

OUT_DIR = Path(r"D:\桌面\arc\plinth\video")
SLIDE_DIR = OUT_DIR / "slides"
AUDIO_DIR = OUT_DIR / "audio"
SENT_DIR  = OUT_DIR / "audio_sent"
AUDIO_DIR.mkdir(parents=True, exist_ok=True)
SENT_DIR.mkdir(parents=True, exist_ok=True)

VOICE = "en-US-AndrewMultilingualNeural"
RATE  = "-4%"

# Each slide is a list of (sentence, pause_after_ms) tuples. Tightened to fit
# 3-minute target. Average pause ~250ms, with longer beats only at key moments.
SCRIPTS = [
    # ─── 01: Title (~7s) ───
    [
        ("Plinth.",                                                        500),
        ("The capital layer for AI trading agents on Arc.",                 400),
    ],

    # ─── 02: Problem (~14s) ───
    [
        ("AI trading agents have a trust problem.",                         300),
        ("Taking outside money needs a fund wrapper, custody, and investors willing to take 'trust my returns' on faith.",  400),
        ("When the agent reports PnL, how does anyone verify it?  Normally, you can't.",  500),
    ],

    # ─── 03: What Plinth is (~18s) ───
    [
        ("Plinth solves this on chain.",                                    300),
        ("The agent creates a vault with an immutable list of approved venues.",  300),
        ("Anyone deposits USDC, gets shares at NAV, redeems on demand.",    300),
        ("The agent directs capital, but can never withdraw to a new address.",  300),
        ("And three independent underwriters post reviews on chain.",       400),
    ],

    # ─── 04: NAV math (very brief, ~6s) ───
    [
        ("NAV is simple — total assets divided by total shares.",           300),
        ("Investors can always redeem at the current price.",               400),
    ],

    # ─── 05: Verifiable PnL — killer feature (~26s) ───
    [
        ("Here's what's different.",                                        300),
        ("When the trading venue is also a public chain, the agent can't lie about PnL.",  400),
        ("On Aster L1, the agent reports minus zero point oh four seven USDC.",  300),
        ("The underwriter recomputes from on-chain trades and matches to zero point zero zero percent.",  400),
        ("Verified by code, not by trust.",                                 400),
    ],

    # ─── 06: Multi-underwriter + Composition (~20s) ───
    [
        ("Same vault. Four reviews. Two signing addresses.",                300),
        ("Verifier says verified. Risk Monitor says critical. LLM rates medium risk.",  300),
        ("A human reviewer adds a qualitative note.",                       350),
        ("And the first on-chain sibling-protocol composition — Mandate authorizes Plinth deposits with cryptographic capability constraints.",  400),
    ],

    # ─── 07: Security + Yield (~22s) ───
    [
        ("Pre-deployment audit found eleven issues — one critical sandwich attack on reportPnL.",  300),
        ("We wrote exploit POCs and deployed v0.5 with fixes. Ninety-eight forge tests pass.",  400),
        ("Plus a yield strategy — idle USDC sweeps at five percent APR.",   350),
        ("Production path uses Circle's USYC on Base via CCTP.",            400),
    ],

    # ─── 08: Live evidence (very brief, ~10s) ───
    [
        ("On chain right now — seven vaults, three real BTC perps on Aster mainnet, one cross-protocol compose.",  350),
        ("Total experimental cost: thirteen cents.",                        500),
    ],

    # ─── 09: Arc fit + Aster framing (~14s) ───
    [
        ("Why Arc. USDC as native gas, sub-cent settlement, L1 finality.",  300),
        ("Real Circle Bridge Kit SDK is integrated.",                       400),
        ("Aster is the demo. Plinth is the product.",                       400),
    ],

    # ─── 10: Closing (~9s) ───
    [
        ("That's Plinth.",                                                  300),
        ("Open source, MIT, no admin keys.  Pre-deployment audit complete.",  300),
        ("Github dot com slash Ccheh slash plinth.",                        300),
        ("Thanks for watching.",                                            200),
    ],
]


async def synth_sentence(text: str, out_path: Path):
    c = edge_tts.Communicate(text, VOICE, rate=RATE)
    await c.save(str(out_path))


async def synth_all_sentences():
    """Generate one mp3 per sentence. Synthesizes in series to avoid edge-tts
    rate limiting that surfaced during parallel attempts."""
    total = sum(len(slide) for slide in SCRIPTS)
    counter = 0
    for slide_idx, slide in enumerate(SCRIPTS, start=1):
        for sent_idx, (text, _) in enumerate(slide, start=1):
            counter += 1
            path = SENT_DIR / f"slide{slide_idx:02d}_sent{sent_idx:02d}.mp3"
            # Skip if already generated (lets us resume after failures)
            if path.exists() and path.stat().st_size > 1000:
                print(f"  [{counter}/{total}] cached slide {slide_idx} sent {sent_idx}")
                continue
            await synth_sentence(text, path)
            print(f"  [{counter}/{total}] slide {slide_idx} sent {sent_idx}: {text[:50]}", flush=True)


def build_slide_audio_ffmpeg(slide_idx: int) -> Path:
    """Concatenate sentence audios for a slide using ffmpeg's concat filter,
    inserting `pause_after_ms` silence between sentences. Uses the bundled
    imageio_ffmpeg binary (no system ffmpeg or ffprobe required)."""
    slide = SCRIPTS[slide_idx - 1]
    silence_dir = AUDIO_DIR / "silence"
    silence_dir.mkdir(exist_ok=True)

    # Build the ffmpeg input list: alternating sentence + silence files
    inputs = []
    filter_parts = []
    n_inputs = 0
    for sent_idx, (_, pause_ms) in enumerate(slide, start=1):
        sent_path = SENT_DIR / f"slide{slide_idx:02d}_sent{sent_idx:02d}.mp3"
        inputs += ["-i", str(sent_path)]
        filter_parts.append(f"[{n_inputs}:a]")
        n_inputs += 1
        if pause_ms > 0:
            # Pre-generate silence file if absent
            sil_path = silence_dir / f"silence_{pause_ms}ms.mp3"
            if not sil_path.exists():
                subprocess.run(
                    [FFMPEG, "-y", "-f", "lavfi", "-i",
                     f"anullsrc=channel_layout=mono:sample_rate=44100",
                     "-t", f"{pause_ms/1000:.3f}", "-q:a", "9",
                     str(sil_path)],
                    capture_output=True, check=True,
                )
            inputs += ["-i", str(sil_path)]
            filter_parts.append(f"[{n_inputs}:a]")
            n_inputs += 1

    concat_filter = "".join(filter_parts) + f"concat=n={n_inputs}:v=0:a=1[out]"
    out_path = AUDIO_DIR / f"narration_{slide_idx:02d}.mp3"
    subprocess.run(
        [FFMPEG, "-y", *inputs, "-filter_complex", concat_filter,
         "-map", "[out]", "-b:a", "128k", str(out_path)],
        capture_output=True, check=True,
    )
    return out_path


print(f"Synthesizing per-sentence audio via {VOICE}...")
asyncio.run(synth_all_sentences())

print("\nBuilding slide audio (pydub splice with controlled silence)...")
slide_paths = sorted(SLIDE_DIR.glob("slide_*.png"))
assert len(slide_paths) == len(SCRIPTS), f"slides={len(slide_paths)} scripts={len(SCRIPTS)}"

clips = []
total_duration = 0.0
for i, slide_png in enumerate(slide_paths, start=1):
    slide_audio_path = build_slide_audio_ffmpeg(i)
    loaded = AudioFileClip(str(slide_audio_path))
    dur = loaded.duration
    img = ImageClip(str(slide_png)).with_duration(dur).with_audio(loaded)
    clips.append(img)
    total_duration += dur
    print(f"  slide {i}: {dur:.1f}s")

print(f"\nTotal video duration: {total_duration:.1f}s = {total_duration/60:.2f} min")

print("Composing video...")
final = concatenate_videoclips(clips, method="compose")
out_path = OUT_DIR / "demo.mp4"
final.write_videofile(
    str(out_path), fps=30, codec="libx264", audio_codec="aac",
    audio_bitrate="128k", preset="medium", threads=4,
)
print(f"\nDone. Wrote {out_path}")
