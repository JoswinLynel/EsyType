# Phase 5, Milestone 3: Settings and data management. Test record

**Date:** 21 November 2026 · **Plan:** `docs/plans/data-management-plan.md` (defaults approved by the owner) · **Builds:** e2e test build (separate folder), then the installed production copy · **Nothing downloaded; no dependency added**

## What was built

- **Backups** (`src-tauri/src/backup.rs`):
  - "Back up now" writes one `EsyType backup <date> <time>.esytype-backup` file to Downloads: an SQLite copy made with `VACUUM INTO`, plus a `backup_info` table (format, app version, schema, time, counts, settings). Not encrypted, and the window says so. Speech models are not included.
  - The file is written under a temporary name and renamed when complete.
- **Restore:**
  - The whole file is checked before anything changes: readable, `integrity_check`, `backup_info` present, schema not newer, counts match.
  - The dialog shows what the backup holds.
  - A safety copy of the current data is made first (`before-restore\`, newest 3 kept). **Undo restore** puts it back.
  - If anything fails after the safety copy, the safety copy is put back and the window says so.
  - An older-schema backup is upgraded on opening.
  - This PC's microphone and model folder are kept, and a model not downloaded here is not switched to.
  - Refused during a dictation or a download.
  - Safety copies hold History text, so they are removed by Delete all history, by turning off "Keep the original transcription", and by Delete all EsyType data.
- **Settings export and import:**
  - Export: a JSON file to Downloads.
  - Import: shows every value that would change ("Hold-to-talk shortcut: Ctrl+F8 → Ctrl+F6") and names what it leaves: this PC's microphone and model folder, unreadable values, values unknown to this version, a model not downloaded here.
  - If a new shortcut cannot be registered, everything else is applied and the shortcuts are kept, with a note.
- **History export:** CSV (Excel-readable UTF-8) or JSON to Downloads; all, or what the search shows. Fields: time (UTC), text, inserted, original, mode, style, program, outcome, model, speech and processing seconds, undone.
- **Data and privacy** in Settings:
  - data and model sizes
  - History's privacy switches, moved from the History page (which now links there; Delete all history stays beside the list)
  - backups and the settings file
  - internet use, naming the one address in the code
  - **Delete all EsyType data**: History, Dictionary, Snippets and notes deleted and compacted; settings back to defaults; safety copies and kept damaged-settings files removed. Speech models only when ticked, and then the first-run wizard opens. Never touches Downloads.
- **The dialog** now also takes a list and a tick box. Tab moves through everything in it.

## Results

| Test | Result |
|---|---|
| Unit tests | **58 of 58** (5 new: backup round trip with the safety copies; refusing a non-backup, truncated, plain database, tampered and newer file; an older-schema backup upgraded; History export and Delete everything (text not recoverable from the file); settings import value by value) |
| `data-e2e.ps1` (new) | **27 of 27, three runs** (once alone, twice in the full regression). Covers: History export (CSV and JSON, all and searched); sizes, moved switches and the internet-use address; settings export; import listing exactly the two changes and naming the microphone, unreadable and unknown values; backup; Delete all (contents, defaults, models and backup kept); restore (the dialog's counts, everything back, settings from the backup); a dictation using the restored Dictionary ("princess" → "Princesa") with the restored shortcut; Undo restore; damaged and newer backups refused with nothing left behind; a forced failure mid-restore putting the data back; Delete all with the models (in a copied folder) opening the wizard, with the shared test models untouched |
| First run / navigation / settings recovery | **32/32, 14/14, 10/10** |
| History UI (switches now in Settings) / Dictionary / Snippets / Scratchpad / Style / Clean / Try it | **33/33, 13/13, 14/14, 15/15, 12/12, 10/10, 2/2** |
| History / Undo / Slow pasting / Insertion / Undo in apps / Spacing (Word, Chrome) | **19/19, 13/13, 21/21, 18/18, 8/8, 14/14** |
| Layout | Settings (Data and privacy) and the Delete all dialog at 100% and 200% zoom |
| Dictation time, Automatic threads, on mains | Idle **2.2 s** median (2.1–2.3 s), two sets. Half load **3.2 s and 3.4 s** medians (3.1–3.5 s), 6 of 6 with text. Unchanged |

### Not run

- Notepad steps and `history-apps`: your Notepad was open.
- ChatGPT: owner rule.
- The five oldest suites: they refuse to run while your EsyType runs.

## Your data before installing

- A backup of your data was made with the new code from a **copy** of your files:
  - `D:\EsyAI\EsyType\backups\EsyType backup 2026-11-21 1437.esytype-backup` (6 dictations, 40 KB)
  - restored into a separate test profile: all 6 dictations back
- The test build never opened your live database. Your `settings.json` was unchanged by hash. The live database could not be hashed while your EsyType held it open; it was only copied.

## Production

- Built with `npx tauri build`, installed with `scripts/install-local.ps1` after quitting only the installed copy.
- Checked after the install:
  - `settings.json` byte-for-byte unchanged
  - History: 6 entries; schema 6
  - startup entry: `D:\EsyAI\EsyType\app\esytype.exe --minimized`
  - the installed file matches the build
  - EsyType started in the tray with no window
