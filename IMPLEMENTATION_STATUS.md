# Implementation status

Last updated: 20 November 2026

**Summary: the dictation milestone is stable in automated testing (Notepad, Word, Chrome, ChatGPT, clipboard, silence, restarts, tray), and the owner reports everyday use works. Phase 4: History is complete and insertion now confirms each paste. Clean mode, the Dictionary, Snippets, Writing styles, Undo and the Scratchpad (steps 2–7) are built and tested, so **Phase 4 is complete in automated testing**; a full regression pass of every end-to-end suite passed on 20 November. The suspected "Try it" regression was not real; the actual fault (hold-to-talk not stopping in EsyType's own window) is fixed. AI enhancement (Phase 5) is **deferred** by the owner (not cancelled, not in progress); current work is the reliability of existing features. Two insertion faults (Word pasting the user's clipboard on a busy PC; no space after typed text) are fixed and tested (Word 35/35). With other programs busy, the old automatic 7 threads made recognition slow and unreliable; Automatic is now one per physical core (4), measured stable and installed (21 Nov). Two checks remain open until the owner completes them (below).**

Status words: **Completed** (works and tested, or for documents: written and reviewed against evidence), **In progress**, **Blocked**, **Not started**.

## Research and design

| Item | Status | Evidence |
|---|---|---|
| Workspace and tool inspection | Completed | Recorded in the open-source evaluation, section 10 |
| REA installed and verified | Completed | `rea doctor` healthy for Claude Code and skill; `claude mcp list` shows connected |
| ESYAI brand analysis | Completed | `docs/research/esyai-brand-analysis.md` |
| Wispr Flow analysis | Completed, with one gap | `docs/research/wispr-flow-analysis.md`; the owner's screenshots were not received |
| Open-source evaluation and licences | Completed | `docs/research/open-source-evaluation.md` |
| Architecture | Completed, awaiting owner review | `docs/architecture/system-design.md` |
| Design system specification | Completed, awaiting owner review | `docs/design/esytype-design-system.md` |
| Benchmark plan | Completed | `docs/testing/benchmark-plan.md` |
| Speech benchmark: Tiny, Base, Small on the development PC | Completed | `docs/testing/2026-11-17-stt-dev-pc.md` |
| First dictation milestone | Completed with recorded audio; manual spoken test pending | `docs/testing/2026-11-17-dictation-milestone.md` |
| Milestone stabilisation | Completed in automated testing; owner checks outstanding (see below) | `docs/testing/2026-11-19-stabilisation.md` |
| History (Phase 4, feature 1) | **Completed** (unit 14/14, privacy and failures 19/19, interface 33/33, Notepad/Word/Chrome 9/9) | `docs/testing/2026-11-19-history.md` |
| Insertion reliability, 20 Nov (Word clipboard, spacing after typed text) | **Completed in automated testing**: Word 35/35 repeated (normal, background reader, slow, compiles); spacing 15/15 and Notepad/Word/Chrome; regressions pass on an idle PC; not yet used by the owner | `docs/testing/2026-11-20-insertion-reliability.md` |
| Phase 5 Milestone 1: foundation (sidebar, Settings page, shared states, settings-file safety) | **Completed in automated testing**, installed 21 Nov (unit 49/49, navigation 14/14, settings recovery 10/10, regression passing; Notepad steps not run); not yet used by the owner | `docs/testing/2026-11-21-foundation.md` |
| Phase 5 Milestone 4: page polish, accessibility, app icon | **Completed in automated testing**, installed 22 Nov (polish 25/25, unit 59/59, full regression on mains, Undo 13/13 after fixing an older pill-timer race; dictation time unchanged: idle 2.1 s, half load 3.2-3.4 s; Notepad steps not run); not yet used by the owner | `docs/testing/2026-11-22-page-polish.md` |
| Phase 5 Milestone 5: Windows installer | **Completed in automated testing**, your PC switched 22 Nov (installer tests 36/36 on a separate test product, full regression on mains, dictation time unchanged; unsigned) | `docs/testing/2026-11-22-installer.md` |
| Built-in product names (recognition plan, Proposal A) | **Completed in automated testing** (22 Nov, test build): names 59% -> 80% on 220 clips, ordinary English unchanged; full regression passed; **released in 0.3.0** and installed on your PC (22 Nov) | `docs/testing/2026-11-22-product-names.md` |
| Milestone 6.1: themes (Dark, Light, Follow Windows) and frosted glass | **Completed in automated testing** (23 Nov, test build): theme suite 33/33 with AA contrast on every page in both themes; full regression passed; dictation time unchanged against pre-6.1; **released in 0.4.0** and installed on your PC (24 Nov). Limits: glass partial until 6.2/6.3; pill always dark; no theme step in first-run setup yet | `docs/testing/2026-11-23-themes.md` |
| Mac design, milestone A: sidebar, Settings panel, heroes and the wave | **Completed in automated testing** (24 Nov, test build): theme 64/64, navigation 17/17, polish, data, first run, History UI and unit tests passed; **not released**. Milestones B-F still to come | `docs/testing/2026-11-24-mac-design-a.md` |
| Settings file robustness | **Completed** (21 Nov): an unreadable `settings.json` keeps its readable values, resets only bad ones, is copied aside and reported; never silently overwritten | `docs/testing/2026-11-21-foundation.md` |
| Speed on a heavily loaded PC | **Completed in automated testing** (owner approved, installed 21 Nov): Automatic is now one thread per physical core (4 here): 3.4 s under half load and 2.2 s idle, no failures in 12. Before: with other programs busy, the automatic 7 threads took a median 43 s (20–120 s, one failure in six) for 10 s of speech; 4 threads (physical cores) 3.5 s, stable; idle 1.8 s against 2.2 s. Full load not measured | `docs/testing/2026-11-21-whisper-threads.md` |
| Insertion reliability | **Completed**: confirmed paste, warning with Copy, clipboard kept in every path (24/24 plus ChatGPT 15/15) | `docs/testing/2026-11-19-insertion.md` |
| Scratchpad (Phase 4, step 7) | **Completed in automated testing** (unit 44/44, end to end 14/14, "Try it" 2/2 hold and toggle, full regression pass); not yet used by the owner | `docs/testing/2026-11-20-scratchpad.md` |
| Undo last dictation (Phase 4, step 6) | **Completed in automated testing** (unit 41/41, test window 13/13, Notepad/Word/Chrome 12/12); not yet used by the owner | `docs/testing/2026-11-20-undo.md` |
| Writing styles (Phase 4, step 5) | **Completed in automated testing** (unit 39/39 with 68 style cases, end to end 12/12, regressions pass); not yet used by the owner | `docs/testing/2026-11-20-writing-styles.md` |
| Snippets (Phase 4, step 4) | **Completed in automated testing** (unit 34/34, end to end 14/14, regressions pass); not yet used by the owner | `docs/testing/2026-11-20-snippets.md` |
| Dictionary (Phase 4, step 3) | **Completed in automated testing** (unit 26/26, end to end 13/13, regressions 19/19 and 10/10); engine hint measured and left opt-in; not yet used by the owner | `docs/testing/2026-11-19-dictionary.md` |
| Clean mode (Phase 4, step 2) | **Completed in automated testing** (rules 96/96, unit 18/18, end to end 10/10, accuracy unchanged); not yet used by the owner | `docs/testing/2026-11-19-clean-mode.md` |

## Outstanding owner checks

These stay open until the owner completes them personally.

| Check | Status |
|---|---|
| Spoken test, 10–20 s of natural speech, in Notepad, Word, Chrome (Gmail) and ChatGPT | **Open** (owner reported general use works on 19 Nov 2026) |
| Real Windows restart: EsyType (now `D:\EsyAI\EsyType\app\esytype.exe`) appears in the tray and dictates without being opened, and History still shows earlier dictations | **Open** (startup entry verified present on 19 Nov after all tests) |

## Build environment

| Item | Status | Note |
|---|---|---|
| Node.js 24.22.3 | Completed | |
| Rust toolchain | Completed | Rust 1.100.0 (minimal profile, clippy, rustfmt) in `D:\AI Projects\Tools\rust`, 646 MB; `RUSTUP_HOME` and `CARGO_HOME` set as user variables |
| Microsoft C++ Build Tools 2022 | Completed | 17.14.37906, MSVC 14.44.35207, in `D:\AI Projects\Tools\vs`; Windows SDK 10.0.26100 on C: (1.7 GB) |
| CMake | Completed | 3.31.6, bundled with Build Tools, on the user PATH |
| Clang / `libclang` (LLVM) | Completed | Clang 19.1.5, Build Tools component, 5.6 GB in the Build Tools folder; `LIBCLANG_PATH` set. **Required on Windows**: `whisper-rs-sys` cannot use its bundled bindings here |
| Native test build | Completed | `D:\AI Projects\Tools\toolchain-check`: whisper-rs 0.16 builds in 69 s, runs, reports 100 languages and CPU features AVX2, FMA, F16C, AVX-512. 2.8 MB executable. No audio has been transcribed yet. |
| Git repository | Completed | Initialised, nothing committed |

## Application components

| Component | Status |
|---|---|
| Desktop shell and windows | Completed for the milestone: main window, recording pill, tray icon, single instance, start with Windows (tested) |
| Production copy | Installed by EsyType's own Windows installer (0.4.0, 24 Nov) at `D:\EsyAI\EsyType\app`, apart from build folders; in Windows' Apps list with an uninstaller. Start menu and startup point there |
| Design system in code | In progress (21 Nov): colour tokens (subset), sidebar, panels, cards, dialog, toast, banner, empty state, loading skeleton, line icons, high-contrast styles; brand fonts not bundled (owner decision pending). Milestone 4 (22 Nov, installed): list toolbar, search, no-match and loading rows, 32 px targets, forced colours throughout, live region, app icon and tray recording dot |
| Audio capture | Completed (tested with the real microphone for 1.2 s; not yet a full spoken dictation) |
| Microphone management | In progress: choose a device; falls back to the Windows default with a warning when it is missing (code path only); no level test |
| Global shortcuts | Completed for the milestone: hold-to-talk, toggle, Esc cancel, accidental-tap guard, rebinding (tested end to end) |
| Speech recognition | Completed for the milestone: worker thread, warm-up, configurable threads, Automatic = one per physical core (tested end to end, idle and under load) |
| Voice activity detection | Completed: bundled Silero VAD rejects silence and noise (tested) |
| Text processing (Clean mode) | Completed in automated testing: Clean (default) and Verbatim; fillers, "scratch that", "new line"/"new paragraph", context-aware numbers (money, percent, times, dates, measurements, ordinals), capitals; original kept; switch in the window and the tray |
| Optional AI clean-up | **Deferred** (owner decision 20 Nov 2026; not cancelled, not in progress) |
| Text insertion | Completed: paste confirmed by the target (Shift+Insert, clipboard promise); "Not typed" warning with Copy when not confirmed; every clipboard format restored in every path; wrong-window guard; dictation kept on the clipboard at least 1 s after the target asks, then the user's clipboard restored unless something newer was copied; space after typed text read from the character before the cursor; outcomes pasted/typed/copied/failed recorded in History; tested in Notepad, Word, Chrome, ChatGPT |
| Local storage | Settings JSON plus a SQLite database (schema version 6: history with style and undone mark, dictionary, snippets, scratchpad notes), with forward-only migrations, backup during upgrade and downgrade protection (tested, including the owner's v1 → v5 upgrades, one version at a time) |
| Model management | Completed for the milestone: three models, verified download, switching, configurable storage folder with verified move (internet download untested) |
| Hardware detection | In progress: RAM, CPU, storage and fit checks; CPU speed probe not built |
| Settings | Its own page (21 Nov) with model, microphone, shortcuts (press-the-keys), text, Undo, startup and threads, storage, data and privacy, about. Data and privacy (Milestone 3, 21 Nov): data and model sizes, History privacy switches, backups (one `.esytype-backup` file; restore with checks, a safety copy and Undo restore), settings export/import with a change list, internet use, Delete all EsyType data. History export (CSV, JSON). Completed in automated testing (`docs/testing/2026-11-21-data-management.md`) |
| Language support | English only, stated in the window; history records the language per entry so other languages can be added later |

## Features

| Feature | Status |
|---|---|
| First-run wizard | **Completed in automated testing and installed (21 Nov 2026)**: eight steps (welcome, privacy, model with hardware and recommendation, download with SHA-256 shown, microphone test, shortcut capture, try it, ready); existing users skip it; Run setup again. Not yet tried with a real microphone or a real internet download (`docs/testing/2026-11-21-first-run.md`) |
| Dashboard | Not started |
| Recording pill | Completed for the milestone: listening, recording with waveform and timer, processing, error; does not take focus (tested) |
| Push to talk and toggle | Completed (tested end to end) |
| Dictionary | Completed in automated testing: words and corrections, protected from Clean, in Clean and Verbatim; add, edit, delete, search, import and export (CSV, JSON), delete all; "add to dictionary" offer after a History edit; optional engine hint (off by default, measured) |
| History | **Completed**: saved after insertion; search, copy, edit (with undo), delete, delete all with confirmation; on/off, 30/90 days/keep, program-name and original-text switches; real-age retention; restarts; Notepad, Word, Chrome; corrupt, newer, locked and read-only databases. Not yet used by the owner. |
| Smart formatting | Not started |
| Writing styles | Completed in automated testing: Standard, Professional, Formal, Casual, Concise, Custom by rules in Clean mode; per-program rules with editable starters; shown on the pill and in History; try-it box |
| Snippets | Completed in automated testing: whole-dictation or anywhere triggers, multi-line text, {date}/{time}/{day}, protected from Dictionary and Clean, in Clean and Verbatim; add, edit, delete, search, import/export, delete all |
| Transforms | Not started |
| Scratchpad | Completed in automated testing: plain-text notes, autosave (also on switching, hiding and quitting), search, copy, export .txt/.md, delete and delete all with confirmation, dictation at the cursor; opened from its tab and the tray; kept until deleted, apart from History |
| Insights | Not started |
| Notetaker Coming Soon page | Not started |
| Installer and updates | Not started |

## Performance claims

| Claim | Status |
|---|---|
| 10 to 15 seconds of speech transcribed in 2 to 3 seconds | **Met on the development PC by Tiny and Base** (Base: 2.6 s for 10 s, 3.0 s for 15 s); **not met by Small** (about 8 s). Other hardware untested. |
| Install size and memory targets | Model RAM measured (Tiny 245 MB, Base 345 MB, Small 601 MB peak); whole-app footprint untested |
| Works on 4 GB and 8 GB machines | **Untested**; no such hardware available yet |

## Open decisions

See `docs/decisions/README.md`: Gemma licence (0008). The default shortcut (0009) was decided on 21 Nov 2026: Ctrl + Space kept.
