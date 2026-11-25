# Changelog

All notable changes to EsyType are recorded here. Dates are ISO 8601.

## Unreleased

### 2026-11-25: EsyMeet milestone 8.1, dual-audio capture (test tools only; the app is unchanged)

- **New capture module, not yet in the app:** `src-tauri/src/capture.rs` records your microphone and the PC's sound (WASAPI loopback) on one timeline, placed by Windows' own capture timestamps. It is driven by the probe `bench/meet-capture`.
- **Measured over two 60-minute and two 15-minute runs:**
  - 0 reopens, 0 device errors, 0 clipping
  - every test sentence read back exactly by Whisper
  - no drift
  - under 1% of one core, about 12 MB of memory
  - dictation unchanged with capture running (2.2 s against 2.3 s)
- **Fixed during the study:**
  - Windows' overrun notices no longer reopen healthy streams.
  - Silent PC sound now keeps up with the clock.
  - Chunks are placed by capture time, not arrival time.
- **Found:** the laptop microphone repeats the speakers' speech about 60 ms later, so the two tracks stay separate.
- **Still to do:** the device-change test (headphones in and out) needs the owner, so 8.1 is not yet complete.
- Report: `docs/testing/2026-11-25-esymeet-capture-study.md`. Architecture: `docs/architecture/esymeet-capture.md`.

### 2026-11-25: EsyMeet study 8.0, the engine for live meetings (test tools only; the app is unchanged)

- **Result:** the short encoder window with a 256-frame margin matches today's accuracy (ordinary 0.8%, LibriSpeech 3.4%). It transcribes a 10-second piece in about 1.3 s on 2 threads, so live meeting text can follow speech by about 2–6 seconds.
- **Cost:** product names spelled exactly drop from 148 to 141 of 250.
- **The November repeats** came from the margin being too small.
- **Your own recordings** are still to be checked.
- Record: `docs/testing/2026-11-25-esymeet-engine-study.md`.

## 0.5.0 (2026-11-25)

The Mac design (milestones A to F) for Windows. Installed on the owner's PC over 0.4.0 with History and settings kept (`docs/testing/2026-11-24-mac-design-e-f.md`, section 5).

### 2026-11-24: Mac design, milestones E and F, and the frosted pill

**Added**

- **Settings:**
  - Mac-style rows in every section.
  - **Shortcuts:** push to talk on one key (Right Ctrl, Right Alt or Right Shift). Hold to dictate; double-tap for hands-free, tap to stop.
  - **Recording:** start and stop sounds with volume (off by default); a maximum recording length of 5, 10, 20 or 30 minutes.
  - **Speech:** language choice and Translate to English (Small model only).
  - **About:** a new About page.
- **The recording pill:** a frosted, rounded glass look. The wave is unchanged and centred.
- **First-run setup:** ten steps, including "What should EsyType call you?" and "Light or dark?", with progress capsules and the wave on Welcome.

**Fixed**

- A dark box drawn around the recording pill (0.4.0).
- The Acknowledgements toggle in About was smaller than the 32 px minimum.

**Tests**

- Unit 68/68.
- New keys suite 11/11. Every end-to-end suite passes on an idle PC, including those milestone D left pending.
- Dictation time unchanged: 2.1 s against 2.1 s.
- Record: `docs/testing/2026-11-24-mac-design-e-f.md`.

### 2026-11-24: Mac design, milestone D, the list pages

**Added**

- **History:** a banner with counts; filters (Today, This week, Not inserted, your top programs); day cards; search matches highlighted; Copy, Edit and Delete as icon buttons; an Edit sheet.
- **Dictionary and Snippets:**
  - banner chips
  - a category, note (Dictionary) and on/off switch per entry; switched-off entries are kept but not used
  - clash warnings
  - Edit sheets
  - a preview before any import changes anything
- **Style:** banner chips; clickable style cards with live examples; app rules in the row style; Custom style and Clean's options as switches; Try it as six result cards.
- **Scratchpad:** a banner with the note's word count; "2 minutes ago" times; .txt and .md buttons.
- Database change v9: category, note and on/off for Dictionary entries; category and on/off for snippets.

**Fixed**

- Up and Down between list rows now keep to the same button.

**Tests**

- Unit 66/66 and most suites pass.
- Four key-pressing suites still need an idle PC.
- Record: `docs/testing/2026-11-24-mac-design-d.md`.

### 2026-11-24: Mac design, milestone C, Insights

**Added**

- The Insights page:
  - words dictated, words per minute, time saved (with "How?") and a meetings tile for EsyMeet
  - words per day for 7, 30 or 90 days, with the average
  - an 18-week activity grid with hover details, streak, busiest day and words a day when active
  - this week, split by kind of app
  - your typing speed (new setting, 40 wpm by default)
- Database change v8: processing time and words per kind of app per day. Numbers only, kinds from the program's name only, filled once from your History.

**Tests**

- Insights 15/15, unit 65/65.
- Full regression passed; dictation time unchanged.
- Record: `docs/testing/2026-11-24-mac-design-c.md`.

### 2026-11-24: Mac design, milestone B

**Added**

- The Dictation page from the Mac design:
  - a greeting with your first name (new optional "Your name" in Settings ▸ General)
  - a microphone card when Windows blocks the microphone
  - the hero with your numbers: total words, words per minute and day streak, and your Dictionary and snippet counts
  - the last 40 dictations grouped by day
- Usage totals per day (migration v7, numbers only). They keep counting with History off; they start from your existing History; "Delete all EsyType data" removes them.

**Changed**

- Clean or Verbatim moved to the top of the Style page (still in the tray).
- The "Try it" box left the Dictation page; History's empty state opens the Scratchpad instead.
- The window remembers its page, Settings section and folded banners in EsyType's data folder.
- The recording pill is unchanged.

**Tests**

- New home suite 12/12 and unit tests 64/64.
- Full regression passed.
- Record: `docs/testing/2026-11-24-mac-design-b.md`.

### 2026-11-24: Mac design, milestone A

**Added**

- The Mac app's layout:
  - the new sidebar, with EsyMeet ("Soon") and Insights (placeholder)
  - the last page remembered
  - Settings as a panel over the window with eight sections; Esc or a click outside closes it; Ctrl+, and the tray's Settings… open it
  - a Permissions section showing Windows' microphone privacy switch
- Page heroes with the animated voice wave in EsyType's logo colours (amber, white, blue), folding into a pill beside the title.
- Window 1120 × 740, minimum 860 × 600; the Mac's colours, type and radii.

**Fixed**

- Light amber text was below AA on a selected model card; it is darker now.

**Tests**

- Theme 64/64, navigation 17/17, polish 25/25, data 27/27, first run 32/32, History UI 33/33, unit 63/63.
- Record: `docs/testing/2026-11-24-mac-design-a.md`.

## 0.4.0 (2026-11-24)

### Milestone 6.1: light and dark themes and frosted glass

**Added**

- **Three themes** in Settings > Appearance:
  - **Follow Windows:** the default. It switches with Windows' light or dark mode, even while EsyType is open.
  - **Dark:** as before.
  - **Light:** new.
- **The window follows the theme:** the title bar follows it too, and the choice is kept after a restart. Existing settings files are not rewritten and simply follow Windows.
- **Frosted glass while Windows' Transparency effects are on:**
  - frosted dialogs and notifications over a softly blurred page
  - a glass rim on panels, cards and entries
  - everything solid when the switch is off or in high contrast

**Fixed**

- **Red "Delete all" buttons and the white-on-red Delete buttons in dialogs** were below WCAG AA contrast in the dark theme (4.35:1 and 3.76:1); both now pass. Every visible text on every page passes AA in both themes.

**Changed**

- Every colour in the interface is now a theme token (design system section 3.9).
- The recording pill keeps its dark look in either theme.

**Tests**

- **New theme suite:** 33 of 33, covering:
  - every page and the dialog checked for AA contrast in both themes
  - the setting kept after a restart, and the title bar
  - the pill
  - glass on and off
- **Other checks:**
  - unit tests 63 of 63
  - full regression passed
  - dictation time unchanged against pre-6.1, alternating: idle 2.15 s against 2.15 s, half load 3.40 s against 3.40 s
- **Record:** `docs/testing/2026-11-23-themes.md`.

### 2026-11-22: Recording kit for the real-voice benchmark (test tools only; the app is unchanged)

**Added**

- `bench/accuracy/record`: a small recorder that shows one sentence at a time and saves your reading at the microphone's own rate. It uses EsyType's own microphone library and 16 kHz conversion code; nothing was downloaded.
- `bench/accuracy/owner-script.json`: 70 sentences in 12 sections (everyday, accent, fast, slow, quiet, pauses, noisy room, numbers, product names, technical, a 90-second dictation, mixed), plus room-tone and noise-only takes.
- `run.ps1 -Set owner` and `score.py --script`: transcribe and score your recordings by section, including words written where nothing was said.
- How to record: `docs/testing/recording-kit.md`.

## 0.3.0 (2026-11-22)

### Built-in product names (recognition plan, Proposal A)

**Added**

- A fixed list of 29 product, brand and technology names corrected after the engine: "chat GPT" becomes ChatGPT, "Superbase" Supabase, "Versal" Vercel, "Microsoft co-pilot" Microsoft Copilot, "N8N" n8n, "node.js" Node.js. Only forms that are not English words, or phrases whose context makes the product certain. Kept apart from your Dictionary (yours wins; it can't be edited, deleted or exported), with a switch on the Dictionary page (on by default). Clean and Verbatim; History keeps what was heard.

**Changed**

- Dictionary phrases now also join across a dot inside a name ("node.js").

**Tests**

- Product names spelled right 59% -> 80% on 220 benchmark clips (five voices, including Indian English), with not one ordinary or LibriSpeech clip changed; unit 63; Dictionary end to end 18/18; full regression; dictation time unchanged. Record: `docs/testing/2026-11-22-product-names.md`. Benchmark tools: `bench/accuracy/`.

### 2026-11-22: Phase 5, Milestone 5: Windows installer (0.2.0)

**Added**

- A per-user Windows installer (Tauri's NSIS bundler, no administrator prompt): folder choice, Start menu and desktop shortcuts, an entry in Windows' Apps list, EsyType's icon and side panel. Upgrades keep every setting and all data; an older installer over a newer EsyType is refused.
- An uninstaller that removes the program, shortcuts and start-with-Windows entry and keeps your data unless you tick "Also delete my settings, History, notes and downloaded speech models"; then only EsyType's own files go.
- Version 0.2.0.

**Tests**

- New `installer-e2e.ps1` (36 checks, run on a separate "EsyType Test" product so your EsyType is never touched) and `installer-screenshots.ps1`; full regression on mains; dictation time unchanged. Your PC switched to the installer after a checked backup; settings, History and the startup entry unchanged. Record: `docs/testing/2026-11-22-installer.md`.

### 2026-11-22: Phase 5, Milestone 4: page polish, accessibility and the app icon

**Added**

- One toolbar on every list page: heading with a count; Import, Export CSV, Export JSON, then Delete all; a search box with a clear button (Esc clears). Placeholder rows while loading, one "Nothing matches" line with Clear search, and an empty state with a first action on every page.
- Keyboard: Up/Down between rows, Esc cancels an edit, Enter or Ctrl+Enter saves, focus moves to the next row after a delete. A toast after every delete and saved edit.
- Accessibility: 32 px minimum targets, Windows high-contrast styles everywhere (pill included), a polite live region announcing each dictation in the main window.
- New app icon (the waveform in the pill's colours, drawn for each size) and a tray icon with a red dot while dictating.

**Fixed**

- Focus now returns to the button that opened a dialog (it was lost after every confirmation).
- A hide timer from one dictation could hide the next dictation's pill, and its Undo button, when the two came within about 5 s.

**Tests**

- New `polish-e2e.ps1` (25/25) and `forced-colors.ps1`; unit tests 59; full regression passing on mains with the final build; dictation time unchanged (idle 2.1 s, half load 3.2-3.4 s). Installed 22 Nov; settings, History and the startup entry unchanged. Record: `docs/testing/2026-11-22-page-polish.md`.

### 2026-11-21: Phase 5, Milestone 3: settings and data management

**Added**

- Backups: one `.esytype-backup` file with History, Dictionary, Snippets, notes and settings (not the models; not encrypted). Restore checks the file first, shows what it holds, makes a safety copy and offers Undo restore; a failure puts the data back.
- Settings export and import, showing every change first and never taking another PC's microphone or model folder.
- History export (CSV, JSON; all or the search results).
- Settings, Data and privacy: data and model sizes, History's privacy switches (moved from the History page), internet use, Delete all EsyType data (models only when ticked).

**Tests**

- New `data-e2e.ps1` (27/27, three runs); unit tests 58; full regression; dictation time unchanged. Your data was backed up first, from a copy (`D:\EsyAI\EsyType\backups`). Record: `docs/testing/2026-11-21-data-management.md`.

### 2026-11-21: Phase 5, Milestone 2: first-run wizard

**Added**

- An eight-step setup on first start: welcome, privacy (with a Keep History switch), speech model with this PC's hardware and a recommendation (Base, or Tiny when Base does not fit), download with speed, time left, Cancel, Retry and a visible SHA-256 check, a 3-second microphone test with a level bar, shortcut, Try it, and a summary. Existing users never see it; Settings → About has Run setup again.
- Shortcuts are changed by pressing the keys (wizard and Settings), with EsyType's own shortcuts paused meanwhile and always restored; unusable combinations are refused with a reason.

**Changed**

- Decision 0009: Ctrl+Space stays the default hold-to-talk shortcut; the wizard names its clashes.

**Fixed**

- Changing one shortcut failed when another program held the other one.

**Tests**

- New `firstrun-e2e.ps1` (32/32, four runs) with a local model server (`model-server.py`); `ui-screenshots.ps1 -Setup`; full regression; dictation time unchanged (2.2 s idle, 3.2–3.4 s half load). Record: `docs/testing/2026-11-21-first-run.md`.

### 2026-11-21: Phase 5, Milestone 1: foundation

**Added**

- Sidebar navigation (Dictation, History, Dictionary, Snippets, Style, Scratchpad, Settings) with the engine status always visible; arrow keys move between pages.
- Dictation is now a home page (shortcuts, Try it, last dictation, Clean/Verbatim); every other setting moved, unchanged, to a new Settings page with sections, a Data and privacy section (where data is kept, Open folder) and About.
- In-window confirmation dialogs (instead of the browser's), toasts, banners, empty states, a loading skeleton, line icons, high-contrast and large-text layouts.

**Fixed**

- A `settings.json` that could not be read was silently replaced by defaults on the next save. Now readable values are kept, only bad ones reset, the original is copied aside, and the window says what happened.
- Model speeds showed as "1.2000000476837158 s"; the window could scroll twice.

**Tests**

- New `navigation-e2e.ps1` (14/14) and `settings-recovery-e2e.ps1` (10/10); `ui-screenshots.ps1` for layout checks; full regression; dictation time unchanged (2.2 s idle). Test fixes: spacing and slow-paste counters (PowerShell 5.1 JSON quirk), Word focus in spacing, History's wait. Record: `docs/testing/2026-11-21-foundation.md`.

### 2026-11-21: Automatic speech threads = physical cores

**Changed**

- Automatic processor threads now means one per physical core, at most all logical processors but one (4 on a 4-core, 8-thread PC; was 7). With other programs busy, 10 s of speech now takes 3.4 s instead of a median 43 s (up to 2 minutes, sometimes nothing); idle it takes 2.2 s instead of 1.8 s. A thread count chosen in Settings is kept. Owner approved (decision 0024).

**Tests**

- `bench/e2e/threads-probe.ps1` measures time, responsiveness, warm-up and accuracy by thread count, idle and with other programs busy. Result: the automatic 7 threads take a median 43 s (one failure in six) for 10 s of speech under half load, 4 threads 3.5 s; idle 1.8 s against 2.2 s. Physical cores recommended as the automatic count; **not applied** until the owner approves. Record: `docs/testing/2026-11-21-whisper-threads.md`.

### 2026-11-20: Insertion reliability; AI enhancement deferred

**Fixed**

- Word sometimes inserted the user's clipboard instead of the dictation on a busy PC, while EsyType reported success. Word reads the clipboard several times per paste, and the last read could come after EsyType put the user's clipboard back (250 ms). The dictation now stays on the clipboard for at least 1 s after the target asks (up to 3 s for a slow target), on a separate thread so nothing waits for it; the next paste, Copy buttons and quitting wait for the restore. If something else was copied in that time, the newer copy is kept.
- A program reading the clipboard without a window (as Chrome does) right after the paste key could be counted as the paste. Such reads are now refused for programs known to identify themselves (Word, Excel, PowerPoint, Outlook, OneNote, Notepad, and any program seen doing so).
- No space between text typed by hand and the dictation ("Shopping listWe need milk."), and possible doubled spaces after typing. EsyType now reads the one character before the cursor (UI Automation, or the standard text-box messages; never in password fields, never stored) and adds a space only after a letter, digit or end punctuation. Where the text cannot be read it adds one only when directly continuing its own dictation (within a minute, no typing or clicking in between).

**Changed**

- AI enhancement (Phase 5) deferred by the owner: no language model, AI model download or cloud AI; not cancelled. See `ROADMAP.md` and decision 0022.

**Tests**

- Word, repeated: 35 of 35 (normal, background reader, slow, slow with reader, real compiles); new `word-repeat.ps1`, `slowpaste-e2e.ps1`, `spacing-e2e.ps1` (15 of 15) and measuring tools; clipboard checks wait for the restore. Full regression passed twice on an idle PC. On a heavily loaded PC speech recognition slows to 7–58 s (finding, not yet fixed). Record: `docs/testing/2026-11-20-insertion-reliability.md`.

### 2026-11-20: Scratchpad (Phase 4 complete)

**Added**

- Scratchpad tab: plain-text notes on this PC, saved automatically (half a second after typing or dictating stops, and on switching note or tab, hiding the window or quitting). Search, copy all, export .txt or .md, delete and delete all with confirmation. Dictation goes in at the cursor with Clean, styles, Dictionary and Snippets. Notes are kept until you delete them; History's settings never touch them. Database schema version 6.
- "Open Scratchpad" in the tray menu.
- Tests: note storage unit tests; `bench/e2e/scratchpad-e2e.ps1` (14 of 14) and `tryit-e2e.ps1` (hold and toggle); a full regression pass of every earlier end-to-end suite.

**Fixed**

- Hold-to-talk kept recording after the keys were let go while EsyType's own window was in front (Scratchpad, "Try it"): EsyType now watches the keys itself while holding.
- A hold could be cancelled as too short when recording was slow to start; the hold is now measured from the key press.

### 2026-11-20: Undo last dictation

**Added**

- Undo on the pill and with Ctrl+Alt+Z: sends the app's own Ctrl+Z once, only for the last dictation, within 60 seconds, in the same window and if you have not typed or clicked since; otherwise it tells you why and sends nothing. Never offered in consoles and terminals (and an editable list of programs).
- Use original on the pill: replaces Clean's text with what was heard, in place.
- Paste last (Alt+Shift+Z): pastes the most recent dictation again.
- `{cursor}` in snippets: the caret lands where the marker was.
- History marks undone dictations (database schema version 5).
- Tests: guard unit tests; `bench/e2e/undo-e2e.ps1` (13 of 13) and `undo-apps-e2e.ps1` (Notepad, Word, Chrome: 12 of 12).

**Fixed (found by the tests before release)**

- The keyboard/mouse watch behind "no typing since" did not start; then it kept only the latest input. Both fixed; if the watch cannot start, Undo is refused.
- The pill could become the active window when its buttons were pressed through accessibility tools; it is now a no-activate window.

### 2026-11-20: Writing styles

**Added**

- Style tab: Standard, Professional, Formal, Casual, Concise and Custom, applied by rules in Clean mode to the app you dictate into (spoken forms written out, contractions expanded, end punctuation, stock phrases shortened, hedges dropped). Per-program rules with editable starters, a default for other programs, Custom switches and a try-it box. Styles never change snippet text or dictionary terms, and never apply in Verbatim.
- The pill shows the style used ("Done · Formal"); History records it (database schema version 4).
- Tests: 68 style cases and 5 more unit tests; `bench/e2e/style-e2e.ps1` (12 of 12).

**Changed**

- Speed tests take the best of three runs (single runs were sometimes slowed by parallel tests or power saving).

### 2026-11-20: Snippets

**Added**

- Snippets tab: say a trigger to insert saved text (signatures, addresses, links), line breaks included, exactly as written. Whole-dictation (default) or anywhere in a sentence (triggers of two words or more). `{date}`, `{time}` and `{day}` placeholders with a preview. Add, edit, delete, search, import and export (CSV, JSON), delete all. Works in Clean and Verbatim.
- Database schema version 3 (snippets table); History and Dictionary kept through the upgrade.
- Tests: 50-case matching table and 7 more unit tests; `bench/e2e/snippets-e2e.ps1` (14 of 14).

### 2026-11-19: Dictionary

**Added**

- Dictionary tab: words (spelled exactly as entered) and corrections (when I say X, write Y), in Clean and Verbatim, never changed by Clean's rules. Add, edit, delete, search, import and export (CSV for Excel, JSON), delete all. Use counts.
- After you edit a History entry, EsyType offers to add the change to the dictionary. Nothing is learned silently.
- Optional engine hint (off by default): measured to spell names right far more often but about 40% slower and slightly less accurate on ordinary speech.
- Database schema version 2 (dictionary table); History is kept through the upgrade.
- Tests: 26 unit tests, `bench/e2e/dictionary-e2e.ps1` (13 of 13), `bench/dictionary-hint/` measurement.

**Fixed**

- The first Dictionary field kept its old name for screen readers after switching to Correction.
- Test harness: windows found by process, not title; no hang when another program is not responding.

### 2026-11-19: Clean mode

**Added**

- Clean mode (default) and Verbatim, switchable in the window and from the tray icon. Clean removes fillers ("um", "uh"), follows "scratch that", "new line" and "new paragraph", writes spoken numbers by context (£25, 10%, 3:30 pm, 5 March 2026, 21st, 5 kilometres; zero to nine stay words), and fixes capitals. Rules only, on this PC.
- The original is kept: History shows it with Copy original and Use original instead; the pill offers Original for a few seconds after a dictation Clean changed.
- Options: digits for small numbers; also remove "you know", "I mean", "like", "sort of", "kind of" when set off by commas.
- Tests: 96 rule cases, speed and accuracy checks, `bench/e2e/clean-e2e.ps1` (10 of 10, speech from Windows text-to-speech).

### 2026-11-19: insertion reliability; History complete

**Changed**

- Pasting now confirms that the target program took the text (clipboard promise) and uses Shift+Insert. Success is reported only when confirmed.
- When a paste is not confirmed, the pill says "Not typed" and offers Copy; your clipboard is left as it was; History records `failed`.
- History outcomes are pasted, typed, copied or failed.
- The production copy is installed in `D:\EsyAI\EsyType\app` (`scripts/install-local.ps1`), apart from every build folder; Start menu and start-with-Windows point there.

**Fixed**

- EsyType could report a paste as done when nothing was inserted (a background program reading the clipboard on Ctrl+V made it look successful).
- Text copied after a window change kept the leading space meant for consecutive dictations.

**Tests**

- `bench/e2e/insertion-e2e.ps1`: 24 of 24 (test window, no text field, typed, window change, Word, Chrome, ChatGPT, Notepad) and ChatGPT in Chrome 15 of 15; History regression 19 of 19.

### 2026-11-19: History

**Added**

- History page: every dictation is saved locally after it is inserted; search, copy, edit (with "undo my edits"), delete, and delete all with a confirmation.
- Privacy settings: history on or off (off saves nothing), keep 30 days, 90 days (default) or until deleted, record the program name (executable file name only) and keep the original transcription, each switchable. Audio is never saved.
- Local SQLite database (`esytype.db`) with versioned migrations, a temporary backup during upgrades, and protection for databases from newer versions.
- "English only for now" stated on the main screen.
- Tests: 4 database unit tests; `bench/e2e/history-e2e.ps1` (17 of 17), including history off, a corrupt, a newer and a locked database.

**Changed**

- A dictation whose insertion fails is still kept in History, so the words are not lost.
- Test builds (`e2e` feature) use their own app identity, so they can run while an installed EsyType is open.

**Fixed (History verification)**

- Deleted, expired or replaced history text could linger in the database's write-ahead log; the log is now flushed and emptied after each.
- Entries that expired while EsyType was idle stayed visible until the next dictation; they are now removed whenever History opens.
- Test builds switched off the installed EsyType's start-with-Windows entry (shared startup name); they no longer touch it. The owner's entry was restored.

**Tests**

- `history-ui-e2e.ps1` (33 checks, every History control and real-age retention), `history-apps-e2e.ps1` (Notepad, Word, Chrome), a read-only database case, and three new unit tests.

### 2026-11-19: milestone stabilisation

**Added**

- Configurable model storage with a verified move; the Base model now lives on D:.
- System tray icon; single instance; start with Windows (on by default, starts hidden in the tray).
- Bundled Silero voice activity model: silence and noise no longer produce invented text.
- Full clipboard save and restore (text, HTML, images, file lists), so dictation pastes instead of typing.
- A space between consecutive dictations into the same window.
- Microphone fallback to the Windows default with a warning when the chosen one is missing.
- Tests: insertion into Notepad, Word, Chrome and ChatGPT; clipboard types; VAD; accuracy through the app; restart and persistence; reliability.

**Fixed**

- The recording pill never hid after its first appearance.
- After a login start, keyboard focus went to the hidden pill window.

**Clarified**

- The Windows 11 Notepad paste failure was caused by the test harness (a Notepad prompt it triggered), not by EsyType.

### 2026-11-17: first dictation milestone

**Added**

- Desktop app (`src-tauri`, `src`): global shortcuts (hold Ctrl+Space, toggle Ctrl+Shift+Space, Esc to cancel), microphone capture, floating recording pill, local transcription on a background thread, insertion into the previous app with clipboard restore, a typing fallback and a wrong-window guard.
- Model choice screen: Tiny, Base, Small with size, memory, measured speed and fit; downloads only the chosen model with SHA-256 verification; switch later from the same screen.
- Thread setting: Automatic (logical processors minus one) or a fixed number.
- Tests: 7 unit tests, a local-server download test, a microphone test, and `bench/e2e/dictation-e2e.ps1` (13 of 13 checks passed).

**Known issues**

- Windows 11 Notepad received `"""` instead of the text through the paste path in one run; not reproduced elsewhere.

### 2026-11-17: speech benchmark and model lineup

**Added**

- `bench/stt-bench`: benchmark program using whisper.cpp through `whisper-rs`.
- `docs/testing/2026-11-17-stt-dev-pc.md`: speed, memory, accuracy, cold/warm and thread results for Tiny, Base and Small on the development PC.
- Decision 0012: three speech models (Tiny, Base, Small), Base as the proposed default.

**Changed**

- Architecture: three-model lineup; recommendation computed from measured data and the user's hardware, not a fixed table; only the selected model is downloaded; threads default to logical processors; model warm-up at start-up.
- Open-source evaluation: removed the provisional hardware-to-model table.

**Found**

- whisper.cpp built with the default Rust `cmake` settings on MSVC is unoptimised (about 7 times slower); fixed in `.cargo/config.toml`.
- Shortening the encoder window is 2 to 8 times faster on short clips but caused repetition loops on 2 of 18 clips; left off.

### 2026-11-16: build toolchain

**Development environment changes on the build PC**

- Rust 1.100.0 (minimal profile, clippy, rustfmt) installed in `D:\AI Projects\Tools\rust`.
- Microsoft C++ Build Tools 2022 (MSVC 14.44) with the Clang component installed in `D:\AI Projects\Tools\vs`; Windows SDK 10.0.26100 installed on C: by Microsoft's installer.
- CMake 3.31.6 (bundled) added to the user PATH; `RUSTUP_HOME`, `CARGO_HOME` and `LIBCLANG_PATH` set as user variables.

**Verified**

- whisper.cpp builds through `whisper-rs` and runs on this PC.

**Found**

- `libclang` is a build requirement on Windows: `whisper-rs-sys` 0.15.0's bundled bindings fail to compile here. Recorded in the open-source evaluation's risk table.

### 2026-11-15: research and architecture

**Added**

- Project folder and documentation structure.
- `docs/research/esyai-brand-analysis.md`: brand identity observed on esyai.co.uk with REA, including exact colour, type, glass, radius, shadow and motion values, and 23 reference images in `docs/research/assets/`.
- `docs/research/wispr-flow-analysis.md`: competitor analysis from the public site, 22 public help articles and a measured install footprint.
- `docs/research/open-source-evaluation.md`: evaluation of speech engines, VAD, local language models, desktop frameworks and supporting libraries, with versions, activity and licences read from the live registries.
- `docs/architecture/system-design.md`: process model, components, pipeline, shortcuts, insertion, model management, storage, privacy and packaging.
- `docs/design/esytype-design-system.md`: design tokens, materials and fallbacks, components, recording pill and waveform.
- `docs/decisions/README.md`: eleven decision records.
- `docs/testing/benchmark-plan.md`: benchmark and functional test plan.

**Development environment changes on the build PC**

- Node.js upgraded from 24.13.1 to 24.22.3 (required by REA).
- REA 6.9.0 installed globally and registered with Claude Code.
- ponytail 5.3.3 plugin installed for Claude Code.

**Not done**

- No application code exists.
- No benchmark or test has been run.
- Rust, C++ build tools, CMake and LLVM are not installed.
