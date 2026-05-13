"""
Plinth — slide-based pitch video generator (v2, post-audit edition).

Covers everything shipped since the original demo.mp4 was made:
  - Verifiable-PnL Underwriter via Aster L1 (3 real BTC perp round-trips)
  - Multi-underwriter design (LLM + Risk Monitor + Verifier + human reviewer Bob)
  - Security audit (11 findings) and Plinth v0.5 (6 fixes deployed)
  - Wallet diversity bootstrap pattern
  - 15-minute agent-integration quickstart doc

Output: D:\\桌面\\arc\\plinth\\video\\slides\\slide_NN.png  (1920x1080)
        D:\\桌面\\arc\\plinth\\video\\audio\\narration_NN.mp3
        D:\\桌面\\arc\\plinth\\video\\demo.mp4 (final, ~3.5 min)

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
HIGHLIGHT = (110, 200, 255)   # arc-cyan
DIM = (90, 96, 115)
GREEN = (110, 220, 150)
RED = (235, 110, 110)
ASTER = (255, 154, 110)       # orange — Aster brand


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
    d.text((W / 2, 230), "AGORA AGENTS HACKATHON",
           font=font("body", 28), fill=ACCENT, anchor="mm")
    d.text((W / 2, 275), "Canteen × Circle on Arc · May 2026",
           font=font("body", 22), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 450), "Plinth",
           font=font("title", 144), fill=TEXT, anchor="mm")
    d.text((W / 2, 580), "Capital layer for AI trading agents on Arc",
           font=font("title", 48), fill=HIGHLIGHT, anchor="mm")
    d.text((W / 2, 720), "Zen Chen   ·   github.com/Ccheh",
           font=font("body", 30), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 780), "6 vaults · 90 forge tests · 11-finding security audit · MIT",
           font=font("body", 24), fill=DIM, anchor="mm")
    d.text((W / 2, 825), "Real BTC perp on Aster L1 mainnet · $0.13 experimental cost",
           font=font("body", 22), fill=GREEN, anchor="mm")
    draw_brand(d)
    return img


def slide_02_problem():
    img, d = new_slide()
    d.text((100, 100), "The trust gap stops AI trading from scaling",
           font=font("title", 56), fill=TEXT)
    d.line([(100, 195), (1100, 195)], fill=ACCENT, width=4)
    lines = [
        ("Your agent has a strategy. It runs on its own balance.", TEXT, 38),
        ("To raise outside capital you'd need:", SUBTLE, 32),
        ("", None, 16),
        ("· a fund legal wrapper, or compliance overhead", SUBTLE, 30),
        ("· custody arrangements you don't have", SUBTLE, 30),
        ("· investors who'll take 'trust my returns' on faith", SUBTLE, 30),
        ("· enough name recognition to overcome the rug risk", SUBTLE, 30),
        ("", None, 30),
        ("And the verifying-PnL problem has no clean answer:", TEXT, 34),
        ("agents can claim any number, investors must believe them.", TEXT, 34),
    ]
    y = 270
    for line, color, sz in lines:
        if line == "":
            y += sz; continue
        d.text((100, y), line, font=font("body", sz), fill=color)
        y += sz + 14
    draw_brand(d)
    return img


def slide_03_what_is_plinth():
    img, d = new_slide()
    d.text((100, 100), "Plinth solves it on chain", font=font("title", 64), fill=TEXT)
    d.line([(100, 195), (730, 195)], fill=ACCENT, width=4)
    d.text((100, 250), "Three roles, all coexisting in one Arc contract:",
           font=font("body", 30), fill=HIGHLIGHT)
    rows = [
        ("AGENT",
         "Creates a vault with an immutable list of venue addresses.",
         "Can direct funds, but can never withdraw to a new address.",
         ACCENT),
        ("INVESTOR",
         "Deposits USDC, receives shares at current NAV.",
         "Redeems on demand. No fund manager intermediary.",
         HIGHLIGHT),
        ("UNDERWRITER",
         "Anyone — runs off-chain analysis, posts reviews on chain.",
         "Multiple underwriters per vault by design.",
         GREEN),
    ]
    y = 340
    for role, body1, body2, c in rows:
        d.rounded_rectangle([(100, y), (W - 100, y + 130)], radius=12,
                            outline=c, width=2, fill=(22, 26, 44))
        d.text((130, y + 22), role, font=font("title", 32), fill=c)
        d.text((130, y + 65), body1, font=font("body", 26), fill=TEXT)
        d.text((130, y + 95), body2, font=font("body", 22), fill=SUBTLE)
        y += 155
    draw_brand(d)
    return img


def slide_04_mechanism():
    img, d = new_slide()
    d.text((100, 100), "How NAV works", font=font("title", 60), fill=TEXT)
    d.line([(100, 185), (440, 185)], fill=ACCENT, width=4)
    d.text((100, 235), "totalAUM = inVault + deployedAUM + reportedPnL",
           font=font("mono", 30), fill=HIGHLIGHT)
    d.text((100, 280), "NAV       = (totalAUM × 1e18) / totalShares",
           font=font("mono", 30), fill=HIGHLIGHT)
    d.text((100, 360), "Concretely, on Arc Testnet:", font=font("body", 32), fill=ACCENT)
    rows = [
        ("Agent deposits 0.001 USDC, gets 0.001 shares",
         "NAV = 1.0 (inception)"),
        ("Investor deposits 0.01 USDC at NAV 1.0",
         "Investor gets 0.01 shares, total shares = 0.011"),
        ("Agent deploys 0.005 USDC to a venue",
         "inVault drops, deployedAUM rises, NAV unchanged"),
        ("Agent reports realized −0.047 USDC PnL (real Aster L1 trade)",
         "totalAUM declines, NAV updates accordingly"),
        ("Investor redeems shares",
         "Receives proportional USDC out at current NAV"),
    ]
    y = 430
    for left, right in rows:
        d.text((100, y), "•", font=font("body", 26), fill=ACCENT)
        d.text((140, y), left, font=font("body", 25), fill=TEXT)
        d.text((140, y + 30), right, font=font("body", 21), fill=SUBTLE)
        y += 75
    draw_brand(d)
    return img


def slide_05_verifiable_pnl():
    img, d = new_slide()
    d.text((100, 100), "The killer feature — Verifiable PnL",
           font=font("title", 56), fill=TEXT)
    d.line([(100, 195), (1100, 195)], fill=GREEN, width=4)
    d.text((100, 240), "When the venue is itself a public chain, the agent can't lie about PnL.",
           font=font("body", 30), fill=GREEN)

    # Left column: Arc (Plinth)
    d.rounded_rectangle([(100, 320), (W // 2 - 30, 720)], radius=12,
                        outline=HIGHLIGHT, width=2, fill=(22, 26, 44))
    d.text((W // 4 - 30, 360), "Plinth (Arc Testnet)",
           font=font("title", 28), fill=HIGHLIGHT, anchor="mm")
    d.text((130, 410), "Agent claims:", font=font("body", 22), fill=SUBTLE)
    d.text((130, 445), "reportedPnL = −0.047207 USDC",
           font=font("mono", 24), fill=TEXT)
    d.text((130, 495), "Posted on chain in tx 0x0f15c4e1...",
           font=font("mono", 18), fill=DIM)
    d.text((130, 580), "(Phase 3 vault — created May 13)",
           font=font("body", 20), fill=SUBTLE)

    # Right column: Aster L1
    d.rounded_rectangle([(W // 2 + 30, 320), (W - 100, 720)], radius=12,
                        outline=ASTER, width=2, fill=(22, 26, 44))
    d.text(((W * 3) // 4 + 30, 360), "Aster L1 (chainId 1666)",
           font=font("title", 28), fill=ASTER, anchor="mm")
    d.text((W // 2 + 60, 410), "Venue evidence:", font=font("body", 22), fill=SUBTLE)
    d.text((W // 2 + 60, 445), "BUY 0.001 BTC @ 80,500.7",
           font=font("mono", 22), fill=TEXT)
    d.text((W // 2 + 60, 478), "SELL 0.001 BTC @ 80,517.9",
           font=font("mono", 22), fill=TEXT)
    d.text((W // 2 + 60, 525), "realized +0.0172, fees −0.0644",
           font=font("mono", 20), fill=DIM)
    d.text((W // 2 + 60, 560), "= net −0.0472 USDT",
           font=font("mono", 22), fill=TEXT)
    d.text((W // 2 + 60, 615), "Pulled from /fapi/v3/userTrades",
           font=font("body", 20), fill=SUBTLE)

    # The reconciliation arrow + verdict
    d.line([(W // 4 - 30 + 70, 700), (W // 2 + 60, 700)], fill=GREEN, width=3)
    d.text((W / 2, 770), "Underwriter reconciles → delta 0.00% → VERIFIED",
           font=font("title", 32), fill=GREEN, anchor="mm")
    d.text((W / 2, 815), "Posted on chain as UnderwriterReviewPosted event. Anyone can rerun the math.",
           font=font("body", 24), fill=TEXT, anchor="mm")

    draw_brand(d)
    return img


def slide_06_multi_underwriter():
    img, d = new_slide()
    d.text((100, 100), "Multi-underwriter — different lenses, posted independently",
           font=font("title", 48), fill=TEXT)
    d.line([(100, 195), (1300, 195)], fill=ACCENT, width=4)
    d.text((100, 245), "Same vault, four independent reviews on chain. Two distinct signing addresses. By design.",
           font=font("body", 26), fill=SUBTLE)

    cards = [
        ("Aster Verifier",  "VERIFIED",
         "PnL matches Aster L1 trade history exactly. Agent is honest.",
         GREEN),
        ("Risk Monitor",    "CRITICAL",
         "Vault is underwater; reportedPnL is 1224% of capital. Position is dangerous.",
         RED),
        ("LLM Underwriter", "MEDIUM",
         "Strategy descriptor is specific. High-leverage perp; size-mismatch risk.",
         ACCENT),
        ("Human Analyst", "BLESSED",
         "From a separate signing address. Reads as 'honest but ill-sized.'",
         HIGHLIGHT),
    ]
    y = 320
    for title, verdict, body, c in cards:
        d.rounded_rectangle([(100, y), (W - 100, y + 130)], radius=10,
                            outline=c, width=2, fill=(22, 26, 44))
        d.text((130, y + 25), title, font=font("title", 26), fill=c)
        d.text((460, y + 25), f"verdict: {verdict}", font=font("mono", 22), fill=c)
        for j, line in enumerate(wrap(body, 90)):
            d.text((130, y + 65 + j * 28), line, font=font("body", 22), fill=TEXT)
        y += 150

    d.text((W / 2, 950), "An honest agent reporting a real loss is exactly when investors need a warning — not reassurance.",
           font=font("body", 22), fill=SUBTLE, anchor="mm")
    draw_brand(d)
    return img


def slide_07_security_audit():
    img, d = new_slide()
    d.text((100, 100), "Security audit + Plinth v0.5", font=font("title", 56), fill=TEXT)
    d.line([(100, 195), (920, 195)], fill=RED, width=4)
    d.text((100, 240), "Pre-deployment self-audit found 11 vulnerabilities. v0.5 closed the 6 real ones.",
           font=font("body", 28), fill=SUBTLE)

    rows = [
        ("#1  Sandwich on reportPnL (CRITICAL)",   "exploit POC passes",  "→ deposit cooldown"),
        ("#2  returnFromVenue griefing (HIGH)",    "exploit POC passes",  "→ caller must be venue|agent"),
        ("#3  reportPnL inflation rug (HIGH)",     "exploit POC passes",  "→ 10× capital cap + rate limit"),
        ("#4  reportPnL on Closed vault (MEDIUM)", "exploit POC passes",  "→ rejected on Closed"),
        ("#6  INT256 overflow (MEDIUM)",           "theoretical",         "→ bounded by #3 fix"),
        ("#8  strategyDescriptor (LOW)",           "gas griefing",        "→ MAX_STRATEGY_LEN = 1024"),
    ]
    y = 300
    for finding, vstatus, fix in rows:
        d.text((100, y), finding, font=font("body", 24), fill=RED)
        d.text((780, y), vstatus, font=font("body", 22), fill=SUBTLE)
        d.text((1150, y), fix, font=font("body", 22), fill=GREEN)
        y += 50

    d.rounded_rectangle([(100, 700), (W - 100, 880)], radius=10,
                        outline=GREEN, width=2, fill=(22, 26, 44))
    d.text((W / 2, 740), "90 / 90 forge tests pass",
           font=font("title", 36), fill=GREEN, anchor="mm")
    d.text((W / 2, 790), "5 exploit POCs (v0 vulnerabilities) + 18 defense tests (v0.5 fixes) + 52 invariant tests",
           font=font("body", 24), fill=TEXT, anchor="mm")
    d.text((W / 2, 835), "PlinthV05 deployed: 0xba1b087b...298f3f96addc7  — deposit cooldown firing on chain",
           font=font("mono", 20), fill=HIGHLIGHT, anchor="mm")
    draw_brand(d)
    return img


def slide_08_live_evidence():
    img, d = new_slide()
    d.text((100, 100), "Live on Arc Testnet", font=font("title", 60), fill=TEXT)
    d.line([(100, 195), (530, 195)], fill=ACCENT, width=4)
    d.text((100, 240), "6 vaults across v0 + v0.5, 7 underwriter reviews, 3 real Aster L1 round-trips.",
           font=font("body", 26), fill=SUBTLE)

    items = [
        ("Plinth v0 (5 vaults)",       "0xc2994ce3...86627",        HIGHLIGHT),
        ("Plinth v0.5 (1 vault)",      "0xba1b087b...8addc7",       GREEN),
        ("MockVenue contracts",         "(re-used by both versions)", DIM),
        ("Vault #5 — Aster verifiable", "VERIFIED + CRITICAL on chain", ACCENT),
        ("Bob's wallet (Underwriter)",  "0xA4Fe6D03...75fef47",      ASTER),
    ]
    y = 320
    for label, val, c in items:
        d.text((100, y), "·", font=font("body", 28), fill=ACCENT)
        d.text((130, y), label, font=font("body", 28), fill=TEXT)
        d.text((730, y), val, font=font("mono", 22), fill=c)
        y += 56

    d.rounded_rectangle([(100, 700), (W - 100, 880)], radius=10,
                        outline=ACCENT, width=2, fill=(22, 26, 44))
    d.text((W / 2, 740), "Real money cost end-to-end: $0.13 USDT on Aster L1",
           font=font("title", 32), fill=ACCENT, anchor="mm")
    d.text((W / 2, 790), "3 BTC perp round-trips, 6 fills, all 3 directional wins, fees ate the gross",
           font=font("body", 22), fill=TEXT, anchor="mm")
    d.text((W / 2, 835), "ccheh.github.io/plinth/verify.html  →  interactive demo, reconciliation in browser",
           font=font("mono", 22), fill=GREEN, anchor="mm")
    draw_brand(d)
    return img


def slide_09_arc_fit_and_aster_framing():
    img, d = new_slide()
    d.text((100, 100), "Why Arc — and why we picked Aster as a demo target",
           font=font("title", 50), fill=TEXT)
    d.line([(100, 195), (1200, 195)], fill=HIGHLIGHT, width=4)
    rows = [
        ("USDC as native gas",
         "Single-tx deposit + redeem. No separate gas token."),
        ("Sub-cent settlement",
         "MIN_DEPOSIT 0.0001 USDC. Tiny shares are economically viable."),
        ("L1 finality",
         "Deposits at a given NAV are final. No chain reorg rewriting share counts."),
        ("Composes with Circle's stack",
         "USYC for idle yield, CCTP for cross-chain — both on the roadmap."),
    ]
    y = 260
    for left, right in rows:
        d.text((100, y), left,  font=font("body", 30), fill=ACCENT)
        d.text((130, y + 36), right, font=font("body", 24), fill=TEXT)
        y += 88

    d.rounded_rectangle([(100, 660), (W - 100, 880)], radius=10,
                        outline=ASTER, width=2, fill=(22, 26, 44))
    d.text((W / 2, 700), "On Aster as a demo target",
           font=font("title", 32), fill=ASTER, anchor="mm")
    d.text((W / 2, 760), "Aster L1 was picked for v0 because it's a public chain with on-chain trade history —",
           font=font("body", 22), fill=TEXT, anchor="mm")
    d.text((W / 2, 790), "exactly what the Verifier needs. The same code works against any public-chain perp DEX,",
           font=font("body", 22), fill=TEXT, anchor="mm")
    d.text((W / 2, 820), "including future Arc-native perp DEXes once they launch.",
           font=font("body", 22), fill=TEXT, anchor="mm")
    d.text((W / 2, 855), "Aster is a demo target, not a dependency. Plinth is the product.",
           font=font("body", 24), fill=ACCENT, anchor="mm")
    draw_brand(d)
    return img


def slide_10_close():
    img, d = new_slide()
    d.text((W / 2, 220), "Plinth", font=font("title", 144), fill=TEXT, anchor="mm")
    d.text((W / 2, 370), "Capital layer for AI trading agents on Arc",
           font=font("title", 42), fill=HIGHLIGHT, anchor="mm")
    d.text((W / 2, 510), "Try it. Push back. Integrate it.",
           font=font("body", 30), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 600), "github.com/Ccheh/plinth",
           font=font("mono", 36), fill=ACCENT, anchor="mm")
    d.text((W / 2, 655), "ccheh.github.io/plinth",
           font=font("mono", 28), fill=HIGHLIGHT, anchor="mm")
    d.text((W / 2, 720), "15-minute agent integration:  docs/quickstart-for-agents.md",
           font=font("mono", 22), fill=GREEN, anchor="mm")
    d.text((W / 2, 820), "MIT licensed. No admin keys. Pre-deployment audit complete.",
           font=font("body", 24), fill=SUBTLE, anchor="mm")
    d.text((W / 2, 860), "Built for Agora Agents Hackathon · Canteen × Circle on Arc · May 2026",
           font=font("body", 22), fill=DIM, anchor="mm")
    draw_brand(d)
    return img


# ============================================================
# build
# ============================================================

slides = [
    slide_01_title,
    slide_02_problem,
    slide_03_what_is_plinth,
    slide_04_mechanism,
    slide_05_verifiable_pnl,
    slide_06_multi_underwriter,
    slide_07_security_audit,
    slide_08_live_evidence,
    slide_09_arc_fit_and_aster_framing,
    slide_10_close,
]

print(f"Generating {len(slides)} slides...")
for i, fn in enumerate(slides, start=1):
    img = fn()
    path = SLIDE_DIR / f"slide_{i:02d}.png"
    img.save(path)
    print(f"  [{i}/{len(slides)}] {path.name}")

print(f"\nSlides saved to: {SLIDE_DIR}")
