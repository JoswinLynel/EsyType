# Snippets: implementation plan (Phase 4, step 4)

**Status:** approved with the recommended defaults and built, 20 November 2026. Snippets run before the Dictionary (see the test record). Test record: `docs/testing/2026-11-20-snippets.md`.
**Scope:** English. Everything on this PC; no downloads, no SDKs, no network.

## 1. What the user gets

A **Snippets** tab. A snippet is a spoken **trigger** and the **text** it inserts:

| Trigger (spoken) | Inserts |
|---|---|
| "my email signature" | Kind regards,⏎Jo Smith⏎Director, Example Ltd⏎07700 900123 |
| "my address" | 1 High Street⏎London⏎SW1A 1AA |
| "meeting link" | https://meet.example.com/jo |
| "today's update" | Update for {date}: |

- **Two ways a trigger can match**, chosen per snippet:
  - **Whole dictation** (default): the snippet is used only when the dictation is the trigger and nothing else ("My email signature." → the signature). Accidental expansion is very unlikely.
  - **Anywhere**: the trigger is replaced wherever it is said ("Join us at meeting link today" → "Join us at https://… today"). Triggers must be at least two words, so a common word cannot fire by accident.
- **Placeholders** filled when the snippet is used: `{date}` (20 November 2026), `{time}` (14:05), `{day}` (Friday). UK formats, the same as Clean mode.
- Trigger up to 60 characters; text up to 4,000 characters including line breaks; up to 1,000 snippets.
- Add, edit, delete, search, **import and export** (CSV and JSON, as for the Dictionary), delete all with confirmation.
- Each snippet shows how often it has been used.

## 2. How it works

```
speech engine → Dictionary → Snippets → Clean rules (or Verbatim) → insert
```

- **Matching** ignores case, punctuation the engine added and fillers ("um, my email signature" still matches). Longest trigger first; whole words only.
- **Snippet text is inserted exactly as written.** It is protected from Clean (no number reformatting, no re-capitalising), with the same placeholder method the Dictionary uses.
- Applies in **Clean and Verbatim**, as the Dictionary does (proposed; decision 3).
- Line breaks paste as normal line breaks; when EsyType has to type instead of paste, a line break is Shift+Enter so a chat box does not send early (existing behaviour).
- Snippets are kept in memory and refreshed when they change; dictation never waits for the database. If the database is unavailable, dictation carries on without snippets.
- **History** stores what was heard (the trigger) as the original and the inserted text as the result, like any dictation, and follows History's on/off and retention settings.

## 3. Storage

Schema version 3, forward-only, with the existing backup-during-upgrade and newer-version protection:

| Column | Meaning |
|---|---|
| `id`, `created_at`, `updated_at` | |
| `trigger` | as entered |
| `trigger_key` | normalised (lower case, words only) — unique, so the same trigger cannot exist twice |
| `body` | the text to insert (up to 4,000 characters) |
| `mode` | `whole` or `anywhere` |
| `uses`, `last_used_at` | counted only while History is on, like the Dictionary |

## 4. Interface

A **Snippets** tab beside Dictation, History and Dictionary:
- Add: trigger, a multi-line text box with a character count, the match choice (Whole dictation / Anywhere) with one line explaining each, and buttons to insert `{date}`, `{time}` and `{day}`;
- a preview of the text with placeholders filled in;
- the list, searchable, with trigger, the first line of the text, match mode, uses, Edit and Delete;
- Import, Export (to Downloads), Delete all.

A trigger that clashes with a dictionary entry or another snippet is pointed out when it is saved.

## 5. Order of work and tests

1. Schema v3 migration. Unit tests: upgrade from v2 with History and Dictionary intact; backup removed; newer version untouched; duplicate trigger blocked.
2. Matching and expansion (pure, no I/O), with a fixed clock for tests. A table of at least 50 cases: whole-dictation matches with case, punctuation and fillers; non-matches when other words are present; Anywhere at word boundaries only; longest trigger first; placeholders; multi-line text; protection from Clean; nothing changed when nothing matches. Speed: 1,000 snippets on a 60-second dictation under 2 ms.
3. Import and export, including multi-line text, quotes and commas.
4. Page; a UI Automation test like the Dictionary's (add, both modes, edit, delete, search, import through the file picker, export, delete all).
5. End to end with spoken audio (Windows' built-in voice): a whole-dictation snippet inserts multi-line text into the test window and History records it; an Anywhere snippet inside a sentence; Verbatim; a dictation that merely contains a whole-dictation trigger is left alone; the database unavailable → dictation still works.
6. Install the production copy (schema upgrade checked on the owner's database); docs.

## 6. Decisions for the owner

1. **Default match mode:** Whole dictation (recommended: no surprises) or Anywhere.
2. **Placeholders:** `{date}`, `{time}`, `{day}` now (recommended). A `{clipboard}` placeholder is left out for now: History would then store whatever was on the clipboard, which can be a password or private text. It can be added later with History keeping only the trigger for such snippets.
3. **Snippets in Verbatim mode too:** yes (recommended, consistent with the Dictionary) or Clean only.
4. **Placing the cursor** inside a snippet (`{cursor}`) is not in this step: moving the caret after insertion is unreliable across apps. Recommended for later, with "Undo last dictation" (step 6), which needs the same caret control.
