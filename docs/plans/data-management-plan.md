# Phase 5, Milestone 3: Settings and data management. Plan

**Date:** 21 November 2026 · **Status:** approved by the owner (21 Nov); **built and tested** (`docs/testing/2026-11-21-data-management.md`). One change while building: Delete all history stays on the History page beside the list it deletes; the other History switches moved to Settings
**Parent plan:** `phase-5-audit-and-plan.md` · **Builds on:** Milestones 1 and 2 (Settings page, dialog, toast, banner; settings recovery; `setup_done`)

**Scope:**
1. Settings export and import
2. Backup and restore of all EsyType data
3. History export
4. A complete Data and privacy section: where data is and how big, History's privacy controls, the internet use, and Delete all EsyType data

**Not in scope:**
- page polish (Milestone 4)
- the installer (Milestone 5)
- encrypted backups: they need an encryption library, which is a new dependency (SQLCipher was deferred in decision 0006)
- automatic, scheduled backups: not asked for
- cloud backup: never, by the owner's rules

Speech, cleaning and insertion code is not changed. No new dependency: SQLite's own `VACUUM INTO` makes the copies, and files are picked with the window's ordinary file picker, as Dictionary and Snippets import already do.

## 1. What exists and is reused

| Piece | Today | Reused for |
|---|---|---|
| Exports to Downloads | `save_export`: never overwrites (adds " (2)"), tests write to their own folder, toast with Show in folder | History export, settings export, backups |
| Import by file picker | Dictionary and Snippets read the chosen file in the window and pass it to EsyType | Settings import, restore |
| Settings checking | Every save checks models, styles and shortcuts, and registers shortcuts (`save_settings`); a damaged file is read value by value (`settings::load`) | Settings import goes through the same path, value by value |
| Database upgrades | Forward-only migrations with a backup during the upgrade; a newer database is refused (downgrade protection) | Restoring an older backup upgrades it the same way; a newer one is refused |
| Delete all History | Deletes, then `VACUUM` so the text cannot be recovered from the file; removes upgrade backups | Delete all EsyType data |
| History privacy controls | On the History page: on/off, keep 30/90 days or until deleted, program names, original text, Delete all history | Moved to Settings → Data and privacy (decided in Milestone 1) |

## 2. Settings export and import

- **Export:** "Export settings" writes `EsyType settings <date>.json` to Downloads:
  - `{ "esytype_settings": 1, "app_version": "…", "exported": "…", "settings": { … } }`
  - holds shortcuts, text mode and Clean options, styles and rules, Undo options, History options, threads, start with Windows
  - holds no dictations, words or notes (those are in backups)
- **Import:** pick the file, then a dialog lists every value that would change ("Hold to talk: Ctrl+Space → Ctrl+F8"), then **Apply** or **Cancel**.
  - Each value is checked on its own, as when reading a damaged file. Unreadable or unknown values are skipped and named.
  - **This PC's microphone and model folder are never changed by an import:** they belong to this PC.
  - **The speech model** is changed only if that model is already downloaded here. Otherwise the dialog says so and keeps the current one; no download starts by itself.
  - Shortcuts are registered as on any save. If one cannot be registered, the rest are still applied and the message names it.
  - A file from a newer EsyType: its unknown values are skipped and listed.
  - A file that is not an EsyType settings file is refused with a reason, and nothing changes.

## 3. Backup and restore

**Backup: one file, not a folder** (a change from the audit's sketch, for you to approve):
- "Back up now" writes `EsyType backup <date> <time>.esytype-backup` to Downloads.
- **One file is easier to move, keep and pick when restoring** than a folder of three files.
- The file is an SQLite database made with `VACUUM INTO` (a consistent copy even while EsyType runs), holding:
  - History, Dictionary, Snippets and Scratchpad notes
  - a `backup_info` table: app version, database schema version, the settings as JSON, time made, and counts of each kind of item
- Speech models are **not** included: they are large and can be downloaded again. The restore says which model the backup used.
- **The file is not encrypted.** The window says so: "This file holds your History and notes. Keep it somewhere private."

**Restore:** pick a `.esytype-backup` file.
1. **Check before touching anything:**
   - it is a readable SQLite database (`integrity_check`) with a `backup_info` table
   - its schema is not newer than this EsyType (otherwise refused: "made by a newer EsyType")
   - its counts match its contents
   
   Anything else is refused with the reason, and nothing changes.
2. **Show what it holds and ask:** "Restore the backup from 21 Nov 2026 14:30? It has 120 dictations, 14 dictionary words, 6 snippets and 3 notes. It **replaces** your current History, Dictionary, Snippets, notes and settings."
3. **Safety copy first:** the current data is backed up to `%LOCALAPPDATA%\EsyAI\EsyType\before-restore\` (newest 3 kept), so a restore can itself be undone with **Undo restore**.
4. **Replace:**
   - close the database
   - put the backup's data in place (an older schema is upgraded on opening, as today)
   - reopen it
   - apply the settings as in an import (this PC's microphone and model folder kept)
   - reload the Dictionary and Snippets used by dictation
5. **If anything fails half-way,** the safety copy is put back and the window says so. The old data is never left half-replaced.

Restore is refused during a dictation or a model download.

## 4. History export

- **Export** on the History page, CSV or JSON (like the Dictionary's) to Downloads.
- Fields: time, text, original text (when kept), mode, style, program (when recorded), outcome, model, speech length, processing time, undone.
- Exports everything, or only the entries matching the current search when there is one: the button says which ("Export 12 shown" / "Export all 120").

## 5. Data and privacy section (Settings)

| Part | Contents |
|---|---|
| Where your data is | Settings, History, Dictionary, Snippets, notes: the data folder and its size. Speech models: the model folder and its size. Open folder for each (as today) |
| History | The switches moved from the History page, unchanged: keep History, how long, program names, original text, Delete all history. The History page links here |
| Backups | Back up now; Restore from a backup…; Undo restore (only after a restore, while the safety copy exists); Export settings; Import settings… |
| Internet use | "EsyType connects to the internet only when you download a speech model: one file from huggingface.co (ggerganov/whisper.cpp, a fixed version), checked by its SHA-256 fingerprint. Nothing you say or write is sent anywhere. No account, no analytics, no update checks." The address shown is the one in the code |
| Delete all EsyType data | A red button. The dialog lists what goes and what stays (below), with a tick box for "Also delete the downloaded speech models (N MB)" |

**Delete all EsyType data:**
- **Goes:**
  - History, Dictionary, Snippets and notes (deleted, then compacted so they cannot be recovered from the file, as Delete all history does today)
  - settings back to their defaults
  - kept copies of damaged settings files
  - restore safety copies
- **Optionally goes:** the speech models.
- **Stays:**
  - exports and backups you saved in Downloads (EsyType never deletes your files outside its own folders)
  - the program itself, and the start-with-Windows entry (both handled by the uninstaller in Milestone 5)
- **Afterwards:**
  - With the models kept: EsyType carries on with default settings.
  - With them deleted: the first-run wizard opens.
- The dialog's button reads "Delete everything", in red, with Cancel focused.

## 6. Safety rules (all of them tested)

1. **Nothing is replaced before it is checked.** Imports and restores read and check the whole file first.
2. **A restore always makes a safety copy first,** and a failure puts it back.
3. **Newer files are refused:** a backup with a newer schema. A settings file from a newer version is applied value by value, with the unknown values listed.
4. **This PC's microphone and model folder** are never taken from another PC's file.
5. **EsyType deletes only inside its own folders.**
6. **Restore and delete-all are refused during a dictation or a download.**

## 7. Tests

- **Unit:**
  - settings import: a full file; a partial file; wrong types; unknown and newer values; not EsyType at all; the microphone and model folder kept; a model not downloaded is kept
  - backup: round trip (everything back, counts equal)
  - restore refusals: a newer schema; a non-backup SQLite file; a truncated file; counts that do not match
  - an older-schema backup upgraded
  - the safety copy made and restored on a forced failure; newest 3 kept
  - delete all: with and without models; files outside EsyType's folders untouched
  - History export (CSV quoting, multi-line text, the original only when kept)
- **End to end, new `data-e2e.ps1`** (test build, own profile, exports to its own folder):
  - add History, Dictionary, Snippets and a note, then back up; Delete all EsyType data; restore; everything is back, and dictation uses the restored Dictionary and Snippets
  - Undo restore
  - export settings, change three, import: the dialog lists exactly those three; Apply
  - a damaged backup and a newer backup refused through the file picker, with nothing changed
  - History export, all and searched, CSV and JSON
  - Delete all with models: the wizard opens
  - the History switches work from their new place
- **Updated:** `history-ui-e2e.ps1` and `navigation-e2e.ps1`, where the History privacy switches moved.
- **Full regression,** plus the dictation-time check (idle and half load, repeated, median and range).
- **Layout:** Settings at 100% and 200% zoom and at the minimum size.
- **Production:** install as before.
  - Before installing, a backup of your real data is made with the test build's backup code, reading a copy of your files, never the live ones. It is checked by restoring it into a test profile.
  - After installing: your settings, History count, schema and startup entry are unchanged.

## 8. Defaults to approve

1. **A backup is one `.esytype-backup` file** (an SQLite copy with the settings inside), saved to Downloads, **not encrypted**, with a privacy note; **models not included**.
2. **Restore replaces** History, Dictionary, Snippets, notes and settings (not merges), after a confirmation that shows what the backup holds, and **always makes a safety copy first** with **Undo restore**.
3. **Imports and restores never change this PC's microphone or model folder,** and never start a model download.
4. **Settings import shows every change before applying**; values it cannot read are skipped and named.
5. **History export** in CSV and JSON; exports what the search shows, or all.
6. **History's privacy controls move to Settings → Data and privacy;** the History page links there.
7. **Delete all EsyType data** keeps models unless ticked, never touches your Downloads, and opens the wizard only if the models were deleted too.
8. **The Internet use text** names the one address in the code.
9. **No new dependencies and no downloads.**

## 9. Order of work

1. Backup file, checks and restore with the safety copy (Rust, unit tests first): the riskiest part
2. Settings export and import with the change list
3. History export
4. Data and privacy section: sizes, moved History controls, internet use, backups, delete all
5. Tests, full regression, the pre-install backup of your data, production install, documentation
