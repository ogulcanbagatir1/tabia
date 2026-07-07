# Tabia — Design & App Store Brief

> Hand this to Claude (or any designer) to produce the **app icon**, **App Store screenshots**, and **App Store listing copy**. It captures what the app is, who it's for, and the exact visual language it already uses so everything stays consistent.

---

## 1. One-liner

**Tabia — a native Mac chess studio for analyzing your games and building an opening repertoire that sticks.**

## 2. Elevator pitch

Tabia is a premium macOS app for chess players who are serious about improving. It brings four things that usually live in separate tools into one fast, beautiful native app:

- **Analysis** — a full engine board (Stockfish, Leela/Lc0, or Lichess cloud) with an evaluation bar, multi-line analysis, and one-click full-game review that grades every move (Brilliant → Blunder) with an accuracy score and an eval graph.
- **Opening Explorer** — browse any position against the **Lichess Masters** database *or* against your own game library, with win/draw/loss stats and notable games.
- **Repertoire trainer** — build your own opening repertoires as trees, then **drill them with spaced repetition**, get coverage-gap reports, and catch where you deviate from your own lines.
- **Your games, unified** — sync your **Chess.com** and **Lichess** accounts, import PGN databases, and explore rich stats (rating charts, results by color, performance by time of day, streaks, top openings).

All local, all native, no web wrapper. It looks and feels like it belongs on macOS.

## 3. The name

**"Tabia"** (also spelled *tabiya*) is a real chess term: a well-known standard position reached at the end of a long, established opening sequence — the launchpad from which the real game begins. It's the perfect name for an app about **openings, preparation, and starting every game from a position of strength.** The name should feel considered and insider-ish, not generic.

- Pronounced roughly "TAH-bee-ah."
- Short, ownable, no chess cliché (no "master", "pro", "genius", crown emojis).

## 4. Who it's for

- Improving club players and enthusiasts (roughly 1200–2200) who study on a Mac.
- People who already use Chess.com / Lichess to *play*, and want a serious desktop tool to *study*.
- Repertoire nerds who want to build and memorize opening lines.
- Secondary: coaches and stronger players who want fast local analysis without a browser.

**Not** a place to play live games against others — it's a study/analysis studio.

## 5. Positioning vs. the field

| Tool | What it is | How Tabia is different |
|---|---|---|
| Chess.com / Lichess apps | Play + basic analysis, web-first | Tabia is native, faster, study-focused, and unifies *both* your accounts |
| ChessBase | Powerful but heavy, Windows-first, dated UI | Tabia is Mac-native, modern, approachable, and costs a fraction |
| Decode/DecodeChess, Chessis | Single-purpose analyzers | Tabia adds repertoire training + database + explorer in one app |

**Elevator differentiator:** *"The one Mac app where you analyze your games, explore openings, and train your repertoire — beautifully, and all in one place."*

## 6. Brand personality

Pick 5 adjectives to design against: **Native · Focused · Premium · Calm · Expert.**

- Feels like an Apple pro tool (think Things, Reflect, Craft, Linear-for-Mac vibes), not like a gaming app.
- Confident and quiet, not loud or gamified. No badges, no confetti, no cartoon mascots.
- Dark, dense, and information-rich — but never cluttered.

## 7. Visual language (already in the app — match it)

The app ships a "liquid glass" dark design system. Use these tokens so marketing assets match the product exactly.

**Surfaces & mood**
- Base background: near-black **`#0E0E14`** with *very* subtle radial glows — cool blue-gray top-left (`#1A2030`), faint purple bottom-right (`#221828`).
- Panels use frosted/translucent "glass" (ultra-thin material) with hairline light borders and soft shadows.
- Overall: dark, deep, glassy, premium. Light mode exists but the **hero/brand look is dark.**

**Accent**
- Apple system blue — **`#0A84FF`** (dark) / **`#007AFF`** (light). This is the single brand accent. Use sparingly for emphasis.

**Chess board (signature element)**
- Classic Lichess-style green board: light **`#EBECD0`**, dark **`#739552`**, last-move highlight **`#F6F669`**. (The app also ships 38 board themes + 32 piece styles, but green-on-cream is the default hero.)

**Move-quality color scale** (useful for screenshots that show analysis)
- Brilliant `#1ABF66` · Great `#3387DE` · Best `#8CCC59` · Book `#A68C66` · Inaccuracy `#EDA619` · Mistake `#E87623` · Blunder `#D62E2E`.

**Typography**
- Apple **San Francisco** (system font) throughout. Titles semibold/bold, dense mono for notation/FEN. Keep marketing type in SF or a close, modern grotesque.

**Geometry**
- Continuous rounded corners (radii 6/8/12/20). Generous but tight spacing. Hairline separators, not heavy lines.

## 8. Deliverable A — App icon

**Current mark:** a minimalist glyph of **four rounded diamonds arranged in a 2×2 rotated square** — essentially a tiny abstract chessboard / "tabiya" tile — rendered dark-charcoal-on-black with a subtle bevel. It's elegant and "stealth premium."

**Keep:** the tabiya/rotated-2×2-diamond mark as the brand symbol, the premium dark feel, the macOS rounded-square (squircle) shape.

**Improve / explore (the current all-black-on-black reads as invisible on the App Store grid and Dock):**
1. **Legibility at small sizes** — the mark must be instantly readable at 32px and 16px. Increase contrast between the diamonds and the background.
2. **A touch of brand color** — consider one accent diamond (or a subtle blue→purple sheen across the mark) using the system-blue accent, so it pops on a white store background while staying premium.
3. **Depth** — a soft top-down light, subtle inner glow, or glassy sheen consistent with the app's "liquid glass" look. Avoid literal chess pieces (crowns, knights) — the abstract tabiya mark is more distinctive and ownable.
4. Deliver the full macOS icon set (16→1024, @1x/@2x) on the standard squircle with correct safe margins.

**Give me 3 directions:** (a) refined dark/stealth, (b) dark with a single accent-blue diamond, (c) glassy gradient (blue→indigo) mark on deep charcoal. I'll pick one.

## 9. Deliverable B — App Store screenshots

Mac App Store needs 16:10 landscape shots (e.g. 2880×1800). Produce a **cohesive set of 5–6**, each on the dark glass backdrop with a short bold caption + one line of subtext. Suggested sequence and captions:

1. **Analysis screen (hero).** Board + eval bar + engine lines + move list. Caption: **"Analyze every move."** Sub: "Stockfish, Leela, or cloud — with instant accuracy and an eval graph."
2. **Full-game review.** Accuracy cards + move classifications + eval graph. Caption: **"Know exactly where you went wrong."** Sub: "Brilliant to Blunder, every move graded."
3. **Opening Explorer.** Lichess Masters stats + notable games. Caption: **"Explore openings like a master."** Sub: "Millions of master games, or your own library."
4. **Repertoire trainer.** Repertoire tree + drill/spaced-repetition. Caption: **"Build a repertoire that sticks."** Sub: "Train your lines with spaced repetition."
5. **Your games, unified.** Chess.com + Lichess stats dashboard (rating chart, W/D/L donut). Caption: **"All your games, one place."** Sub: "Sync Chess.com and Lichess. See your real trends."
6. **Themes (optional).** Grid of board/piece themes. Caption: **"Make it yours."** Sub: "38 boards, 32 piece sets, light or dark."

Style: real UI (not fake mockups), captions in SF Bold, dark backdrop, accent-blue used sparingly. Keep them consistent — same type treatment and margins across all.

## 10. Deliverable C — App Store listing copy

- **App name:** `Tabia`
- **Subtitle (≤30 chars):** options — `Chess analysis & repertoire` · `Study chess like a pro` · `Analyze. Explore. Train.`
- **Promotional text (≤170 chars):** "Analyze your games with a top engine, explore openings from millions of master games, and drill your repertoire with spaced repetition — all in one native Mac app."
- **Keywords:** chess, analysis, stockfish, opening, repertoire, PGN, database, lichess, chess.com, trainer, engine, eco, study, coach.
- **Description:** expand section 2 into ~4 short paragraphs (Analyze / Explore / Train / Your games), then a bulleted feature list, then a "Built native for macOS" closer. Keep it benefit-led, not a feature dump.
- **Category:** primary **Games › Board** (or **Education**); consider Board.
- **Tone:** confident, clean, no hype words ("revolutionary", "ultimate"). Let the features speak.

## 11. Do's and don'ts

**Do:** lean into the dark liquid-glass premium look · keep the green board as a recognizable anchor · use system blue as the *only* accent · show real UI · keep everything calm and Apple-native.

**Don't:** use crown/knight clichés or gold "champion" styling · gamify (badges, confetti, cartoon pieces) · use heavy gradients or neon · make it look like a web app or a Windows tool · overcrowd the icon.

---

### Quick facts sheet (for reference)
- **Platform:** macOS 15.5+, native SwiftUI, App Sandbox on. Version 1.0.0.
- **Bundle id:** `com.ogulcan.Tabia`.
- **Core features:** engine analysis (Stockfish/Lc0/Lichess cloud), full-game review with move grading + accuracy, opening explorer (Lichess Masters + personal library), repertoire builder + spaced-repetition drilling + coverage gaps, game database with folders and PGN import/export, Chess.com + Lichess account sync with stats dashboards, 38 board themes + 32 piece sets, light/dark.
- **Vibe words:** native, focused, premium, calm, expert.
- **Accent:** `#0A84FF`. **Board:** `#EBECD0` / `#739552`. **Background:** `#0E0E14`.
