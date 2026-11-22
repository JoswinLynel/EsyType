# Phase 5, Milestone 4: Page polish, accessibility and the app icon. Plan

**Date:** 21 November 2026 · **Status:** defaults approved by the owner (21 Nov; icon candidate A chosen); **built, tested and installed** (22 Nov; `docs/testing/2026-11-22-page-polish.md`). Change while building: Style's app rules also got the search box, for one toolbar everywhere
**Parent plan:** `phase-5-audit-and-plan.md` · **Builds on:** Milestones 1 to 3 (sidebar, shared dialog, toast, banner, empty state, skeleton and icons in `src/ui.tsx`)

**Scope:**
1. The five data pages (History, Dictionary, Snippets, Style, Scratchpad) made consistent: toolbars, search, counts, loading, empty and no-match states, keyboard use, feedback
2. Accessibility pass: pointer targets, high-contrast (forced colours), the dictation live region, text sizes
3. The app icon and the tray's recording variant, made locally

**Not in scope:**
- the installer (Milestone 5)
- the Dictation home and Settings pages: rebuilt in Milestones 1 to 3; they only pick up the shared fixes (targets, forced colours)
- brand fonts: still need a download (decision 2 of the phase plan); asked again in section 8
- a dashboard or insights page: not part of Phase 5
- hiding row actions until hover (design system 8.5): see section 7

Speech, cleaning and insertion code is not changed. No new dependency and no download. The icons are drawn with Python's Pillow, which is already installed, and embedded at build time with Tauri's own `include_image!`, so no image crate is added.

## 1. What the audit found (from the code, 21 Nov)

Milestone 1 already put every page on the shared dialog, toasts, banners and empty states, and Esc already closes dialogs. What is left is unevenness between pages:

| Item | History | Dictionary | Snippets | Style (apps) | Scratchpad |
|---|---|---|---|---|---|
| List heading | "History", no count | "Your dictionary (N)" | "Your snippets (N)" | "Apps", no count | none |
| Actions | Export CSV, Export JSON, Delete all history (large red button) | Import, Export CSV, Export JSON, Delete all (small) | as Dictionary | none | New note at the top; Delete all notes **under** the list |
| Search | under the heading | under the heading | under the heading | none | under New note |
| No match | "No dictations match." | "Nothing matches." | "Nothing matches." | n/a | "No notes match." |
| Empty state | no button | no button | no button | **none**: an empty list | no button |
| While loading | **shows the empty state** for a moment, then the list | same | same | n/a | same |
| After a delete | no message | no message | no message | no message | toast |
| Esc while editing a row | nothing | nothing | nothing | n/a | n/a |
| Arrow keys in the list | no | no | no | no | no |

**Accessibility:**
- **Pointer targets below the design system's 32 px:** small buttons (30), Clean/Verbatim and Word/Correction tabs (30), the toast's close button (28), the pill's buttons (30).
- **High contrast:** only panels, cards, dialogs and selected items have forced-colour styles. The pill's bars, progress bars, the meter, skeletons and disabled buttons are unchecked.
- **Live region:** the pill announces its state politely. The main window, which the design system names, does not.
- **Text sizes:** checked at 100% and 200% in Milestones 1 to 3; 125% and 150% not yet.

**Icon:**
- The current icon (`src-tauri/icons`) is already white waveform bars on a black rounded square, with every Windows size (16 to 256).
- Missing:
  - the favicon's blue-to-amber colour
  - small sizes drawn for their size (16 and 24 are shrunk from 1024)
  - a tray variant while recording: the tray shows the same icon whatever EsyType is doing

## 2. Page toolbar and list states (one shared component)

A `ListHead` and a `SearchBox` in `src/ui.tsx`, used by all five pages:

- **Heading with the count:** "History (120)", "Dictionary (14)", "Snippets (6)", "Apps (3)", "Notes (4)".
- **Actions on the right, always in this order:**
  1. Import… (Dictionary, Snippets)
  2. Export CSV, Export JSON
  3. a gap, then the red Delete all

  Same size and style everywhere. The button names stay as they are ("Delete all history", "Delete all notes", "Delete all"), because they say what goes, and the test suites find them by name.
- **Search directly under the heading,** with a clear (×) button. Esc in the box clears it.
- **Loading:** three skeleton rows until the first answer arrives. Never the empty state while the list is still loading.
- **No match:** `Nothing matches "abc".` with a **Clear search** button, the same on every page.
- **Empty states, each with one first action:**

| Page | Line | Sentence | Button |
|---|---|---|---|
| History | Nothing here yet | Your dictations appear here as you speak. | **Try it** (opens Dictation, with the cursor in the practice box) |
| History, with History off | History is off | New dictations are not saved. | **Privacy settings** |
| Dictionary | Your dictionary is empty | Add names and terms the speech engine gets wrong. | **Add a word** (cursor in the word box) |
| Snippets | No snippets yet | Try your email signature, address or a meeting link. | **Add a snippet** (cursor in the trigger box) |
| Style, apps | No app rules yet | Every app uses {default style}. | **Add a rule** (cursor in the program box) |
| Scratchpad | No notes yet | Write or dictate; notes save as you go. | **New note** |

- **Scratchpad** keeps its two columns. Its list gets the same heading and search, and "Delete all notes" moves from under the list to the heading. The per-note buttons (Copy all, Export .txt, Export .md, Delete) stay under the note. The inline "Saving… · Saved" line also stays: it is a continuous state, not a one-off event.

## 3. Keyboard and feedback

- **Arrow keys in lists:** Up and Down move to the same button on the next or previous row (or the row's first button), on all five pages, as in the sidebar. Inside a text box the arrows keep their usual meaning.
- **Esc cancels a row being edited** (History, Dictionary, Snippets), with nothing saved. A dialog, if open, takes Esc first.
- **Ctrl+Enter saves a row being edited.** Enter already adds in the single-line boxes.
- **Focus after a delete** moves to the next row (or the previous one, or the empty state's button), never lost to the top of the window.
- **A toast after every change you can't see in place:**
  - deleting a dictation, dictionary entry, snippet or app rule
  - saving an edited dictionary entry or snippet
  - the History offer ("Add X → Y to the dictionary?") stays inline: it is a question, not a message

## 4. Accessibility pass

- **Pointer targets at least 32 px:**
  - small buttons, tabs and the toast's close button go to 32
  - the pill's buttons go to 32 (the pill stays 48 high)
  - checkbox and radio rows get a 32 px minimum height, so the whole row is the target
- **High contrast (forced colours):**
  - styles for everything that is drawn with colour alone: the pill's bars and border, progress and meter fills, skeletons, chips, the selected sidebar item, disabled buttons (GrayText), focus rings (Highlight) and key caps
  - glass fills dropped, as the design system says
- **Live region in the main window:**
  - a hidden polite status line announces each dictation: Listening; Transcribing; Typed; Copied, press Ctrl+V; and the error text
  - not the level updates or the timer
  - the pill keeps its own announcement for when the window is closed to the tray
- **Text sizes:** every page at 100%, 125%, 150% and 200%, and at the minimum window size. Nothing cut off or overlapping, and no sideways scrolling.

## 5. App icon and tray

- **Made locally** by a new script, `scripts/make-icons.py` (Pillow, already installed; run by hand, its output checked in):
  - draws every Windows size itself: 16, 24, 32, 48, 64 and 256 in `icon.ico`, plus `32x32.png` and `128x128.png`
  - 16 and 24 px use fewer, thicker bars so they stay sharp instead of blurring
- **Three candidates for you to pick from,** shown side by side at every size, on dark and light backgrounds, before anything is installed:
  - **A:** today's shape, with the bars in the favicon's colours (blue at the base, white in the middle, amber at the tips, as on the recording pill)
  - **B:** thinner, more numerous bars fading at the edges, closer to the favicon's fluted look, in the same colours
  - **C:** today's white bars unchanged; only the small sizes redrawn
- **Tray:**
  - at rest: the app icon. It is black with light bars, so it can be seen on both light and dark taskbars.
  - while listening, recording or transcribing: the same icon with a red dot, and the tooltip "EsyType · Recording"
  - back to normal when the pill hides
  - the switch happens in the one place that already drives the pill (`pill()` in `main.rs`), so no dictation code changes
- **Not done:** the design system's monochrome tray icon. A white-only icon disappears on a light taskbar, and following the taskbar's theme needs more code than it is worth now. The full-colour icon works on both.
- **After installing,** Windows may show the old icon on the Start menu shortcut until its icon cache refreshes. Nothing is changed in Windows to force it.

## 6. Tests

- **Unit:** the tray's state mapping (which pill states show the red dot).
- **New end-to-end suite, `polish-e2e.ps1`** (test build, own profile, seeded data):
  - every list page: heading with the right count; the actions in the stated order, by position
  - search, then no match with Clear search bringing the list back; Esc clears the search box
  - each empty state's button puts the cursor in the right box (or opens the right page)
  - while a seeded list loads, the empty state never appears (checked every 30 ms for a second after opening the page)
  - Up and Down move between rows; Esc cancels an edit with nothing saved (checked in the database); Ctrl+Enter saves
  - focus after a delete lands on the next row
  - every button and tab on every page at least 32 px high (measured through UI Automation, adjusted for the display scale)
  - live region: the main window's status element is polite. During a test-audio dictation it reads Listening, Transcribing, then Typed.
  - tray: the test build writes a trace line on each tray icon change. A dictation gives "recording", then "rest".
- **High contrast without changing Windows:**
  - the test build is started with WebView2's debugging port (an environment variable for that process only)
  - each page and the pill are captured with forced colours emulated
  - I review the screenshots and send them to you
  - optional owner check: one look in a real Windows contrast theme, which is a system setting I won't change
- **Updated suites** where a visible text changes (the no-match lines, the empty states): History UI, Dictionary, Snippets, Scratchpad, Style, in the same change.
- **Layout:** screenshots of every page, before and after, at 100%, 125%, 150% and 200% and at the minimum size.
- **Full regression,** plus the dictation-time check: idle and half load, repeated, median and range. The `pill()` change touches the dictation path, so this matters here.
- **Production:** install as before, checking:
  - settings by hash, History count, schema, startup entry
  - the new icon on the program file
  - the tray icon at rest

## 7. Design-system deviations, for you to approve

1. **Row actions stay visible.** The design system shows History's Copy, Edit and Delete only on hover or focus. Hidden buttons are harder to find, especially for keyboard and screen-reader users, and the tests find them by name. Recommendation: keep them visible, as today, and record the change in the design system.
2. **Tray: the full-colour icon with a red dot,** instead of a monochrome icon (section 5).

## 8. Defaults to approve

1. **One toolbar for all five list pages:** heading with count; Import, Export CSV, Export JSON, then a red Delete all; search under it. The existing button names are kept.
2. **Skeleton rows while loading; the same no-match line with Clear search; an empty state with one first action on every page** (section 2 table).
3. **Keyboard:** Up and Down between rows, Esc cancels an edit, Ctrl+Enter saves, focus moves to the next row after a delete.
4. **A toast after every delete and every saved edit;** Scratchpad's Saving/Saved line stays.
5. **Accessibility:** 32 px targets, forced-colour styles everywhere, a polite live region in the main window, text sizes from 100% to 200%.
6. **Icon:** three locally drawn candidates (A, B, C in section 5) for you to choose before the build goes further. Small sizes are drawn for their size.
7. **Tray:** the app icon, with a red dot while dictating.
8. **Deviations 1 and 2** in section 7.
9. **Brand fonts stay system fonts** in this milestone. Bundling Instrument Serif and Barlow is a download of a few hundred KB; say so if you want it, and I will ask before downloading.
10. **No new dependencies and no downloads.**

## 9. Order of work

1. `ListHead`, `SearchBox`, the list loading and no-match states, and the arrow-key helper in `ui.tsx`
2. The five pages moved onto them, one at a time, with each page's existing suite run after it
3. Keyboard (Esc, Ctrl+Enter, focus after delete) and the missing toasts
4. Accessibility: targets, forced colours, live region, text sizes
5. Icon candidates, rendered for your choice. Then the chosen icon and the tray variant.
6. `polish-e2e.ps1`, forced-colour captures, full regression and timing, production install, documentation
