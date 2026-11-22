# Phase 5, Milestone 1: Foundation. Plan

**Date:** 21 November 2026 · **Status:** approved by the owner (21 Nov); **built, tested and installed** (`docs/testing/2026-11-21-foundation.md`)
**Parent plan:** `phase-5-audit-and-plan.md`
**Scope:**
- the settings-file fix
- sidebar navigation
- Dictation as a home screen
- a Settings page
- shared states (empty, loading, error, dialog, toast) and icons

Not in scope:
- the first-run wizard (Milestone 2)
- export, import and backup (Milestone 3)
- per-page redesign (Milestone 4)
- the installer (Milestone 5)

Speech, cleaning and insertion code is not changed.

## 1. Settings-file safety (first, Rust)

Today: if `settings.json` cannot be read, the defaults are used silently and the next save overwrites the file.

| Case | New behaviour |
|---|---|
| File missing (first start) | Defaults, as today; no message |
| Valid file with one or more values of the wrong type or unknown values (for example `"threads": "3"`) | Keep every readable value; only the bad ones go back to their defaults. The original file is kept as `settings.damaged-<date-time>.json` next to it. The window shows a banner: "Some settings could not be read and were reset: Processor threads. Your original file was kept." |
| Not valid JSON at all (damaged, empty, truncated) | The original is kept as `settings.damaged-<date-time>.json`; defaults are used; banner: "Your settings file could not be read, so EsyType is using default settings. The original was kept as …" with **Show in folder** |
| Saving | Unchanged (temporary file, then rename). The damaged copy is never deleted by EsyType |

- Unknown extra fields from a newer version are not an error (serde ignores them, as today).
- At most 5 damaged copies are kept. Only when there are more than 5 is the oldest removed, so a loop of failures cannot fill the disk.
- Unit tests: missing, valid, one wrong-type field, several, not JSON, empty file, a newer version's extra fields, the damaged copy written once and the original file untouched until the next save.

## 2. Navigation: a sidebar

- **Shape:** left sidebar per the design system (section 8.4): 224 px wide, the wordmark "EsyType." at the top.
- **Items:** icon and label each.
  - Order: Dictation, History, Dictionary, Snippets, Style, Scratchpad; then a divider and **Settings** at the bottom.
  - No "Soon" items: Notetaker, Insights and Transforms do not exist and are not shown.
- **Footer:** the engine status, always visible:
  - "Local · Base · 4 threads" with a green dot
  - amber "Loading model…"
  - red "Model failed to load", opening Settings → Speech model
- **Keyboard and accessibility:**
  - Up/Down arrows move between items, Enter opens.
  - The current page is marked for screen readers (`aria-current`).
  - Item names stay exactly as today ("Dictation", "History", "Scratchpad" …), so the tray's "Open Scratchpad" and the tests keep working.
- **Window:** the default size (980 × 720) and the minimum (760 × 560) stay; the page area scrolls, the sidebar does not.

## 3. Dictation becomes the home screen

Top to bottom:
1. **"Hold `Ctrl+Space`, speak, release."** and the start/stop and Esc line (as today), with a warning banner if a shortcut could not be registered.
2. **Try it:** the practice box (its accessible name "Practice area" kept).
3. **Last dictation:**
   - length, time taken and outcome, in words (as today)
   - an empty state before the first dictation: "Your first dictation will appear here."
4. **Text mode:** the Clean / Verbatim switch (the most used setting; also in the tray). Clean's two options move to Settings → Text.

Everything else on today's Dictation tab moves to Settings.

## 4. Settings page

One scrolling page with a short list of sections at the top (jump links):

| Section | Contents (moved, unchanged in behaviour) |
|---|---|
| Speech model | The three model cards, download, progress, cancel; the hardware line |
| Microphone | Device choice and the "not connected" warning |
| Shortcuts | Hold to talk, start/stop, Undo, Paste last; Save; the examples and the Ctrl+Space note |
| Text | Clean's options (zero to nine as words; extra fillers); the dictionary hint stays on the Dictionary page |
| Undo | "Show Undo on the pill", the never-offer list, the explanation |
| Startup and performance | Start with Windows; processor threads with the Automatic explanation |
| Storage | The model folder and Move |
| Data and privacy | Where EsyType keeps data (the data folder and the model folder, with Show in folder); a link to History's privacy controls, which stay on the History page in this milestone and move here in Milestone 3 with the data tools |
| About | "EsyType. by EsyAI.", version, "Runs on this PC. The only internet use is downloading the speech model you choose." |

## 5. Shared states and components

| Component | Used for | Replaces |
|---|---|---|
| **Dialog** (in-window, `role="dialog"`, focus kept inside, Esc cancels, primary action on the right, named by its action: "Delete", "Delete all", "Continue") | Every confirmation (12 today) | The browser's `confirm()` boxes |
| **Toast** (bottom centre, up to 6 s, optional action, announced to screen readers) | "Settings saved", "Exported to Downloads" with **Show in folder**, "Deleted" | One-line status texts after save and export |
| **Banner** (inline, red or amber, icon and words) | Database unavailable, shortcut not registered, damaged settings, save failed | Bare red text |
| **Empty state** (icon, one display-italic line, one sentence, one button) | History, Dictionary, Snippets, Scratchpad, Last dictation | One grey sentence (the current sentences are kept as the grey line, so the tests still find them) |
| **Loading** | The window's first moment (a quiet skeleton of sidebar and page instead of "Loading…"); a disabled state on buttons while they work | "Loading…" |
| **Icons** | About 14 simple line icons drawn for EsyType in the design system's style (24 grid, 1.75 stroke, `currentColor`), as inline SVG | None today; no icon library is added |

## 6. Defaults to approve

1. **Bad values reset one at a time**, the original file kept, and a banner saying which settings were reset (section 1).
2. **Sidebar** with the six pages and Settings at the bottom; **no "Soon" items** (section 2).
3. **Clean / Verbatim stays on the home screen**; Clean's options move to Settings → Text (section 3).
4. **History's privacy controls stay on the History page** until Milestone 3 (Settings links to them), so they move only once.
5. **Confirmation buttons are named by their action** ("Delete all", "Cancel"), not "OK".
6. **System fonts for now.** The brand fonts (Instrument Serif, Barlow) need a small download and stay a separate decision; the layout is built so they drop in later.
7. **No new dependencies, no downloads:** icons are drawn inline; dialogs and toasts are written in the existing React code.

## 7. Tests

- **Unit:** the settings cases in section 1; the existing 47 stay green.
- **End to end, new:**
  - `navigation-e2e.ps1`: every sidebar item opens its page by mouse and keyboard; the tray's Open Scratchpad lands on Scratchpad; the footer status matches the engine.
  - `settings-recovery-e2e.ps1`: damaged file, one wrong value, not JSON; banner, kept copy, readable values preserved, shortcuts still work.
- **End to end, updated:**
  - the seven UI suites (`clean`, `dictionary`, `history-ui`, `scratchpad`, `snippets`, `style`, `tryit`), for the new places (Settings) and the dialog button names
  - `uia.ps1`'s dialog helper
- **Full regression** of every suite, plus a dictation-time check (the thread probe at Automatic, idle and half load, repeated, median and range), to show dictation is unchanged.
- **Text size:** pages checked at 100%, 150% and 200% zoom in the test build's window. This uses the window's own zoom, not Windows' display setting, which is a system change.
- **Production:** installed as before, after the tests (quit only the installed copy; verify History, settings, the startup entry); the new settings code reads the owner's real `settings.json` unchanged.

## 8. Order of work

1. Settings-file fix and its tests (can ship on its own if the rest takes longer)
2. Components (dialog, toast, banner, empty state, icons)
3. Sidebar and footer
4. Home screen
5. Settings page
6. Replace `confirm()` and status lines across the pages
7. Update and add tests; full regression; production install; documentation
