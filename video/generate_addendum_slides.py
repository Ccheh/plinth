"""
Addendum video slides — covers the 4 innovations shipped AFTER the codebase
walkthrough video was rendered. Visually consistent with the codebase video.

Output: D:\桌面\arc\plinth\video\slides_addendum\slide_NN.png  (1920x1080)
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path(r"D:\桌面\arc\plinth\video")
SLIDE_DIR = OUT_DIR / "slides_addendum"
SLIDE_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080
BG = (15, 18, 33)
TEXT = (235, 235, 240)
SUBTLE = (160, 165, 180)
ACCENT = (255, 200, 80)
HIGHLIGHT = (110, 200, 255)
DIM = (90, 96, 115)
GREEN = (110, 220, 150)
CODE_BG = (24, 28, 45)


def get_fonts():
    base = r"C:\Windows\Fonts"
    cands = {
        "title": ["calibrib.ttf", "arialbd.ttf", "segoeuib.ttf"],
        "body":  ["calibri.ttf",  "arial.ttf",   "segoeui.ttf"],
        "mono":  ["consola.ttf",  "cour.ttf"],
        "monob": ["consolab.ttf", "courbd.ttf"],
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
    d.text((60, H - 55), "Plinth — Innovation Sprint Addendum  ·  github.com/Ccheh/plinth",
           font=f, fill=SUBTLE)


def draw_header(d, title, subtitle=None, accent_width=900):
    d.text((100, 80), title, font=font("title", 56), fill=TEXT)
    d.line([(100, 175), (100 + accent_width, 175)], fill=ACCENT, width=4)
    if subtitle:
        d.text((100, 200), subtitle, font=font("body", 28), fill=HIGHLIGHT)


# ============================================================
# slides
# ============================================================

def slide_01_title():
    img, d = new_slide()
    d.text((W/2, 230), "CIRCLE DEVELOPER GRANT · ADDENDUM", font=font("body", 28), fill=ACCENT, anchor="mm")
    d.text((W/2, 270), "Shipped after the codebase walkthrough · May 2026", font=font("body", 22), fill=SUBTLE, anchor="mm")
    d.text((W/2, 430), "Innovation Sprint", font=font("title", 110), fill=TEXT, anchor="mm")
    d.text((W/2, 560), "4 new deliverables addressing Grant evaluator concerns", font=font("title", 36), fill=HIGHLIGHT, anchor="mm")
    # 4 chips
    chips = [
        ("Composition #3", "Crucible × Plinth"),
        ("Composition #4", "Helm × Plinth"),
        ("Public Goods", "@plinth/verifier-core"),
        ("Sustainability", "PlinthSponsorPool"),
    ]
    cx = 240
    for kind, name in chips:
        d.rounded_rectangle([cx, 700, cx + 360, 870], radius=12, fill=CODE_BG)
        d.text((cx + 180, 745), kind, font=font("body", 24), fill=ACCENT, anchor="mm")
        d.text((cx + 180, 810), name, font=font("monob", 28), fill=HIGHLIGHT, anchor="mm")
        cx += 380
    d.text((W/2, 950), "Total: 11 contracts on Arc Testnet · 176/176 tests · 4 compositions live", font=font("body", 26), fill=GREEN, anchor="mm")
    draw_brand(d)
    return img


def slide_02_crucible_bridge():
    img, d = new_slide()
    draw_header(d, "Composition #3 — Crucible × Plinth", "Quality-proportional management fee release", accent_width=1200)
    d.text((100, 260), "The unsolved problem:", font=font("body", 30), fill=HIGHLIGHT)
    d.text((100, 310), "Enzyme and dHEDGE charge management fees regardless of agent quality.", font=font("body", 26), fill=TEXT)
    d.text((100, 350), "Investor pays even when the agent's output is bad.", font=font("body", 26), fill=TEXT)

    d.text((100, 430), "What Crucible × Plinth ships:", font=font("body", 30), fill=GREEN)
    rows = [
        ("1.", "Sponsor escrows a fee budget into the bridge, tied to a Crucible market."),
        ("2.", "Crucible market resolves with a scoreBps — quality consensus via Schelling."),
        ("3.", "Bridge releases scoreBps proportion of the escrow to the agent."),
        ("4.", "Remainder refunded to the sponsor. Zero fee if zero quality."),
    ]
    y = 490
    for num, desc in rows:
        d.text((130, y), num, font=font("title", 40), fill=ACCENT)
        d.text((210, y + 5), desc, font=font("body", 26), fill=TEXT)
        y += 70

    d.rounded_rectangle([100, 820, 1820, 920], radius=10, fill=CODE_BG)
    d.text((130, 845), "Deployed:  0xa948e26546c3634da03df8b078b1c8d79ba54a78", font=font("mono", 26), fill=HIGHLIGHT)
    d.text((130, 885), "13/13 unit tests passing · Arc Testnet · zero-score refund path verified", font=font("body", 22), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_03_helm_bridge():
    img, d = new_slide()
    draw_header(d, "Composition #4 — Helm × Plinth", "Metric-conditional fee release", accent_width=1200)
    d.text((100, 260), "Why not just bonus-tier the fee?", font=font("body", 30), fill=HIGHLIGHT)
    d.text((100, 310), "Most agent contracts vest based on time. On-chain milestone vesting is a gap.", font=font("body", 26), fill=TEXT)
    d.text((100, 350), "Helm × Plinth makes the agent's reward conditional on a verifiable metric.", font=font("body", 26), fill=TEXT)

    d.text((100, 430), "Flow:", font=font("body", 30), fill=GREEN)
    rows = [
        ("1.", "Sponsor escrows fee + selects a Helm market (e.g., NAV growth ≥ 5 bps)."),
        ("2.", "Helm market resolves at the milestone deadline via oracle."),
        ("3.", "If metricMet == true: agent receives full escrow. Binary, not proportional."),
        ("4.", "If false: full refund to sponsor. The agent has incentive to hit milestones."),
    ]
    y = 490
    for num, desc in rows:
        d.text((130, y), num, font=font("title", 40), fill=ACCENT)
        d.text((210, y + 5), desc, font=font("body", 26), fill=TEXT)
        y += 70

    d.rounded_rectangle([100, 820, 1820, 920], radius=10, fill=CODE_BG)
    d.text((130, 845), "Deployed:  0xdd612ded1b3972dac53acd7cd0c959a45a82defe", font=font("mono", 26), fill=HIGHLIGHT)
    d.text((130, 885), "8/8 unit tests passing · binary settle + refund verified", font=font("body", 22), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_04_verifier_core():
    img, d = new_slide()
    draw_header(d, "@plinth/verifier-core — public-goods extraction", "npm-ready package: verifier interface + reference impls", accent_width=1300)
    d.text((100, 260), "The pattern problem:", font=font("body", 30), fill=HIGHLIGHT)
    d.text((100, 310), "Every fund-management protocol that wants verifiable PnL has to reinvent", font=font("body", 26), fill=TEXT)
    d.text((100, 350), "the verifier abstraction. Plinth solved it once. We extracted it for others.", font=font("body", 26), fill=TEXT)

    d.text((100, 440), "What's in the package:", font=font("body", 30), fill=GREEN)
    items = [
        ("@plinth/verifier-core",       "IPerpVerifier interface · classify() verdict logic · renderMarkdown()"),
        ("@plinth/verifier-core/aster", "AsterVerifier — reference impl, the file that proved the pattern works"),
        ("@plinth/verifier-core/synthra","SynthraPerpVerifier — Arc-native perp scaffold (ABI pending)"),
    ]
    y = 500
    for name, desc in items:
        d.rounded_rectangle([100, y, 1820, y + 95], radius=8, fill=CODE_BG)
        d.text((130, y + 18), name, font=font("monob", 28), fill=ACCENT)
        d.text((130, y + 55), desc, font=font("body", 22), fill=TEXT)
        y += 110

    d.text((100, 880), "MIT licensed · ready for npm publish · roadmap: HyperLiquid, generic Uniswap-v3, CEX base.", font=font("body", 24), fill=GREEN)
    d.text((100, 920), "Any protocol can drop this in their Underwriter pipeline.", font=font("body", 24), fill=TEXT)
    draw_brand(d)
    return img


def slide_05_sponsor_pool_and_outro():
    img, d = new_slide()
    draw_header(d, "PlinthSponsorPool + the honest revenue answer", "Sustainability for the Underwriter network", accent_width=1300)
    d.text((100, 260), "The question evaluators always ask:", font=font("body", 30), fill=HIGHLIGHT)
    d.text((100, 310), '"Where does protocol revenue come from?"  Honest answer: Plinth itself takes nothing.', font=font("body", 26), fill=TEXT)

    d.text((100, 400), "How the Underwriter network sustains:", font=font("body", 30), fill=GREEN)
    rows = [
        ("1.", "Vault investors (or anyone) deposit USDC into a per-vault sponsor pool."),
        ("2.", "Underwriters who post reviews claim a fixed REWARD_PER_REVIEW from the pool."),
        ("3.", "Per-address dedup prevents Sybil drain. Sponsors refill when they want coverage."),
        ("4.", "Plinth takes zero cut. Pure investor → underwriter market, like Polymarket bounties."),
    ]
    y = 460
    for num, desc in rows:
        d.text((130, y), num, font=font("title", 40), fill=ACCENT)
        d.text((210, y + 5), desc, font=font("body", 26), fill=TEXT)
        y += 70

    d.rounded_rectangle([100, 770, 1820, 870], radius=10, fill=CODE_BG)
    d.text((130, 795), "Deployed:  0xf28a58e71b822e76527032973223e422686068e2", font=font("mono", 26), fill=HIGHLIGHT)
    d.text((130, 835), "10/10 unit tests · dedup + refill-cycle + Sybil-drain coverage verified", font=font("body", 22), fill=SUBTLE)

    d.line([(100, 920), (W - 100, 920)], fill=DIM, width=2)
    d.text((W/2, 970), "github.com/Ccheh/plinth  ·  4 compositions · 11 contracts · 176/176 · MIT  ·  Thanks.", font=font("body", 26), fill=TEXT, anchor="mm")
    draw_brand(d)
    return img


SLIDES = [
    ("slide_01.png", slide_01_title),
    ("slide_02.png", slide_02_crucible_bridge),
    ("slide_03.png", slide_03_helm_bridge),
    ("slide_04.png", slide_04_verifier_core),
    ("slide_05.png", slide_05_sponsor_pool_and_outro),
]


if __name__ == "__main__":
    for name, fn in SLIDES:
        img = fn()
        path = SLIDE_DIR / name
        img.save(path, "PNG", optimize=True)
        print(f"  saved {name}")
    print(f"\nDone. {len(SLIDES)} slides in {SLIDE_DIR}")
