# Clean Mode: implementation plan (Phase 4, step 2)

**Status:** approved with the recommended defaults and built, 19 November 2026. Test record and differences from this plan: `docs/testing/2026-11-19-clean-mode.md`.
**Scope:** English only. Rule-based, on this PC, no AI model, no network, no new downloads or SDKs.

## 1. What the user gets

| Mode | Output |
|---|---|
| **Verbatim** | Exactly what the speech engine produced (after the existing safety filter that drops "[silence]"-type annotations). Nothing else changes. |
| **Clean** | The same words, tidied by rules: fillers removed, voice corrections applied, numbers formatted for the context, capitalisation and spacing fixed, spoken line breaks honoured. |

- One setting on the Dictation page: **Verbatim / Clean**, plus a toggle in the tray menu. Per-app modes come later with Writing styles (Phase 4, step 5).
- The original is always kept (History `raw_text`) unless the user turned off "Keep the original transcription"; the window says plainly that restoring then is not possible.
- Restore:
  - **History:** "Original" is shown under any entry Clean changed, with **Copy original** and **Use original instead** (sets the entry's text to the original).
  - **Right after a dictation:** the pill shows **Original** for 8 seconds when Clean changed something. In this step it copies the original to the clipboard (the user's choice, like Copy today). Replacing the inserted text in place needs "Undo last dictation" (Phase 4, step 6), which will reuse the confirmed-paste and wrong-window guards; this button then becomes "Restore original".

## 2. Where it runs

```
speech engine → stt::clean (existing safety filter) = raw_text (Verbatim)
             → text::clean::apply(raw, Rules::en())  = final_text (Clean)
             → spacing heuristic → insert → History(raw_text, final_text, mode)
```

New module `src-tauri/src/text/` with `clean.rs` (pipeline, pure functions, no I/O) and `en.rs` (English word lists and rules). Other languages later add `xx.rs`; History already stores `language`. Dictionary corrections and snippets (steps 3 and 4) slot in before the Clean rules, as the architecture already specifies (section 5.3).

Budget: under 5 ms for a 60-second dictation; measured in unit tests.

## 3. Rules, in order

Each rule is small, table-driven and covered by its own tests. When a rule is unsure, it leaves the text alone: a missed tidy-up is better than a changed meaning.

### 3.1 Voice corrections (first, so later rules see the final words)

| Spoken | Effect |
|---|---|
| "scratch that", "delete that", "strike that" | Removes the sentence before it (back to the previous sentence end in this dictation); at the very start, removes nothing and the command itself is dropped |
| "new line" / "new paragraph" | Line break / blank line (sent as Shift+Enter in apps that submit on Enter, as today) |

Only whole-phrase matches at a clause boundary count. A command used as content ("he said scratch that idea") is a known ambiguity; v1 accepts it only when followed by a pause punctuation from the engine (full stop or comma) or at the end, and the test set records the cases it gets wrong. Inline corrections ("at five, no, six") are **not** in v1: too easy to get wrong without a language model; listed for later.

### 3.2 Fillers

- Default list (always removed in Clean): um, uh, er, erm, ah, hmm, mm, uh-huh as standalone words.
- Optional, off by default: "you know", "I mean", "like", "sort of", "kind of" (often meaningful).
- Stutters: an immediately repeated word ("the the") collapses to one, except words that legitimately repeat ("that that", "had had").
- Punctuation left behind ("Um, so" → "So") is repaired.
- Note: Whisper Base already omits many fillers. Measured on real speech before tuning (section 5).

### 3.3 Numbers (context-aware)

Parse spoken numbers ("twenty five", "two thousand and twenty six", "three point five") and decide by context:

| Context | Example spoken | Clean |
|---|---|---|
| Money | "five pounds", "twenty dollars fifty" | £5, $20.50 |
| Percent | "ten percent" | 10% |
| Time | "three thirty pm", "half past three" | 3:30 pm, 3:30 |
| Dates | "the fifth of march twenty twenty six" | 5 March 2026 |
| Measurements and units | "five kilometres", "two gigabytes" | 5 km, 2 GB |
| Ordinals | "twenty first" | 21st |
| Phone-like digit runs | "oh seven seven..." | 077… (grouped) |
| Plain counts, zero to nine | "three apples" | three apples |
| Plain counts, 10 and above | "twenty five apples" | 25 apples |
| Idioms and non-numbers | "no one", "one of the", "at once" | unchanged |

Digits the engine already wrote are kept, apart from applying the same style (e.g. "5 apples" → "five apples" only if the owner chooses the words-for-small-numbers style).

### 3.4 Capitalisation, punctuation, spacing

- Sentence starts capitalised after any removal; lone "i" → "I".
- Collapse doubled spaces and punctuation, remove spaces before punctuation, ensure the dictation ends with a full stop only if the engine's text did (no invented punctuation).
- Words the dictionary marks as case-sensitive (step 3) are never re-cased.

### 3.5 Spoken lists (stretch for this step)

"Number one … number two …" or "first … second …" at sentence starts become a numbered list on separate lines. Kept behind a flag until the test set shows it is reliable.

## 4. Settings and data

| Setting | Default | Note |
|---|---|---|
| `text_mode` | **Clean** (proposed) | "verbatim" or "clean"; owner to decide |
| `clean_fillers_extended` | off | the optional filler list |
| `clean_small_numbers_as_words` | on (UK style) | zero to nine as words in plain counts |
| `clean_locale` | en-GB | £, day-month-year dates, "colour" untouched (no spelling changes in this step) |

No database change: `mode` and `raw_text` already exist (schema v1). History shows a "Clean" or "Verbatim" label and the original when they differ.

## 5. Testing

1. **Rule tests (unit):** a table of at least 200 input/output pairs, with each rule's edge cases and the "leave it alone" cases (idioms, ambiguous numbers, commands used as content).
2. **No harm to accuracy:** run Clean on the 10 benchmark transcripts; after normalisation the word error rate must not rise (Verbatim stays identical by construction).
3. **Dictation-style speech:** a short set the owner records (fillers, numbers, money, times, "scratch that") or reads from a script; transcribed by the app, checked by hand. Needed because LibriSpeech is read speech without fillers.
4. **End to end:** `insertion-e2e.ps1`-style run in Clean and Verbatim: correct text inserted, History shows mode, raw and final, the pill's Original button copies the original, clipboard preserved.
5. **Speed:** under 5 ms per dictation.

## 6. Order of work

1. `text::clean` skeleton, Verbatim pass-through, settings, History labels. Tests.
2. Capitalisation and spacing; fillers. Tests.
3. Voice corrections and line breaks. Tests.
4. Numbers. Tests (largest part).
5. Interface: mode switch, tray toggle, pill "Original", History original/use original.
6. Owner's dictation-style recordings; tune; end-to-end tests; docs.
7. Spoken lists, if the earlier steps are solid.

## 7. Decisions for the owner

1. Default mode for new installs: **Clean** (recommended, matches what users expect from dictation apps) or Verbatim.
2. Small numbers in plain counts: words ("three apples", UK style guides, recommended) or digits ("3 apples").
3. Locale for money and dates: en-GB (recommended) or en-US.
4. Whether the pill's Original button in this step should copy the original (recommended until Undo exists) or be left out until step 6.
