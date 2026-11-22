# Scratchpad: test record

**Date:** 20 November 2026 · **Plan:** `docs/plans/scratchpad-plan.md` (owner approved the recommended defaults) · **Builds:** e2e test build (separate folder) and the installed production copy

## Results

| Test | Result |
|---|---|
| Unit tests (all) | **44 of 44** (3 ignored, as before) |
| `notes::tests::titles`, `notes::tests::storage` (create, save, list newest first, search any case with `%` matched literally, 100,000-character limit, missing note, delete, delete all; History's delete-all and retention leave notes alone) | Pass |
| `history` upgrade tests v1, v2, v3 → v6 (everything kept, `scratchpad_notes` created) | Pass |
| Shortcut keys for the hold watch (`shortcut_keys_for_the_hold_watch`) | Pass |
| End to end, `bench/e2e/scratchpad-e2e.ps1` (test build's own window) | **14 of 14** |
| End to end, "Try it" box, `bench/e2e/tryit-e2e.ps1`, hold and toggle | **2 of 2** each |
| Owner's installation | Upgraded from schema 5 to 6; History kept; no backup left; start-with-Windows entry intact (`D:\EsyAI\EsyType\app\esytype.exe --minimized`) |

Scratchpad end-to-end detail (speech from Windows' built-in voice; test shortcuts Ctrl+F8 dictate, Ctrl+F9 Undo):

| Case | Result |
|---|---|
| Typed note | Autosaved |
| Dictation into the note ("Um, we need milk and twenty five pounds of flour.") | Inserted at the cursor, cleaned ("Um" gone, "25"), autosaved; clipboard untouched |
| EsyType's Undo | Removes the dictation from the note; the result is autosaved |
| Restart | The note is listed and opens with its text |
| Snippet into a new note (seeded while EsyType was closed) | Two-line snippet text inserted and saved; two notes |
| Export .txt and .md | Both files written; text as in the note |
| Delete | Asks ("This cannot be undone."); Cancel keeps the note; OK removes it |
| Delete all notes | Asks, then removes every note |
| Broken database | The page says notes cannot be saved; text can still be written in the window |

## Regression pass (owed since Undo, step 6)

All earlier end-to-end suites, against the final test build:

| Suite | Result |
|---|---|
| History (`history-e2e.ps1`) | **19 of 19** |
| Clean mode (`clean-e2e.ps1`) | **10 of 10** |
| Dictionary (`dictionary-e2e.ps1`) | **13 of 13** |
| Snippets (`snippets-e2e.ps1`) | **14 of 14** |
| Writing styles (`style-e2e.ps1`) | **12 of 12** |
| Undo, test window (`undo-e2e.ps1`) | **13 of 13** |
| Undo, Notepad, Word, Chrome (`undo-apps-e2e.ps1`) | **12 of 12** (11 of 12 in the first run: see below) |

The PC was on a low battery (12–16%) for these runs, and transcription was 2–5 times slower than usual.

## Problems found and fixed

| Problem | Fix |
|---|---|
| **Hold-to-talk did not stop in EsyType's own window.** The shortcut library detects the release by waiting for Windows to say the key was "never pressed", which it does not say while EsyType's own window is in front, so dictating into the Scratchpad or "Try it" kept recording | EsyType watches the shortcut's keys itself while holding (every 30 ms) and stops when one is let go; the library's own release still works, and stopping twice is harmless |
| **A held shortcut counted as "too short" when recording was slow to start.** The 0.4 s minimum hold was measured from when recording got going; once recording took 0.9 s to start, so a 0.9 s hold was cancelled | The hold is measured from the key press |
| Clean test still looked for the pill's **Original** button, which became **Use original** with Undo | Test updated: Use original puts back what was heard, and the clipboard is kept |
| History test's database-lock helper opened a Windows Terminal window that took focus (Windows 11 ignores "hidden" when Terminal is the default console), so EsyType rightly copied instead of typing; the lock was also shorter than the database library's 5 s wait on a slow run | Helper runs inside the test's own console; lock held for 20 s |
| Style test: the list's options appear slowly in the accessibility tree on a busy PC | Test opens the list again and waits longer before giving up |

## Found, not fixed (recorded in TODO)

- **Word, slow PC:** in one of two runs Word received the user's clipboard contents instead of the dictation. Word asked for the text (EsyType counted it as pasted) and then read the clipboard again more than 0.25 s later, after EsyType had put the user's clipboard back. It did not happen in the rerun or in any earlier Word test. This is the insertion path from 19 November, not the Scratchpad; it needs a longer or smarter hold after Word's first request.
- **No space after typed text:** dictating straight after text typed in the same box adds no separating space ("Shopping listWe…"). EsyType only adds a space after its own previous dictation.

## Differences from the plan

| Plan | Built | Why |
|---|---|---|
| Section 0 and decision 4: dictation into EsyType's own window inserted directly by the page (suspected "Not typed" regression in the "Try it" box) | Not built: the normal confirmed paste is used | The suspected regression was not real. Pasting into EsyType's own window is confirmed like any other program and leaves the clipboard untouched. What failed was the hold-to-talk release (fixed above). Pasted text is undone by the box's own Ctrl+Z (EsyType's Undo sends it, tested) |
| Ctrl+Z in the note removes the dictation (test) | Tested with EsyType's Undo shortcut | EsyType's Undo sends the same Ctrl+Z, after its guards |

## Not tested

- A person using the Scratchpad day to day; very long notes near the 100,000-character limit in the window (limit covered by unit tests).
- Quitting from the tray with unsaved typing (the page saves within half a second of typing stopping; quitting waits up to 1.5 s for it).
- The tray's "Open Scratchpad" item (clicking the tray icon's menu in a test could act on the owner's EsyType, which has the same menu).
