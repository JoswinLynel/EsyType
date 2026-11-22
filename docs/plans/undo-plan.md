# Undo last dictation: implementation plan (Phase 4, step 6)

**Status:** approved with the recommended defaults and built, 20 November 2026. Test record and differences from this plan: `docs/testing/2026-11-20-undo.md`.
**Scope:** everything on this PC; no downloads, no SDKs, no network.

This step acts on the app you are typing in after the text has gone in, so it is built around one rule: **if EsyType cannot be sure what it would change, it does nothing and says so.**

## 1. What the user gets

| Action | How | What happens |
|---|---|---|
| **Undo** the last dictation | **Undo** button on the pill after each dictation, and a shortcut (proposed Ctrl+Alt+Z, changeable) | EsyType sends the app's own Undo (Ctrl+Z) once, which removes the pasted text as one step in Notepad, Word, browsers and most editors |
| **Restore original** (Clean changed the text) | The pill's **Original** button now offers **Use original** | Undo, then paste what the speech engine heard |
| **Paste last** dictation again | A shortcut (proposed Alt+Shift+Z, as Wispr Flow uses) | Pastes the most recent dictation where the cursor is now — the recovery for "Not typed" or a closed window |
| **`{cursor}` in snippets** | Put `{cursor}` in a snippet's text | After the snippet is pasted, the caret moves back to that point (e.g. between greeting and signature) |

## 2. When EsyType refuses

Undo and Restore original are offered only when all of these hold; otherwise the pill explains why and nothing is sent:

- the dictation was **pasted or typed** (not "copied" or "not typed");
- it is the **most recent** dictation, at most **60 seconds** old;
- the **same window** is in front as when the text went in;
- **no key presses or clicks have happened since** in any app (Windows' last-input time, read when the dictation ends and again at Undo; the Undo shortcut itself is allowed for). Typing after a dictation would otherwise make Ctrl+Z undo the user's own typing.

After Undo the entry stays in History, marked **undone**, so the words are never lost.

**Honest limits:**
- EsyType cannot see the app's text, so it cannot confirm the app's Undo removed exactly the dictation. Most apps treat a paste as one undo step; text that had to be *typed* key by key may need more than one Undo in some apps, so for typed dictations the pill says "Undo sent (typed text may need Ctrl+Z again)".
- Some programs use Ctrl+Z for something else (terminals send an end-of-input character). Undo is not offered for known terminals (Windows Terminal, cmd, PowerShell console, WSL) and can be switched off per program.

## 3. `{cursor}`

- After pasting a snippet containing `{cursor}`, EsyType presses Left once per character after the marker (a line break counts once, as Notepad, Word and browsers move over it in one step).
- Only when the paste was confirmed by the app, the same window is still in front and no input has happened since; otherwise the snippet stays as pasted with the caret at the end.
- Limited to 300 characters after the marker, so a mistake cannot send hundreds of keys.
- Only the first `{cursor}` counts; the marker itself is never inserted.

## 4. Settings and data

| Setting | Default |
|---|---|
| Undo shortcut | Ctrl+Alt+Z (proposed; decision 2) |
| Paste last shortcut | Alt+Shift+Z |
| Show Undo on the pill | On |
| Programs where Undo is never offered | Windows Terminal, cmd, PowerShell console, WSL (editable) |

History gains an `undone` mark (schema v5, forward-only, usual backup and protection). The last dictation's details needed for Undo (window, time, outcome, length) are kept in memory only.

## 5. Order of work and tests

1. Guards (pure logic with an injected clock and input time) — unit tests for every refusal and acceptance case.
2. Undo and Restore original; pill buttons; shortcuts; History `undone` (schema v5 with an upgrade test).
3. Paste last.
4. `{cursor}`.
5. End to end, in the test window (rich text box) and with permission-safe real apps as before (a new Notepad tab, a new Word document, the Chrome test profile):
   - Undo removes exactly the dictation (text before it untouched);
   - Restore original replaces the Clean text with what was heard;
   - refusals: other window in front, a key pressed after the dictation, older than 60 s, "copied"/"not typed" outcomes, a terminal — nothing sent in each case;
   - Paste last after a "Not typed" dictation;
   - `{cursor}` places the caret (checked by typing a marker character in the test window);
   - the user's clipboard is put back in every path.
6. Install the production copy (upgrade checked on the owner's database); docs.

## 6. Decisions for the owner

1. **Undo method:** the app's own Ctrl+Z with the guards above (recommended), rather than selecting the inserted characters and deleting them, which breaks when the app formats text or the caret has moved.
2. **Shortcuts:** Undo Ctrl+Alt+Z and Paste last Alt+Shift+Z (recommended), or no Undo shortcut (pill button only).
3. **Time window:** 60 seconds (recommended) or until any other input only.
4. **`{cursor}`:** build it in this step with the limits above (recommended), or leave it out.
5. **Confirming Undo by reading the app's text** (UI Automation, read at that moment, never stored): not built (recommended, keeps EsyType from reading what you write), or built as an opt-in so EsyType can tell you when Undo did not remove the dictation.
