# Scratchpad: implementation plan (Phase 4, step 7)

**Status:** built and tested 20 November 2026 (owner approved the recommended defaults). Decision 4 (direct insertion into EsyType's own window) was not built: the suspected regression in section 0 was not real, and the actual fault was the hold-to-talk release; see `docs/testing/2026-11-20-scratchpad.md`.
**Scope:** everything on this PC; no downloads, no SDKs, no network. The last Phase 4 step.

## 0. A likely regression to fix first

Since the confirmed-paste change (19 November), EsyType hands dictated text only to the program it is typing into. EsyType's own window gets clipboard text through WebView2's helper process, a different program, so dictating into the **"Try it" box** on the Dictation page probably now ends as "Not typed". This has not been checked yet. The fix below (inserting directly into EsyType's own window) is the first piece of work, with a test.

## 1. What the user gets

A **Scratchpad** tab: a private place to dictate and write drafts, saved automatically on this PC.

- A list of notes (newest first, titled by their first line) and the open note beside it.
- **New note**, **search**, **delete** (with confirmation), **delete all** (with confirmation), **copy all text**, **export** as .txt or .md to Downloads.
- **Plain text** with line breaks (decision 1); the app's own Undo/Redo (Ctrl+Z / Ctrl+Y) work as in any text box, including after a dictation.
- **Dictating into the Scratchpad** works like dictating anywhere: Clean, your style, Dictionary and Snippets apply, and the text goes in at the cursor. Because it is EsyType's own window, the text is inserted directly, never through the clipboard.
- Opened from the tab or from the tray menu ("Open Scratchpad"); no shortcut by default (decision 2).
- A word count and "Saved" status under the note.

## 2. Never losing a note

- **Autosave** half a second after you stop typing or dictating, and immediately when you switch note, switch tab, close or hide the window, or quit EsyType.
- Saved to the local database (schema v6, table `scratchpad_notes`: id, body, created_at, updated_at; the title is derived, not stored). Forward-only migration with the usual backup and newer-version protection.
- If the database is unavailable, the page says so, keeps the text in the window and offers **Copy all**; nothing is silently dropped.
- Notes are **yours until you delete them**: History's on/off and retention do not touch them (decision 3). History's "Delete all" does not delete notes; Scratchpad has its own.
- Limits: 100,000 characters per note, 1,000 notes.

## 3. How dictation reaches EsyType's own window

When the window EsyType is typing into is its own main window, the text is sent to the page, which inserts it at the cursor of the focused text box (Scratchpad note, "Try it", or any other field) using the browser's own text insertion, so the box's Undo works. Outcome `pasted`; your clipboard is not touched at all. If no text box has focus, the pill says so and the text is kept in History and offered with Copy.

## 4. Order of work and tests

1. **Own-window insertion** and a test for the "Try it" box (it should pass afterwards; the test first confirms whether it fails today).
2. Schema v6 with an upgrade test (v5 → v6 keeps everything); note storage with unit tests (create, update, list, search, delete, delete all, limits).
3. Scratchpad page with autosave; tray item.
4. End to end: type into a note through UI Automation, wait, restart the test build: the note is there; dictate into a note (Clean and a snippet apply, the clipboard untouched); Ctrl+Z in the note removes the dictation; delete and delete all ask first; export .txt and .md; database unavailable → warning, text still in the window.
5. Regression pass of the earlier end-to-end suites (outstanding from step 6).
6. Install the production copy (upgrade checked on the owner's database); docs; Phase 4 complete.

## 5. Decisions for the owner

1. **Plain text** (recommended: dependable, exports cleanly) or rich text (bold, lists).
2. **Opening it:** tab and tray menu, no shortcut (recommended), or also a shortcut such as Ctrl+Alt+S.
3. **Keeping notes:** until you delete them, independent of History settings (recommended), or follow History's retention.
4. **Dictation into EsyType's own window inserts directly** (recommended; also fixes the "Try it" box).
