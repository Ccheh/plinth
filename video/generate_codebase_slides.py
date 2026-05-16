"""
Codebase walkthrough slides — 10 slides for the Circle Developer Grant video.

Reuses fonts + colors + helpers from generate_slides.py so the visual identity
matches the existing pitch video.

Output: D:\桌面\arc\plinth\video\slides_codebase\slide_NN.png  (1920x1080)
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path(r"D:\桌面\arc\plinth\video")
SLIDE_DIR = OUT_DIR / "slides_codebase"
SLIDE_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080
BG = (15, 18, 33)
TEXT = (235, 235, 240)
SUBTLE = (160, 165, 180)
ACCENT = (255, 200, 80)
HIGHLIGHT = (110, 200, 255)
DIM = (90, 96, 115)
GREEN = (110, 220, 150)
RED = (235, 110, 110)
CODE_BG = (24, 28, 45)
CODE_TEXT = (220, 225, 235)
KEYWORD = (200, 130, 240)
STRING = (160, 200, 130)
COMMENT = (110, 115, 140)


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
    d.text((60, H - 55), "Plinth — Codebase Walkthrough  ·  github.com/Ccheh/plinth",
           font=f, fill=SUBTLE)


def draw_header(d, title, subtitle=None, accent_width=900):
    d.text((100, 80), title, font=font("title", 56), fill=TEXT)
    d.line([(100, 175), (100 + accent_width, 175)], fill=ACCENT, width=4)
    if subtitle:
        d.text((100, 200), subtitle, font=font("body", 28), fill=HIGHLIGHT)


def draw_code_block(d, x, y, lines, font_size=24, line_height=34, max_width=1700, pad=20):
    """Draw a code block with subtle syntax coloring (purple keywords, green strings)."""
    n_lines = len(lines)
    h = n_lines * line_height + 2 * pad
    d.rounded_rectangle([x, y, x + max_width, y + h], radius=8, fill=CODE_BG)
    fbase = font("mono", font_size)
    keywords = {"function", "external", "internal", "public", "view", "pure", "if", "else", "return",
                "revert", "emit", "for", "while", "uint256", "uint64", "uint8", "int256", "bytes32",
                "bytes4", "address", "bool", "struct", "mapping", "constant", "contract", "interface",
                "import", "from", "const", "true", "false", "this", "msg", "payable"}
    for i, raw in enumerate(lines):
        cy = y + pad + i * line_height
        if raw.lstrip().startswith("//") or raw.lstrip().startswith("/*") or raw.lstrip().startswith("*"):
            d.text((x + pad, cy), raw, font=fbase, fill=COMMENT)
            continue
        # naive colorize per-token
        col = x + pad
        token = ""
        in_string = False
        for ch in raw + " ":
            if ch == '"' or ch == "'":
                if in_string:
                    token += ch
                    d.text((col, cy), token, font=fbase, fill=STRING)
                    col += d.textlength(token, font=fbase)
                    token = ""
                    in_string = False
                else:
                    if token:
                        color = KEYWORD if token in keywords else CODE_TEXT
                        d.text((col, cy), token, font=fbase, fill=color)
                        col += d.textlength(token, font=fbase)
                        token = ""
                    in_string = True
                    token = ch
            elif in_string:
                token += ch
            elif ch.isalnum() or ch == "_":
                token += ch
            else:
                if token:
                    color = KEYWORD if token in keywords else CODE_TEXT
                    d.text((col, cy), token, font=fbase, fill=color)
                    col += d.textlength(token, font=fbase)
                    token = ""
                d.text((col, cy), ch, font=fbase, fill=CODE_TEXT)
                col += d.textlength(ch, font=fbase)
    return h


# ============================================================
# slides
# ============================================================

def slide_01_title():
    img, d = new_slide()
    d.text((W/2, 250), "CIRCLE DEVELOPER GRANT", font=font("body", 28), fill=ACCENT, anchor="mm")
    d.text((W/2, 290), "Plinth — Codebase Walkthrough · Arc Testnet · May 2026", font=font("body", 22), fill=SUBTLE, anchor="mm")
    d.text((W/2, 460), "Plinth v0.6", font=font("title", 130), fill=TEXT, anchor="mm")
    d.text((W/2, 590), "On-chain RiskGuard · 11 contracts live · 4 sibling compositions", font=font("title", 38), fill=HIGHLIGHT, anchor="mm")
    d.text((W/2, 730), "176/176 unit tests + 3 stateful invariants (60K+ runs)", font=font("body", 32), fill=TEXT, anchor="mm")
    d.text((W/2, 790), "Circle SDKs integrated · Verifiable PnL via Aster L1 · @plinth/verifier-core", font=font("body", 28), fill=GREEN, anchor="mm")
    d.text((W/2, 850), "Zen Chen · github.com/Ccheh/plinth · MIT, no admin keys", font=font("body", 26), fill=SUBTLE, anchor="mm")
    draw_brand(d)
    return img


def slide_02_overview():
    img, d = new_slide()
    draw_header(d, "What you'll see in this video", "Eight stops: four in the repo + four shipped before submission", accent_width=1400)

    # Left column — codebase tour
    d.text((100, 250), "Part 1 — Codebase tour", font=font("monob", 32), fill=ACCENT)
    items_left = [
        ("1.", "PlinthV06.sol", "On-chain RiskGuard — 4 risk hooks lifted into contract"),
        ("2.", "CadencePlinthBridge.sol", "2nd composition — fees stream via Cadence Nanopayments"),
        ("3.", "yield-strategy.ts", "Three Circle SDKs wired end-to-end"),
        ("4.", "On-chain evidence", "Charlie wallet faucet→deposit; Aster L1 0.00% delta"),
    ]
    y = 320
    for num, file, desc in items_left:
        d.text((100, y), num, font=font("title", 44), fill=ACCENT)
        d.text((170, y - 2), file, font=font("monob", 26), fill=HIGHLIGHT)
        d.text((170, y + 42), desc, font=font("body", 20), fill=SUBTLE)
        y += 130

    # Right column — innovation sprint
    d.text((1000, 250), "Part 2 — Innovation sprint", font=font("monob", 32), fill=GREEN)
    items_right = [
        ("5.", "CruciblePlinthBridge", "Composition #3 — quality-proportional fees"),
        ("6.", "HelmPlinthBridge", "Composition #4 — metric-conditional fees"),
        ("7.", "@plinth/verifier-core", "npm-ready public-goods extraction"),
        ("8.", "PlinthSponsorPool", "Underwriter network sustainability"),
    ]
    y = 320
    for num, file, desc in items_right:
        d.text((1000, y), num, font=font("title", 44), fill=GREEN)
        d.text((1070, y - 2), file, font=font("monob", 26), fill=HIGHLIGHT)
        d.text((1070, y + 42), desc, font=font("body", 20), fill=SUBTLE)
        y += 130

    d.text((W/2, 920), "Total runtime: about six minutes.", font=font("body", 26), fill=TEXT, anchor="mm")
    draw_brand(d)
    return img


def slide_03_v06_riskguard_overview():
    img, d = new_slide()
    draw_header(d, "PlinthV06 — on-chain RiskGuard", "v0.5 → v0.6: 4 risk signals lifted from off-chain script into contract")
    d.text((100, 270), "Why this matters:", font=font("body", 30), fill=HIGHLIGHT)
    d.text((100, 320), 'Persona-8 critique: "Risk Monitor is a script the author can turn off."', font=font("body", 26), fill=SUBTLE)
    d.text((100, 360), "v0.6 makes 4 of those signals cryptographically enforced — no admin key.", font=font("body", 26), fill=TEXT)

    cols = [
        ("#1", "Agent-as-venue flag", "createVault emits AgentAsVenueFlag if agent ∈ approvedVenues"),
        ("#2", "Concentration cap", "deployToVenue REVERTS if any venue would hold > 80% of AUM"),
        ("#3", "NAV floor", "reportPnL auto-Closes vault if NAV drops below 10% of inception"),
        ("#4", "Whale deposit flag", "deposit emits WhaleDeposit if single deposit > 50% pre-AUM"),
    ]
    y = 460
    for tag, name, desc in cols:
        d.rounded_rectangle([100, y, 1820, y + 110], radius=8, fill=CODE_BG)
        d.text((130, y + 25), tag, font=font("title", 44), fill=ACCENT)
        d.text((220, y + 20), name, font=font("monob", 32), fill=HIGHLIGHT)
        d.text((220, y + 65), desc, font=font("body", 24), fill=TEXT)
        y += 130
    draw_brand(d)
    return img


def slide_04_concentration_code():
    img, d = new_slide()
    draw_header(d, "RiskGuard hook #2 — venue concentration cap", "PlinthV06.sol deployToVenue")
    code = [
        "function deployToVenue(bytes32 vaultId, address venue, uint256 amount) external nonReentrant {",
        "    Vault storage v = vaults[vaultId];",
        "    if (msg.sender != v.agent) revert NotAgent();",
        "    if (!_isApprovedVenue[vaultId][venue]) revert VenueNotApproved();",
        "    if (v.inVault < amount) revert InsufficientLiquidity();",
        "",
        "    // v0.6: concentration check — REVERT if this transfer would push",
        "    // the destination venue past 80% of total deployedAUM",
        "    uint256 newDeployed = v.deployedAUM + amount;",
        "    if (v.deployedAUM > 0) {",
        "        uint256 newVenueBalance = venueBalance[vaultId][venue] + amount;",
        "        if (newVenueBalance * 10_000 > newDeployed * MAX_VENUE_CONCENTRATION_BPS) {",
        "            revert VenueConcentrationExceeded();",
        "        }",
        "    }",
        "",
        "    v.inVault -= amount;",
        "    v.deployedAUM = newDeployed;",
        "    venueBalance[vaultId][venue] += amount;",
        "    emit DeployToVenue(vaultId, venue, amount, v.inVault, v.deployedAUM);",
        "    (bool ok,) = venue.call{value: amount}(\"\");",
        "    if (!ok) revert TransferFailed();",
        "}",
    ]
    draw_code_block(d, 100, 270, code, font_size=20, line_height=30, max_width=1720)
    d.text((100, 970), "MAX_VENUE_CONCENTRATION_BPS = 8000 (80%)  ·  immutable, no admin override", font=font("body", 24), fill=GREEN)
    draw_brand(d)
    return img


def slide_05_navfloor_code():
    img, d = new_slide()
    draw_header(d, "RiskGuard hook #3 — NAV floor auto-close", "PlinthV06.sol reportPnL")
    code = [
        "function reportPnL(bytes32 vaultId, int256 newPnL) external {",
        "    // ... v0.5 magnitude cap + rate limit checks ...",
        "    v.reportedPnL = newPnL;",
        "    lastReportAt[vaultId] = block.timestamp;",
        "    emit PnLReported(vaultId, oldPnL, newPnL, _totalAUMOf(v));",
        "",
        "    // v0.6: NAV-floor auto-close. After the report, if NAV has dropped",
        "    // below 10% of inception, the vault auto-Closes. Investors retain",
        "    // redemption rights against remaining inVault capital.",
        "    uint256 navAfter = _navOf(v);",
        "    if (navAfter < (INCEPTION_NAV * NAV_FLOOR_BPS) / 10_000) {",
        "        v.status = VaultStatus.Closed;",
        "        emit VaultAutoClosed(vaultId, navAfter, \"NAV below floor (10% of inception)\");",
        "        emit VaultClosed(vaultId);",
        "    }",
        "}",
    ]
    draw_code_block(d, 100, 270, code, font_size=22, line_height=32, max_width=1720)
    d.text((100, 870), "NAV_FLOOR_BPS = 1000 (10% of inception)", font=font("body", 24), fill=GREEN)
    d.text((100, 910), "Auto-close is enforced by the contract — no admin path to override.", font=font("body", 24), fill=TEXT)
    d.text((100, 950), "Test coverage: test_reportPnL_autoCloses_whenNAVFallsBelowFloor()", font=font("mono", 22), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_06_cadence_bridge():
    img, d = new_slide()
    draw_header(d, "CadencePlinthBridge — 2nd cross-protocol composition", "CadencePlinthBridge.sol routeManagementFee")
    code = [
        "function routeManagementFee(bytes32 vaultId) external payable returns (address agent) {",
        "    if (msg.value == 0) revert ZeroAmount();",
        "",
        "    // Read agent from Plinth (no spoofing — caller can't fake who gets credited)",
        "    (agent, , , , , , , ) = plinth.vaults(vaultId);",
        "    if (agent == address(0)) revert VaultNotFound();",
        "",
        "    // Forward to Cadence's PaymentEscrowV2 as deposit credited to agent",
        "    try cadence.depositFor{value: msg.value}(agent) {",
        "        // success",
        "    } catch {",
        "        revert CadenceDepositFailed();",
        "    }",
        "",
        "    unchecked {",
        "        totalRouted[vaultId] += msg.value;",
        "        eventCount[vaultId] += 1;",
        "    }",
        "    emit FeeRouted(vaultId, agent, msg.sender, msg.value, ...);",
        "}",
    ]
    draw_code_block(d, 100, 270, code, font_size=20, line_height=30, max_width=1720)
    d.text((100, 970), "Live tx: 0xf5cb23cf... (Arc Testnet) · Cadence escrow at 0xc95b1b20...", font=font("mono", 20), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_07_circle_sdks():
    img, d = new_slide()
    draw_header(d, "Real Circle SDK integration", "sdk-ts/examples/yield-strategy.ts (production-path wiring)")
    code = [
        "import { BridgeKit, type BridgeResult } from \"@circle-fin/bridge-kit\";",
        "import { createViemAdapterFromPrivateKey } from \"@circle-fin/adapter-viem-v2\";",
        "import { CctpV2Provider } from \"@circle-fin/provider-cctp-v2\";",
        "",
        "// Production path: idle vault USDC sweeps from Arc to Base for USYC exposure",
        "const arcAdapter  = createViemAdapterFromPrivateKey(AGENT_PK, ARC_CHAIN);",
        "const baseAdapter = createViemAdapterFromPrivateKey(AGENT_PK, BASE_CHAIN);",
        "const cctpProvider = new CctpV2Provider({ /* config */ });",
        "",
        "const bridgeKit = new BridgeKit({",
        "    sourceAdapter: arcAdapter,",
        "    destinationAdapter: baseAdapter,",
        "    providers: [cctpProvider],",
        "});",
        "",
        "const result = await bridgeKit.bridge({ amount: parseUnits(\"100\", 6) });",
    ]
    draw_code_block(d, 100, 270, code, font_size=22, line_height=32, max_width=1720)
    d.text((100, 910), "✓ Not placeholder. Real @circle-fin SDK family wired end-to-end.", font=font("body", 26), fill=GREEN)
    d.text((100, 950), "Production target: USYC on Base via CCTP (Grant milestone M2).", font=font("body", 24), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_08_charlie_evidence():
    img, d = new_slide()
    draw_header(d, "On-chain evidence — Charlie wallet (fresh)", "End-to-end: faucet → Plinth deposit, NO operator keys involved")
    d.text((100, 270), "Charlie wallet (generated via viem.generatePrivateKey for this test)", font=font("body", 26), fill=SUBTLE)
    d.text((100, 310), "0xAbc9c5cE0691750710D17152C2Ce42178eac328a", font=font("mono", 26), fill=HIGHLIGHT)
    rows = [
        ("1.", "Wallet generated (off-chain)", "viem.generatePrivateKey — fresh keypair, no overlap"),
        ("2.", "Funded via faucet.circle.com", "tx 0xf86499eb...  block 42,462,623  → 20 USDC delivered"),
        ("3.", "Deposit to PlinthV05 Vault #4", "tx 0x329ad4c8...  block 42,462,837  → 0.0001 shares minted"),
    ]
    y = 410
    for num, action, detail in rows:
        d.rounded_rectangle([100, y, 1820, y + 130], radius=8, fill=CODE_BG)
        d.text((130, y + 30), num, font=font("title", 52), fill=ACCENT)
        d.text((230, y + 25), action, font=font("monob", 32), fill=HIGHLIGHT)
        d.text((230, y + 75), detail, font=font("mono", 22), fill=TEXT)
        y += 150
    d.text((100, 920), "Cost: 0.0019 USDC gas  ·  No operator-key involvement after step 1", font=font("body", 26), fill=GREEN)
    d.text((100, 960), "Documented transparently in docs/charlie-test.md", font=font("mono", 22), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_09_aster_pnl():
    img, d = new_slide()
    draw_header(d, "Verifiable PnL — Aster L1 reconciliation", "Vault #5 demo: cross-chain trade history matched 0.00% delta")
    rows = [
        ("Agent reports on Arc", "−0.047207 USDC realized PnL", "tx 0x0f15c4e1..."),
        ("Aster L1 venue side", "3 BTC perp round-trips, 6 fills", "userTrades API"),
        ("Net realized on Aster", "+0.0172 gross − 0.0644 fees = −0.0472 USDT", "venue computation"),
        ("Underwriter verdict", "VERIFIED — matched within 0.00% delta", "tx 0x7ee06f9c..."),
    ]
    y = 260
    for tag, val, src in rows:
        d.rounded_rectangle([100, y, 1820, y + 120], radius=8, fill=CODE_BG)
        d.text((130, y + 38), tag, font=font("monob", 30), fill=ACCENT)
        d.text((620, y + 25), val, font=font("body", 28), fill=HIGHLIGHT)
        d.text((620, y + 70), src, font=font("mono", 22), fill=SUBTLE)
        y += 140
    d.text((100, 870), "Same architecture applies to any future Arc-native perp DEX (Synthra, etc.)", font=font("body", 26), fill=TEXT)
    d.text((100, 920), "Grant M2-M5 generalizes this from Aster-specific to multi-venue.", font=font("body", 24), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_10_crucible_bridge():
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


def slide_11_helm_bridge():
    img, d = new_slide()
    draw_header(d, "Composition #4 — Helm × Plinth", "Metric-conditional fee release", accent_width=1200)
    d.text((100, 260), "Why not just bonus-tier the fee?", font=font("body", 30), fill=HIGHLIGHT)
    d.text((100, 310), "Most agent contracts vest based on time. On-chain milestone vesting is a gap.", font=font("body", 26), fill=TEXT)
    d.text((100, 350), "Helm × Plinth makes the agent's reward conditional on a verifiable metric.", font=font("body", 26), fill=TEXT)

    d.text((100, 430), "Flow:", font=font("body", 30), fill=GREEN)
    rows = [
        ("1.", "Sponsor escrows fee + selects a Helm market (e.g., NAV growth >= 5 bps)."),
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


def slide_12_verifier_core():
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


def slide_13_sponsor_pool():
    img, d = new_slide()
    draw_header(d, "PlinthSponsorPool + the honest revenue answer", "Sustainability for the Underwriter network", accent_width=1300)
    d.text((100, 260), "The question evaluators always ask:", font=font("body", 30), fill=HIGHLIGHT)
    d.text((100, 310), '"Where does protocol revenue come from?"  Honest answer: Plinth itself takes nothing.', font=font("body", 26), fill=TEXT)

    d.text((100, 400), "How the Underwriter network sustains:", font=font("body", 30), fill=GREEN)
    rows = [
        ("1.", "Vault investors (or anyone) deposit USDC into a per-vault sponsor pool."),
        ("2.", "Underwriters who post reviews claim a fixed REWARD_PER_REVIEW from the pool."),
        ("3.", "Per-address dedup prevents Sybil drain. Sponsors refill when they want coverage."),
        ("4.", "Plinth takes zero cut. Pure investor -> underwriter market, like Polymarket bounties."),
    ]
    y = 460
    for num, desc in rows:
        d.text((130, y), num, font=font("title", 40), fill=ACCENT)
        d.text((210, y + 5), desc, font=font("body", 26), fill=TEXT)
        y += 70

    d.rounded_rectangle([100, 770, 1820, 870], radius=10, fill=CODE_BG)
    d.text((130, 795), "Deployed:  0xf28a58e71b822e76527032973223e422686068e2", font=font("mono", 26), fill=HIGHLIGHT)
    d.text((130, 835), "10/10 unit tests · dedup + refill-cycle + Sybil-drain coverage verified", font=font("body", 22), fill=SUBTLE)
    draw_brand(d)
    return img


def slide_14_outro():
    img, d = new_slide()
    d.text((W/2, 180), "What the grant funds", font=font("title", 64), fill=TEXT, anchor="mm")
    d.line([(W/2 - 320, 230), (W/2 + 320, 230)], fill=ACCENT, width=4)
    rows = [
        ("M1", "External audit (Trail of Bits / Spearbit) + 5 third-party testnet vaults"),
        ("M2", "Production USYC integration on Base via CCTP — real T-bill yield, not mock"),
        ("M3", "Plinth × Circle Gateway — unified depositor balance across chains"),
        ("M4", "Mainnet deployment + first $5K real TVL + Immunefi bounty"),
        ("M5", "@plinth/verifier-core npm publish + 5 venue adapters + SponsorPool TVL milestone"),
    ]
    y = 290
    for tag, desc in rows:
        d.text((180, y), tag, font=font("title", 42), fill=ACCENT)
        d.text((300, y + 5), desc, font=font("body", 26), fill=TEXT)
        y += 80
    d.line([(200, 760), (W - 200, 760)], fill=DIM, width=2)
    d.text((W/2, 800), "$50,000 USDC across 5 milestones", font=font("title", 42), fill=HIGHLIGHT, anchor="mm")
    d.text((W/2, 855), "github.com/Ccheh/plinth  ·  MIT  ·  no admin keys  ·  audit-grade", font=font("body", 28), fill=TEXT, anchor="mm")
    d.text((W/2, 905), "11 contracts · 176/176 tests · 4 compositions · 2 OSS extractions on chain.", font=font("body", 24), fill=GREEN, anchor="mm")
    d.text((W/2, 960), "Thanks for the consideration.", font=font("body", 26), fill=SUBTLE, anchor="mm")
    draw_brand(d)
    return img


SLIDES = [
    ("slide_01.png", slide_01_title),
    ("slide_02.png", slide_02_overview),
    ("slide_03.png", slide_03_v06_riskguard_overview),
    ("slide_04.png", slide_04_concentration_code),
    ("slide_05.png", slide_05_navfloor_code),
    ("slide_06.png", slide_06_cadence_bridge),
    ("slide_07.png", slide_07_circle_sdks),
    ("slide_08.png", slide_08_charlie_evidence),
    ("slide_09.png", slide_09_aster_pnl),
    ("slide_10.png", slide_10_crucible_bridge),
    ("slide_11.png", slide_11_helm_bridge),
    ("slide_12.png", slide_12_verifier_core),
    ("slide_13.png", slide_13_sponsor_pool),
    ("slide_14.png", slide_14_outro),
]


if __name__ == "__main__":
    for name, fn in SLIDES:
        img = fn()
        path = SLIDE_DIR / name
        img.save(path, "PNG", optimize=True)
        print(f"  saved {name}")
    print(f"\nDone. {len(SLIDES)} slides in {SLIDE_DIR}")
