# Dictionary: test record

**Date:** 19 November 2026 · **Plan:** `docs/plans/dictionary-plan.md` (owner approved the recommended defaults) · **Builds:** e2e test build (separate folder) and the installed production copy

## 1. The engine hint, measured first

`bench/dictionary-hint/measure.ps1` (results: `summary.py`). 15 sentences, each with an uncommon name or term, spoken by Windows' three built-in voices (45 clips), plus the 10 benchmark clips and 5 s of silence and of quiet noise. Base Q5_1, the app's settings, 7 threads, with and without the glossary ("Glossary: EsyType, Siobhan, Kubernetes, …").

| | No hint | Glossary hint | Agreed limit |
|---|---|---|---|
| Term spelled exactly | 7 of 45 | 24 of 45 | (must improve) |
| Word error rate, benchmark clips | 3.5% (24/680) | 4.3% (29/680) | +0.5 points at most |
| Time per name clip / benchmark clip | 1.86 s / 3.62 s | 2.59 s / 5.14 s | +10% at most |
| Silence | "you" | "You" | |
| Quiet noise | (nothing) | "The other one is a little bit more." | |

Also seen: the hint put a dictionary word in the wrong place ("I tested EsyType" → "I tested Siobhan" with one voice).

**Decision (per the approved rule):** the hint fails two of the three limits, so it is **off by default** and offered as an opt-in setting with this trade-off stated on the Dictionary page. The Dictionary works through exact spellings and corrections; the measurement doubles as a list of useful corrections (Tori → Tauri, Superbase → Supabase, Chavon → Siobhan). In the app the voice-activity gate stops silence and noise before the engine.

## 2. Unit tests: 26 of 26 (3 ignored, as before)

| Test | Checks |
|---|---|
| `dictionary::matching_table` | 25 cases: whole words, any case, phrases across a space, hyphen or one comma (not a full stop), longest phrase first, possessives with ' and ’, sentence-start capitals for all-lower-case entries, mixed case kept ("iPhone"), nothing changed when nothing matches |
| `protects_terms_from_clean` | "twenty one pilots" stays "Twenty One Pilots" while "twenty five pounds" becomes "£25"; a term at the start is not re-cased |
| `hint_lists_written_forms_most_used_first` | order by use, duplicates dropped, 600-character budget |
| `validation` | empty, punctuation-only, missing replacement, same as heard, over 60 characters, unknown kind |
| `csv_and_json_round_trip` | quotes, commas, line breaks and accents survive; two-column CSV; bad header refused |
| `storage_with_duplicates_and_import` | duplicate blocked per kind (any case), edit, use count, import reports added/duplicates/problems, delete, delete all, History untouched |
| `fast_with_a_large_dictionary` | 1,000 entries on a 60-second dictation under 2 ms |
| `history::upgrade_from_v1_keeps_history` | a version-1 database with History upgrades to version 2, History intact, backup removed |

## 3. End to end: `bench/e2e/dictionary-e2e.ps1`, 13 of 13

| Check | Result |
|---|---|
| Add a word and two corrections on the page | Pass |
| Duplicate ("TORI" when "Tori" exists) blocked with a message | Pass |
| Edit an entry; search | Pass |
| Spoken "…built with Tauri…" (engine heard "Tori") in Clean | "Tauri" inserted |
| Spoken "PostgreSQL" (engine heard "PostgresQL") | "PostgreSQL" inserted |
| Use counted | Pass |
| Verbatim: the dictionary still applies | "Tauri" inserted, mode `verbatim` |
| Editing a History entry offers "Add … → … to your dictionary?"; Add stores it | Pass |
| Export CSV and JSON (to a test folder in test builds; Downloads in the app) | Pass |
| Delete all asks ("cannot be undone… export first"), then empties | Pass |
| Import the exported CSV through the real Windows file picker | "Imported 4 entries; 0 already there." |

Regression on the final build: `history-e2e.ps1` 19 of 19 (corrupt, newer, locked and read-only databases still never stop dictation; the Dictionary is simply unavailable then), `clean-e2e.ps1` 10 of 10.

**The owner's installation:** upgraded from schema 1 to 2 on first start; the History entry kept; dictionary empty; no backup files left; start-with-Windows entry intact.

## 4. Problems found and fixed

| Problem | Fix |
|---|---|
| **Deadlock:** the status call locked the dictionary twice in one expression, so the window never finished loading (test build only; never installed) | One lock, released before anything else is read |
| **Accessibility:** after switching Word → Correction, the first field kept its old name for screen readers ("Word or name…" while the label said "When I say") | The field is recreated with an explicit label when the kind changes |
| Tests found an installed EsyType's hidden window by title ("EsyType") instead of the test build's | Windows are found by process (`Get-AppWindow`) |
| Listing desktop windows through UI Automation hung while Windows Settings was not responding (the owner's window; not touched) | Windows are listed with `EnumWindows`, which never waits on another program (`Get-TopWindows`); used by the clean, insertion, history-apps and dictionary tests |
| WebView2 builds its accessibility tree on first request, so first lookups failed | Element lookups retry for up to 2 s |
| The History test still expected new dictations to be `verbatim` (Clean became the default in step 2) | Expectation updated |
| Older scripts (reliability, restart, dictation, accuracy, clipboard-vad, realmic) use Ctrl+Space and window titles | They now stop at once if an installed EsyType is running |

## 5. Not tested

- The opt-in hint inside the app (measured with the benchmark tool, which uses the same engine settings).
- The owner's own vocabulary and accent.
- Plural forms of entries ("EsyTypes") are not matched; possessives are.
