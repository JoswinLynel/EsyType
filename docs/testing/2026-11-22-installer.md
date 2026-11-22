# Phase 5, Milestone 5: Windows installer. Test record

**Date:** 22 November 2026 · **Plan:** `docs/plans/installer-plan.md` (defaults approved by the owner; side panel and desktop-shortcut box approved while building) · **Builds:** "EsyType Test" installers 0.2.0 and 0.2.1 for testing; the real EsyType 0.2.0 installer, installed on the owner's PC · **Downloaded (owner approved):** NSIS 3.13 (2.4 MB) and `nsis_tauri_utils.dll` (34 KB), checked by the Tauri bundler against fixed SHA-1 values, kept on D: (`%LOCALAPPDATA%\tauri` is a folder link to `D:\AI Projects\Tools\tauri-tools`). No dependency added

## 1. What was built

**Configuration** (`src-tauri/tauri.conf.json`), using Tauri's own NSIS bundler:
- per-user install, no administrator prompt
- English, with EsyType's wording on the uninstaller's tick box (`src-tauri/installer-english.nsh`, a copy of Tauri's English text with the product name filled in where Tauri left a placeholder)
- the app icon for the installer and uninstaller; a black side panel with the waveform on the welcome and last pages (`icons/installer-sidebar.bmp`, drawn by `scripts/make-icons.py sidebar`)
- publisher "EsyAI"
- downgrades refused: Tauri allows them by default, and the plan said they are refused
- WebView2 fetched from Microsoft only on a PC without it

**Installer hooks** (`src-tauri/installer-hooks.nsh`):
- **After installing:** start with Windows points at the installed program, unless the settings file says it is off. Spacing in the file is ignored, because the owner's file was written by an older script with different spacing. This covers an interactive upgrade that runs the old uninstaller first.
- **After uninstalling** (not during an upgrade):
  - the start-with-Windows entry is removed
  - with "Also delete my settings, History, notes and downloaded speech models" ticked, EsyType's own files are deleted one by one, then its folders if empty
  - no folder tree is ever deleted, so folder links are not followed and your own files stay

**Version 0.2.0** in `tauri.conf.json`, `Cargo.toml` and `package.json`.

**Test product "EsyType Test":**
- `tauri.test.conf.json`: product name, identifier `uk.co.esyai.esytype.test`, program file `esytype-test.exe`
- Cargo feature `installer-test`: data folder `EsyAI\EsyType Test`
- Used only to build the test installers.

## 2. Found and fixed while building

1. **An interactive upgrade could turn off start with Windows.** It could, when "Uninstall before installing" was chosen and "Run" unticked. Fixed by the post-install step above.
2. **Downgrades were allowed** (Tauri's default). Now refused; tested.
3. **The bundler adds its own byte-order mark** to a custom language file. Two marks broke the build, so the file is saved without one.
4. **Tauri's English text shows `{{product_name}}` unfilled** in a few messages, such as "is running, please close it". EsyType's copy uses the product name.
5. **This Tauri version (CLI 2.12.5) has no `/DELETEAPPDATA` option.** A silent uninstall always keeps data; deleting data is through the uninstaller window, as from Windows' Apps list. The test ticks the box in that window.
6. **The first test-installer build ran out of memory.** C: was nearly full, so Windows' page file could not grow. Builds now run two compile jobs at a time and reuse already-compiled libraries.
7. **Silent installs also make a desktop shortcut** (the installer's default, kept by the owner). The tests now check it is made and removed.

## 3. Results

| Test | Result |
|---|---|
| `installer-e2e.ps1` (new, 36 checks, "EsyType Test" only) | **35/35 three times and 36/36 once** (the desktop-shortcut checks added last). Covers: clean install (files, Apps entry, Start menu, desktop shortcut, start with Windows, no data written, the wizard on first start); existing user in the tray; upgrade 0.2.0 → 0.2.1 while running (same folder, new version, running copy closed, data byte-for-byte unchanged, start with Windows kept); older over newer refused; uninstall keeping data (all files unchanged; program folder, shortcuts, Apps entry, startup entry gone); take-over of a scripted copy (one shortcut, startup entry re-pointed, kept data found, no wizard); start with Windows off stays off; uninstall deleting data through the window (EsyType's files and the browser-engine folder gone; a file of yours and a folder link's files kept). After every step: your EsyType's process, settings hash, History, startup entry, shortcut and Apps list unchanged |
| `installer-screenshots.ps1` (new) | Every installer and uninstaller page captured: welcome, folder, progress, finish, uninstall with the tick box, uninstalled |
| Unit tests | **59 of 59** |
| Full regression (final build, on mains) | Polish 25/25 ×2, data 27/27 (twice alone; once inside the run it stopped at its last step on a control not found), first run 32/32, navigation 14/14, settings recovery 10/10, History UI 33/33, Dictionary 13/13, Snippets 14/14, Scratchpad 15/15, Style 12/12, Clean 10/10, Try it 2/2, History 19/19, Undo 13/13, slow paste 21/21, insertion (Word, Chrome) 18/18, Undo in apps 8/8, spacing 14/14 |
| Dictation time, on mains | Idle **2.2 s** median (2.1–2.2 s), two sets. Half load **3.4 s and 3.5 s** medians (3.4–3.6 s), 12 of 12 with text. Within earlier runs (3.1–3.7 s); nothing on the dictation path changed |

**Not run:**
- the Notepad steps and `history-apps` (your Notepad was open)
- ChatGPT (owner rule)
- the five oldest suites
- the 200% display-scale screenshots: this PC already runs at 200%, and changing it is a system setting

## 4. Your PC

**Before switching:**
- **Backup** from a copy of your files: `D:\EsyAI\EsyType\backups\EsyType backup 2026-11-22 1429.esytype-backup` (6 dictations).
- **Checked** by restoring it into a separate test profile: 6 dictations back. Your live files were unchanged.

**The switch:**
- quit only your installed EsyType
- ran `EsyType_0.2.0_x64-setup.exe /S /D=D:\EsyAI\EsyType\app`
- started EsyType in the tray

| Check | Result |
|---|---|
| `settings.json` | byte-for-byte unchanged |
| History | 6 entries; schema 6 |
| Start with Windows | `D:\EsyAI\EsyType\app\esytype.exe --minimized` |
| Apps list | "EsyType" 0.2.0, publisher EsyAI, folder `D:\EsyAI\EsyType\app` |
| Start menu | one shortcut, pointing at the installed program |
| Program files | the uninstaller and voice model are in place; EsyType runs in the tray with no window |
| The installed program | the same as the build, apart from three bytes: the bundler's bundle-type marker (`NSS` against `UNK`) |
| Desktop | the silent install made a shortcut. Removed, as agreed for your PC |

**From now on,** production updates come from the installer. `scripts/install-local.ps1` stays in the repository for reference only.

## 5. For you to know

- **Unsigned:** Windows SmartScreen may warn when you run the installer yourself. Choose More info, then Run anyway. Signing waits for ESYAI's certificate.
- **To uninstall:** Windows Settings → Apps → EsyType. Your data stays unless you tick the box. A models folder you moved elsewhere is never removed by the uninstaller; Settings → Data and privacy → Delete all EsyType data, with the models ticked, removes it first.
- **C: drive:** 500 MB free at the end, after being as low as 246 MB. The `_npx` tool cache (568 MB on C:) is untouched: it holds your npx tools, including MCP servers.
