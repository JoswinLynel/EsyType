# Phase 5, Milestone 1: Foundation. Test record

**Date:** 21 November 2026 · **Plan:** `docs/plans/foundation-plan.md` (defaults approved by the owner) · **Builds:** e2e test build (separate folder), then the installed production copy · **Nothing downloaded; no dependency added**

## What was built

- **Settings file safety** (`settings.rs`):
  - A `settings.json` that cannot be read in full no longer silently becomes the defaults that the next save writes over it.
  - Values that read are kept; only the bad ones reset.
  - The original is copied to `settings.damaged-<date>-<time>.json` (newest five kept) and is not rewritten at start-up.
  - A banner names what was reset, with Show in folder and Dismiss.
- **Sidebar** with Dictation, History, Dictionary, Snippets, Style, Scratchpad and Settings:
  - icons drawn inline
  - arrow keys move between items
  - the footer always shows "Local · model · threads"
  - icons only when the window is narrow or text is large
- **Dictation home:** shortcuts, Try it, Last dictation (with an empty state), Clean/Verbatim.
- **Settings page:**
  - sections: Speech model, Microphone, Shortcuts, Text, Undo, Startup and performance, Storage, Data and privacy (data and model folders, Open folder), About
  - controls and saved settings unchanged
- **Shared states** (`src/ui.tsx`):
  - an in-window dialog replaces all 12 browser `confirm()` boxes: action named, destructive actions red with Cancel focused, Esc cancels, the rest of the window inert while open
  - toasts for saved/exported/copied (with Show in folder) and errors
  - banners for database, shortcut, model and settings problems
  - empty states on History, Dictionary, Snippets, Scratchpad and Last dictation
  - a loading skeleton
  - styles for Windows' high-contrast themes
- **Fixed on the way:** model cards showed speeds such as "1.2000000476837158 s" (now "1.2 s"), and the document itself could scroll beside the page (two scrollbars).

Speech, cleaning and insertion code are not changed. The only other Rust changes are two commands (dismiss the banner, open EsyType's own folders) and, in test builds only, a page-zoom option for layout checks.

## Results

| Test | Result |
|---|---|
| Unit tests | **49 of 49** (2 new: reading settings in every damaged form; at most five kept copies) |
| `settings-recovery-e2e.ps1` (new) | **10 of 10**: one wrong value (only it resets, banner names it, original copied and untouched, dictation works with the kept shortcut, Dismiss); not JSON (defaults, banner, copy, Show in folder); a good file (no banner, no copy) |
| `navigation-e2e.ps1` (new) | **14 of 14, three runs**: every page by mouse; arrow keys and Enter; footer status; every Settings section; Esc closes a dialog and keeps the note; a toast after Copy all |
| History UI / Dictionary / Snippets / Scratchpad / Style / Clean / Try it | **33/33, 13/13, 14/14, 15/15, 12/12, 10/10, 2/2** |
| History / Insertion (test windows, Word, Chrome) / Undo in Word and Chrome / Slow pasting | **19/19, 18/18, 8/8, 21/21** |
| Undo (test window) / Spacing (test windows, Word, Chrome) | **13/13, 14/14** after reruns (below) |
| Layout by screenshot (`ui-screenshots.ps1`) | Every page and the dialog checked at 100% and 200% zoom and at the minimum window size (760 × 560) |
| Dictation time, Automatic threads, 10 s clip | Idle on mains: **2.2 s** median (2.1–2.2 s), as before this milestone. Half load: 3.4 s median in 14 of 15 runs; 1 run produced no text in 2 minutes (on battery, below) |

### Failures found and what they were

- **Undo 9 of 13, Try it 1 of 2, spacing 10 of 12 in the full run.**
  - The full run happened with the PC on battery, and the Claude app sometimes took the foreground (the tests refuse to type then).
  - Run again on mains: Undo 13 of 13, Try it 2 of 2.
  - The pill was also checked directly: after a dictation it shows Done with Undo for its whole display time.
- **Spacing, unreadable app (failed the same way three times): a test bug introduced on 20 Nov.**
  - The suite's dictation counter read a JSON list through PowerShell 5.1's `ConvertFrom-Json`, which passes the whole list as one item. The count never rose after the first dictation, so each wait ran to its limit.
  - Harmless at the old 10 s limit. At the 60 s limit raised on 20 Nov, dictations were about 80 s apart, beyond the 60 s in which EsyType adds a space after its own dictation, so EsyType correctly added none.
  - Fixed in `spacing-e2e.ps1` and `slowpaste-e2e.ps1`; spacing then passed 12 of 12 test-window checks.
- **Spacing, Word "not in front".**
  - Closing the test's own window handed the foreground back to the Claude app, and Word started through automation was not allowed to take it. The test rightly refused to send keys.
  - The test now starts Word while its own window is still in front: 14 of 14.
- **Snippets import 13 of 14 once**: the step that types into Windows' file picker. 14 of 14 when run again.
- **History UI 31 of 33 once**: its own 7.5 s wait for dictated text ran out. Raised to 60 s like the other suites, then 33 of 33.
- **Navigation, Esc once did not close the dialog**: focus can land outside the dialog when the window is brought back to the front. The dialog now handles Esc wherever focus is (an app fix); then 14 of 14 three times.
- **One half-load dictation with no text in 2 minutes**, on battery (1 of 15 Automatic-thread runs under half load today, 0 of 12 this morning on mains). Its log was not kept (the probe overwrote it), so the cause is unknown. The probe now keeps one log per run. Recorded as open, not explained.

### Not run

- **Notepad steps:** your own Notepad was open (40 lingering Notepad processes from the 19–20 Nov test tabs share it), so suites ran with `-Apps word,chrome`, and `history-apps` (always Notepad) was skipped.
- **ChatGPT:** owner rule.
- **The five oldest suites** (dictation, reliability, restart, clipboard-vad, accuracy): they refuse to run while your EsyType is running (they use Ctrl+Space and its window title). Their checks are covered by the newer suites.
- **The real microphone suite.**
- **Windows' own display scaling** was not changed (a system setting); large text was checked with the test build's page zoom instead.

## Production

- Built with `npx tauri build` and installed with `scripts/install-local.ps1` after quitting only the installed copy.
- Checked after the install:
  - your `settings.json`: unchanged, and read without problems (no damaged copy made)
  - History: 5 entries
  - database schema: 6
  - startup entry: `D:\EsyAI\EsyType\app\esytype.exe --minimized`
  - the installed file matches the build
