# Phase 5: Product polish and first-run experience. Audit and plan

**Date:** 21 November 2026 · **Status:** audit complete; plan **awaiting owner approval**; no code changed for this phase
**Fixed by the owner:**
- AI Enhancement is deferred
- no additional models or cloud services
- Whisper Tiny, Base and Small only
- local and private
- dictation performance and reliability must not get worse
- no downloads, SDKs or unnecessary dependencies without approval
- production and test builds kept apart, and user data preserved

Numbering: this phase replaces the old "Phase 5: AI enhancement", which stays deferred and unnumbered (decision 0022). The old Phase 6 (advanced interface) and Phase 7 (installer) items needed here are taken into this phase. The rest stay where they are.

## 1. What exists today (audited from the code, not the plan)

Legend:
- **Exists**: built and tested; reuse it, do not rebuild
- **Partial**: some of it exists
- **Missing**: not built

### 1.1 Interface

| Item | State | Where / notes |
|---|---|---|
| Main window, dark theme, brand colours | **Exists** (a subset of the design system) | `src/styles.css`: tokens, panels, cards, chips, buttons, inputs, tabs, progress bar, pill |
| Navigation | **Partial** | Six pill tabs across the top (Dictation, History, Dictionary, Snippets, Style, Scratchpad). The design system specifies a left sidebar with Settings and Help pinned at the bottom; not built |
| Settings page | **Missing as a page** | Every setting lives on the Dictation tab in seven panels: Try it, Speech model, Text, Microphone and performance, Model storage, Shortcuts, Undo list. It reads as a settings dump, not a home screen |
| History, Dictionary, Snippets, Style, Scratchpad pages | **Exist**, tested end to end | `src/history.tsx`, `dictionary.tsx`, `snippets.tsx`, `style.tsx`, `scratchpad.tsx`. Search, edit, delete and delete all, import and export (Dictionary, Snippets), export (Scratchpad) |
| Empty states | **Partial** | One grey sentence each ("No dictations saved yet.", "No snippets yet. Try your email signature…"). The design system's empty state (icon, one display line, one sentence, one button) is not built |
| Loading states | **Partial** | The whole window shows "Loading…" text until the first status arrives; a status chip shows "Loading model…" |
| Errors | **Partial** | Inline red text; a "database cannot be used" message on each data page. No consistent banner |
| Confirmations | **Partial** | The browser's `confirm()` box on every delete, which looks foreign in a premium app. The design system's Dialog is not built |
| Notifications | **Partial** | The recording pill (listening, processing, done with style, Undo, Use original, Copy, errors). No in-window toast |
| Icons | **Missing** | No icons in the window. The design system specifies Lucide; adding it is a dependency, so this plan uses a handful of inline SVG icons instead |
| Brand fonts | **Missing** | Instrument Serif and Barlow are not bundled (system fonts are used, as `styles.css` notes). Bundling them needs a download, so it is an owner decision (section 4) |
| App icon | **Partial** | `src-tauri/icons` holds a placeholder icon and a source image; the designed icon and the tray recording variant are not made |
| Accessibility | **Partial** | Labels, focus ring, keyboard-reachable controls and reduced-motion support on the pill. Not done: forced-colours (high contrast) styles, testing at 125–200% text size, a live region announcing dictation state |
| About, licences, network requests list | **Missing** | Planned in the architecture (section 13) |

### 1.2 First run

| Item | State | Where / notes |
|---|---|---|
| Welcome screen | **Partial** | With no model installed, the window shows a single page: "Private · On this PC · No account", "Speak. It types.", one sentence, then the model chooser |
| Privacy explanation | **Partial** | The one sentence and the eyebrow chip; no explanation of what stays on the PC, the one network request (the model download) or History |
| Tiny / Base / Small selection | **Exists** | Model cards: size, memory, speed, languages, a fit chip and a Recommended badge (`main.tsx`, `models.rs`). Exactly three models; Base recommended |
| Hardware recommendation | **Partial** | RAM, storage, CPU name, threads and AVX2 are detected (`hardware.rs`); the fit chips are "Fits this PC", "May feel slow" (from the dev PC's speed) and "Not enough memory / storage". The recommendation is always Base; there is no speed check on the user's own PC |
| Download progress | **Exists** | Percentage and MB, cancel, resume from a partial file; pinned download address |
| SHA-256 verification | **Exists**, unit-tested | Every model is verified before use (`models.rs`); a failed file is rejected. The window does not show a "Verifying" step or say that it was verified |
| Microphone selection | **Exists** (not in first run) | Device list and the Windows default with a fallback warning; no level meter or test |
| Shortcut configuration | **Exists** (not in first run) | Typed text fields ("Ctrl+Space"), saved and registered, with an error if registration fails. No "press the keys" capture; the default hold-to-talk key (decision 0009) is still open |
| Final confirmation / practice | **Partial** | The "Try it" box on the Dictation tab |
| First-run detection | **Partial** | "No model installed" means first run. There is no setup-complete flag, so a wizard would need one, with existing users (who have a model) treated as set up |

### 1.3 Settings and data

| Item | State | Where / notes |
|---|---|---|
| Settings storage | **Exists**, with one **defect** | `settings.json` is written atomically (temporary file, then rename). **Defect found in this audit:** if the file cannot be read (damaged, or a value of the wrong type), `settings::load` silently uses the defaults, and the next save **overwrites the user's file**: settings lost, shortcuts back to Ctrl+Space. Seen for real during the 21 Nov benchmark, with the test build's own settings |
| Settings export / import | **Missing** | |
| Backup / restore of user data | **Missing** | The database takes a backup copy only during a schema upgrade, and removes it afterwards. Dictionary, Snippets and Scratchpad export their own items; **History has no export** |
| Privacy controls | **Exist**, spread out | History on/off, retention (30/90 days, forever), record program names (never titles), keep originals, delete all with compaction. On the History tab |
| Data location and size | **Missing** | No page shows where data is or how big it is; there is a "show in folder" command, used for exports |
| Delete everything | **Missing** | Each kind of data has its own delete-all |

### 1.4 Installation

| Item | State | Where / notes |
|---|---|---|
| Production copy | **Exists** | `scripts/install-local.ps1`: refuses a test build, refuses while EsyType runs, copies to `D:\EsyAI\EsyType\app`, checks the copy by hash, writes the Start menu shortcut, starts EsyType; the app writes its own start-with-Windows entry |
| Data kept apart from the program | **Exists** | Settings, database and models are in `%LOCALAPPDATA%\EsyAI\EsyType` (models can be moved), never in the program folder |
| Upgrades keep data | **Exists** for the database | Forward-only migrations, a backup during the upgrade, refusal to open a newer database (downgrade protection); tested v1 → v6 with the owner's data |
| Single instance | **Exists** | |
| Windows installer | **Missing** | `tauri.conf.json` has `"bundle": { "active": false }`. The architecture plans NSIS, per user, with no administrator prompt. The Tauri bundler fetches the NSIS tools on first use: a download, so an owner decision |
| Uninstall | **Missing** | Nothing registered in Windows' Apps list; the start-with-Windows entry would be left behind |
| Code signing | **Missing** | Needs a certificate procured by ESYAI |
| Updates | **Missing** | Planned (signed updater); not part of this phase unless the owner asks |

## 2. Risks to protect while changing the interface

- **Dictation must not get slower or less reliable.** The changes are to the window, settings and packaging. The speech, cleaning and insertion code is not touched. Every milestone ends with the full end-to-end regression, idle and under load where timing matters (the owner's 21 Nov rule: repeated runs, median and range).
- **Seven UI test suites** (`clean`, `dictionary`, `history-ui`, `scratchpad`, `snippets`, `style`, `tryit`) find controls by their visible names ("Scratchpad", "Practice area", "Verbatim…", "Delete all history"). A navigation change keeps those names or updates the suites in the same change.
- **Existing users must not see the first-run wizard again.** A new "setup complete" flag counts as set when a model is already installed.
- **Restore and import must never destroy current data.** A safety copy is always taken first, and the file is checked (version and hashes) before anything is replaced.

## 3. Plan: five milestones, one at a time

Each milestone gets the usual cycle:
1. A short plan in `docs/plans/`
2. Owner approves the defaults
3. Build
4. Unit and end-to-end tests in the test build
5. Install production (quit only the installed copy; verify History, settings and the startup entry)
6. Documentation

### Milestone 1: Foundation (navigation, Settings page, shared states) and the settings-file fix

- **Settings-file safety (first, small):**
  - If `settings.json` cannot be read, keep it as `settings.damaged-<date>.json`, run on the defaults, and say so in the window.
  - Never overwrite an unreadable file silently.
  - A value of the wrong type falls back for that field only, keeping the others.
  - Unit tests.
- **Sidebar navigation** per the design system (section 8.4):
  - Dictation (home), History, Dictionary, Snippets, Style, Scratchpad; then Settings at the bottom.
  - The footer shows the engine status ("Local · Base · 4 threads"), so the privacy promise is always visible.
  - No "Soon" items for features that do not exist.
- **Dictation becomes a real home:** shortcut reminder, Try it box, last dictation (time, outcome), engine status, Clean/Verbatim switch.
- **Settings page** gathers what is on the Dictation tab today, in sections:
  - Speech model
  - Microphone
  - Shortcuts (including Undo)
  - Text
  - Startup and performance
  - Storage
  - Data and privacy (the History privacy switches move here or are linked)
  - About
  
  Controls, behaviour and saved settings are unchanged.
- **Shared components** from the design system, used by every page:
  - empty state (icon, line, sentence, button)
  - dialog, replacing every `confirm()`
  - toast (saved, exported, undone; with an action where useful)
  - error banner
  - loading skeleton
  - about ten inline SVG line icons, with no icon library added
- **Tests:** update the seven UI suites; full regression; check at 100%, 150% and 200% text size.

### Milestone 2: First-run wizard

One step per screen (design system section 8.6), reusing Milestone 1's components and the existing model, microphone and shortcut code:
1. **Welcome.**
2. **Privacy:** what stays on this PC, the single network request (the model file, from a fixed address, checked by SHA-256), History and how to turn it off.
3. **This PC:** CPU, memory, storage, AVX2, with status chips.
4. **Model:** the three cards with the hardware recommendation.
5. **Download:**
   - progress, speed and time left
   - retry and cancel
   - a visible "Checking the file (SHA-256)… Verified" step
6. **Microphone:** choose, a live level meter (the pill already receives levels), a short test recording.
7. **Shortcuts:**
   - press the keys to set them
   - checked by registering them, with a warning if another program holds them
   - the default decided by the owner (decision 0009)
8. **Try it:** a practice box.
9. **Done:** a summary and "Start in the tray".

Existing users skip it; it can be reopened from Settings. **Tests:** a clean test profile run end to end (with the local model server the unit tests already use, so no internet), plus an existing-user profile that must not see it.

### Milestone 3: Settings and data management

- **Settings export / import:**
  - a JSON file of the settings
  - import checks every value, shows what will change, keeps the current microphone and model folder unless asked, and re-registers shortcuts
- **Backup / restore:**
  - one folder per backup holding a consistent copy of the database (SQLite's own `VACUUM INTO`, no new dependency), `settings.json` and a manifest (app version, schema version, SHA-256 of each file)
  - models are left out (large, and they can be downloaded again), with an option to include them
  - restore checks the manifest and refuses a newer schema; it takes a safety copy of the current data first, replaces, then reopens the database
- **History export** (CSV and JSON), like the Dictionary's.
- **Data and privacy page:**
  - where each kind of data is stored and how large it is
  - open the folder
  - the History privacy switches
  - "Delete all EsyType data" with a dialog that lists what goes and what stays (models optional)
  - the network-requests list from the architecture (model download only)
- **Tests:** round trips (export → import, backup → restore) on copies of real-shaped data, damaged and newer-version backups refused, a restore that fails half-way leaves the old data in place.

### Milestone 4: Page polish

- History, Dictionary, Snippets, Style and Scratchpad on the shared components:
  - consistent toolbars (search, import/export, delete all in the same places)
  - empty states with a first action
  - keyboard use (arrow keys in lists, Esc closes dialogs)
  - toasts instead of status lines
- Accessibility pass: forced colours, the live region, pointer targets.
- The designed app icon and the tray recording variant (made locally from the existing source image).

### Milestone 5: Windows installer

- **Installer:** Tauri's NSIS bundler, per user, no administrator prompt, Start menu shortcut, optional start with Windows, registered in Windows' Apps list.
- **Install location:** the default and whether it can be changed is an owner decision (today `D:\EsyAI\EsyType\app`; the C: drive is nearly full on the development PC).
- **Upgrade:**
  - closes the running EsyType
  - replaces only the program folder
  - data and models untouched
  - database migrations as today
  - takes over from the current scripted copy (the start-with-Windows entry is re-pointed)
- **Uninstall:**
  - removes the program, shortcuts and the start-with-Windows entry
  - asks whether to also remove settings, History, notes and models; the default is to keep them
  - Tauri's own "delete app data" option does not cover EsyType's data folder, so this needs an uninstall hook
- **Test matrix:** clean install, upgrade from the scripted copy, upgrade between two installer versions, uninstall keep-data and remove-data, reinstall finds kept data. Run on a test Windows user account where possible, never against the owner's data without a backup.
- Signing waits for ESYAI's certificate. An unsigned installer shows Windows SmartScreen's warning, which is fine for testing but not for customers.

## 4. Decisions needed from the owner

| # | Decision | Recommendation | Needed by |
|---|---|---|---|
| 1 | Approve this plan and Milestone 1 first | Yes (section 5) | Now |
| 2 | Bundle the brand fonts (Instrument Serif, Barlow; open licence) | Yes: a one-time download of a few hundred KB of font files, kept in the app, never loaded from the internet. Until then, system fonts | Milestone 1 or 4 |
| 3 | Default hold-to-talk shortcut (decision 0009, open since the start) | Decide before the wizard; Ctrl+Space clashes with Windows' input-language switch and code editors | Milestone 2 |
| 4 | Let the Tauri bundler download NSIS (a few MB) to build the installer | Yes, when Milestone 5 starts; asked again then | Milestone 5 |
| 5 | Install location: Windows' standard per-user folder on C:, or a choice in the installer (D: on this PC) | Offer the choice, defaulting to the standard folder | Milestone 5 |
| 6 | Code-signing certificate | Procured by ESYAI before any public release | Before release |

## 5. Recommended first milestone: Milestone 1 (foundation and the settings-file fix)

Why this one first:
1. **It fixes a real data-loss defect.** A damaged or mistyped `settings.json` is silently replaced with defaults today. It is small and fits the reliability-first rule.
2. **Everything else builds on it:**
   - The wizard reuses the model, microphone and shortcut controls, once they are separate components on the Settings page.
   - Data management needs the Settings page and the dialog.
   - Page polish needs the empty state, toast and dialog.
   
   Building the wizard first would mean building those pieces twice.
3. **It is the most visible gain in polish for the least risk:**
   - The window stops being one long settings page.
   - Every page gets consistent states.
   - No speech, cleaning or insertion code changes, so dictation performance is untouched by construction (and re-measured anyway).
4. **It needs nothing new:** no download, no dependency, no SDK. Fonts are optional (decision 2).
5. **It keeps the tests honest:** the seven UI suites are updated once, at the start, rather than on every later milestone.

Expected size: about the same as one Phase 4 step. The next step, on the owner's approval, is the Milestone 1 plan with its defaults (`docs/plans/foundation-plan.md`).
