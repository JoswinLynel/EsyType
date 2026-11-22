# Recognition accuracy: product names and overall accuracy. Findings and plan

**Date:** 22 November 2026 · **Status:** approved as recommended (22 Nov). Proposal A built and tested in the test build, full regression passed (`docs/testing/2026-11-22-product-names.md`); released in 0.3.0 and installed on your PC (22 Nov)
**Asked for:**
- better recognition of product, brand and technology names
- an investigation of overall accuracy, with a proper benchmark

**Limits (owner):**
- no other model, no cloud, no downloads, Whisper stays (Tiny, Base, Small)
- ordinary English must not get worse
- Clean and Verbatim behave as now, and raw text stays in History
- your settings and Dictionary are untouched
- no production change without your approval

**Measured for this report (test tools only):**
- **Test clips:** 42 sentences spoken by five Windows voices (British, two American, and two Indian English: Heera and Ravi): 210 clips.
- **Comparison set:** the 10 LibriSpeech clips used since 17 Nov.
- **Engine:** Base (the default model) with EsyType's exact engine settings, run through `bench/stt-bench`.
- **Files:** scripts in `bench/accuracy/`; results in `D:\AI Projects\Tools\bench\results\accuracy`.

## 1. What exists today (from the code)

| Part | Today | Where |
|---|---|---|
| Audio capture | The microphone at its own rate (usually 48 kHz), mixed to mono, then reduced to 16 kHz by averaging blocks of samples (a "box filter"). No level adjustment | `audio.rs` |
| Voice activity (Silero, bundled) | Used only as a gate: no speech found → nothing typed; otherwise the whole recording goes to Whisper. Trimming to the speech was tried and made accuracy worse (4.4% against 3.4% word errors) | `stt.rs` |
| Whisper settings | Greedy decoding (one candidate), English fixed, no carried-over context, blank and non-speech tokens suppressed, the automatic thread count. Whisper's own retry at a higher temperature is left at its default | `stt.rs` |
| Initial prompt ("hint") | Only when you turn on "Also give these words to the speech engine as a hint" (off by default). It sends "Glossary: word, word, …" from your Dictionary, most used first, up to 600 characters (about 150 tokens) | `dictionary.rs`, `main.rs` |
| Dictionary | Your words and corrections ("when I say X, write Y"), matched as whole words or phrases in any case, in Clean and Verbatim. Matched terms are protected from Clean's other rules | `dictionary.rs` |
| Clean mode | Rules only: fillers, voice commands, numbers, styles, capitals. The engine's original text is kept in History | `clean.rs` |

**Is the Dictionary passed to Whisper, and does it help?**
- **Only when the hint is on**, which it is not by default.
- **It was measured on 19 Nov** (`docs/testing/2026-11-19-dictionary.md`). Rare names were spelled right in 24 of 45 clips, against 7 without the hint, but:
  - ordinary English got worse (3.5% → 4.3% word errors)
  - dictation was 40% slower
  - one name appeared where it was not said
- **So today, product names depend on Whisper alone** unless you add Dictionary entries yourself.

## 2. Baseline (measured 22 Nov, Base model)

| Set | Words | Word errors (WER) | Character errors (CER) | Notes |
|---|---|---|---|---|
| Product sentences (26 × 5 voices) | 1,005 | 12.5% | 3.0% | **Product names spelled exactly: 148 of 250 (59%)**: British/US voices 91/150, Indian English 57/100 |
| Ordinary sentences with look-alike words ("the cloud", "clawed", "react calmly", "excel", "notion", "python", "canvas", "Gemini" the star sign) | 515 | 0.8% | 0.3% | British/US 0.0%, Indian English 1.9%. No brand spelled where none was said |
| Mixed everyday and product | 135 | 1.5% | 0.1% | |
| LibriSpeech (real read speech) | 680 | 3.5% | 1.2% | Same as the 17 Nov benchmark (3.4%) |

- **Error types:** mostly substituted words (82 in the product set), few missing words (3), some extra words (41, mostly split names like "chat GPT"), and no repeated words.
- **Speed:** 2.5 s per short sentence and 4.5 s per LibriSpeech clip, measured on battery, for comparing variants only.
- **Peak memory:** 286 MB.

### Where accuracy is lost

1. **Product names, four kinds of error** (all 102 misses read one by one):
   - **Split or mis-cased names:** "chat GPT", "chatgpt", "GIT Hub", "Air Table", "node.js", "N8N", "Postgres QL", "Microsoft Co-pilot". About half of all misses. **Fixable safely**, because the wrong form is not ordinary English.
   - **Phonetic misspellings that are not words:** "Superbase", "Supbase", "Versal". **Fixable safely.**
   - **Names that sound like real words:**
     - "claw", "cloth" and "clogged" for Claude
     - "dolly" and "Dali" for DALL-E
     - "mid-journey"
     - "easy type" for EsyType, and "Easy AI" for EsyAI
     - "notion" and "perplexity" in lower case

     **Not safe to correct automatically:** a rule would turn "The cat clawed at the door" into "Claude".
   - **Garbled:** "J-mini" for Gemini, "power or to make" for Power Automate, "Jevoscript". Only the engine itself can do better.
2. **Indian English** (synthetic voices): ordinary sentences 1.9% against 0% for British/US. Product names are about the same (57% against 61%).
3. **Not yet measurable,** because we have no real recordings: your microphone and room, real accents, quiet speech, background noise, fast or slow speech, and long dictation. The synthetic voices are cleaner than real speech: their ordinary-English error rate is near 0%, so they cannot show these losses. **The biggest gap is a real-voice benchmark** (section 6).
4. **LibriSpeech's 3.5%** is mostly rare names in 19th-century novels ("Uncas", "Raoul"). That's not typical dictation.

## 3. What was tried for this report

| Variant (same clips, same session) | Names right | Brand where none was said | Ordinary sentences | LibriSpeech | Time | Memory |
|---|---|---|---|---|---|---|
| **Baseline** | 148/250 (59%) | 0 | 0.8% | 3.5% | 2.55 s / 4.48 s | 286 MB |
| **Short prompt** (one sentence naming 10 products, about 25 tokens) | 191/250 (76%) | **8** ("clawed" → "Claude" ×3, "python" → "Python" ×5) | **1.7%** (Indian English 1.9% → **3.9%**) | 3.7% | same | 323 MB |
| **Beam search** (5 candidates instead of 1) | 152/250 (61%) | 1 | 0.6% | 3.7% | +25% on long clips | 346 MB |
| **Correction list** (section 4, applied offline to the baseline text) | **203/250 (81%)** | **0** | **0.8%: not one word changed** | **3.5%: not one word changed** | +0 (text rules take well under 1 ms) | +0 |
| Short prompt + correction list | 211/250 (84%) | 8 | 1.7% | 3.7% | same | 323 MB |

**What this shows:**
- **A short prompt costs no time.** The old 600-character glossary did. But it **pushes product names into ordinary speech**, and doubles ordinary-English errors for the Indian English voices. As you warned, more words in the prompt is not automatically better.
- **Beam search** gains 4 names, costs 25% on long dictations and 60 MB, and doesn't help ordinary English. **Not recommended.**
- **A careful correction list** gives most of the gain with none of the risk on these sets.

## 4. Proposal A: built-in product vocabulary (product names)

- **A fixed list built into EsyType**, separate from your Dictionary, of about 25 products with their known mis-hearings. For example:

  | Heard (any case) | Written |
  |---|---|
  | chat GPT, chatgpt, chat G P T, chat GBT | ChatGPT |
  | Superbase, Supbase | Supabase |
  | Versal | Vercel |
  | Microsoft co-pilot | Microsoft Copilot (never "co-pilot" alone) |
  | git hub, github | GitHub |
  | air table, airtable | Airtable |
  | Postgres QL | PostgreSQL |
  | node js, node.js | Node.js |
  | N8N | n8n |
  | power automate | Power Automate (the phrase, never "power" alone) |

  Plus Power BI, JavaScript, TypeScript, WordPress, WhatsApp, PowerPoint, GitLab, Next.js, Make.com and DALL-E. The candidate list is in `bench/accuracy/simulate-rules.py`.
- **Only two kinds of rule are allowed:**
  - a form that is not an English word
  - a phrase whose context makes the product certain

  Names that are also English words (Claude, Gemini, Notion, Python, Excel, React, Teams, Canva, Word, Make) **are never corrected by the list**. Whisper usually capitalises them correctly in context, and your own Dictionary or the hint can add them if you want.
- **It works through the existing Dictionary matcher:**
  - whole words, any case, phrases across spaces and hyphens
  - in Clean and in Verbatim, exactly as your Dictionary does today
  - matched names are protected from Clean's other rules, so "n8n" keeps its case
  - **History keeps the engine's original text**, as now
- **Your Dictionary always wins:** if you have an entry for the same words, yours is used.
- **Built-in entries can't be deleted.** They are not in your Dictionary's table, so Delete all, import and export never touch them. The Dictionary page shows them as a read-only list, with one switch, "Correct common product names", on by default. They have no use counts and add nothing to the hint.
- **Measured on the baseline text:** names 59% → 81%, and not one word changed in the 1,195 words of ordinary sentences and LibriSpeech.
- **Needs your decision (section 9):**
  - "open AI" → OpenAI could wrongly change "an open AI model"; I'd only correct "openai", which costs 2 of the 55 names gained.
  - "Versal" is a real (rare) name.
  - EsyType and EsyAI are spoken like "easy type" and "Easy AI", which are ordinary phrases, so the list can't fix them safely. Your own Dictionary can, if you rarely say "easy type".

## 5. Proposal B: a better optional hint (product names)

- **Keep the hint opt-in** (off by default). It was measured twice, on 19 and 22 Nov, and both times made ordinary English worse.
- **When it is on,** replace the 600-character "Glossary: …" list with a short sentence built from your Dictionary only: the 10 most-used entries, about 25 tokens. The 22 Nov measurement shows a prompt this short costs no time, where the long list cost 40%. The built-in vocabulary is not added to it.
- **Measured before it ships,** with your Dictionary-style names, on the same sets: names, false brands, ordinary English and time. If it still harms ordinary English, the Dictionary page will say so in numbers, as it does now.

## 6. Proposal C: a real-voice benchmark (overall accuracy; needed before any engine or audio change)

Synthetic voices can't show the losses you asked about (accents, quiet speech, noise, speed, your microphone). Measured improvements need real recordings, kept on this PC only.

**1. A recording kit** (`bench/accuracy/record`, a small test tool using the audio library EsyType already has; no download):
- shows one sentence at a time and records it from your microphone at its own rate, as raw WAV
- keeping the native rate lets us also test the 16 kHz conversion

**2. A script for you to read, about 15 minutes.** 70 sentences across the 12 categories you listed:
1. everyday conversation
2. your own accent
3. fast speech
4. slow speech
5. quiet speech
6. natural pauses
7. a noisy room (TV or kitchen noise on)
8. numbers, dates and money
9. product names
10. technical terms
11. a 90-second long dictation
12. mixed casual and professional language

Each is read once, at your normal distance from the microphone.

**3. Derived variants, made from the clean recordings with no download:**
- quieter by 20 and 30 dB
- the synthetic voices at faster and slower rates
- background noise mixed in at fixed levels

**4. Measured for every variant:**
- WER and CER
- substituted, missing, extra and repeated words
- product names spelled right, and brands where none was said
- time per clip and peak memory
- **raw engine output and Clean output scored separately**, so recognition and text cleaning are told apart (a small test tool runs the app's own Clean code on the engine text)

**5. Rules for every comparison:**
- on mains, with the variants run alternately on the same recordings
- a change is kept only if it helps beyond the run-to-run noise, with:
  - no rise in ordinary-English WER above 0.2 points
  - no brand where none was said
  - time +5% at most
  - memory +10 MB at most

## 7. Proposal D: overall accuracy candidates, ranked (each tested with section 6 before anything changes)

| # | Candidate | Expected benefit | Cost and risk |
|---|---|---|---|
| 1 | **Built-in vocabulary** (A) | Large for product names (measured +22 points); none for ordinary English | None measured |
| 2 | **Voice-activity gate on quiet speech** | Possibly large for quiet speakers: today a dictation the gate judges as "no speech" is dropped entirely. Measure with the quiet recordings, then lower the gate's threshold if needed | A lower threshold lets more silence through; Whisper's empty-output filter stays |
| 3 | **Better 16 kHz conversion** (a proper low-pass filter instead of block averaging) | Small, possibly measurable on real 48 kHz audio: the box filter lets some high-frequency noise fold into the speech band | A few lines and negligible CPU; tested on your native-rate recordings |
| 4 | **Short hint format** (B) | Names, for those who turn the hint on | Stays opt-in, because of the measured harm to ordinary English |
| 5 | **Model advice for accents:** Small (multilingual) had the lowest WER (2.9%) on 17 Nov but is about 3× slower | Possibly better for accented speech; measure on your recordings | Advice in the wizard and Settings only; the default stays Base unless the numbers say otherwise |
| 6 | **Level normalisation** before Whisper | Probably none (Whisper normalises internally); test only | |

**Not recommended (measured or by design):**
- **Beam search:** +4 names, +25% time, +60 MB.
- **Trimming silence before Whisper:** measured worse on 17 Nov.
- **Shortening Whisper's audio window to speed it up:** risks accuracy.
- **Changing threads:** the automatic count was set by measurement on 21 Nov.
- **Noise-removal or accent models:** another model, outside the limits.
- **Temperature changes:** no evidence.
- **Grammar "fixing":** you asked for accuracy, not cosmetic rewriting.

## 8. Files that will change

**Proposal A** (all in the same layers as today):
- **New:** `src-tauri/src/vocabulary.rs`, the built-in list and its tests.
- **Changed:**
  - `dictionary.rs`: built-in entries join the matcher after yours, with yours first on any clash
  - `main.rs`: loading them when the Dictionary reloads
  - `settings.rs`: `builtin_vocabulary`, default on. Your existing settings file gains nothing until you change a setting, as with earlier new settings.
  - `src/dictionary.tsx`: the read-only list and the switch
  - `bench/e2e/dictionary-e2e.ps1`: built-ins can't be deleted or exported, and yours win
- **No change to** the database, your Dictionary entries, or the speech engine.

**Proposal B:** `dictionary.rs` (the hint text) and the Dictionary page text.

**Proposal C (test tools only):** `bench/accuracy/` (the recorder, the reading script, derived variants, scoring) and `bench/stt-bench` (a beam option was added for this report; a Clean scorer comes next).

**Proposal D, only if a candidate passes:** `audio.rs` (conversion), `stt.rs` (gate threshold), the wizard and Settings text (model advice).

## 9. Decisions to approve

1. **Proposal A, the built-in vocabulary,** on by default, separate from your Dictionary, in Clean and Verbatim like your Dictionary, raw text kept in History.
2. **The "open AI" question:** correct only "openai" (recommended), or also "open AI".
3. **"Versal" → Vercel:** keep (recommended: "Versal" is very rare in everyday speech) or drop.
4. **EsyType and EsyAI are not auto-corrected** (they sound like "easy type" and "Easy AI"). Recommended: I add them to your own Dictionary only if you ask.
5. **Proposal B:** the hint stays opt-in and becomes a short sentence from your Dictionary.
6. **Proposal C:** I build the recording kit, and you record the script, about 15 minutes, once. The recordings stay on this PC only, under `D:\AI Projects\Tools\bench\audio\owner`.
7. **Proposal D:** candidates 2, 3, 5 and 6 are measured on your recordings and reported, each with numbers, before any change.
8. **Release:** after building and the full regression, a new installer version. Your installed copy changes only when you approve that release.

## 10. Order of work

1. **Proposal A:** list and tests, the Dictionary integration, the page, the measurement on all sets (with and without the list), the regression. Then I report and wait for your approval to release.
2. **Proposal C:** the recording kit. You record. Then the real-voice baseline.
3. **Proposal D:** one candidate at a time, each measured against the baseline, kept only if it passes.
4. **Proposal B,** measured.
5. **Release** with your approval.
