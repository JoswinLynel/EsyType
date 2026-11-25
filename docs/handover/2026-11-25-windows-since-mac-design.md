# EsyType for Windows: everything done since the Mac design, for the Mac build

**From:** the Windows build of EsyType (Tauri 2, Rust, React). **Period:** 24–25 November 2026. **Starting point:** the Mac design-system artifact ("Design System"), which the owner asked the Windows app to copy in full.

**What this is:** every change made in that period, in order:
- what was built
- the owner's decisions that the Mac build should follow too
- what is Windows-only (with the Mac equivalent where there is one)
- **the tests run after every phase, with their results**, as the bar for the Mac build

Full Windows records are in `docs/testing/` (file names in each section).

---

## 0. Owner decisions that apply to both platforms

| Decision | Detail |
|---|---|
| **Wave colours** | The voice wave uses the **logo colours: amber → white → blue** (`#dfa164` → `#ffffff` → `#27669a`), not the artifact's purple middle (`#a78bfa` / `#5a2fc2`). The logo itself is unchanged |
| **Recording pill** | **A capsule** (fully rounded ends) with a **light frost**: mostly dark, a faint top sheen, a thin light edge.<br>The wave inside is unchanged and vertically centred.<br>A frosted rounded rectangle was tried on Windows and rejected as "boxy" (25 Nov). On the Mac a true vibrancy capsule is possible; keep the frost light |
| **Local only** | No cloud, no accounts, no extra AI models or downloads. AI enhancement is deferred |
| **Insights totals survive History** | Usage totals are kept when History is off or trimmed; "Delete all data" removes them |
| **Sounds** | Start and stop sounds exist but are **off by default** |
| **Languages** | Language choice and "Translate to English" **only with the multilingual (Small) model**; greyed out for English-only models |
| **One-key push to talk** | Right Ctrl, Right Alt or Right Shift (on the Mac: right Command, right Option or right Shift); double-tap for hands-free, one tap to stop. Off by default |
| **Not built, by choice** | Hiding the pill from screen sharing (**skipped**); the update notification (**deferred** until the owner asks); EsyMeet speaker separation (needs a model: separate approval) |
| **Accessibility rules kept over the artifact** | Every clickable target at least 32 px high; all text WCAG AA in both themes (tertiary ink 64%, not 56%; light-theme warning `#8a5206`, not `#a16207`); reduced motion stops count-ups and animations |

---

## 1. Milestone A: window, sidebar, Settings panel, page heroes, the wave

Record: `docs/testing/2026-11-24-mac-design-a.md`.

**Built:**
- **Window:** 1120 × 740 on first open, minimum 860 × 600.
- **Sidebar:**
  - the wordmark
  - Dictation, EsyMeet ("Soon") and Insights
  - the "YOUR WORDS" heading, then History, Dictionary, Snippets, Style and Scratchpad
  - Settings at the bottom (it opens the panel and is never shown as selected)
  - the engine chip ("Local · Base · 4 threads"), which opens Models
  - the last page is remembered across restarts
- **Settings is a panel over the window:** 82% × 86% of the window, at most 1040 × 760, on a dimmed backdrop.
  - **Its own sidebar:** General, Shortcuts, Recording, Speech, Models, History & Privacy, Permissions, then About under "ESYTYPE". Version and "On this PC" at the bottom.
  - **Closing:** Esc or a click outside closes it.
  - **Opened from:** the sidebar, the engine chip, the tray's "Settings…" and Ctrl+, (⌘, on the Mac). The last section is remembered.
- **Permissions section:** shows whether the OS lets EsyType use the microphone, with a button to the OS settings page.
- **Page heroes:**
  - **Where:** Dictation, History, Dictionary, Snippets, Style and Scratchpad, with the artifact's headlines.
  - **Look:** a dark banner in both themes, the page's glow colour and a hero button.
  - **Fold switch:** folds the hero into a small pill beside the title, remembered per page. Dictation's hero doesn't fold.
- **The voice wave:** the artifact's formula on a canvas at 30 fps, in the logo colours. It stops when the app isn't in front, is hidden, or reduced motion is on.
- **Tokens:** canvas, surfaces, hairlines, accent tint, card radius 20, shadows. Titles in Georgia (the serif); body in the system font; key caps in the mono font.

**Windows-only:**
- Window memory lives in `ui-state.json` in the data folder, not webview storage.
- Mica behind the window: not done.

**Tests after A:**

| Suite | Result |
|---|---|
| Theme (AA contrast on 8 pages and 8 Settings sections, both themes; wave colours; wave still when not in front; fold remembered; theme kept after restart; glass on/off) | 64/64 |
| Navigation (every page, EsyMeet "Soon", keyboard, every Settings section, Esc closes, Ctrl+, reopens at the last section) | 17/17 |
| Polish (every button ≥ 32 px on every page and section) | 25/25 |
| Data, first run, History UI | 27/27, 32/32, 33/33 |
| Unit tests | 63/63 |
| Wave CPU (whole app, 10 s) | 12–17% of one core only while in front and moving; 0 when hidden or behind |
| Dictation time | No regression shown. Re-timed on a quiet PC in B: 2.15 s against 2.2 s before |

**Found and fixed:** the light amber warning failed AA (4.06:1). Now `#8a5206`.

---

## 2. Milestone B: Dictation page and usage totals

Record: `docs/testing/2026-11-24-mac-design-b.md`.

**Built:**
- **Greeting:** "Welcome back, <first name>". Your name is an optional field in Settings ▸ General ▸ About you.
- **Microphone card:** only when the OS blocks the microphone, with "Allow…". It is checked again when the window comes to the front and every 2 s while blocked.
- **Hero:** "Your voice, typed *anywhere*." with the user's shortcuts and "Set your style".
- **Numbers card:**
  - total words ("12.4K"), words per minute and the day streak; opens Insights
  - "N in your dictionary · N snippets"; opens Dictionary
- **Recent dictations:** the last 40, grouped Today / Yesterday / date. A search button opens History. With History off, the page says the totals still count.
- **Moved:** Clean or Verbatim moved to the top of Style.
- **Removed:** the old "Try it" box. Practice is now a setup step and the Scratchpad.
- **Usage totals:** a `usage_days` table (day, dictations, words, seconds of speech; numbers only).
  - Filled once from existing History on upgrade.
  - Kept by "Delete all history"; removed by "Delete all data".
  - **Streak:** consecutive days ending today, or yesterday if you haven't dictated yet today.
  - **Words per minute:** words ÷ minutes of speech.

**Tests after B:**

| Suite | Result |
|---|---|
| Unit (streak; backfill from History; totals kept or removed by the two deletes) | 64/64 |
| Home, new: greeting with and without a name; 12.4K, 124 wpm, 3-day streak from seeded data; counts; recent list order; no mic card when allowed; links; with History off a real dictation adds to totals and saves no text; the table holds numbers only | 12/12 |
| Full regression: theme, navigation, polish, data, first run, settings recovery, History UI, Dictionary, Snippets, Scratchpad, Style, Clean, Try it, History, Undo, slow paste, insertion, Undo in apps, spacing | All passed |
| Dictation time (alternating A B B A blocks, 12 runs each) | 2.15 s against 2.2 s before: no difference |

---

## 3. Milestone C: Insights

Record: `docs/testing/2026-11-24-mac-design-c.md`.

**Built:**
- **Four tiles, counting up:**
  - Words dictated ("since <first day>")
  - Words per minute
  - **Time saved** at the user's typing speed, with "How?" showing the sum: typing time − speaking time − processing time
  - Meetings transcribed ("—" until EsyMeet)
- **Words per day:** 7 / 30 / 90 days, with the total and a dashed average line.
- **Activity grid:** 18 weeks, Monday first, shaded by share of the busiest day.
  - Hover text per day ("Thu 15 Oct: 1,000 words"); one screen-reader summary for the whole grid.
  - Streak, busiest day, and words a day when active.
- **This week:** daily bars (today bold) and the split by kind of app, with percentages.
- **Typing speed:** a stepper, 10–150 wpm in steps of 5, default 40.
- **Database:**
  - processing time per day
  - `usage_apps` (day, kind, words)
  - **Kinds come from the program's file name only, never window titles:** Email, Chat, Documents, Code, Notes, Browser, Other. "Note which program" off counts everything as Other.

**Tests after C:**

| Suite | Result |
|---|---|
| Unit (app kinds match for every known program; backfill; this week's split) | 65/65 |
| Insights, new, against seeded data with known answers: tiles (3,550 words, 150 wpm, "1 h 5 min" at 40 wpm, "—"); "How?"; 7/30/90 bars, totals and averages; 18 × 7 grid, busiest day, hover text, screen-reader summary; streak; week split; typing speed + saves and Time saved follows | 15/15 |
| Theme (AA on Insights, both themes) and the full regression | All passed |
| Dictation time | 2.15 s against 2.1 s: no regression |

**Found and fixed:** the "How?" link was 20 px high; it now has a 32 px target.

---

## 4. Milestone D: History, Dictionary, Snippets, Style, Scratchpad

Record: `docs/testing/2026-11-24-mac-design-d.md`.

**Built:**
- **History:**
  - **Banner:** live chips ("N dictations", "N words", "N not inserted").
  - **Summary line:** Privacy settings, CSV/JSON export and an outlined "Delete all" that names the count.
  - **Filters:** All, Today, This week, Not inserted, and the top 6 programs.
  - **Day groups:** "TODAY", "YESTERDAY" or the full date, each with a count.
  - **Each row:** a time and program tile; the text up to 8 lines, with search matches in accent; details ("WINWORD.EXE · 5 words · 4 s spoken · Clean, Professional"); a "Not inserted" badge.
  - **Row actions:** Copy, Edit and Delete as icon buttons, shown on hover or focus and always available to screen readers.
  - **Edit:** a sheet. **Empty state:** "Nothing here yet" with a small wave.
- **Dictionary:**
  - Banner with "Add new word" and the latest 4 words as chips.
  - Add form: Word | Correction, "When I say → Write".
  - Rows: spoken → written, category, note, use count; an on/off switch per entry; a warning when an earlier entry already uses the same words.
  - Edit sheet: type, words, category (Brand, Technical, Abbreviation, Name, Other or your own), note, on/off.
  - **Import shows a preview** (to add, already there, skipped and why) and changes nothing until Import.
- **Snippets:**
  - Banner chips ("my email signature", "{date}").
  - Text box limit 4,000 characters, turning red at the limit.
  - Rows: the trigger in quotes with a Whole or Anywhere badge, the first line, category, uses; an on/off switch; a clash warning when one trigger contains another.
  - Edit sheet; import with preview.
- **Style:**
  - Banner chips (Professional, Casual, Concise) set the default.
  - Clean or Verbatim.
  - **Six style cards** with the same example sentence in each style; a click sets the default.
  - App rules as rows.
  - Custom style as four switches ("Full stop at the end": As spoken · Always · Never).
  - **"Clean, before any style" card** with Clean's two options.
  - Try it: six result cards.
- **Scratchpad:** banner with the note's word count; "2 minutes ago" times; .txt and .md export; outlined Delete.
- **Database:** category, note and on/off for Dictionary entries; category and on/off for snippets. **Switched-off entries are kept and exported but not used while dictating.**

**Tests after D:**

| Suite | Result |
|---|---|
| Unit (categories and on/off; switched-off entries kept but unused; an import's dry run changes nothing; History filters and counts) | 66/66 |
| Dictionary / Snippets / Style, including the import preview changing nothing until Import | 18/18, 14/14, 12/12 |
| History UI: banner count; Today shows only today's; an app chip shows only that program's; All grouped by day; "Delete all" names the count | 37/37 |
| Theme, navigation, home, Insights, data, settings recovery, Clean, Try it, History, slow paste, Undo, insertion, spacing | All passed |
| Polish, Scratchpad, first run, Undo in apps (key-pressing; need an idle PC) | Passed later with E/F: 25/25, 15/15, 34/34, 8/8 |

**Found and fixed:**
- **A class-name clash:** the export buttons used the pill's class name and stretched across the window.
- **Arrow keys:** Up/Down between rows now keep to the same button.

---

## 5. Milestones E and F, and the pill

Record: `docs/testing/2026-11-24-mac-design-e-f.md`.

**Settings (E):**
- Rows in the artifact's style in every section.
- **General:** theme; About you (name, typing speed); open at login.
- **Shortcuts:** the usual shortcuts, plus **one-key push to talk**.
  - Hold to dictate. Two quick taps (within 400 ms) start hands-free, where the pill says "Hands-free" and shows Stop. One tap stops it. A short tap (under 400 ms) records nothing.
  - **The key is swallowed** while it is the push-to-talk key, so a held right Alt won't open menus.
  - **Windows:** a low-level keyboard hook on its own thread. **Mac:** a CGEventTap on flagsChanged, which needs Input Monitoring / Accessibility permission.
- **Recording:**
  - Start and stop sounds: two short generated tones, rising and falling; off by default; volume slider with a preview.
  - Maximum recording length: 5 / 10 / 20 / 30 minutes. A forgotten dictation is stopped and typed.
- **Speech:**
  - Language (Detect automatically, or one of about 30) and Translate to English, only with the Small model.
  - Clean, Style and the Dictionary apply only to English or translated text.
- **About:** icon, version, tagline, esyai.co.uk and acknowledgements.

**First-run setup (F):** ten steps.
- **The steps:** Welcome (with the wave) · Privacy · "What should EsyType call you?" · "Light or dark?" · Speech model · Download · Microphone · Shortcut · Try it · Ready.
- **Layout:** small progress capsules; Back on the left, the main action on the right.

**The pill:**
- **Content:** a status dot (red recording, green typed, amber warning), the wave, a timer and ✕. Then:
  - Hands-free: the label and a Stop button
  - after typing: Copy, Original / Use original and Undo
- **Look, final (25 Nov):** capsule, light frost, wave unchanged and centred.
- **Windows history, for awareness:**
  1. A frosted rounded rectangle using Windows' Acrylic. Windows can't blur a capsule, so it was a rectangle; the owner found it boxy.
  2. A dark box drawn around the pill in 0.4.0 came from the page's dark colour scheme; fixed.
  3. The final capsule is a dark translucent tint on a transparent window. On Windows, 94% opacity was needed for the frost to look light; 84% showed too much through.

**Tests after E and F (run with the PC idle; keys only into the tests' own windows):**

| Suite | Result |
|---|---|
| Unit (one-key decisions; tones; new setting defaults) | 68/68 |
| **Keys, new:** hold right Ctrl dictates and types; a short tap records nothing; the key is swallowed (Right Ctrl+Q types a plain q); a double tap shows "Hands-free" and keeps listening after release; one tap stops and types; the maximum length (7 s in the test) stops and types; sounds on cause no audio errors; double-tap off means two taps record nothing; Language greyed out for Base; Shortcuts shows the one-key choice | 11/11 |
| First run (including Name, Theme and key capture) | 34/34 |
| Polish (every button ≥ 32 px) | 25/25 |
| Every other suite (theme 64/64 and the full regression) | All passed |
| Dictation time (A B B A, 12 runs each) | 2.1 s against 2.1 s: no regression |
| **Not tested** | Hearing the sounds (needs a person); translation end to end (no non-English recordings); right Alt and right Shift (only right Ctrl pressed) |

**Found and fixed:**
- **A real fault:** the Acknowledgements toggle in About was 20 px high; it now has a 32 px target.
- **Tests out of date:** they still looked for the old History list. Page text is now read from list items too.

---

## 6. Release 0.5.0 (Windows), 25 Nov

- **Installer:** built and installed over 0.4.0 after a checked backup.
- **Data:**
  - Database updated in place from v6 to v9, integrity checked.
  - History and settings unchanged; Insights totals filled from History.
- **README:** six new screenshots with demo content (never real dictations) and the real default shortcuts.
- **For the Mac release, the same checks:**
  - backup first, and restore the backup into a test profile to prove it
  - migrate in place, never reset; byte-compare settings; count History before and after
  - start-at-login entry still set

---

## 7. EsyMeet: phase 8.0, can the engine keep up with a meeting?

Record: `docs/testing/2026-11-25-esymeet-engine-study.md`.

**Question:** Whisper processes a 30 s window, so a 5 s piece costs as much as 30 s (about 2.1 s on this laptop). Live meeting text would then lag 10–20 s. The "short window" (`audio_ctx`) is much faster, but earlier it repeated whole sentences.

**Result (220 synthetic clips + 10 LibriSpeech, Base):**

| Setting | Ordinary | LibriSpeech | Product names exact | Time per clip |
|---|---|---|---|---|
| Normal window | 0.8% | 3.5% | 148/250 | 2.04 s |
| Short window, margin 64 frames | 19.2% (repeats) | 3.7% | 135 | 0.27 s |
| **Short window, margin 256 frames (5.1 s)** | **0.8%** | **3.4%** | 141 | 0.42 s |

- **Cause of the repeats:** too little room after the speech. With ≥ 128 frames of margin the repeats are gone.
- **Ruled out:** one segment, no timestamps and a token limit all made things worse.
- **Speed for meeting pieces** (2 threads, short window): 5 s → 0.78 s, 10 s → 1.33 s, 15 s → 1.87 s. Both sides of a call fit with cores to spare.
- **Decision:**
  - **Meetings:** use the short window with a 256-frame margin.
  - **Dictation:** keep the normal window. The short window would make it about 4× faster, but it spells 7 fewer product names out of 250; that's the owner's call later.
- **Mac:** the same applies to whisper.cpp on the Mac (`audio_ctx` = clip length + 256 frames). Re-measure, since Apple Silicon is faster.
- **Still open:** confirm on the owner's own voice recordings.

---

## 8. EsyMeet: phase 8.1, capturing the microphone and the computer's sound

Report: `docs/testing/2026-11-25-esymeet-capture-study.md`. Architecture: `docs/architecture/esymeet-capture.md`. **Not in the app yet**; built and tested as a separate module and probe.

**Design (portable ideas):**
- **Two separate tracks**, "You" (microphone) and "Others" (the computer's sound), each 16 kHz mono, on **one shared timeline**.
- **Placement:** each chunk is placed by the **OS's capture timestamp** of its first sample, not by when it arrived.
- **Silence:** while a source sends nothing, its file is kept up to the clock with silence, so both tracks always advance.
- **Overrun / glitch notices from the OS are counted, never a reason to reopen a healthy stream.**
- **Device changes:**
  - Check the default devices every 2 s and reopen on a change or a real error.
  - Open the **actual** current default device, not a "follows the default" virtual device.
  - Log a lost device once per reason.
- **Do not mix the two tracks:** the laptop microphone repeats the speakers' speech about 60 ms later, so a mix would contain the other side twice. Keep them separate and drop echoes (phase 9.3).
- **Mac equivalents:** the computer's sound via ScreenCaptureKit audio or a Core Audio process tap; the microphone via AVAudioEngine. The same rules apply: one clock, capture timestamps, separate tracks, echo.

**Tests after 8.1 (all on mains, the capture running in the background):**

| Test | Result |
|---|---|
| Content: a spoken sentence played through the speakers, captured and read back by Whisper | 11 of 11 per hour, 0% errors, in two 60-minute runs; 9 of 9 in short runs |
| Stability, 60 min (twice) | 0 reopens, 0 device errors, 0 clipping, 0 late chunks |
| Timing: tones played by the probe itself every 10 s for 15 min | Placed by arrival time: one 49 ms jump. **Placed by capture timestamp: 180–182 ms on the speakers (12–13 ms on Bluetooth earbuds), steady to ±1 ms**; drift −6 ms per hour. Each 200 ms tone measured 199–200 ms long (nothing lost or doubled) |
| Microphone against computer sound (from echo, 6 sentences) | Microphone 49–88 ms later; the sentence read word for word from the microphone in 6 of 6 |
| Overruns | Reopening on them cost 1.4 s of microphone audio in 30 s; after the fix, 0 reopens |
| Device change: owner's Bluetooth earbuds out and back in | First **failed** (computer sound lost for the rest of the run). After opening the real device on its own thread: **14 of 14 sentences captured through both switches** |
| Dictation with capture running (off/on/off/on, 5 each) | 2.3 s without, 2.2 s with: no effect |
| CPU and memory, 60 min | Under 1% of one core; about 12 MB working set, 2.5 MB private, flat |
| **Not tested** | Changing the default microphone; wired and USB devices; recovery after a crash; a real call (synthetic voice only) |

**Still to change before it goes into the app (8.3):**
- short temporary pieces, deleted once transcribed (whole files are about 460 MB an hour)
- a bounded queue
- check stream errors every 100 ms
- crash recovery

---

## 9. The tests to run after every phase (the checklist used on Windows)

1. **Unit tests** for any new logic: decisions, migrations, calculations, parsers. Every one must pass.
2. **The phase's own end-to-end suite**, written for the phase against seeded data with known answers (for example Insights: exact tile values).
3. **The full regression:** every existing suite, one at a time, on an idle computer, plugged in. Suites type only into their own test windows and stop rather than type anywhere else.
4. **Theme and contrast audit:** every page and Settings section in light and dark, WCAG AA for all text.
5. **Polish:** every clickable target at least 32 px; keyboard reachable; reduced motion respected.
6. **Dictation time A/B against the previous build:** alternating blocks (A B B A …), 12+ runs each, median and range, on mains. Never conclude from one run.
7. **Data safety on upgrade:** migrate, never reset; settings byte-compared; History counted before and after; backup restored into a test profile.
8. **A written record per phase:** what was built, each suite's result, failures and their fixes, what was not tested and why.
9. **Release only with the owner's approval**, through the installer, after a checked backup.

---

## 10. What's next (approved plan, phases 8–10)

- **8.2:** "Meeting detected" prompt when a call app or browser starts using the microphone. Start / Not now; never records by itself.
- **8.3:** recording session on the EsyMeet page (Start, Pause, Stop, timer, two level meters).
- **9.1–9.3:** pieces cut at pauses; live transcript with "You" / "Others"; echo removal.
- **10:** past meetings: list, search, copy, export.

**Proposed to the owner (not decided):** build 8.3 → 9.1 → 9.2 first, so a working EsyMeet arrives sooner, then 8.2.
