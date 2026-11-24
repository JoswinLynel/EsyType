# Mac design, milestone C: Insights. Test record

**Date:** 24 November 2026 · **Plan:** `docs/plans/mac-parity-gap-analysis.md` (milestone C) · **Build:** e2e test build only · **Production: not changed** (0.4.0 stays installed) · **Nothing downloaded; no dependency added** (charts are drawn by EsyType)

## 1. What was built

The Insights page, as in the Mac design, from the daily usage totals (kept even when History is off or trimmed):

- **Four tiles, counting up when the page opens:**
  - **Words dictated**, "since <first day>".
  - **Words per minute**: speaking speed.
  - **Time saved** at your typing speed. "How?" shows the sum: typing time − speaking time − processing time.
  - **Meetings transcribed**: "—", comes with EsyMeet.
- **Words per day:** 7, 30 or 90 days, with the total ("1,250 words in 30 days") and a dashed average line ("avg 42").
- **Activity:**
  - **The grid:** the last 18 weeks, Monday first, coloured by each day's share of the busiest day.
  - **Hover:** each day shows its words ("Thu 15 Oct: 1,000 words"). Screen readers get one summary of the whole grid.
  - **Under it:** your day streak, busiest day, and words a day when active.
- **This week:** a bar for each day (today in bold) and the split by kind of app with percentages, largest first.
- **Typing speed:** a stepper, 10–150 wpm in steps of 5, saved as a new setting (`typing_wpm`, 40 by default) and used for Time saved.
- **Motion:** with Windows' reduced-motion setting there are no count-ups, growing bars or appearing squares.

### Database change v8 (nothing reset)
- **Processing time per day**, for Time saved.
- **Words per kind of app per day** (`usage_apps`). Numbers only.
- **Started from History:** both are filled once from the History already on the PC.
- **Kinds come from the program's file name only,** never window titles or what you wrote:
  - **Email:** Outlook, Thunderbird…
  - **Chat:** Slack, Teams, WhatsApp, Discord…
  - **Documents:** Word, Excel, PowerPoint, Acrobat…
  - **Code:** VS Code, Visual Studio, terminals…
  - **Notes:** OneNote, Obsidian, Notion, Notepad, and EsyType's own Scratchpad.
  - **Browser:** one kind for every website.
  - **Other:** everything else.
- **Your switch wins:** with "Note which program" off, dictations count as Other.
- **Delete all EsyType data** removes these totals too.

## 2. Tests

Test build, own profiles; keys only into the test build's own windows.

| Suite | Result |
|---|---|
| Unit tests | **65 of 65**. New: the database's app-kind sorting matches EsyType's own list for every known program; processing time and app kinds are filled from an older History; this week's split |
| Insights (new) | **15 of 15**, against seeded totals with known answers:<br>• the four tiles: 3,550 words, 150 wpm, "1 h 5 min" saved at 40 wpm, "—" meetings<br>• "How?" and its sum<br>• 7/30/90 days: bar counts, totals and averages<br>• the 18 × 7 grid: active days, busiest day, the hover text, the screen-reader summary<br>• streak, busiest day, words a day when active<br>• this week's total and split<br>• typing speed: + saves 45 wpm, and Time saved follows |
| Theme | **64 of 64**, including AA contrast on Insights in both themes |
| Home / navigation / polish / data / first run | **12/12, 17/17, 25/25, 27/27, 32/32** |
| Settings recovery / History UI | **10/10, 33/33** |
| Dictionary / Snippets / Scratchpad / Style / Clean / Try it | **18/18, 14/14, 15/15, 12/12, 10/10, 2/2** |
| History / Undo / slow paste / insertion / Undo in apps / spacing (Word, Chrome) | **19/19, 13/13, 21/21, 18/18, 8/8, 14/14** |

**Not run:**
- the Notepad steps and `history-apps` (your Notepad was open)
- ChatGPT (your rule)
- the five oldest suites

**Failures along the way:**
- **Fixed:** the "How?" link was 20 px high, below EsyType's 32 px minimum; it now has a 32 px target and looks the same.
- **Did not repeat:** Snippets' "Edit a snippet" failed once and passed 14 of 14 on the rerun.

## 3. Dictation time

**Conditions:** alternating blocks of 3, A B B A B A A B, on mains on a quiet PC: clip `6930_10s`, Base, 4 threads. A = the pre-6.1 test build; B = this build.

| | Pre-6.1 | Milestone C |
|---|---|---|
| Median (range) | **2.1 s** (2.0–2.1), 12 runs | **2.15 s** (2.1–3.4), 12 runs |
| Block medians | 2.1, 2.1, 2.0, 2.1 | 2.1, 2.2, 2.1, 2.2 |

**No regression:**
- **Size of the gap:** 0.05 s, half the timer's 0.1 s resolution.
- **The other way round in B:** milestone B's run had the new build slightly faster (2.15 s against 2.2 s).
- **The one slow run:** 3.4 s, in the last block; that block's median was 2.2 s.
- **What changed at dictation time:** one more small database write, for the kind of app.

## 4. Not done in C

- **Chart polish:** the chart animates between ranges by redrawing, not with the Mac's morph.
- **Hover:** words-per-day bars show their numbers on hover through the system tooltip only.
