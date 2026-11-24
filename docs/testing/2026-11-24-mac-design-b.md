# Mac design, milestone B: the Dictation page and usage totals. Test record

**Date:** 24 November 2026 · **Plan:** `docs/plans/mac-parity-gap-analysis.md` (milestone B) · **Build:** e2e test build only · **Production: not changed** (0.4.0 stays installed) · **Nothing downloaded; no dependency added**

**Owner's instruction (24 Nov):** "Don't change the design of the pill but continue with the rest." The recording pill is unchanged, including whether it shows in screen sharing.

## 1. What was built

### The Dictation page, as in the Mac design
- **Greeting:** "Welcome back, <first name>", or "Welcome back" without a name.
- **Your name:** a new optional field in Settings ▸ General ("ABOUT YOU"), kept only in the settings file.
- **Microphone card:** shown only when Windows' privacy switch blocks the microphone. It has an "Allow…" button that opens the right Windows page, and is checked again when the window comes to the front and every 2 seconds while blocked.
- **Hero:** "Your voice, typed *anywhere*." with your shortcuts, and "Set your style".
- **Numbers card beside the hero:**
  - total words (12,400 shows as "12.4K"), words per minute and the day streak; the card opens Insights
  - "Your words: N in your dictionary · N snippets", which opens Dictionary
- **Recent dictations:** the last 40, grouped under Today, Yesterday or the date, with the time and up to three lines each. A search button opens History. With History off, the page says so and that the totals still count.
- **Moved:** Clean or Verbatim is now at the top of the Style page (and still in the tray menu).
- **Removed:** the "Try it" practice box. You can practise in the Scratchpad, and History's empty state now offers "Open Scratchpad". Onboarding gets its own Try it step in milestone F.
- **Removed:** the "Last dictation" timing line.

### Usage totals (database migration v7, nothing reset)
- **A new table, `usage_days`:** one row per local day with dictations, words and seconds of speech. Numbers only; no text.
- **Kept with History off or trimmed:** your decision of 22 Nov.
- **Removed** by "Delete all EsyType data"; kept by "Delete all history".
- **Started from History:** on upgrade, the table is filled once from the History already on the PC.
- **Backups include it:** a backup is a copy of the whole database.
- **Streak:** days in a row with a dictation, ending today, or yesterday if you haven't dictated yet today.
- **Words per minute:** speaking speed, words divided by minutes of speech.
- **Limit:** a dictation removed again with Undo still counts. It's noted in the code as a known limit to fix when Insights needs exact figures.

### Remembered window state moved to EsyType's data folder
The last page, the last Settings section and folded banners are now kept in `ui-state.json` beside the settings, not in the webview's storage.

The test build's webview storage turned out to be one folder shared by every test profile, so one test run's remembered page leaked into the next. Your installed EsyType uses its own folder and was never affected.

## 2. Tests (test build, own profiles; keys only into the test build's own windows)

| Suite | Result |
|---|---|
| Unit tests | **64 of 64**. New: the streak, filling the totals from an older History on upgrade, totals kept by "Delete all history" and removed by "Delete all EsyType data" |
| Home (new) | **12 of 12**: greeting with and without your name; 12.4K, 124 wpm, 3-day streak from seeded totals; Dictionary and snippet counts; recent dictations under Today, newest first; no microphone card while allowed; the numbers open Insights; Set your style opens Style with Clean or Verbatim at the top; with History off, a real dictation adds to the totals and no text is saved; the table holds numbers only |
| Theme / navigation / polish / data / first run | **64/64, 17/17, 25/25, 27/27, 32/32** |
| Settings recovery / History UI | **10/10, 33/33** |
| Dictionary / Snippets / Scratchpad / Style / Clean / Try it | **18/18, 14/14, 15/15, 12/12, 10/10, 2/2** |
| History / Undo / slow paste / insertion / Undo in apps / spacing (Word, Chrome) | **19/19, 13/13, 21/21, 18/18, 8/8, 14/14** |

**Not run:**
- the Notepad steps and `history-apps` (your Notepad was open)
- ChatGPT (your rule)
- the five oldest suites

**Test changes:**
- **Where tests dictate:** the suites that dictated into the old practice box now dictate into a new Scratchpad note.
- **Clean or Verbatim:** the suites that switched Verbatim on the Dictation page now do it on Style.
- **New expected file:** History UI now accepts `ui-state.json` as an expected file.

**Failures along the way:**
- **Test steps fixed:**
  - a note box found before the page had redrawn
  - text inside buttons read as button names
  - a settings file written with a byte-order mark
  - the "·" character in a PowerShell 5.1 script
- **Did not repeat:** a slow first read of the page (settings recovery), Try it's first run, and one History UI deletion.

## 3. Dictation time

**Conditions:** alternating blocks of 3 dictations, A B B A B A A B, on mains on a quiet PC: clip `6930_10s`, Base, 4 threads. A = the pre-6.1 test build; B = this build.

| | Pre-6.1 | Milestone B |
|---|---|---|
| Median (range) | **2.2 s** (2.1–2.3), 12 runs | **2.15 s** (2.1–2.3), 12 runs |
| Block medians | 2.1, 2.2, 2.1, 2.2 | 2.1, 2.2, 2.2, 2.1 |

- **No difference:** saving a dictation now also updates the day's totals (one small database write after the text is typed), and it doesn't show.
- **Milestone A's question answered:** milestone A's run this afternoon (3.9 s against 4.2 s) was on a slow, warm PC. On a quiet PC both builds measure the same as yesterday's 2.15 s.

## 4. Not done in B

- **The recording pill:** unchanged, at your request.
- **"No speech heard" warning, sounds, microphone test:** milestone E, with their Recording settings.
