# Clean mode: test record

**Date:** 19 November 2026 · **Build:** e2e test build (separate folder) and the installed production copy · **Plan:** `docs/plans/clean-mode-plan.md` (owner approved the recommended defaults)

## Results

| Test | Result |
|---|---|
| Rule table (`clean::tests::rule_table`): 96 input/output pairs, including the "leave it alone" cases | **96 of 96** |
| Options (extended fillers, digits for small numbers) | Pass |
| Tokenising and re-joining leaves every input unchanged (so Clean changes only what a rule changes) | Pass |
| Speed: about 60 seconds of speech | Under 5 ms |
| Accuracy on the 10 benchmark clips (Base Q5_1 transcripts) | **No change**: 23 errors in 680 words with and without Clean. Clean changed none of them: audiobook speech has no fillers or commands |
| All unit tests | 18 of 18 (3 ignored: download, microphone, accuracy kit) |
| End to end, `bench/e2e/clean-e2e.ps1`: phrases spoken by Windows text-to-speech (built in), recognised by the real engine, inserted into the test's own window | **10 of 10** |

End-to-end detail:

| Spoken | Engine heard | Inserted (Clean) |
|---|---|---|
| "I want tea. Scratch that. I want coffee." | I want tea. Scratch that. I want coffee. | I want coffee. |
| "Um, the ticket costs twenty five pounds, and prices rose ten percent." | Um, the ticket costs £25, and prices rose 10%. | The ticket costs £25, and prices rose 10%. |
| "We meet at three thirty pm on the fifth of March, with three guests." | We meet at 3.30pm on 5 March, with three guests. | unchanged |
| "Dear Sam. New paragraph. Thanks for the call." | Dear Sam. New paragraph. Thanks for the call. | Dear Sam. (blank line) Thanks for the call. |
| Same "scratch that" phrase after switching to Verbatim in the window | as heard | exactly as heard |

Also checked: History stores mode `clean` or `verbatim`, the original and the inserted text; the pill shows **Original** after a dictation Clean changed and copies exactly what was heard; the window's Verbatim choice is saved.

**Finding:** the speech engine already writes most numbers, money, percentages, times and dates as digits in UK style ("£25", "10%", "3.30pm", "5 March"). Clean's number rules matter for the numbers it leaves as words, and it deliberately leaves the engine's own digits alone.

## Differences from the plan

| Plan | Built | Why |
|---|---|---|
| "scratch that", "delete that", "strike that" | "scratch that" only | "Please delete that." is ordinary content |
| "5 km", "2 GB" | "5 kilometres", "2 gigabytes" (digits, unit as spoken) | Changing the spoken word is not needed and can be wrong |
| Engine digits restyled | Engine digits left alone | "Version 2", "page 3", "step 1" would become words |
| Times as "3:30 pm" | Spoken times → "3:30 pm"; the engine's "3.30pm" kept | Same rule as above |
| At least 200 rule cases | 96 | Each rule's cases and the leave-alone cases are covered; more will be added from real use |
| Spoken lists (stretch) | Not built | Kept for later, as planned |

## Not tested

- A person speaking with real fillers and hesitations (text-to-speech does not hesitate). The owner's own dictations are the real test.
- The tray's Clean mode tick (clicked by hand only; it uses the same save path as the window).
- Inline corrections ("at five, no, six"): not in this step, by design.
