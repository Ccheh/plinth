"""
Plinth — slide-based pitch video generator.
Reuses the pattern from arc/hackathon-submission/generate_video.py but tuned
for the Agora Agents Hackathon submission.

Output: D:\\桌面\\arc\\plinth\\video\\slides\\slide_NN.png  (1920x1080)
        D:\\桌面\\arc\\plinth\\video\\audio\\narration_NN.mp3
        D:\\桌面\\arc\\plinth\\video\\demo.mp4 (final, ~3 min)

Run:
    python video/generate_slides.py    # makes slides
    python video/generate_video.py     # composes voiced video
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path(r"D:\桌面\arc\plinth\video")
SLIDE_DIR = OUT_DIR / "slides"
SLIDE_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080
BG = (15, 18, 33)             # dark navy
TEXT = (235, 235, 240)
SUBTLE = (160, 165, 180)
ACCENT = (255, 200, 80)       # gold
HIGHLIGHT = (110, 200, 255)
DIM = (90, 96, 115)
GREEN = (110, 220, 150)
RED = (235, 110, 110)


def get_fonts():
    base = r"C:\Windows\Fonts"
    cands = {
        "title": ["calibrib.ttf", "arialbd.ttf", "segoeuib.ttf"],
        "body":  ["calibri.ttf",  "arial.ttf",   "segoeui.ttf"],
        "mono":  ["consola.ttf",  "cour.ttf"],
    }
    chosen = {}
    for key, files in cands.items():
        for f in files:
            p = os.path.join(base, f)
            if os.path.exists(p):
                chosen[key] = p; break
        else:
            chosen[key] = None
    return chosen


FONTS = get_fonts()


def font(kind, size):
    p = FONTS.get(kind)
    if p:
        return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def new_slide():
    img = Image.new("RGB", (W, H), BG)
    return img, ImageDraw.Draw(img)


def draw_brand(d):
    f = font("body", 22)
    d.text((60, H - 55), "Plinth — Capital Layer for AI Trading Agents on Arc",
           font=f, fill=SUBTLE)


def wrap(text, max_chars):
    out = []
    line = ""
    for word in text.split():
        if len(line) + len(word) + 1 <= max_chars:
            line = (line + " " + word).strip()
        else:
            out.append(line); line = word
    if line:
        out.append(line)
    return out


# ============================================================
# slides
# ============================================================

def slide_01_title():
    img, d = new_slide()
    d.text((W / 2, 240), "AGORA AGENTS HACKATHON",
           font=font("body", 28), fill=ACCENT, anchor="mm")
    d.text((W / 2, 285), "Canteen × Circle on Arc",
           font=font("body", 22), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 460), "Plinth",
           font=font("title", 144), fill=TEXT, anchor="mm")
    d.text((W / 2, 590), "Capital layer for AI trading agents on Arc",
           font=font("title", 48), fill=HIGHLIGHT, anchor="mm")
    d.text((W / 2, 750), "Zen Chen   ·   github.com/Ccheh",
           font=font("body", 30), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 800), "4 vaults live on Arc Testnet  ·  52 forge + 29 SDK tests  ·  MIT-licensed",
           font=font("body", 24), fill=DIM, anchor="mm")
    draw_brand(d)
    return img, 7.0


def slide_02_problem():
    img, d = new_slide()
    d.text((100, 100), "The problem", font=font("title", 64), fill=TEXT)
    d.line([(100, 195), (430, 195)], fill=ACCENT, width=4)
    body = [
        ("AI trading agents have a structural ceiling.", TEXT, 42),
        ("", None, 24),
        ("They run on the agent's own balance.", SUBTLE, 36),
        ("Demo PnL on $100 of testnet USDC isn't a fund.", SUBTLE, 36),
        ("There is no on-chain primitive to raise capital,", SUBTLE, 36),
        ("manage shares, or constrain the agent's authority", SUBTLE, 36),
        ("over investor funds.", SUBTLE, 36),
        ("", None, 24),
        ("Result: most agent demos can't scale past their", TEXT, 38),
        ("seed budget. Real capital won't trust them.", TEXT, 38),
    ]
    y = 280
    for line, color, sz in body:
        if line == "":
            y += sz; continue
        d.text((100, y), line, font=font("body", sz), fill=color); y += sz + 12
    draw_brand(d)
    return img, 16.0


def slide_03_what_is_plinth():
    img, d = new_slide()
    d.text((100, 100), "What Plinth is", font=font("title", 64), fill=TEXT)
    d.line([(100, 195), (440, 195)], fill=ACCENT, width=4)
    d.text((100, 240), "Hedge fund infrastructure for AI trading agents on Arc:",
           font=font("body", 32), fill=HIGHLIGHT)
    bullets = [
        "1.  Agent creates a vault with an immutable list of approved venues.",
        "2.  Anyone deposits USDC, receives shares at current NAV.",
        "3.  Agent deploys vault capital — only to whitelisted venues.",
        "4.  Agent reports PnL → NAV updates → share price moves.",
        "5.  Investors redeem at the current NAV at any time.",
    ]
    y = 330
    for b in bullets:
        d.text((100, y), b, font=font("body", 32), fill=TEXT); y += 60
    d.rounded_rectangle([(100, 770), (W - 100, 880)], radius=12,
                        outline=ACCENT, width=3, fill=(22, 26, 44))
    d.text((W / 2, 800), "Hard constraint:",
           font=font("body", 26), fill=ACCENT, anchor="mm")
    d.text((W / 2, 845), "Agent can NEVER transfer pool funds to addresses outside approvedVenues.",
           font=font("body", 28), fill=TEXT, anchor="mm")
    draw_brand(d)
    return img, 20.0


def slide_04_mechanism():
    img, d = new_slide()
    d.text((100, 100), "How NAV works", font=font("title", 60), fill=TEXT)
    d.line([(100, 185), (440, 185)], fill=ACCENT, width=4)
    d.text((100, 235), "totalAUM = inVault + deployedAUM + reportedPnL",
           font=font("mono", 30), fill=HIGHLIGHT)
    d.text((100, 280), "NAV       = (totalAUM × 1e18) / totalShares",
           font=font("mono", 30), fill=HIGHLIGHT)
    d.text((100, 360), "Example:", font=font("body", 32), fill=ACCENT)
    rows = [
        ("Day 1:  agent deposits 0.005 USDC, gets 0.005 shares",
         "NAV = 1.0 USDC/share (inception)"),
        ("Day 2:  investor deposits 0.003 USDC",
         "NAV still 1.0, investor gets 0.003 shares"),
        ("Day 3:  agent deploys to venue, reports +0.003 PnL",
         "NAV jumps to 1.375  →  investor's share now worth $0.41"),
        ("Day 4:  investor redeems half (0.0015 shares)",
         "Receives 0.00206 USDC  (= 0.0015 × 1.375)"),
    ]
    y = 430
    for left, right in rows:
        d.text((100, y), "•", font=font("body", 28), fill=ACCENT)
        d.text((140, y), left, font=font("body", 26), fill=TEXT)
        d.text((140, y + 32), right, font=font("body", 22), fill=SUBTLE)
        y += 90
    draw_brand(d)
    return img, 22.0


def slide_05_live_evidence():
    img, d = new_slide()
    d.text((100, 100), "Live on Arc Testnet today", font=font("title", 56), fill=TEXT)
    d.line([(100, 185), (760, 185)], fill=ACCENT, width=4)
    d.text((100, 235), "Plinth deployed + 4 vaults active + 8 lifecycle txs:",
           font=font("body", 28), fill=SUBTLE)
    items = [
        ("Plinth contract",     "0xc2994ce3...86627"),
        ("Vault 1 — BTC perp momentum",     "NAV 1.375  ·  full lifecycle ran"),
        ("Vault 2 — ETH mean reversion",    "+2 depositors, 0.007 USDC TVL"),
        ("Vault 3 — SOL perp grid bot",     "deployed 0.002, +0.001 PnL reported"),
        ("Vault 4 — Multi-asset arbitrage", "fresh, awaiting depositors"),
        ("2 underwriter reviews on chain",  "auditable risk attestations"),
    ]
    y = 290
    for label, val in items:
        d.text((100, y), "•", font=font("body", 28), fill=ACCENT)
        d.text((130, y), label, font=font("body", 28), fill=TEXT)
        d.text((780, y), val, font=font("mono", 24), fill=HIGHLIGHT)
        y += 64
    d.rounded_rectangle([(100, 770), (W - 100, 870)], radius=10,
                        outline=DIM, width=2, fill=(22, 26, 44))
    d.text((W / 2, 800), "Verifiable: testnet.arcscan.app/address/0xc2994ce3df...86627",
           font=font("mono", 22), fill=HIGHLIGHT, anchor="mm")
    d.text((W / 2, 845), "Live web UI: ccheh.github.io/plinth",
           font=font("mono", 22), fill=GREEN, anchor="mm")
    draw_brand(d)
    return img, 22.0


def slide_06_circle_fit():
    img, d = new_slide()
    d.text((100, 100), "Why this fits Arc specifically", font=font("title", 56), fill=TEXT)
    d.line([(100, 185), (820, 185)], fill=ACCENT, width=4)
    rows = [
        ("USDC as native gas",
         "Single-tx deposit + redeem. No separate gas token to manage."),
        ("Sub-cent settlement",
         "Small-share economics work. A $0.50 redeem isn't eaten by gas."),
        ("L1 finality",
         "A deposit at NAV 1.50 is final — no chain reorg rewrites shares."),
        ("USDC-native settlement",
         "Vault accounting and venue settlement use the same currency."),
        ("Regulated stablecoin + compliance hooks",
         "Future-proof: institutional vaults can plug in audit hooks at L1."),
    ]
    y = 240
    for left, right in rows:
        d.text((100, y), left,    font=font("body", 30), fill=ACCENT)
        for line in wrap(right, 90):
            d.text((130, y + 40), line, font=font("body", 24), fill=TEXT); y += 32
        y += 70
    draw_brand(d)
    return img, 18.0


def slide_07_innovation():
    img, d = new_slide()
    d.text((100, 100), "What's different about Plinth", font=font("title", 56), fill=TEXT)
    d.line([(100, 185), (790, 185)], fill=ACCENT, width=4)
    points = [
        ("Capability constraint, not custody constraint",
         "Agent never holds the keys — but does direct the funds. approvedVenues is immutable. The agent's drain attack surface is publicly visible to off-chain reviewers."),
        ("Underwriter Agent (LLM)",
         "An off-chain LLM reads each vault's strategy descriptor + on-chain state, outputs a structured risk review, commits the review hash on chain. Anyone can post; consumers select trusted reviewers."),
        ("Sub-cent shares",
         "MIN_DEPOSIT 0.0001 USDC. Plinth lets retail-sized capital diversify across AI strategies — only possible because Arc's gas economics support it."),
        ("Composable with the stack",
         "Mandate (auth) + Cadence (per-call pay) + Crucible (quality) + Helm (group decisions) + Plinth (capital) = the agent economy stack."),
    ]
    y = 230
    for h_, b in points:
        d.text((100, y), h_, font=font("body", 30), fill=ACCENT)
        for line in wrap(b, 95):
            d.text((130, y + 40), line, font=font("body", 22), fill=TEXT); y += 30
        y += 60
    draw_brand(d)
    return img, 22.0


def slide_08_honest_limits():
    img, d = new_slide()
    d.text((100, 100), "Honest limits", font=font("title", 60), fill=TEXT)
    d.line([(100, 185), (400, 185)], fill=ACCENT, width=4)
    limits = [
        ("v0, pre-audit, pre-mainnet.",
         "52 forge tests + Slither pass + adversarial scenarios. No external review yet."),
        ("No production adopters.",
         "Submitted to Agora Agents Hackathon. The bet: trading agent teams need this primitive."),
        ("Agent-reported PnL is trust-based.",
         "v0 relies on Underwriter to catch lies. v0.2 will add stake/bond honesty enforcement."),
        ("Agent can list themselves as a venue.",
         "Intentional Underwriter-detectable failure mode. Off-chain review flags this as CRITICAL."),
        ("Native USDC only (Arc 18-decimal).",
         "Mainnet adaptation needs IERC-20 semantics. Mechanism portable; implementation isn't."),
    ]
    y = 230
    for h_, b in limits:
        d.text((100, y), h_, font=font("body", 28), fill=RED)
        for line in wrap(b, 95):
            d.text((130, y + 38), line, font=font("body", 22), fill=TEXT); y += 30
        y += 60
    draw_brand(d)
    return img, 18.0


def slide_09_close():
    img, d = new_slide()
    d.text((W / 2, 240), "Plinth", font=font("title", 144), fill=TEXT, anchor="mm")
    d.text((W / 2, 390), "Capital layer for AI trading agents on Arc",
           font=font("title", 42), fill=HIGHLIGHT, anchor="mm")
    d.text((W / 2, 540), "github.com/Ccheh/plinth",
           font=font("mono", 36), fill=ACCENT, anchor="mm")
    d.text((W / 2, 600), "ccheh.github.io/plinth",
           font=font("mono", 30), fill=HIGHLIGHT, anchor="mm")
    d.text((W / 2, 660), "Contract: 0xc2994ce3df612ebd2f898244a992a0bbfef86627",
           font=font("mono", 22), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 800), "MIT-licensed. No admin keys. Audit-pending.",
           font=font("body", 28), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 850), "Built on Arc Testnet for Agora Agents Hackathon, May 2026.",
           font=font("body", 24), fill=DIM, anchor="mm")
    draw_brand(d)
    return img, 8.0


# ============================================================
# build
# ============================================================

slides = [
    slide_01_title,
    slide_02_problem,
    slide_03_what_is_plinth,
    slide_04_mechanism,
    slide_05_live_evidence,
    slide_06_circle_fit,
    slide_07_innovation,
    slide_08_honest_limits,
    slide_09_close,
]

print(f"Generating {len(slides)} slides...")
total = 0.0
for i, fn in enumerate(slides, start=1):
    img, dur = fn()
    path = SLIDE_DIR / f"slide_{i:02d}.png"
    img.save(path)
    print(f"  [{i}/{len(slides)}] {path.name} ({dur:.1f}s)")
    total += dur

print(f"\nTotal duration target: {total:.1f}s = {total/60:.1f}min")
print(f"Slides saved to: {SLIDE_DIR}")
