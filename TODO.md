# Roadmap and next actions

Status words: **Done**, **In progress**, **Blocked**, **Not started**. A feature is Done only when it works end to end and has been tested; a screen that exists is not a feature.

## Waiting on the owner

| Item | Why it matters | Blocking? |
|---|---|---|
| Approve the engine benchmark's model downloads (several gigabytes of Whisper and Parakeet files, to D:) | The benchmark decides the default model per hardware class | **Yes**, for the engine proof |
| Wispr Flow screenshots | They were mentioned but not received; used for layout reference only | No |
| Gemma licence decision | Whether to offer Gemma 3 1B as a clean-up model (decision 0008) | No |
| Update server address and a code-signing certificate | Needed before public release | No, until Phase 7 |

## Phase 1: brand and product research. Done

- [x] Inspect the workspace and installed tools
- [x] Install and verify REA
- [x] ESYAI brand analysis
- [x] Wispr Flow analysis
- [x] Open-source and licence evaluation
- [x] Speech engine and clean-up model comparison
- [x] Technical stack selection
- [x] Architecture
- [x] Design system specification

## Phase 2: foundation. Not started

Kept deliberately thin so the engine is proven before interface work expands.

- [x] Install toolchain: Rust on D:, C++ Build Tools on D: (Windows SDK on C:), CMake on PATH (16 Nov 2026)
- [x] **Engine proof:** `bench/stt-bench` transcribes test clips with whisper.cpp; Tiny, Base and Small benchmarked on the development PC (`docs/testing/2026-11-17-stt-dev-pc.md`)
- [x] Choose the three model files and the default (Base); Parakeet not pursued for now
- [ ] Repetition guard for the shortened encoder window, then re-test (largest speed gain found)
- [ ] Validate the CPU-probe speed prediction on at least two other machines (including a 4 GB or 8 GB laptop)
- [ ] Record a dictation-style test set (laptop microphone, names, technical terms)
- [x] App scaffold: Tauri 2 + React in `src-tauri` and `src` (single crate with one module per component; split into crates when it grows)
- [ ] Design tokens, fonts and glass classes; material detection with solid fallback
- [ ] Main window shell with sidebar and empty pages
- [ ] SQLite storage with migrations; settings

## Phase 3: core dictation. Not started

**First working milestone.** Demonstrated together on 17 Nov 2026 with recorded audio (`docs/testing/2026-11-17-dictation-milestone.md`):

- [x] EsyType launches
- [x] A microphone can be selected
- [x] A global shortcut starts recording
- [x] The floating recording pill appears
- [x] Speech is transcribed locally
- [x] The text appears in another application at the original cursor position (test windows)
- [x] No account; no network once the model is downloaded (not yet tested with the network disabled)
- [x] Insertion tested in Notepad, Word, Chrome and ChatGPT with recorded audio (19 Nov 2026)
- [x] Windows 11 Notepad paste issue: not an EsyType bug (test artefact; see `docs/testing/2026-11-19-stabilisation.md`)
- [x] Stabilisation: storage on D:, clipboard restore, VAD, tray, single instance, start with Windows, restart persistence
- [ ] **OUTSTANDING, owner to complete:** spoken test in Notepad, Word, Chrome (Gmail) and ChatGPT, 10–20 s of natural speech each (owner reported general use works on 19 Nov 2026; the per-app check is not yet done)
- [ ] **OUTSTANDING, owner to complete:** a real Windows restart with EsyType set to start with Windows

Work items:

- [ ] Audio capture and microphone management
- [ ] Keyboard hook and shortcut state machine
- [ ] Recording pill window and waveform
- [ ] Speech engine integration with warm model and VAD
- [ ] Text insertion with target verification and clipboard restore
- [ ] Model manager: manifest, download, resume, verify, delete
- [ ] Test the milestone in Notepad, Word, Chrome (Gmail, ChatGPT) and Edge

## Phase 4: productivity. Complete in automated testing (20 Nov 2026)

Order agreed with the owner: History, Clean mode, Dictionary, Snippets, Writing styles, Undo last dictation, Scratchpad. English only for now; other languages later.

- [x] Personal dictionary with corrections, import and export (19 Nov 2026, `docs/testing/2026-11-19-dictionary.md`)
- [ ] Dictionary later: plural forms; revisit the engine hint with a smaller, per-dictation glossary
- [x] History with search, copy, edit, delete, clear; retention and privacy switches (19 Nov 2026, `docs/testing/2026-11-19-history.md`)
- [x] Snippets (20 Nov 2026, `docs/testing/2026-11-20-snippets.md`)
- [ ] Snippets later: `{cursor}` with Undo last dictation; `{clipboard}` if History can keep only the trigger for such snippets
- [x] Writing styles and per-application rules (20 Nov 2026, `docs/testing/2026-11-20-writing-styles.md`)
- [ ] Writing styles later: per-site styles in browsers (needs the window title, owner declined for now). Tone changes would need a language model: deferred with Phase 5
- [x] Undo last dictation, Restore original, Paste last, `{cursor}` (20 Nov 2026, `docs/testing/2026-11-20-undo.md`)
- [x] Full regression pass of the earlier end-to-end suites (20 Nov 2026, `docs/testing/2026-11-20-scratchpad.md`)
- [x] Scratchpad (20 Nov 2026, `docs/testing/2026-11-20-scratchpad.md`); the suspected "Try it" regression was a hold-release fault, fixed
- [ ] Scratchpad later: add a separating space when dictating straight after typed text (today only after EsyType's own dictation)
- [ ] Insertion: Word on a slow PC once pasted the user's clipboard instead of the dictation (it read the clipboard again after EsyType restored it); hold the text longer after a Word request and add a slow-PC test
- [ ] History: try History with real dictations (owner); consider full-text search (FTS5 is compiled in) if LIKE search becomes slow
- [x] Insertion: paste confirmed by the target; warning with Copy otherwise (19 Nov 2026, `docs/testing/2026-11-19-insertion.md`)
- [ ] Insertion: per-app paste key setting if a program is found that ignores Shift+Insert
- [x] Clean mode: Clean and Verbatim, fillers, "scratch that", line breaks, numbers, capitals, original kept (19 Nov 2026, `docs/testing/2026-11-19-clean-mode.md`)
- [ ] Clean mode later: spoken lists, inline corrections ("five, no, six"), more rule cases from real dictation

## Now: reliability of the existing features (owner priority, 20 Nov 2026)

Before any new feature: make dictation, Clean and Verbatim, the Dictionary, Snippets, Writing styles, Undo, History and the Scratchpad dependable. See `ROADMAP.md`.

- [x] Insertion: Word pasted the user's clipboard on a busy PC (fixed and tested, `docs/testing/2026-11-20-insertion-reliability.md`)
- [x] Insertion: a space after text typed by hand (fixed and tested, same record)
- [x] Measure speech recognition by thread count, idle and under load (21 Nov 2026, `docs/testing/2026-11-21-whisper-threads.md`): 7 threads 43 s median and one failure in six under half load; 4 threads 3.5 s, stable
- [x] Automatic threads = physical cores (owner approved 21 Nov 2026, decision 0024): 4 here instead of 7; under half load 3.4 s instead of 43 s, idle 2.2 s instead of 1.8 s; installed
- [ ] Measure at full load (all processors busy) before considering a load-adaptive thread count
- [ ] Confirm the reliability of the remaining features under load (Clean/Verbatim, Dictionary, Snippets, Writing styles, Undo, History, Scratchpad): their suites pass idle; under load they timed out on recognition
- [ ] Owner checks still open (spoken per-app test, real Windows restart): see `IMPLEMENTATION_STATUS.md`

## Phase 5: product polish and first-run experience. Milestones 1 to 5 done (21-22 Nov 2026)

Plan: `docs/plans/phase-5-audit-and-plan.md`. AI enhancement is not part of it.

- [x] Audit of the interface, first run, settings and data, installation
- [x] Milestone 1 (21 Nov, `docs/testing/2026-11-21-foundation.md`; installed): foundation (sidebar, Settings page, shared empty/loading/error/dialog/toast states) and the settings-file fix (a damaged `settings.json` is silently replaced by defaults today). Recommended first
- [ ] Open from Milestone 1: one Automatic-thread dictation under half load gave no text in 2 minutes (1 of 15, on battery; log not kept). Watch for it; the probe now keeps logs
- [x] Milestone 2 (21 Nov, `docs/testing/2026-11-21-first-run.md`; installed): first-run wizard, shortcut capture, decision 0009 (Ctrl+Space kept)
- [ ] Open from Milestone 2: try the wizard's microphone test with your real microphone (thresholds not yet checked on real voices); a Ctrl+Win hold (keyboard hook) only if you want it, as its own plan
- [x] Milestone 3 (21 Nov, `docs/testing/2026-11-21-data-management.md`; installed): settings export/import, backup/restore with safety copy and Undo restore, History export, Data and privacy section, Delete all EsyType data
- [x] Milestone 4 (22 Nov, `docs/testing/2026-11-22-page-polish.md`; installed): page toolbars and list states, keyboard, toasts, 32 px targets, high contrast, live region, app icon (candidate A), tray recording dot; two older bugs fixed (dialog focus, pill hidden early)
- [ ] Optional owner check: EsyType in a real Windows contrast theme
- [x] Milestone 5 (22 Nov, `docs/testing/2026-11-22-installer.md`; your PC switched to the installer): Windows installer (NSIS per user), upgrades keeping data, uninstall with keep-data default
- [ ] Owner decisions: brand fonts download; signing certificate (NSIS download and install location decided 22 Nov)

## Recognition accuracy (owner request, 22 Nov 2026; plan `docs/plans/recognition-accuracy-plan.md`, approved)

- [x] Audit and baseline (product names 59% on 220 synthetic clips; ordinary English 0.8%; LibriSpeech 3.5%)
- [x] Proposal A: built-in product names (80%, ordinary English unchanged; test build, full regression passed)
- [x] Release Proposal A (0.3.0, installed 22 Nov)
- [x] Proposal C: recording kit built and checked (22 Nov; `docs/testing/recording-kit.md`)
- [ ] Your 15-minute recording (instructions: `docs/testing/recording-kit.md`)
- [ ] Real-voice baseline from your recording, including what the engine writes for silence and noise
- [ ] Proposal D: quiet-speech gate, 16 kHz conversion, Small for accents, level normalisation (each measured first)
- [ ] Proposal B: short hint format (opt-in), measured

## AI enhancement (formerly Phase 5). Deferred (owner decision, 20 Nov 2026)

Not cancelled, not in progress. Rule-based Clean mode is the text processing; no language model, AI model download, cloud AI or AI requirement. Nothing below is to be built or prepared until the owner decides otherwise (decision 0022).

- Helper executable with llama.cpp
- AI Enhanced mode with meaning guards and review before insertion
- Transforms: rewrite, summarise, improve grammar, make professional, convert to email, make concise, custom
- Hardware compatibility scoring for clean-up models
- Compare Qwen2.5 and Qwen3 small models

## Next generation, Phases 6-11 (owner brief 22 Nov 2026; plan `docs/plans/next-generation-audit-and-plan.md`, approved)

- [x] 6.1 Theme system and glass materials: Dark, Light, Follow Windows; frosted dialogs; AA contrast in both themes (23 Nov, test build, `docs/testing/2026-11-23-themes.md`)
- [x] Release 6.1 (0.4.0, installed 24 Nov)
- [x] Mac design milestone A: sidebar, EsyMeet and Insights placeholders, Settings panel, heroes and the wave (24 Nov, test build, `docs/testing/2026-11-24-mac-design-a.md`; plan `docs/plans/mac-parity-gap-analysis.md`)
- [ ] Mac design milestones B-F: Dictation home and pill, Insights, list pages, Settings rows, onboarding; Mica behind the window
- [ ] 6.3 Dictation screen and the glass recording pill (shape A or B chosen from screenshots)
- [ ] 7.1 Profile and onboarding (name, theme step)
- [ ] 8.0 Engine study (bench only): short audio window without repeated sentences
- [ ] 8.1-8.3 EsyMeet capture, detection and recording session; 9.1-9.3 live transcription; 10 meeting history; 11.1-11.2 Insights

## Phase 6 (earlier outline, replaced by the plan above)

- [x] First-run wizard: done in Phase 5, Milestone 2
- [ ] Dashboard
- [ ] Insights
- [ ] Notetaker Coming Soon page (no working controls)
- [ ] Settings completion, including the network-requests list
- [ ] Motion pass (accessibility pass and app icon done in Phase 5, Milestone 4)

## Phase 7: testing and release. Not started

- [ ] Full functional test plan
- [ ] Performance and memory measurements; simulated low-memory runs clearly labelled
- [ ] Offline and privacy verification
- [x] Installer, uninstaller, shortcuts, data-preserving updates (Phase 5, Milestone 5)
- [ ] Third-party notices and in-app licences page
- [ ] Code signing
- [ ] User documentation
