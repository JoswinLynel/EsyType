# Mac design, milestone A: window, sidebar, Settings panel, heroes and the wave. Test record

**Date:** 24 November 2026 · **Plan:** `docs/plans/mac-parity-gap-analysis.md` (milestone A) · **Build:** e2e test build only · **Production: not changed** (0.4.0 stays installed) · **Nothing downloaded; no dependency added**

## 1. What was built

- **Window:** 1120 × 740 on first open, minimum 860 × 600.
- **Sidebar to the Mac design:**
  - the wordmark
  - Dictation, **EsyMeet** (with "Soon") and **Insights**
  - the eyebrow "YOUR WORDS", then History, Dictionary, Snippets, Style and Scratchpad
  - Settings at the bottom; it opens the panel and is never shown as selected
  - the engine chip, which opens Models
  - **the last page opened comes back** after a restart
- **EsyMeet page:** says it isn't built yet. **Insights page:** a placeholder until milestone C.
- **Settings is a panel over the window**, not a page:
  - 82% × 86% of the window, at most 1040 × 760, on a dimmed backdrop
  - its own sidebar: General, Shortcuts, Recording, Speech, Models, History & Privacy, Permissions; then About under "ESYTYPE"
  - version and "On this PC" at the bottom
  - section titles in Georgia italic; the last section is remembered
  - **Esc** or a click outside closes it
  - opened from the sidebar, the engine chip, the new tray item **Settings…** and **Ctrl+,**
- **Settings sections:**
  - **General:** the theme as a segmented control (Follow Windows · Dark · Light); start with Windows.
  - **Speech:** the Clean options and processor threads.
  - **Models:** the model cards and the model folder.
  - **Permissions** (new): whether Windows' microphone privacy switch lets EsyType hear you, with "Open Windows settings" when it is blocked.
  - All other settings are unchanged, only regrouped.
- **Page heroes** on Dictation, History, Dictionary, Snippets, Style and Scratchpad, with the Mac's headlines ("EsyType spells the way *you* do.").
  - **Look:** a dark banner in both themes, with the page's glow colour and a hero button where the Mac has one (Add new word, New snippet, New note, Set your style).
  - **Fold switch:** folds a hero into a small pill beside the page title, remembered per page. The Dictation hero doesn't fold.
- **The voice wave:** the Mac's formula, drawn on its own canvas at 30 frames a second.
  - **Colours:** EsyType's amber → white → blue, as in the logo, at your request (the Mac uses a purple middle).
  - **When it moves:** it stops when EsyType is not in front, is hidden, or Windows asks for reduced motion.
- **Colours and type from the Mac tokens:**
  - **Surfaces:** canvas, surfaces, hairlines, accent tint, card radius 20 and shadows.
  - **Fonts:** Georgia for titles and headlines; Segoe UI Variable for everything else; Cascadia Mono for key caps.
  - **Buttons:** the main action of a card is now an accent capsule.
  - **Dictation:** greets "Welcome back".

### Where EsyType keeps its own values

| Mac design | EsyType | Why |
|---|---|---|
| Wave middle `#a78bfa` / `#5a2fc2` | white | your request: the logo's colours |
| Tertiary ink at 56% (light) | 64% | 56% fails WCAG AA on the cards; EsyType's contrast check covers every text |
| Switch 38 × 22 | 38 × 22 track in a 32 px high target | EsyType's rule: every button at least 32 px high |
| Warning `#a16207` (light) | `#8a5206` | the amber "May feel slow on many PCs" chip was 4.06:1 in the Models section; now passes AA |
| Fluent System Icons | EsyType's own line icons | Fluent would be a download |

## 2. Tests (test build, own profiles; nothing typed outside test windows)

| Suite | Result |
|---|---|
| Theme | **64 of 64**: AA contrast on 8 pages and all 8 Settings sections in both themes; the dialog; the wave drawn in the logo colours and still when not in front; the hero fold kept after a restart; light and dark settings kept after a restart; glass on and off |
| Navigation | **17 of 17**: every page, EsyMeet "Soon", keyboard, every Settings section, Esc closes the panel, Ctrl+, opens it at the last section |
| Polish | **25 of 25** (every button at least 32 px on every page and Settings section) |
| Data | **27 of 27** |
| First run | **32 of 32** |
| History UI | **33 of 33** |
| Forced colours (high contrast) | live region PASS; screenshots checked |
| Unit tests | **63 of 63** |

**Failures along the way, all fixed:**
- **Test steps for the new layout:** Settings now opens as a panel and closes with Esc, so the suites open it through a new helper. The helper presses Esc only after making sure the test build's own window is in front.
- **One real contrast miss:** the light amber; fixed as in the table above.
- **First run stopped once** without finding its shortcut box; on the rerun it passed 32 of 32.

## 3. Dictation time and the wave's cost

Alternating blocks of 3 dictations, 8 blocks per build (A B B A, then B A A B B A A B), Base, 4 threads, on mains. A = the pre-6.1 test build (which timed the same as 6.1 yesterday); B = this build.

| | Pre-6.1 | Milestone A |
|---|---|---|
| Median (range) | 3.9 s (3.5–5.8), 18 runs | 4.2 s (3.5–4.9), 18 runs |
| Block medians | 3.8, 3.7, 4.1, 5.2, 3.7, 4.1 | 4.0, 4.3, 4.5, 4.4, 4.2, 3.8 |

- **A slow day:** both builds were far slower than yesterday's 2.15 s on the same clip.
- **Not shown to be a regression:** the new build was higher in 4 of 6 block pairs, but the ranges overlap and the spread is large.
- **The only new code that runs while EsyType is open is the wave, so it was measured** (CPU used by EsyType's whole process tree over 10 s):

| State | Pre-6.1 | Milestone A |
|---|---|---|
| Hidden in the tray (as in the timing runs) | 0.02–0.03 s | 0.00–0.03 s |
| Open on Dictation, behind another window | 0.02–0.03 s | 0.02–0.03 s |
| Open on Dictation, in front (wave moving) | 0.00 s | 1.2–1.7 s (about 12–17% of one core) |

**The wave has no route to slowing a dictation into another app:** it stops whenever EsyType is not in front.
- **Re-time before release:** the dictation times should be measured again on a quiet day.
- **Tried, didn't help:**
  - **Fewer redraws:** building the gradient once per size changed nothing.
  - **Fade:** drawing it in the canvas instead of a CSS mask saved about 15%, and was kept.
  - **Own layer:** putting the canvas on its own layer made it worse, and was undone.

## 4. Not done yet (later milestones)

- Insights itself (milestone C).
- **Dictation home** (milestone B): your name, the numbers card and recent dictations.
- **Recording pill states** (milestone B).
- **Hero chips with live counts** (milestone D).
- **Settings rows in the Mac's row style:** the sections still use EsyType's existing controls (milestone E).
- **Onboarding** (milestone F).
- **Mica behind the window:** not attempted in this step.
- **Folding animation:** the fold is immediate, without the Mac's spring.
