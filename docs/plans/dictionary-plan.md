# Dictionary: implementation plan (Phase 4, step 3)

**Status:** approved with the recommended defaults and built, 19 November 2026. The engine hint failed the measurement, so it is off by default (opt-in). Test record: `docs/testing/2026-11-19-dictionary.md`.
**Scope:** English. Everything on this PC; no model downloads, no SDKs, no network.

## 1. What the user gets

A **Dictionary** tab with two kinds of entry:

| Kind | Example | What EsyType does |
|---|---|---|
| **Word** (a name or term to get right) | EsyType, Siobhan, Kubernetes, Dr Okonkwo | Gives it to the speech engine as a hint, and makes sure it is spelled and capitalised exactly as entered when it is heard ("esytype" → "EsyType") |
| **Correction** (heard → write) | easy type → EsyType; jay son → JSON; Shivon → Siobhan | Replaces the heard words with the written form, whole words only |

- Add, edit, delete, search; duplicates blocked; 60 characters per field.
- **Import and export** as CSV (opens in Excel) or JSON. Import adds new entries, skips duplicates and reports what it did; it never overwrites without asking.
- **Learn from my edits:** when you edit a History entry, EsyType compares the words and offers "Add *easy type → EsyType* to the Dictionary?". Nothing is learned silently.
- Each entry shows how often it has been used, so stale entries are easy to spot.
- **Delete all dictionary entries** with a confirmation, separate from History's delete-all.

## 2. How it works

```
audio → speech engine (+ hint: dictionary words) → raw text
      → dictionary corrections and spellings → Clean rules (or Verbatim) → insert
```

### 2.1 The engine hint (to be measured before it is switched on)

Whisper accepts an *initial prompt*: text it treats as what came before, which nudges it towards those spellings. EsyType would pass the dictionary's words as a short glossary ("Glossary: EsyType, Siobhan, Kubernetes.").

Known risks, which is why it is measured first (section 5, step 1):
- the prompt has room for roughly 200 tokens (about 100 short terms); beyond that EsyType chooses the most used and most recent words;
- on silence or noise Whisper can repeat prompt words (the voice-activity gate already blocks silent recordings);
- a hint can pull similar-sounding ordinary words towards a term;
- a longer prompt adds a little transcription time.

The hint is switched on by default only if the measurement shows names are recognised more often, ordinary speech is no worse (word error rate within 0.5 points) and transcription is no more than 10% slower. Otherwise the Dictionary works through corrections alone and the hint stays an off-by-default option.

### 2.2 Corrections and spellings

- Whole words and phrases only, case-insensitive, longest match first ("new york times" before "new york"), across punctuation the engine added between the words.
- The written form is used exactly as entered. At the start of a sentence a lower-case entry is capitalised ("iPhone" stays "iPhone").
- Possessives and plurals follow the entry: "esytype's" → "EsyType's".
- Matched terms are protected from Clean: "Twenty One Pilots" is not turned into "21 Pilots", and Clean never re-cases them.
- Applied in Clean mode, and in Verbatim mode as well (proposed; see decision 1): Verbatim then means "what you said, spelled your way".
- Entries are kept in memory and refreshed when they change, so dictation never waits for the database. If the database is unavailable, dictation carries on without the Dictionary and the page says why.

## 3. Storage

Schema version 2, a forward-only migration with the existing backup-during-upgrade and newer-version protection:

| Column | Meaning |
|---|---|
| `id`, `created_at`, `updated_at` | |
| `kind` | `word` or `correction` |
| `term` | the word, or the heard form of a correction |
| `replacement` | the written form (corrections only) |
| `uses`, `last_used_at` | counted when an entry changes a dictation (for the hint's priority and the page) |

A unique index on (kind, lower-case term) blocks duplicates. History is not touched by the migration (tested). The dictionary is not history: retention and History's delete-all do not remove it; it has its own delete-all.

## 4. Interface

New **Dictionary** tab beside Dictation and History, in the same glass style:
- an Add bar with a Word / Correction switch (correction shows "When I say…" and "Write…");
- the list, searchable, with kind, uses, Edit and Delete;
- Import, Export (CSV or JSON, a save dialog), Delete all;
- a line saying whether hints are on and how many words they include;
- in History's Edit, after saving: the "Add to Dictionary?" offer.

## 5. Order of work and tests

1. **Measure the hint first.** Sentences with uncommon names and terms, spoken by Windows' built-in voices (Hazel, David, Zira; no download), transcribed by Base with and without the glossary: term accuracy, word error rate on the 10 benchmark clips (must not worsen), time per dictation, and silence/noise clips (must stay empty). Results decide section 2.1's default.
2. Schema v2 migration. Unit tests: upgrade from v1 with history intact, backup removed, newer version untouched, duplicate blocked.
3. Matching engine (pure, no I/O). A table of at least 60 cases: whole words, case, sentence start, punctuation between words, possessives, longest match, overlapping entries, protection from Clean, nothing changed when nothing matches. Speed: 1,000 entries on a 60-second dictation under 2 ms.
4. Import and export: round trip with commas, quotes, line breaks and accents; Excel-style CSV; invalid rows reported, not imported.
5. Page and History offer; a UI Automation test like `history-ui-e2e.ps1` (add, edit, delete, search, import, export, delete all, learn-from-edit).
6. End to end with spoken audio (built-in voices): dictionary terms come out right in Clean and Verbatim; with the database unavailable, dictation still works.
7. Install the production copy; update docs.

## 6. Decisions for the owner

1. **Dictionary in Verbatim mode too:** yes (recommended: Verbatim keeps your words, spelled your way) or Verbatim stays the raw engine output.
2. **Engine hint:** on by default only if the measurement in step 1 shows it helps (recommended), or always off and opt-in.
3. **Learn from my edits:** offer after a History edit (recommended) or leave it for later.
4. **Formats:** CSV and JSON (recommended) or CSV only.
