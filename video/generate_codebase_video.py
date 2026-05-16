"""
Builds the codebase walkthrough video for the Circle Developer Grant submission.

Reuses the same TTS + ffmpeg splice pipeline as generate_video.py but with:
  - Different slide directory: slides_codebase/
  - Different SCRIPTS content tuned to ≤ 5 minutes
  - Different output: demo-codebase.mp4
"""

import asyncio
import subprocess
from pathlib import Path

import edge_tts
import imageio_ffmpeg
from moviepy import AudioFileClip, ImageClip, concatenate_videoclips

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

OUT_DIR = Path(r"D:\桌面\arc\plinth\video")
SLIDE_DIR = OUT_DIR / "slides_codebase"
AUDIO_DIR = OUT_DIR / "audio_codebase"
SENT_DIR  = OUT_DIR / "audio_sent_codebase"
AUDIO_DIR.mkdir(parents=True, exist_ok=True)
SENT_DIR.mkdir(parents=True, exist_ok=True)

VOICE = "en-US-BrianMultilingualNeural"
DEFAULT_RATE = "-2%"

# Scripts now use 3-tuples: (text, rate_override_or_None, pause_ms).
# rate_override examples: "-8%" for slow punchlines, "-10%" for emphatic, "+0%" for normal.
# Pause durations: 200ms in-sentence, 350ms between sentences, 500-700ms between sub-topics.
SCRIPTS = [
    # ─── 01: Title — confident, deliberate opening ───
    [
        ("Plinth.",                                                                                "-12%", 600),
        ("Capital layer for AI trading agents on Arc.",                                            "-4%",  450),
        ("Eleven contracts live. One seventy six tests passing. Four sibling-protocol compositions, all on chain.", "-2%",  500),
        ("This is the codebase walkthrough for the Circle Developer Grant.",                        "-3%",  450),
    ],

    # ─── 02: Overview — set up the two halves ───
    [
        ("Eight stops. We're going to split this into two halves.",                                "-2%",  550),
        ("First, the four locations in the repo that Circle asked about.",                         "-2%",  400),
        ("Plinth V six, with on-chain risk enforcement.",                                          "-3%",  300),
        ("CadencePlinthBridge, cross-protocol fee streaming.",                                     "-3%",  300),
        ("The yield-strategy SDK example, wiring three Circle SDKs end-to-end.",                   "-3%",  300),
        ("And on-chain evidence — the Charlie wallet flow, plus the Aster L one reconciliation.",  "-3%",  550),
        ("Then, four innovations shipped right before this submission.",                           "-2%",  400),
        ("Crucible bridge. Helm bridge. The verifier-core package. And SponsorPool.",              "-5%",  500),
    ],

    # ─── 03: V06 RiskGuard overview — the persona-8 callback ───
    [
        ("v zero point five had four risk signals — but they ran off-chain, as a Python script.",  "-2%",  450),
        ("And a reviewer could rightly ask — what if the author just turns it off?",               "-5%",  550),
        ("So v zero point six lifts all four of them into contract enforcement. No admin key.",    "-3%",  500),
        ("Agent-as-venue, flagged at create.  Concentration cap, enforced at deploy.",             "-3%",  400),
        ("NAV floor auto-close, at PnL reports.  Whale deposit flag, at deposit.",                 "-3%",  500),
    ],

    # ─── 04: Concentration code — code reading rhythm ───
    [
        ("Here's the concentration check, inside deployToVenue.",                                  "-3%",  450),
        ("After every transfer, we recompute that venue's share of total deployed AUM.",           "-2%",  400),
        ("If the ratio would cross eighty percent — the call reverts.",                            "-6%",  500),
        ("MAX_VENUE_CONCENTRATION_BPS is an immutable constant.",                                  "-3%",  400),
        ("There's no admin path to disable it. The test coverage proves it fires.",                "-3%",  450),
    ],

    # ─── 05: NAV floor ───
    [
        ("And here's the NAV floor.",                                                              "-5%",  500),
        ("After reportPnL updates state, we read the new NAV.",                                    "-2%",  350),
        ("If it's fallen below ten percent of inception — the vault auto-closes.",                 "-6%",  500),
        ("Investors keep their redemption rights against whatever's left inVault.",                "-2%",  400),
        ("The agent loses all further deposit and deploy authority on that vault.",                "-3%",  500),
    ],

    # ─── 06: Cadence × Plinth ───
    [
        ("CadencePlinthBridge — this is the second on-chain sibling composition.",                 "-2%",  450),
        ("The first one was MandatePlinthBridge.  Capability-bound credit.",                       "-3%",  400),
        ("This one streams management fees through Cadence's Nanopayments rail.",                  "-2%",  400),
        ("The bridge reads the vault's agent directly from Plinth.",                               "-2%",  300),
        ("So a caller can't spoof who gets credited.",                                             "-5%",  450),
        ("Then it forwards funds via cadence.depositFor — and the agent now has full Cadence access downstream.", "-3%",  500),
    ],

    # ─── 07: Circle SDK ───
    [
        ("This is the real Circle SDK integration. Not placeholders.",                             "-5%",  500),
        ("Three packages — from the at-circle-fin npm scope.",                                     "-3%",  400),
        ("Bridge Kit.  Adapter-viem-v2.  Provider-CCTP-v2.",                                       "-7%",  500),
        ("Wired together to route idle vault USDC from Arc to Base.",                              "-3%",  400),
        ("For USYC exposure, when the production target lands.",                                   "-3%",  400),
        ("Grant milestone two funds the testnet-to-mainnet path.",                                 "-3%",  500),
    ],

    # ─── 08: Charlie evidence ───
    [
        ("Now — on-chain evidence.",                                                               "-7%",  550),
        ("Charlie is a fresh wallet I generated specifically for this test.",                      "-2%",  400),
        ("Funded via Circle's public faucet at faucet dot circle dot com.",                        "-3%",  400),
        ("Then Charlie deposited zero point zero zero zero one USDC into Vault Four.",             "-4%",  450),
        ("Two transactions.  Zero operator-key involvement after generation.",                     "-5%",  450),
        ("The full disclosure lives in docs slash charlie hyphen test dot md.",                    "-3%",  500),
    ],

    # ─── 09: Aster verifiable PnL — the showpiece ───
    [
        ("And here is the killer feature — verifiable PnL.",                                       "-6%",  550),
        ("Vault Five ran three real BTC perp round-trips, on Aster L one mainnet.",                "-3%",  500),
        ("The agent reported minus zero point zero four seven USDC on Arc.",                       "-4%",  400),
        ("Then the Underwriter independently summed Aster's trade history.",                       "-3%",  400),
        ("Net realized — minus zero point zero four seven USDT.",                                  "-5%",  450),
        ("Matched at zero point zero zero percent delta.  Verified, posted on chain.",             "-7%",  550),
    ],

    # ─── 10: Crucible × Plinth — second-half lead-in ───
    [
        ("Alright. That was the codebase tour. Now the four innovations shipped before submission.", "-2%",  600),
        ("Composition number three — Crucible times Plinth.",                                      "-4%",  450),
        ("Enzyme and dHEDGE charge management fees regardless of agent quality.",                  "-2%",  400),
        ("This bridge ties the fee to a Crucible quality market.",                                 "-3%",  400),
        ("If the market resolves with score eight thousand basis points, the agent gets eighty percent.", "-3%",  400),
        ("Remainder refunded. Zero score, equals zero fee.",                                       "-6%",  500),
    ],

    # ─── 11: Helm × Plinth ───
    [
        ("Composition number four — Helm times Plinth.",                                           "-4%",  450),
        ("Same escrow shape, but the gate is a verifiable on-chain milestone.",                    "-2%",  400),
        ("If NAV growth hits the target by deadline, the agent gets the full fee.",                "-3%",  400),
        ("If not — sponsor gets a full refund. Binary, not proportional.",                         "-6%",  500),
    ],

    # ─── 12: verifier-core ───
    [
        ("Public-goods extraction — at plinth slash verifier-core, on npm.",                       "-3%",  500),
        ("Every fund-management protocol that wants verifiable PnL has to reinvent the verifier.", "-2%",  400),
        ("Plinth solved it once. We pulled the interface and reference impls into a standalone package.", "-3%",  500),
        ("AsterVerifier is the file that proved the pattern actually works.",                      "-3%",  400),
        ("Any other protocol can drop this into their Underwriter pipeline, tomorrow.",            "-3%",  500),
    ],

    # ─── 13: SponsorPool — the honest revenue answer ───
    [
        ("And here's the honest revenue answer.",                                                  "-5%",  500),
        ("Plinth itself takes zero protocol fee.",                                                 "-7%",  550),
        ("PlinthSponsorPool is a per-vault pool — investors deposit, underwriters claim a fixed reward per review.", "-2%",  450),
        ("Per-address dedup prevents Sybil drain, even across refills.",                           "-3%",  400),
        ("Pure investor-to-underwriter market. Plinth itself, doesn't extract.",                   "-5%",  550),
    ],

    # ─── 14: Outro ───
    [
        ("Fifty thousand USDC, across five milestones.",                                           "-4%",  500),
        ("M one — external audit.  M two — USYC via CCTP.  M three — Gateway integration.",        "-3%",  450),
        ("M four — mainnet, plus first five thousand real TVL.",                                   "-3%",  400),
        ("M five — verifier-core npm publish, five venue adapters, plus SponsorPool TVL milestone.", "-3%",  500),
        ("github dot com slash Ccheh slash plinth. MIT. Audit-grade.",                             "-3%",  500),
        ("Eleven contracts. One seventy six tests. Four compositions. Thanks for the consideration.", "-5%",  500),
    ],
]


async def synth_sentence(text: str, out_path: Path, rate: str = None):
    actual_rate = rate or DEFAULT_RATE
    last_err = None
    for attempt in range(1, 8):
        try:
            c = edge_tts.Communicate(text, VOICE, rate=actual_rate)
            await asyncio.wait_for(c.save(str(out_path)), timeout=20.0)
            return
        except Exception as e:
            last_err = e
            print(f"    edge-tts attempt {attempt}/7 failed: {type(e).__name__}; retrying in {attempt}s...", flush=True)
            try:
                out_path.unlink(missing_ok=True)  # remove partial file
            except Exception:
                pass
            await asyncio.sleep(attempt)
    raise last_err


async def synth_all_sentences():
    total = sum(len(slide) for slide in SCRIPTS)
    counter = 0
    for slide_idx, slide in enumerate(SCRIPTS, start=1):
        for sent_idx, (text, rate, _) in enumerate(slide, start=1):
            counter += 1
            path = SENT_DIR / f"slide{slide_idx:02d}_sent{sent_idx:02d}.mp3"
            if path.exists() and path.stat().st_size > 1000:
                print(f"  [{counter}/{total}] cached slide {slide_idx} sent {sent_idx}")
                continue
            await synth_sentence(text, path, rate=rate)
            print(f"  [{counter}/{total}] slide {slide_idx} sent {sent_idx} (rate={rate}): {text[:50]}", flush=True)


def build_slide_audio_ffmpeg(slide_idx: int) -> Path:
    slide = SCRIPTS[slide_idx - 1]
    silence_dir = AUDIO_DIR / "silence"
    silence_dir.mkdir(exist_ok=True)
    inputs = []
    filter_parts = []
    n_inputs = 0
    for sent_idx, (_, _, pause_ms) in enumerate(slide, start=1):
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
out_path = OUT_DIR / "demo-codebase.mp4"
final.write_videofile(
    str(out_path), fps=30, codec="libx264", audio_codec="aac",
    audio_bitrate="128k", preset="medium", threads=4,
)
print(f"\nDone. Wrote {out_path}")
