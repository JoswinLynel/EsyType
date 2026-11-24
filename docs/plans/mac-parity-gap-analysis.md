# Matching the Mac design system: gap analysis and plan

**Date:** 24 November 2026 · **Source:** the "EsyType" design system artifact, built from the macOS app for the Windows team (README, 10 page specs, 17 component specs, tokens) · **Owner's request:** copy every feature, the UI and the design; keep EsyType's own wave colours (amber, white, blue, as in the logo) instead of the Mac's purple; do not change the logo.

## 1. Owner's overrides of the Mac spec

| Mac spec | EsyType keeps |
|---|---|
| Wave gradient `mark-amber` → `mark-mid` (purple `#a78bfa` / `#5a2fc2`) → `mark-blue` | amber `#dfa164` → **white** → blue `#27669a`, as in the logo and today's pill, everywhere the wave appears (heroes, folded pill, empty History, recording pill) |
| App icon with a lavender glow and purple wave middle | the current logo, unchanged |
| "this Mac", ⌥ keys, SF Symbols, Accessibility and Input Monitoring permissions | "this PC", Windows keys, EsyType's own line icons, only the microphone permission (Windows needs no others) |

## 2. What EsyType already has

Every page exists with its core features: Dictation, History (search, retention, CSV/JSON export, not-inserted outcome), Dictionary (words, corrections, import/export, hint switch, built-in product names), Snippets (whole/anywhere, `{date}`), Style (Standard, Professional, Formal, Casual, Concise, Custom; app rules), Scratchpad, Settings, first-run setup, models with SHA-256 checks, backup and restore, themes (Follow Windows, Dark, Light), frosted glass, the recording pill with Undo, the tray.

## 3. Gaps, by area

### 3.1 Window, navigation, shared components (milestone A): done in test build, 24 Nov (`docs/testing/2026-11-24-mac-design-a.md`); Mica and the fold animation still to do
- Window 1120 × 740, minimum 860 × 600; Mica behind the window; transparent title area.
- Sidebar to spec: wordmark; Dictation, **EsyMeet** ("Soon"), **Insights**; eyebrow "YOUR WORDS"; History, Dictionary, Snippets, Style, Scratchpad; Settings at the bottom (never selected); engine chip. Last page remembered.
- **Settings becomes a panel over the window** (82% × 86%, at most 1040 × 760, on a scrim; Esc or a click outside closes it), with its own sidebar: General, Shortcuts, Recording, Speech, Models, History & Privacy, Permissions, About. Opened from the sidebar, the tray and **Ctrl+,**.
- Page title row in Georgia italic 40 px on every page except Dictation.
- **Page hero** on History, Dictionary, Snippets, Style, Scratchpad (and Dictation, not foldable): dark gradient, page glow colour, upright Georgia headline with one italic word, message, hero button and chips, the **voice wave** on the right. **Fold switch** folds it into a 40 px pill beside the title; remembered per page.
- **Speaking wave** on a canvas at 30 frames a second, the spec's formula, paused when the window is hidden or not in front, one still frame with reduced motion.
- Tokens and type scale from the spec (surface, glass, hairlines, radii, shadows; Georgia, Cambria figures, Segoe UI Variable, Cascadia Mono); buttons (accent, pill, danger pill, dark, icon, hero), segmented control, switch rows, filter chips, count badges, empty states, focus ring.

### 3.2 Dictation home and recording pill (milestone B): the Dictation page and usage totals done in test build, 24 Nov (`docs/testing/2026-11-24-mac-design-b.md`). The pill is left as it is (owner, 24 Nov)
- Greeting "Welcome back, <first name>" (new setting: your name).
- Permissions card when the microphone is blocked in Windows' privacy settings.
- Hero "Your voice, typed *anywhere*." with the configured keys and "Set your style".
- Numbers card: total words, words per minute, day streak (opens Insights); "Your words" with dictionary and snippet counts. **Usage totals are kept even when History is off** (owner's decision, 22 Nov): a new daily totals table (migration).
- Recent dictations grouped by day (last 40).
- Today's "Try it", "Last dictation" and Clean/Verbatim cards move: Try it is on the Style page; Clean/Verbatim becomes the Clean card on Style.
- Pill: Acrylic glass capsule (shape A), states Listening, Hands-free (Stop and insert button), Warning "No speech heard", Transcribing (sweep), Typed + Undo, Undone, Copied, Error; **hidden from screen sharing** (switch in Settings ▸ General, on by default).

### 3.3 Insights (milestone C): done in test build, 24 Nov (`docs/testing/2026-11-24-mac-design-c.md`)
- Four tiles counting up: words dictated, words per minute, time saved (with "How?"), meetings transcribed ("—", comes with EsyMeet).
- Words per day: 7 / 30 / 90 days, average line.
- Activity heatmap, 18 weeks; streak, busiest day, words a day when active.
- This week: day bars and the split by kind of app (from the program's name only, never window titles).
- Typing speed stepper (10–150 wpm) used for Time saved.

### 3.4 History, Dictionary, Snippets, Style, Scratchpad (milestone D): built and committed locally, 24 Nov (`docs/testing/2026-11-24-mac-design-d.md`); four key-pressing suites still to run on an idle PC
- **History:** hero with counts and "not inserted" chip; filter chips (All, Today, This week, Not inserted, six most-used apps); day cards; details line (app, words, seconds spoken, language); Not inserted badge with tooltip; hover Copy, Edit, Delete (also as keyboard actions); Edit sheet; search matches highlighted; empty state with a small wave.
- **Dictionary:** hero with latest words; Word | Correction segmented form; entries gain **language, category, description and an on/off switch** (migration); conflict warning; Edit sheet; **import preview** before anything changes; "Show the list (29 names)".
- **Snippets:** hero chips; {date} {time} {day} buttons; 4,000-character counter; mode radios; entries gain **category and on/off** (migration); clash warning; Edit sheet.
- **Style:** six style cards with live examples and the default marked; app rules with app icons and "Not installed"; Custom style switches and Full stop segmented; Clean card with five switches; Try it grid of six results.
- **Scratchpad:** two panes (list + editor), .txt and .md export, status line.

### 3.5 Settings content (milestone E)
- **General:** theme segmented; open at login; hide the pill from screen sharing; your name; shown in meetings as.
- **Shortcuts:** push to talk as a single key (Right Alt, Right Ctrl…, Off); hands-free combination; double-tap for hands-free; Esc, Paste last, Undo key caps.
- **Recording:** microphone with a missing-mic warning; **Test your microphone** with live level; **start and stop sounds** with volume (sounds generated in code, nothing downloaded); warn when no speech is heard (3/5/10 s); maximum recording length (5/10/20/30 min).
- **Speech:** model; **language** (auto-detect or one) and **translate to English**, offered only with the multilingual Small model already in the catalogue (Tiny and Base are English-only). No new model.
- **Models:** one card per model with size, Download / progress / Cancel / Installed / Remove.
- **History & Privacy:** "Nothing leaves this PC.", keep history, remember which app, saved count and Clear History.
- **Permissions:** microphone (Windows privacy setting).
- **About:** icon, version, "Private voice typing by EsyAI. Make Life Esy.", acknowledgements with licence texts.

### 3.6 Onboarding (milestone F)
640 × 500, nine steps with progress capsules: Welcome; microphone; your name; light or dark; typing into apps (Windows needs no permission: a short explanation); your shortcut; your computer and the recommended model; download with verification; Try it.

### 3.7 EsyMeet
Sidebar entry with "Soon" and a page saying it isn't built yet. The meeting feature itself stays in the approved plan (Phases 8–10).

## 4. Order and how each milestone is finished

A → B → C → D → E → F. Each: test build only, the existing suites updated to the new layout and passing, new checks for what was added, contrast audit in both themes, dictation time against the previous build (separate worktree), a test record, a commit, then a release only with the owner's approval. Database changes are migrations; nothing is reset.

## 5. Nothing downloaded

No new SDK, model or package. Icons are drawn in EsyType's own line style (the Mac spec suggests Fluent System Icons; that would be a download, so it is not used unless the owner asks). Sounds are generated in code.
