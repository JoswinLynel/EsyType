# Phase 5, Milestone 2: First-run wizard. Plan

**Date:** 21 November 2026 · **Status:** approved by the owner with shortcut option A (21 Nov); **built and tested** (`docs/testing/2026-11-21-first-run.md`)
**Parent plan:** `phase-5-audit-and-plan.md` · **Builds on:** Milestone 1 (`foundation-plan.md`: dialog, toast, banner, empty state, icons, Settings page)

**Scope:** a step-by-step setup shown the first time EsyType starts, reusing the existing model, download, microphone and shortcut code.

**Not in scope:**
- export, import and backup (Milestone 3)
- page polish (Milestone 4)
- the installer (Milestone 5)
- any new model, download source or dependency

Speech, cleaning and insertion code is not changed.

## 1. What already exists and is reused

| Piece | Today | In the wizard |
|---|---|---|
| Three model cards, fit chips, Recommended badge | `ModelChooser` (`settings.tsx`), `hardware::fit` | Used as is, with a recommendation that follows this PC (section 3) |
| Download: progress, cancel, resume, SHA-256 check | `models::download`, `download` events | Used as is. The window adds speed, time left, Retry and a visible "Checking the file" step. No Rust change: the check runs after the last byte arrives, so the window shows it between "100%" and "finished" |
| Hardware facts | `hardware::detect` (CPU, cores, AVX2, memory, free storage) | Shown on the model step |
| Microphone list, Windows default, "not connected" warning | Settings → Microphone | Used as is, plus a test (section 4) |
| Shortcut fields, registration, "another app may be using it" | Settings → Shortcuts, `register_keys` | Used, plus press-the-keys capture (section 5) |
| Practice box | Dictation → Try it | Used as is |
| First-run detection | "No model installed" shows a single page (`main.tsx`) | Replaced by a setup-complete flag (section 2) |

## 2. When the wizard appears

- **New setting `setup_done`** (true or false) in `settings.json`.
- **Existing users never see it.** When the setting is missing or false and a model is already installed, EsyType sets it to true at start-up and shows the normal window. This covers your installed copy.
- **First start:** no model installed and `setup_done` false → the window opens on the wizard, even when started with `--minimized` (otherwise a new user would see nothing).
- **Closing the window mid-setup:** EsyType stays in the tray, and a download carries on. Opening the window returns to the same step. After a restart, the wizard starts again at Welcome; a downloaded model is shown as installed and is not downloaded again.
- **Run setup again:** a button in Settings → About. Nothing is deleted or reset; it only walks through the same steps with the current choices filled in.
- With the wizard done, the window is the Milestone 1 window, unchanged.

## 3. The steps

One step per screen (design system section 8.6): a step counter ("Step 3 of 8"), Back and Continue, Esc does nothing (no accidental exit), keyboard reachable throughout.

| # | Step | Contents |
|---|---|---|
| 1 | **Welcome** | "Speak. It types." One sentence on what EsyType does; **Get started** |
| 2 | **Privacy** | What stays on this PC: your voice, the text, History, Dictionary, Snippets and notes. The only internet use: downloading the speech model you choose, from one fixed address, checked by its SHA-256 fingerprint before use. No account, no analytics. One switch: **Keep a History of dictations on this PC** (on; kept 90 days; program names only, never window titles), with "Change this any time in History" |
| 3 | **Speech model** | This PC: processor, cores, memory, free storage, AVX2, each with a chip. The three cards, with **Recommended for this PC** on one (rule below). Speed figures say they were measured on a development PC |
| 4 | **Download** | Progress, MB, speed and time left; Cancel; on failure the reason in words and **Retry** (resumes from the partial file). Then "Checking the file (SHA-256)…" → "Verified". A file that fails the check is removed and the step says so. **Continue** is available while it downloads: the microphone and shortcut steps do not need the model |
| 5 | **Microphone** | The device list (Windows default first); **Test microphone** (section 4) |
| 6 | **Shortcut** | Hold-to-talk and start/stop shown as keycaps; **Change** captures the keys (section 5); a plain note on the default's known clashes (section 6). Undo and Paste last stay in Settings |
| 7 | **Try it** | The practice box: "Click here, hold `Ctrl+Space`, say a sentence, let go." Waits with "Finishing the download…" if the model is not ready. Shows how long it took. **Skip** is allowed |
| 8 | **Ready** | A summary (model, microphone, shortcut, History on/off), **Start EsyType with Windows** (on, as today), **Finish**: sets `setup_done`, hides the window to the tray with the usual tray message |

**Recommendation rule** (no hardware-to-model table, as you decided on 17 Nov):
- Base, as today,
- unless Base does not fit this PC's free memory or storage: then Tiny, if Tiny fits;
- Small is never recommended automatically;
- if nothing fits, no badge, and the step says why (free storage or memory).

## 4. Microphone test

- **Test microphone** records for 3 seconds from the chosen device and shows a live level bar (the same levels the pill already gets).
- Result in words: "We heard you", "Very quiet: move closer or check the input level in Windows' sound settings", or "Nothing heard".
- Nothing is saved or transcribed. Windows shows its usual microphone-in-use icon only during those 3 seconds.
- New command `mic_test(device)`; refused while a dictation is running.

## 5. Shortcut capture

- **Change** → "Press the keys you want, then let go" → shows them → **Use this** or **Cancel**.
- While capturing, EsyType's own shortcuts are paused (otherwise Windows hands `Ctrl+Space` to EsyType and the window never sees it). They are restored on Use, Cancel, Esc, the window losing focus, or after 20 seconds, whichever comes first, so a capture can never leave you without shortcuts.
- Rules, checked before saving:
  - at least one of Ctrl, Alt, Shift or Win plus one other key, or a single function key (F1–F24)
  - Win combinations and Alt+Tab-style system keys that Windows keeps for itself are refused with a reason
  - must differ from the other shortcuts
- Saving uses today's `save_settings` path: if registration fails, the old shortcut is put back and the message says another app may be using it.
- The same capture replaces the typed fields in Settings → Shortcuts.
- New command `pause_shortcuts(on)`.

## 6. Decision 0009: the default hold-to-talk shortcut

What I found while planning:
- **The decision record says "both are supported"; the build supports only one kind.** Shortcuts go through Windows' `RegisterHotKey` (the global-shortcut plugin), which needs a main key. A modifier-only chord such as **Ctrl+Win** cannot be registered this way. It needs a low-level keyboard hook, which the architecture describes but was never built. It must also stop the Start menu opening when Win is released.
- I will correct the decision record and system design to say so.

| Option | What it means | Risk |
|---|---|---|
| **A. Keep Ctrl+Space (recommended for this milestone)** | Works today and is covered by every test suite. The wizard shows it, says plainly where it clashes (Chinese input-method switching, Excel's select-column, code completion in editors, Word's clear-formatting), and **Change** is one click | None new. Users of those apps change it at setup instead of finding out later |
| B. Build Ctrl+Win hold in this milestone | New keyboard hook on its own thread; Start-menu suppression; double-tap to lock | New input code on the dictation path, the area your reliability rule protects. Roughly doubles this milestone and needs the full insertion and undo regression again |
| C. A different ordinary chord as default (you name it) | Same mechanism as A | I would check it against Windows' reserved shortcuts and common apps before it ships |

**Recommendation: A now.** Record the Ctrl+Win hold as its own later piece, with its own plan and tests, so it can be judged on reliability alone. The toggle stays `Ctrl+Shift+Space` in every option.

## 7. Defaults to approve

1. **Eight steps** as in section 3, with Back on every step and no Esc exit.
2. **Existing users skip the wizard**: a model installed counts as set up (section 2).
3. **The wizard opens even when started minimized** on a PC that is not set up.
4. **Recommendation:** Base, or Tiny when Base does not fit; Small never recommended automatically.
5. **Continue while downloading**: microphone and shortcut steps can be done during the download; Try it waits for it.
6. **Privacy step has one switch** (Keep History, on). Retention and the other History options stay in History.
7. **Microphone test:** 3 seconds, a level bar and a result in words; nothing saved, no playback.
8. **Shortcut capture** pauses EsyType's shortcuts, with automatic restore after 20 seconds or on focus loss, and also replaces the typed fields in Settings.
9. **Decision 0009: option A** (section 6).
10. **Run setup again** in Settings → About; it never deletes anything.
11. **No new dependencies, no downloads.** Tests serve the models from a local server using the model files already on this PC.

## 8. Tests

- **Unit:**
  - `setup_done`: missing with a model installed → true; missing with none → false; true kept
  - the recommendation rule (Base; Tiny when Base does not fit; none when nothing fits)
  - shortcut capture rules (allowed, refused and duplicate combinations)
- **End to end, new `firstrun-e2e.ps1`** (test build, an empty test profile, models served by a local server from the files already on D:, no internet):
  - every step by keyboard and mouse; Back keeps choices
  - download: cancel, Retry resumes, speed and time left shown, "Verified" shown
  - a damaged file served on purpose: rejected, removed, message shown
  - server not running: the error in words, Retry works once it runs
  - microphone test with the test build's audio: level shown, "We heard you"
  - capture `Ctrl+F8`, then dictate with it in Try it; shortcuts restored after a cancelled capture and after the 20-second limit
  - Finish: window hides to the tray, `setup_done` saved; restart shows the normal window
  - started with `--minimized` on an empty profile: the wizard shows
  - existing-user profile (model installed, no flag): no wizard, flag set, settings otherwise unchanged
  - Run setup again: History, Dictionary, Snippets and notes untouched
- **Updated:** `navigation-e2e.ps1` and the UI suites, if any control they use moves (the Settings → Shortcuts fields do).
- **Full regression** of every suite, plus the dictation-time check (thread probe at Automatic, idle and half load, repeated, median and range).
- **Layout:** every step at 100% and 200% zoom and at the minimum window size.
- **Production:** installed after the tests (quit only the installed copy). Check it opens straight to the normal window, `setup_done` is set, and History, settings and the startup entry are intact.

Same limits as Milestone 1: no Notepad steps while your Notepad is open, never ChatGPT.

## 9. Order of work

1. `setup_done` and its start-up rule, with unit tests (safe on its own)
2. The wizard shell (step counter, Back/Continue) and steps 1, 2, 3 and 8
3. Download step additions (speed, time left, Retry, checking step)
4. Microphone test (`mic_test`)
5. Shortcut capture (`pause_shortcuts`) in the wizard and Settings
6. Try it step, Run setup again
7. Tests, full regression, production install, documentation
