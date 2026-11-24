# Mac design, milestone D: History, Dictionary, Snippets, Style and Scratchpad. Test record

**Date:** 24 November 2026 · **Plan:** `docs/plans/mac-parity-gap-analysis.md` (milestone D) · **Build:** e2e test build only · **Production: not changed** (0.4.0 stays installed) · **Committed locally, not pushed:** four key-pressing suites still need a run on an idle PC (section 2) · **Nothing downloaded; no dependency added**

## 1. What was built

### History
- **Banner** with live chips: "N dictations", "N words" and, when there are any, "N not inserted". The last one shows just those.
- **Summary line** with the counts, Privacy settings, CSV and JSON export, and an outlined "Delete all". The confirmation names the count ("Delete all 12").
- **Filter chips:** All, Today, This week, Not inserted (only when there are any), and your six most used programs.
- **Day groups:** each day has a heading ("TODAY", "YESTERDAY", "Monday 17 November 2026") with a count and one card.
- **Each dictation:**
  - the time, with a small tile for its program
  - the text, up to 8 lines, with search matches in accent ink
  - details ("WINWORD.EXE · 5 words · 4 s spoken · Clean, Professional")
  - a "Not inserted" badge with an explanation
- **Row actions:** Copy (turns into a tick), Edit and Delete as round icon buttons. They show on hover and on keyboard focus, and are always available to screen readers.
- **Edit sheet** with Cancel and Save (and Undo my edits). The "Add to dictionary?" offer, the original transcription, "Show more" and export are kept.
- **Empty state:** a small wave and "Nothing here yet".

### Dictionary
- **Banner:** "Add new word" and chips with your four latest words; a chip searches for its word.
- **Add form:** Word | Correction, with an arrow between "When I say" and "Write", and a status line ("Added “EsyType”.").
- **The hint and product names** are switch rows.
- **List rows:** a word or correction tile, the words ("spoken → **written**"), and details ("Word · Brand · note · used 3 times").
  - **Warning:** shown when an earlier entry already uses the same spoken words; the earlier one wins.
  - **Buttons:** Edit and Delete appear fully on hover or focus.
  - **On/off switch per entry:** switched-off entries stay listed and exported but aren't used while dictating.
- **Edit sheet:** type, words, category (Brand, Technical, Abbreviation, Name, Other or your own), note, on/off.
- **Import preview:** a dialog shows what an import would do (to add, already there, not imported and why). Nothing changes until you choose Import.

### Snippets
- **Banner:** "New snippet"; the chip "my email signature" fills the trigger and sets Anywhere; "{date}" adds the placeholder to the text.
- **Add form:** the two "When to use it" choices sit side by side; the text box turns red at 4,000 characters.
- **List rows:** the trigger in quotes with a Whole or Anywhere badge, the first line of the text, category, uses.
  - **Clash warning:** shown when one trigger is part of another and could match the same words.
  - **On/off switch per snippet.**
- **Edit sheet:** trigger, text, mode, category, on/off. Import has the same preview.

### Style
- **Banner chips** Professional, Casual and Concise set the style for other apps.
- **Clean or Verbatim** sits under the banner.
- **Six style cards** with the example sentence in each style. Click one to use it for other apps; the default is marked "Other apps", others show how many apps use them.
- **App rules** in the row style, with a program tile, a style list and a red bin.
- **Custom style** as four switch rows; "Full stop at the end" is As spoken · Always · Never.
- **New card, "Clean, before any style":** it says what Clean always does and holds Clean's two options, moved from Settings ▸ Speech.
- **Try it:** six result cards, starting with the example sentence.

### Scratchpad
- **Banner:** "New note" and a chip with the open note's word count.
- **Notes list:** a dark "New note" button and an outlined "Delete all"; times read "2 minutes ago".
- **Editor:** 16 px text; Copy all, .txt and .md as small buttons; an outlined Delete.

### Database change v9 (nothing reset)
- **Dictionary:** category, note and on/off.
- **Snippets:** category and on/off.

## 2. Tests

Test build, own profiles; keys only into the test build's own windows.

| Suite | Result |
|---|---|
| Unit tests | **66 of 66**. New: categories and on/off for Dictionary and snippets; switched-off entries kept but not used; an import's dry run changes nothing; History filters (today, this week, not inserted, one app) and counts |
| Dictionary / Snippets / Style | **18/18, 14/14, 12/12** (new: Import shows its preview and changes nothing until Import) |
| History UI | **37 of 37**. New: the banner's count; Today shows only today's dictations; an app chip shows only that program's; All again, grouped by day; "Delete all" names the count |
| Theme | **64 of 64**: AA contrast on every page and Settings section in both themes |
| Navigation / home / Insights / data / settings recovery | **17/17, 12/12, 15/15, 27/27, 10/10** |
| Clean / Try it / History / slow paste / Undo / insertion / spacing (Word, Chrome) | **10/10, 2/2, 19/19, 21/21, 13/13, 18/18, 14/14** |

### Still to run on an idle PC
These suites press real keys and refuse to unless the test build's own window is in front. On 24 Nov evening the owner was using the PC, so they stopped before typing anywhere:
- **Polish:** 19 of 19 checks passed before it stopped, three times at the same step: putting the keyboard on a Dictionary row's Edit button. The same step succeeds when driven directly in the page, so it is not yet known whether this is a fault or the busy PC.
- **Scratchpad:** 8 checks passed in one run; dictation into a note worked.
- **First run:** 17 of 17 checks passed before its key-capture steps.
- **Undo in apps.**

**Also not done:** the dictation timing for D. The pages changed; the dictation path did not.

**Failures along the way, fixed:**
- **History export buttons:** the CSV and JSON buttons were drawn across the top of the window, because they used the class name `pill`, which the recording pill also uses.
- **Moving between rows:** Up and Down went to the wrong button now that row buttons are icons; they now match buttons by accessible name.
- **Test steps for the new layout:**
  - Word and Correction became plain pressed buttons again.
  - Confirmations that name the count ("Delete all 6").
  - Imports that confirm a preview.
  - Switches found as buttons.
  - Row and chip names exposed as list items.

## 3. Dictation time

Not measured for D yet (it needs the idle PC too). D changes only the pages; the dictation path is unchanged since milestone C, which measured 2.1 s against 2.15 s.

## 4. Not done in D (deliberately)

- **Clean's switches:** the Mac's five switches (fillers, repeated words, repeated phrases, punctuation, capitals) need changes in EsyType's Clean engine. EsyType keeps its own two options; changing Clean is a separate step.
- **Language per Dictionary entry:** EsyType dictates in English for now; this comes with language support (milestone E).
- **App icons:** EsyType stores only a program's file name, not its location, so rows show a letter tile, not the program's icon.
- **Exports:** they don't include the new category, note or on/off yet, so other EsyType versions can still read them.
