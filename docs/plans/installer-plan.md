# Phase 5, Milestone 5: Windows installer. Plan

**Date:** 22 November 2026 · **Status:** defaults approved by the owner (22 Nov); **built, tested and installed on the owner's PC** (`docs/testing/2026-11-22-installer.md`). Added while building, with the owner's OK: an EsyType side panel on the welcome and last pages; the installer's desktop-shortcut box kept. Changed: downgrades are refused through `allowDowngrades: false` (Tauri allows them by default); deleting data is done in the uninstaller window, as this Tauri version has no command-line option for it
**Parent plan:** `phase-5-audit-and-plan.md` (Milestone 5; owner decisions 4, 5 and 6) · **Builds on:** the scripted production copy (`scripts/install-local.ps1`), EsyType re-pointing its own start-with-Windows entry when it starts, and Milestone 3's Delete all EsyType data

**Scope:**
1. A per-user Windows installer, with no administrator prompt
2. Upgrades that keep every setting, History, Dictionary, Snippets, notes and models
3. Taking over from today's scripted copy at `D:\EsyAI\EsyType\app`
4. An uninstaller, registered in Windows' Apps list, that keeps your data unless you tick to remove it
5. A test matrix that never touches your installed EsyType or your data, then the switch of your PC to the installer

**Not in scope:**
- automatic updates: they need a signing key and an update server
- code signing: waits for ESYAI's certificate (decision 6)
- an all-users (Program Files) install: needs administrator rights
- bundling a speech model in the installer: models stay a choice in the first-run wizard
- brand fonts: still a separate decision

Speech, cleaning and insertion code is not changed.

## 1. What exists and what is missing

| Piece | Today | Milestone 5 |
|---|---|---|
| Program | `npx tauri build` gives `esytype.exe` (18.7 MB) plus the voice-activity model (0.9 MB) | The same two files, packed by Tauri's own NSIS bundler |
| Install | `install-local.ps1` copies them to `D:\EsyAI\EsyType\app` and makes a Start menu shortcut | An installer: folder choice, Start menu shortcut, Apps-list entry, uninstaller |
| Start with Windows | EsyType writes its own entry (`HKCU\...\Run`, value "EsyType") and re-points it at whichever copy runs | Unchanged. The uninstaller removes the entry |
| Data | `%LOCALAPPDATA%\EsyAI\EsyType` (settings, database, models by default); a models folder can be moved anywhere | Never touched by installing or upgrading. Uninstall keeps it unless you tick to remove it |
| Uninstall | None: nothing in Windows' Apps list; the startup entry would be left behind | Section 5 |
| NSIS tools | **Not on this PC.** The Tauri bundler downloads them on the first installer build | Section 7: needs your yes |

## 2. The installer

- **Built by Tauri's NSIS bundler.** It is part of the Tauri CLI already installed. Configuration in `tauri.conf.json` only (`bundle.active`, `targets: ["nsis"]`), plus one small hooks file (`src-tauri/installer-hooks.nsh`) for the uninstall steps Tauri does not do. No custom installer template, no new dependency.
- **Install for this user only** (`installMode: currentUser`): no administrator prompt.
  - Default folder: `%LOCALAPPDATA%\EsyType` (Tauri's default for per-user installs).
  - The folder page lets you choose another. On this PC that is `D:\EsyAI\EsyType\app`, where EsyType is now, because C: has only 0.4 GB free.
  - Upgrades go to the folder of the previous install without asking again.
- **Shown in the Apps list** as "EsyType", publisher "EsyAI", with version, size and icon. The installer and uninstaller use the app icon.
- **Start menu:** "EsyType" (one shortcut, replacing the one the script made).
- **At the end:** a "Run EsyType" tick box, on by default. EsyType then starts as usual: the wizard for a new user, the tray for an existing one.
- **Start with Windows** stays EsyType's own setting: on by default, in the wizard and in Settings. There is no separate installer tick box. The parent plan suggested one, but it would duplicate the setting and need a custom installer page.
- **WebView2** (the browser engine the window uses) is part of Windows 11.
  - The installer's default mode (`downloadBootstrapper`) downloads it from Microsoft only on a PC that lacks it, such as an old Windows 10.
  - That is the installer's only possible network use, and it never happens on Windows 11.
- **Language:** English.
- **Unsigned for now:** Windows SmartScreen will say "Windows protected your PC". Choose More info, then Run anyway. Fine for your testing, not for customers.
- **Version:** the first installer is **0.2.0** (today 0.1.0), set in `tauri.conf.json`, `Cargo.toml` and `package.json` together. Each later installer raises it.

## 3. Upgrades

- **Running EsyType is closed first.** The installer asks; in silent mode it closes it. It looks for the program file name, so a different program is never closed.
- Only the program folder is replaced. Settings, History, models and the data folder are not touched. A database upgrade, if a version brings one, happens as today when EsyType starts (forward-only, with a backup during the upgrade).
- **An older installer over a newer install** is refused by the bundler's version check. A newer database is also refused by EsyType itself (downgrade protection, already tested).
- **Taking over from the scripted copy:**
  - install into the same folder, `D:\EsyAI\EsyType\app`
  - the installer replaces the two files and the Start menu shortcut, and adds the Apps-list entry
  - EsyType re-points its start-with-Windows entry when it starts
  - `install-local.ps1` is then retired for your production copy (section 9, item 7)

## 4. Data stays where it is

Nothing in this milestone moves `%LOCALAPPDATA%\EsyAI\EsyType`. The program folder and the data folder stay separate, as they are today.

## 5. Uninstall

- **Always removed:**
  - the program folder
  - the Start menu shortcut
  - the Apps-list entry
  - the start-with-Windows entry (the "EsyType" value under `HKCU\...\Run`; by our hook, skipped during an upgrade, which Tauri also runs through the uninstaller)
- **"Delete the application data" tick box,** off by default. When ticked:
  - Tauri removes its own browser-engine folder (`%LOCALAPPDATA%\uk.co.esyai.esytype`)
  - our hook removes **only EsyType's own files** in `%LOCALAPPDATA%\EsyAI\EsyType`:
    - `settings.json` and kept damaged-settings copies
    - the database and its log files, and upgrade backups
    - restore safety copies and a pending restore
    - downloaded models and unfinished downloads in the default models folder
  - then the folders, if they are empty. Anything else you put there stays.
  - A **removal of the whole folder tree** (`RMDir /r`) is deliberately not used: it follows folder links (junctions) out of the folder (a known Tauri issue, tauri-apps/tauri#16323), and it would delete files that are not EsyType's.
- **A models folder you moved elsewhere** is not removed by the uninstaller; it cannot read where you moved it. Settings → Data and privacy → Delete all EsyType data, with the models ticked, removes it before uninstalling. The uninstall page's text says so.
- Exports and backups you saved in Downloads are never touched.

## 6. Testing without touching your EsyType

Installers write to your user account: the Apps list, the Start menu, the startup entry, and they close a running program by its file name. So the test installers are a **separate product, "EsyType Test"**:

| | Your EsyType | EsyType Test (test installers only) |
|---|---|---|
| Program file | `esytype.exe` | `esytype-test.exe`, so the installer can never find and close yours |
| Identifier | `uk.co.esyai.esytype` | `uk.co.esyai.esytype.test` (own single-instance lock, own Apps-list entry, own browser-engine folder) |
| Data folder | `%LOCALAPPDATA%\EsyAI\EsyType` | `%LOCALAPPDATA%\EsyAI\EsyType Test` (a test-only build switch) |
| Start menu, startup value | "EsyType" | "EsyType Test" |
| Install folder | yours | `D:\AI Projects\Tools\e2e\install-test\...` |
| Shortcuts | yours | F-key shortcuts (Ctrl+F8 and so on), set in its seeded settings, so nothing clashes with yours |
| Models | yours | the shared test models on D: (its seeded settings point there) |

- Made from the same code by one test-only Cargo feature (the data-folder name) and a Tauri config overlay (`tauri.test.conf.json`: product name, identifier, program name). The real installer is built without either.
- **While testing,** an "EsyType Test" entry appears in your Apps list and Start menu for a few minutes and is removed by the uninstall tests.
- The data folder lives on C:: a few MB, plus its browser-engine folder (tens of MB), all removed at the end.
- The tests check your EsyType's process, settings hash, History count and startup entry before and after every step.

**Test matrix** (installers run silently, `/S`, with the folder given; plus one interactive pass for screenshots):

1. **Clean install:** files in place, Apps-list entry, Start menu shortcut. It starts, the wizard opens on an empty profile, start-with-Windows points at it.
2. **Take-over from a scripted copy** (made by the script into a test folder): one Start menu shortcut, startup entry re-pointed, data unchanged.
3. **Upgrade 0.2.0 → 0.2.1:**
   - same folder
   - data and settings byte-for-byte unchanged
   - History count unchanged
   - the Apps list shows 0.2.1
   - a running EsyType Test is closed and your EsyType is not
4. **Older over newer:** refused, nothing changed.
5. **Uninstall, keep data (default):**
   - program, shortcut, Apps-list entry and startup entry gone
   - every data file still there
   - reinstall finds them: settings and History back, no wizard
6. **Uninstall, delete data** (`/DELETEAPPDATA`):
   - EsyType's files gone
   - a file of yours placed in the folder is kept
   - a folder link inside it is not followed (the files it points to stay)
   - the browser-engine folder is gone
7. **Throughout:** your EsyType keeps running with the same process; your settings hash, History count and startup entry are unchanged.
8. **Interactive pass:** screenshots of each installer and uninstaller page at 100% and 200% for you to see.

Then the **full regression** as usual (the program is unchanged apart from the version, so the dictation-time check confirms nothing moved), on mains.

## 7. The NSIS download (needs your yes)

- **What:** the first installer build makes the Tauri bundler download NSIS 3.11 and Tauri's small NSIS plugin.
- **Size and source:** a few MB in total, from Tauri's own GitHub releases.
- **Where:** saved under `%LOCALAPPDATA%\tauri` (on C:).
- **What it is:** a build tool on this PC only. Nothing is added to EsyType itself.
- I will ask again right before it happens, with the exact file names and sizes.

## 8. Switching your PC to the installer (last step)

1. **Back up your data** with Back up now's code, from a copy, as in Milestone 3 (a `.esytype-backup` in `D:\EsyAI\EsyType\backups`), and check it by restoring it into a test profile.
2. **Quit only your installed EsyType.**
3. **Run the real 0.2.0 installer** into `D:\EsyAI\EsyType\app`.
4. **Check:**
   - settings by hash, History count, schema
   - the startup entry points at the same `esytype.exe`
   - one Start menu shortcut
   - "EsyType 0.2.0" in the Apps list
   - EsyType in the tray with no window

## 9. Defaults to approve

1. **Tauri's NSIS installer, per user, no administrator prompt;** English; unsigned until the certificate exists.
2. **Install folder:** Tauri's per-user default (`%LOCALAPPDATA%\EsyType`) with a folder page to change it; on this PC, `D:\EsyAI\EsyType\app`. Upgrades reuse the folder.
3. **No start-with-Windows tick box in the installer:** EsyType's own setting stays the one place (on by default).
4. **WebView2:** downloaded from Microsoft only on a PC that lacks it (never on Windows 11).
5. **Uninstall keeps your data by default.** With "Delete the application data" ticked, only EsyType's own known files go (no folder-tree deletion). A moved models folder stays, and the page says so.
6. **First installer version 0.2.0.**
7. **After the switch, production updates come from the installer;** `scripts/install-local.ps1` stays in the repository for reference but is no longer used for your copy.
8. **Testing through a separate "EsyType Test" product** (section 6), with its brief entries in your Apps list and Start menu, and small test data on C:.
9. **The NSIS download** (section 7), asked again right before it happens.
10. **No other downloads and no new dependencies.**

## 10. Order of work

1. Version 0.2.0, bundle configuration, uninstall hooks, the test overlay and the test-only data-folder switch
2. Ask for the NSIS download, then build the test installers (0.2.0 and 0.2.1)
3. The test matrix (`installer-e2e.ps1`), then the interactive screenshots
4. Full regression and dictation time, on mains
5. Back up your data, switch your PC to the real installer, check, document
