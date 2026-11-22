# Phase 5, Milestone 4: Page polish, accessibility and the app icon. Test record

**Date:** 21–22 November 2026 · **Plan:** `docs/plans/page-polish-plan.md` (defaults approved by the owner; icon candidate A chosen) · **Builds:** e2e test build, then the installed production copy (22 Nov, after the final regression on mains, section 6) · **Nothing downloaded; no dependency added**

## 1. What was built

**Lists (History, Dictionary, Snippets, Style apps, Scratchpad notes)**, on shared pieces in `src/ui.tsx`:
- **Heading with a count:** "Dictionary (14)".
- **Actions in one order:** Import, Export CSV, Export JSON, then the red Delete all, set apart. Existing button names kept. Scratchpad's Delete all notes moved from under the list to its heading.
- **Search box:** search icon, a clear (×) button, Esc clears. Style's app rules gained a search too.
- **While loading:** three placeholder rows. The empty state no longer flashes up before the items.
- **No match:** `Nothing matches "abc".` with Clear search, the same on every page.
- **Empty states with one first action:**
  - History: Try it, which opens Dictation with the cursor in the practice box; Privacy settings when History is off
  - Dictionary: Add a word
  - Snippets: Add a snippet
  - Style: Add a rule, after "Every app uses Standard."
  - Scratchpad: New note

**Keyboard:**
- Up and Down move to the same button on the next or previous row.
- Esc cancels a row being edited.
- Enter (Dictionary) or Ctrl+Enter (Snippets, History) saves it.
- After a delete, focus goes to the row now in its place.

**Toasts** after every delete (dictation, dictionary entry, snippet, app rule, note) and every saved edit.

**Accessibility:**
- **Every button at least 32 px high,** including small buttons, tabs, the toast's close button, the sidebar's engine-status button (it was 24 px) and the pill's buttons. Checkbox and radio rows are at least 32 px.
- **High contrast (forced colours):** styles for the pill's bars and border, progress bars and the meter, skeletons, chips, selected items, disabled buttons, focus rings, key caps and list rows. The pill's icons now follow the text colour.
- **Live region:** a hidden polite status line in the main window announces Listening, Transcribing, Typed, Copied and errors.

**App icon and tray** (owner chose candidate A):
- **App icon:** the nine-bar waveform in the recording pill's colours, drawn by `scripts/make-icons.py` (Pillow, already installed) at 16, 24, 32, 48, 64 and 256 px. The 16 and 24 px sizes use five thick bars on whole pixels. The ICO frames are checked against the drawings by the script.
- **Old icons kept** in `src-tauri/icons/previous/`.
- **Tray:** the app icon at rest. While listening, recording or transcribing it shows a red dot and the tooltip "EsyType · Recording". The change is queued on the main thread, so the dictation thread never waits for it.

**Design system:** the two approved deviations recorded. Row actions stay visible; the tray uses the full-colour icon, not a monochrome one.

## 2. Bugs found and fixed along the way

1. **Focus after a dialog was lost.** This is older than this milestone (Milestone 1's dialog). When a dialog closed, focus could not go back to the button that opened it, because the rest of the window was still marked inert at that moment. Keyboard users lost their place after every confirmation. Now the inert mark is lifted first, and focus is back before the caller continues.
2. **A pill could vanish early.** This is older than this milestone. A hide timer left over from one dictation could hide the next dictation's pill when the two came within about 5 s, taking its Undo button with it. Found when the Undo suite failed on a slower (battery) run. Now a timer only hides the pill if nothing newer was shown since.
3. **The sidebar's engine-status button** was 24 px high; it is now 32 px.
4. **Scratchpad said "1 words".** Now "1 word".
5. **Delete all wrapped badly at 200% text size:** a divider was left dangling. Replaced by a wider gap.

## 3. Results

| Test | Result |
|---|---|
| Unit tests | **59 of 59** (new: the tray's recording states), run after the last change |
| `polish-e2e.ps1` (new, 25 checks) | **25 of 25, four runs** (two alone, two through the runner). Two earlier runs inside the full regression failed one check (Esc in the search box) and could not be repeated. That check now logs which key reached which element |
| Forced colours (`forced-colors.ps1`, new) | Every page, a dialog and the pill (recording, transcribing) captured with Windows high contrast emulated inside the test build only. All readable; borders, focus and disabled states in Windows' colours. The live region reads role status, live polite in the browser's accessibility tree |
| Layout | Every page at 100%, 125%, 150% and 200% text size, at the minimum window size, and empty. One fix (Delete all wrapping, above) |
| Full regression (before fixes 1 and 2) | Data 27/27, first run 32/32, navigation 14/14, settings recovery 10/10, Dictionary 13/13, Snippets 14/14, Style 12/12, Clean 10/10, Try it 2/2, History 19/19, slow paste 21/21, insertion (Word, Chrome) 18/18, Undo in apps 8/8, spacing 14/14 |
| Reruns after the fixes | **Undo 13/13** (twice; it failed before fix 2). **History UI 33/33** (two texts updated in the suite). **Scratchpad 15/15**. **Polish 25/25** |
| Try it after the fixes | Failed once, environment: on a nearly flat battery the model took about 10 s to load and the test presses the shortcut after 9 s (trace: "model ready" 36 ms after the shortcut) |

### Dictation time

- **Measured on battery** (54% falling to 27%, Balanced plan); Milestone 3 was measured on mains.

| Measurement | Result |
|---|---|
| Idle | 3.1 s median (2.9–3.3 s), two sets |
| Half load | 3.3 s and 3.2 s medians (3.2–3.4 s), 12 of 12 with text |

- **These cannot be compared with Milestone 3's 2.2 s idle.** Model loading was slower by the same ratio (4.5–4.8 s against 2.8 s), and later, on a lower battery, everything roughly doubled again.
- **A/B on the same power,** alternating, the same build with the tray change switched off by a test-only variable (`ESYTYPE_TEST_NO_TRAY`):

| Tray change | Median | Range |
|---|---|---|
| On | 5.1 s | 5.0–5.6 s |
| Off | 5.3 s | 5.2–5.8 s |
| Off | 4.9 s | 4.8–5.6 s |

  No measurable effect.
- **Still owed:** the usual idle and half-load check on mains.

### Not run

- The Notepad steps and `history-apps`: your Notepad was open.
- ChatGPT: owner rule. Once, your ChatGPT app came to the front after the test windows closed. The Undo suite stopped there by itself, sending no keys, and passed on the rerun.
- The five oldest suites: they refuse to run while your EsyType runs.
- **After fixes 1 and 2,** these were not rerun: data, first run, navigation, settings recovery, Dictionary, Snippets, Style, Clean, History, slow paste, insertion, Undo in apps, spacing (section 5).

## 4. Test tooling

- **`polish-e2e.ps1` reads focus through the page itself.** UI Automation's focus reporting for WebView2 content proved unreliable, so the suite gives its own test-build process a debugging port. It focuses elements and reads `document.activeElement` through it. Keys are still real key presses, sent only after checking that the window is in front and the page has keyboard focus.
- **`forced-colors.ps1`** uses the same port to switch on the emulation. Windows' contrast setting is never touched.
- **`ui-screenshots.ps1 -Seeded`** takes screenshots with filled lists.
- **`data-seed.py`** has two new commands: `many` and `query`.

## 5. Final regression on mains (22 Nov, final build)

All with fixes 1 and 2 in the build, on mains. Some suites had to be rerun because the Claude app came to the front mid-test. The suites then stopped themselves, sending no keys; they passed on the rerun.

| Test | Result |
|---|---|
| Unit tests | **59 of 59** (the snippet timing test, which failed once on battery, passes) |
| Polish | **25 of 25, twice.** The Esc check now types the search text with real keys; filling it through UI Automation was not like a person typing |
| Data / first run / navigation / settings recovery | **27/27, 32/32, 14/14, 10/10** |
| History UI / Dictionary / Snippets / Scratchpad / Style / Clean / Try it | **33/33, 13/13, 14/14, 15/15, 12/12, 10/10, 2/2** |
| History / Undo / slow paste / insertion / Undo in apps / spacing (Word, Chrome) | **19/19, 13/13, 21/21, 18/18, 8/8, 14/14** |
| Dictation time, Automatic threads, on mains | Idle **2.1 s** median (2.0–2.1 s), two sets. Half load **3.2 s and 3.4 s** medians (3.1–3.7 s), 12 of 12 with text. Same as Milestone 3 (2.2 s; 3.2–3.4 s) |

- **The first run after plugging in was not usable.** The laptop dropped back to battery during it, and right after charging resumed the processor was still slow (model load 10 s). Those results were set aside; the figures above come from the runs once the processor was back to full speed.
- **Not run:** the Notepad steps and `history-apps` (your Notepad was open), ChatGPT (owner rule), and the five oldest suites.

## 6. Production

- Built with `npx tauri build`, installed with `scripts/install-local.ps1` after quitting only the installed copy.
- Checked after the install:
  - `settings.json` byte-for-byte unchanged
  - History: 6 entries; schema 6
  - startup entry: `D:\EsyAI\EsyType\app\esytype.exe --minimized`
  - the installed file matches the build
  - EsyType started in the tray, with no window shown
- **Not checked by eye:** the new icon in the Start menu and the tray, and the tray's red dot (the test build's trace showed it switching). Windows may keep showing the old Start menu icon until its icon cache refreshes.
- **Optional owner check:** EsyType in a real Windows contrast theme.
