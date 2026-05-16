"""
Builds the addendum walkthrough video — covers the 4 innovations shipped AFTER
demo-codebase.mp4 was rendered. Same TTS + ffmpeg pipeline as the codebase video.

Output: D:\桌面\arc\plinth\video\demo-addendum.mp4
Target duration: 80–100 seconds.
"""

import asyncio
import subprocess
from pathlib import Path

import edge_tts
import imageio_ffmpeg
from moviepy import AudioFileClip, ImageClip, concatenate_videoclips

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

OUT_DIR = Path(r"D:\桌面\arc\plinth\video")
SLIDE_DIR = OUT_DIR / "slides_addendum"
AUDIO_DIR = OUT_DIR / "audio_addendum"
SENT_DIR  = OUT_DIR / "audio_sent_addendum"
AUDIO_DIR.mkdir(parents=True, exist_ok=True)
SENT_DIR.mkdir(parents=True, exist_ok=True)

VOICE = "en-US-AndrewMultilingualNeural"
RATE  = "-4%"

SCRIPTS = [
    # ─── 01: Title (~14s) ───
    [
        ("Plinth — Innovation Sprint Addendum.",                                       300),
        ("Four new deliverables shipped between the main walkthrough and submission.", 300),
        ("Each addresses a question Grant evaluators reliably ask.",                   400),
    ],

    # ─── 02: Crucible × Plinth (~22s) ───
    [
        ("Composition number three — Crucible times Plinth.",                          300),
        ("Enzyme and dHEDGE charge management fees regardless of agent quality.",      300),
        ("This bridge ties the fee to a Crucible quality market.",                     300),
        ("If the market resolves with score eight thousand basis points, agent gets eighty percent.", 400),
        ("Remainder refunded. Zero score equals zero fee.",                            400),
    ],

    # ─── 03: Helm × Plinth (~20s) ───
    [
        ("Composition number four — Helm times Plinth.",                               300),
        ("Same escrow shape, but the gate is a verifiable on-chain milestone.",        300),
        ("If NAV growth hits the target by deadline, agent gets the full fee.",        300),
        ("If not, sponsor gets a full refund. Binary, not proportional.",              400),
    ],

    # ─── 04: verifier-core (~22s) ───
    [
        ("Public-goods extraction — at-plinth slash verifier-core on npm.",            300),
        ("Every fund-management protocol that wants verifiable PnL reinvents the verifier.", 300),
        ("Plinth solved it once. We pulled the interface and reference impls into a standalone package.", 400),
        ("AsterVerifier is the file that proved the pattern works.",                   300),
        ("Any other protocol can drop this into their Underwriter pipeline tomorrow.", 400),
    ],

    # ─── 05: SponsorPool + close (~24s) ───
    [
        ("And the honest revenue answer.",                                             300),
        ("Plinth itself takes zero protocol fee.",                                     400),
        ("PlinthSponsorPool is a per-vault pool — investors deposit, underwriters claim a fixed reward per review.", 400),
        ("Per-address dedup prevents Sybil drain across refills.",                     300),
        ("Pure investor-to-underwriter market. Plinth doesn't extract.",               300),
        ("github dot com slash Ccheh slash plinth. Thanks.",                           300),
    ],
]


async def synth_sentence(text: str, out_path: Path):
    c = edge_tts.Communicate(text, VOICE, rate=RATE)
    await c.save(str(out_path))


async def synth_all_sentences():
    total = sum(len(slide) for slide in SCRIPTS)
    counter = 0
    for slide_idx, slide in enumerate(SCRIPTS, start=1):
        for sent_idx, (text, _) in enumerate(slide, start=1):
            counter += 1
            path = SENT_DIR / f"slide{slide_idx:02d}_sent{sent_idx:02d}.mp3"
            if path.exists() and path.stat().st_size > 1000:
                print(f"  [{counter}/{total}] cached slide {slide_idx} sent {sent_idx}")
                continue
            await synth_sentence(text, path)
            print(f"  [{counter}/{total}] slide {slide_idx} sent {sent_idx}: {text[:50]}", flush=True)


def build_slide_audio_ffmpeg(slide_idx: int) -> Path:
    slide = SCRIPTS[slide_idx - 1]
    silence_dir = AUDIO_DIR / "silence"
    silence_dir.mkdir(exist_ok=True)
    inputs = []
    filter_parts = []
    n_inputs = 0
    for sent_idx, (_, pause_ms) in enumerate(slide, start=1):
        sent_path = SENT_DIR / f"slide{slide_idx:02d}_sent{sent_idx:02d}.mp3"
        inputs += ["-i", str(sent_path)]
        filter_parts.append(f"[{n_inputs}:a]")
        n_inputs += 1
        if pause_ms > 0:
            sil_path = silence_dir / f"silence_{pause_ms}ms.mp3"
            if not sil_path.exists():
                subprocess.run(
                    [FFMPEG, "-y", "-f", "lavfi", "-i",
                     "anullsrc=channel_layout=mono:sample_rate=44100",
                     "-t", f"{pause_ms/1000:.3f}", "-q:a", "9", str(sil_path)],
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

print("\nBuilding slide audio...")
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
out_path = OUT_DIR / "demo-addendum.mp4"
final.write_videofile(
    str(out_path), fps=30, codec="libx264", audio_codec="aac",
    audio_bitrate="128k", preset="medium", threads=4,
)
print(f"\nDone. Wrote {out_path}")
