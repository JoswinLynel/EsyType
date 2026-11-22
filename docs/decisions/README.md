# Decision records

One entry per significant decision. Status is **Accepted**, **Proposed** (needs the owner's confirmation) or **Open** (a choice is still to be made). Full reasoning lives in the linked document; this file is the index and the short form.

| No. | Decision | Status | Date |
|---|---|---|---|
| 0001 | Product name is EsyType | Accepted | 2026-11-15 |
| 0002 | Tauri 2, React, TypeScript, Tailwind, Rust core | Proposed | 2026-11-15 |
| 0003 | whisper.cpp behind a `SpeechEngine` interface; Parakeet not pursued for now | Accepted | 2026-11-17 |
| 0004 | AI clean-up runs in a separate helper executable over pipes | Proposed | 2026-11-15 |
| 0005 | Own keyboard-hook and text-insertion modules on the `windows` crate | Proposed | 2026-11-15 |
| 0006 | Local database: SQLite, per-user folder, secure delete; SQLCipher encryption deferred | Proposed | 2026-11-15 |
| 0007 | Models are downloaded by the app from a pinned, hashed manifest; never bundled in the installer | Proposed | 2026-11-15 |
| 0008 | Clean-up models: Qwen2.5 0.5B and 1.5B first; Gemma held for a licence decision | Proposed | 2026-11-15 |
| 0009 | Default push-to-talk shortcut: Ctrl + Space kept; the first-run wizard explains its clashes and lets you change it | Accepted | 2026-11-21 |
| 0010 | Main window uses Mica with a solid fallback; pill uses tinted translucency, not live blur | Proposed | 2026-11-15 |
| 0011 | Wispr Flow research limited to public pages, user screenshots and install footprint | Accepted | 2026-11-15 |
| 0012 | Three speech models (Tiny, Base, Small); Base is the default recommendation | Proposed | 2026-11-17 |

---

## 0001 Product name is EsyType

The brief used both "EsyType" and "EsyTalk". The owner chose EsyType. The design-system file is therefore `esytype-design-system.md`.

## 0002 Tauri 2, React, TypeScript, Tailwind, Rust core

**Why:** smallest footprint of the candidates, direct Win32 access from Rust, Windows material support, and the same web stack as esyai.co.uk so brand tokens transfer. Electron rejected for footprint; WinUI 3 for stack mismatch; Tauri 3 is alpha.
**Detail:** `docs/research/open-source-evaluation.md` section 6.

## 0003 whisper.cpp first, engine interface, Parakeet to benchmark

**Update 17 Nov 2026:** the owner limited the product to Whisper Tiny, Base and Small. Parakeet was not benchmarked (it would need an extra download) and is not pursued for now. The engine interface stays.

**Why:** covers Tiny to Medium, multilingual and English-only, quantised, CPU-first, MIT, no runtime. Parakeet V3 may be faster on CPU and must be measured before the default model per hardware class is fixed.
**Consequence:** no engine-specific types outside `esytype-stt`.
**Detail:** open-source evaluation section 3.

## 0004 AI clean-up in a separate helper executable

**Why:** avoids two ggml copies in one binary, makes dictation independent of clean-up by construction, releases memory on exit, and needs no network port.
**Cost:** a second small executable to build, sign and ship.
**Detail:** system design section 9.

## 0005 Own keyboard-hook and insertion modules

**Why:** hold-to-talk on modifier-only chords, double-tap, key swallowing, focus verification and multi-format clipboard restore are not all available from existing crates. The most successful open-source app in this space also wrote its own.
**Detail:** system design sections 6 and 7.

## 0006 Local database protection

**Decision:** per-user data folder, no audio or window titles stored, `secure_delete` on, retention controls, full data deletion. Encryption at rest with SQLCipher is deferred.
**Why deferred:** it complicates the Windows build and full-text search, and does not protect against the realistic threat (software running as the same user). Device encryption is the right defence against disk theft and is recommended in the privacy page.
**Revisit:** before public release.

## 0007 Pinned, hashed model manifest

**Why:** integrity (SHA-256 per file), reproducibility (pinned revisions), and control over exactly which hosts the app contacts. Licences allow an ESYAI mirror later.
**Detail:** system design section 10.

## 0008 Clean-up models

**Decision:** Qwen2.5-0.5B-Instruct and Qwen2.5-1.5B-Instruct (Apache-2.0, ungated). Gemma 3 1B waits for ESYAI to decide whether to carry Google's use restrictions in EsyType's licence. Qwen3 small models to be compared in the AI phase.
**Detail:** open-source evaluation section 5.2.

## 0009 Default push-to-talk shortcut

The brief specifies Ctrl + Space. It conflicts with input-method switching, column selection in spreadsheets, code completion in IDEs and clear-formatting in Word. Recommended alternative: Ctrl + Win held, double-tap to lock, with Ctrl + Shift + Space as toggle.
**Correction (21 Nov 2026):** the build registers shortcuts with Windows' `RegisterHotKey` (global-shortcut plugin), which needs a main key, so modifier-only chords such as Ctrl + Win are **not** supported today; they need the low-level keyboard hook in system design section 6, which was never built. Options and a recommendation for Milestone 2: `docs/plans/first-run-plan.md` section 6.
**Decision (owner, 21 Nov 2026): option A.** Ctrl + Space stays the default hold-to-talk shortcut and Ctrl + Shift + Space the toggle. The first-run wizard names the known clashes and lets the user press new keys. A modifier-only Ctrl + Win hold needs a low-level keyboard hook; if wanted, it is a separate piece of work with its own plan and tests.
**Owner to decide.** Detail: system design section 6.

## 0010 Materials

**Decision:** Mica on Windows 11 for the main window, Acrylic as an opt-in, solid fallback elsewhere and whenever Windows disables transparency. The pill uses a high-opacity tint with the brand's hairline edge because a web-rendered window cannot blur the desktop in a pill shape.
**Detail:** design system section 2.

## 0011 Scope of competitor research

Public site and help centre, the owner's screenshots, and the names and sizes of installed files. No unpacking or reading of application code.

## 0012 Three speech models; Base by default

**Decision (owner):** the first release offers exactly three speech models: Tiny (low-resource computers), Base (balanced everyday dictation) and Small (more capable computers). Only the selected model is downloaded; others can be added later in Settings.
**Files:** `tiny.en` Q5_1 (32 MB), `base.en` Q5_1 (60 MB), multilingual `small` Q5_1 (190 MB), chosen from measured speed, memory and accuracy.
**Default recommendation (proposed):** Base. On the development PC it transcribes 10 s of speech in 2.6 s with 3.4% word error rate and 345 MB of RAM; Tiny is faster but less accurate; Small was about three times slower and not measurably more accurate.
**Recommendation logic:** computed per machine from measured model data and the user's hardware (architecture section 10.3), not from a fixed hardware table.
**Detail:** `docs/testing/2026-11-17-stt-dev-pc.md`.

## 0013 History storage and privacy defaults

**Decision (owner, 19 Nov 2026):** History in a local SQLite database (`esytype.db`), schema version 1 with forward-only migrations. Defaults: history on, kept 90 days (30 days and "until I delete it" offered), program executable name recorded, original transcription kept. Each of these can be switched off; history off writes no text at all. Never stored: audio, window titles, document names, URLs, email subjects. Backups made during a migration are deleted when it succeeds. Database failures must never interrupt dictation.
**Detail:** system design section 11; `docs/testing/2026-11-19-history.md`.

## 0014 Confirmed paste with Shift+Insert

**Decision (19 Nov 2026):** paste through a clipboard promise and report `pasted` only when the target asks for the text; paste with Shift+Insert instead of Ctrl+V; when not confirmed, restore the clipboard and offer Copy (`failed`). With Ctrl+V a background clipboard reader made failed pastes look successful; identifying readers with Windows' wait-chain diagnostics was too slow (up to 1.3 s while the clipboard is held).
**Detail:** `docs/testing/2026-11-19-insertion.md`.

## 0015 Production copy installed apart from build folders

**Decision (19 Nov 2026):** the copy the owner runs lives in `D:\EsyAI\EsyType\app`, installed by `scripts/install-local.ps1` from the release build. Build folders are never run as production, so no build can overwrite the running program or the start-with-Windows target. To be replaced by a real installer in Phase 7.

## 0016 Clean mode defaults

**Decision (owner, 19 Nov 2026):** Clean is the default text mode; zero to nine as words in plain counts; UK formats (£, day month year); the pill's Original button copies the original until "Undo last dictation" exists. Clean is rules only: no model, no network.
**Detail:** `docs/plans/clean-mode-plan.md`, `docs/testing/2026-11-19-clean-mode.md`.

## 0017 Dictionary: corrections by default, engine hint opt-in

**Decision (owner rule, applied to the measurement, 19 Nov 2026):** the Dictionary applies exact spellings and corrections in Clean and Verbatim, protected from Clean's rules. Giving its words to Whisper as an initial prompt spelled names right far more often (24/45 vs 7/45) but cost about 40% speed and 0.8 points of word error rate on ordinary speech, and sometimes inserted a dictionary word wrongly, so it is off by default and opt-in. Dictionary use counts are stored only while History is on.
**Detail:** `docs/testing/2026-11-19-dictionary.md`.

## 0018 Snippets

**Decision (owner, 20 Nov 2026):** snippets match the whole dictation by default (Anywhere is per snippet and needs a trigger of two words or more); `{date}`, `{time}`, `{day}` placeholders; no `{clipboard}` (History would store clipboard contents); applied in Clean and Verbatim; `{cursor}` waits for Undo last dictation. Built with snippets matching before the Dictionary, so snippet text is protected from corrections and Clean.
**Detail:** `docs/plans/snippets-plan.md`, `docs/testing/2026-11-20-snippets.md`.

## 0019 Writing styles by rules, per program

**Decision (owner, 20 Nov 2026):** six styles (Standard, Professional, Formal, Casual, Concise, Custom) applied by rules in Clean mode only; Standard for programs without a rule; editable starter rules (Outlook, Word → Professional; Teams, Slack, WhatsApp, Discord, Telegram, Messenger → Casual); programs identified by executable name only, so a browser has one style for all websites. Styles do not change tone; that is for the optional language model (Phase 5).
**Detail:** `docs/plans/writing-styles-plan.md`, `docs/testing/2026-11-20-writing-styles.md`.

## 0020 Undo with the app's own Ctrl+Z, behind guards

**Decision (owner, 20 Nov 2026):** Undo sends the app's own Ctrl+Z once, and only when EsyType is sure what it would undo: the last dictation, pasted or typed, within 60 seconds, the same window in front, and no key press or click since. Otherwise nothing is sent and the pill says why. Shortcuts Ctrl+Alt+Z (Undo) and Alt+Shift+Z (Paste last). `{cursor}` in snippets built. The app's text is not read to confirm Undo. To know about typing since, EsyType runs low-level keyboard and mouse hooks for the minute after each dictation, recording only the time of the first key press or click.
**Detail:** `docs/plans/undo-plan.md`, `docs/testing/2026-11-20-undo.md`.

## 0021 Scratchpad: plain-text notes kept until deleted

**Decision (owner, 20 Nov 2026):** the Scratchpad holds plain-text notes in the local database (schema v6, table `scratchpad_notes`), autosaved, kept until the user deletes them and independent of History's settings, retention and delete-all. Opened from its tab and the tray menu; no shortcut. Dictation into it uses the normal confirmed paste (the planned direct insertion was not needed). Hold-to-talk release is watched by EsyType itself while holding, because the shortcut library misses it while EsyType's own window is in front.
**Detail:** `docs/plans/scratchpad-plan.md`, `docs/testing/2026-11-20-scratchpad.md`.

## 0022 AI enhancement deferred

**Decision (owner, 20 Nov 2026):** do not start Phase 5 (AI enhancement). Whisper stays the speech engine; rule-based Clean mode stays the default text processing, Verbatim the alternative. No local language model, cloud AI API, AI enhancement model or additional model download; nothing in EsyType may require AI; normal dictation stays lightweight, fast, private and local. AI enhancement is deferred, not cancelled: its architecture is not to be prepared. The priority is reliability of the existing features.
**Detail:** `ROADMAP.md`.

## 0023 Insertion: longer clipboard hold, anonymous reads, spacing from the text before the cursor

**Decision (20 Nov 2026, from measurements):** after the target first asks for the dictation, the text stays on the clipboard for at least 1 s (scaled with the target's response time, at most 3 s) instead of 250 ms, on the paste's own thread so nothing else waits; the user's clipboard is then restored unless something newer was copied. Reads that do not identify the program are refused for programs known to identify themselves (Office, Notepad, and programs seen doing so). Putting the promise back after each read, which would have made every read visible, was rejected: it made Word paste nothing or stop answering. A leading space is decided from the character before the cursor (UI Automation, or text-box messages), falling back to "only directly after EsyType's own dictation". Shift+Insert and the wrong-window guard are unchanged.
**Detail:** `docs/testing/2026-11-20-insertion-reliability.md`.

## 0024 Automatic speech threads: one per physical core

**Decision (21 Nov 2026, owner approved from measurements):** the Automatic thread count is the number of physical cores, at most all logical processors but one, at least one; half the logical processors if the core count cannot be read. A thread count the user has chosen is kept. On the development PC: 4 instead of 7. With other programs busy, 7 threads took a median 43 s (20–120 s, one failure in six) for 10 s of speech; 4 threads 3.5 s (range 0.2 s); idle 1.8 s against 2.2 s. Accuracy and window responsiveness were the same for every count. A count that adapts to the CPU load at each dictation was not adopted: below 4 threads was slower at half load, and full load has not been measured.
**Detail:** `docs/testing/2026-11-21-whisper-threads.md`.
