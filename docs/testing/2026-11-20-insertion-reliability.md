# Insertion reliability: Word clipboard and spacing after typed text

**Date:** 20 November 2026 · **Asked by:** the owner (priority A: Word clipboard; priority B: spacing) · **Builds:** e2e test build (separate folder) and the installed production copy · **No models, downloads or SDKs added** (two modules of the already-present `windows` crate switched on: COM and UI Automation)

## A. Word sometimes pasted the user's clipboard

### What was seen

Once on 20 Nov (battery at 12%) and once more while reproducing it (a compile running alongside): Word asked for the dictation, EsyType counted the paste as confirmed, and Word inserted the **user's clipboard** instead. EsyType reported `pasted`, a false success.

### Cause (measured)

EsyType hands the text over as a clipboard "promise" and, once the target has asked for it, kept it on the clipboard **250 ms** before putting the user's clipboard back. A measuring tool (`bench/e2e/clipboard-probe.py`, `word-probe.ps1`) that does the same, and also offers the restored clipboard as a promise so that late reads are visible, showed:

| Finding | Evidence |
|---|---|
| **Word reads the clipboard several times per paste.** Putting the promise back after each read (to see them) showed 2–4 reads, the last up to ~220 ms after the first on an idle PC | e.g. reads at 27, 35, 40 and 217 ms after the paste key |
| Only the first read is visible to EsyType; later ones are served from the text already handed over, until the restore | |
| On a busy PC the last read can fall after the 250 ms restore, so Word inserts the user's clipboard | Failure while a compile ran: Word (identified by its own process) took the text at 40 ms, then inserted the user's clipboard |
| Word's later "read about 215 ms after every clipboard change" was **Windows' clipboard-history service**, not Word; it respects the "do not monitor" markers EsyType already adds | process 4300 = `svchost.exe`; no reads with markers |
| A related false success, reproduced: a background program that reads without identifying itself (no window, as Chrome does) right after the paste key was counted as the paste; a slow target then got the user's clipboard. It also received the dictation | `slowpaste-e2e.ps1 -Reactor`, before the fix: "taken ~31 ms after the paste key (opened by no window)", wrong text 2 of 2 |
| Who identifies itself: Word and Notepad open the clipboard with their own window; Chrome does not | trace "opened by pid …" / "no window" |

### What was changed (`src-tauri/src/insert.rs`)

1. **Longer hold:** after the first request the text stays on the clipboard for at least **1 s** (25 times the target's response time, at most 3 s).
2. **Nothing waits for the hold:** the paste runs on its own thread; the outcome is reported as soon as the target asks, so the pill, History and the next dictation are not delayed. The next paste, EsyType's own copying (Copy buttons) and quitting wait until the user's clipboard is back.
3. **Never overwrite a newer copy:** if anything else was copied during the hold (by the user or a program), it is left; the user's old clipboard is not put back over it.
4. **Anonymous reads:** a read without a window is refused for programs known to identify themselves (Word, Excel, PowerPoint, Outlook, OneNote, Notepad, and any program seen doing so since EsyType started); for others (Chrome, Electron apps) it is still counted, and the 1 s hold covers a slow target.
5. **Rejected:** waiting for the target to answer a no-op message (returned at once, as programs answer messages mid-paste), and putting the promise back after each read (made Word paste nothing or stop answering in 2 of 8 tries).

Unchanged: Shift+Insert, the wrong-window guard, refusing requests before the paste key and from other identified programs, the 3 s confirmation limit, "Not typed" with Copy.

### Results

| Test | Before | After |
|---|---|---|
| Real Word, dictate + check + Undo + History + clipboard (`word-repeat.ps1`), normal | 1 failure in 7 (compile running) | **10 of 10** |
| … with a background program reading the clipboard anonymously after every change | | **5 of 5** |
| … slow: all 8 cores busy (below normal priority) and the test's Word at the lowest priority | | **5 of 5** |
| … slow and the background reader | | **5 of 5** |
| … with real compiles running throughout (the condition that failed) | | **10 of 10** |
| Late-pasting test window (one read 0.6 s or 1.5 s after the key) with the background reader (`slowpaste-e2e.ps1 -Reactor`) | wrong text 2 of 2 | **all pass** (3 runs each, twice) |
| Windows that read twice, 0.6 s apart (synchronous and deferred) | user's clipboard every time | dictation every time (reported, not required) |
| You copy something during the hold | (not tested) | **your new copy kept** (3 of 3, and in the Clean suite) |
| Measuring tool, Word, 250 ms vs 1 s hold, all cores busy | 15 of 15 both (busy loops alone do not slow Word enough) | |

### Limits

- A program that reads the text and then reads again more than ~1 s later (3 s if it was slow to ask the first time) still gets the user's clipboard. None of Notepad, Word or Chrome did.
- While the dictation is on the clipboard (about a second), a program that reads the clipboard and ignores the "do not monitor" markers can see it. This was true before for the shorter hold.
- If you press Ctrl+V yourself within that second you paste the dictation, not your clipboard.
- If EsyType is killed (not quit) during the hold, the dictation stays on the clipboard. Quitting from the tray waits for the restore.

## B. No space after text typed by hand

### Cause

EsyType could not see the text around the cursor, so it added a space only when the previous dictation had gone to the same window within 10 minutes. Text typed by hand got none ("Shopping listWe need milk."), and after the user typed a space or cleared the box, a dictation could get a doubled or stray space.

### What was changed (`src-tauri/src/caret.rs`, new)

- EsyType reads **the one character before the cursor** through UI Automation (Windows' accessibility interface), or, for plain Windows text boxes that do not offer it, with the standard text-box messages. In a separate thread, 300 ms at most; the character is used once and never stored or logged; password fields are never read; the focused element must be inside the window being typed into.
- A space goes in front after a letter, digit or end punctuation (`.` `,` `)` …), not after a space, tab, line break, opening bracket or quote, or at the start; never when the dictated text starts with punctuation or a line break.
- **Fallback when the text cannot be read:** a space only when directly continuing EsyType's own dictation in that window: within a minute, with no key press or click in between (the Undo input watch). Otherwise no space: a missing space is possible there, a doubled one is not.

### Results (`bench/e2e/spacing-e2e.ps1`)

| Case | Result |
|---|---|
| Typed "Shopping list", then dictation | "Shopping list Congratulations…" |
| Ends in a full stop / a comma | one space |
| Already ends in a space | no extra space |
| Ends in a line break; empty box | no space |
| Two dictations in a row | one space between |
| Space typed after a dictation, then dictation | not doubled |
| App whose text cannot be read: after typed text | no space added (conservative) |
| … after its own dictation / after a typed space | one space / not doubled |
| Notepad (test file tab), Word (new document), Chrome (test profile): typed text, then two dictations | "Shopping list X X" in all three |
| Scratchpad: typed "Shopping list", then dictation | "Shopping list We need milk…" |
| Whole suite | **14 of 14, then 15 of 15 twice** (one case added) |

## Regression (all against the final test build)

| Suite | Normal (two passes) | Slow (cores busy) |
|---|---|---|
| Unit tests | **47 of 47** (3 runs) | |
| Insertion (test windows, Notepad, Word, Chrome) | **21 of 21** | not valid: timed out (below) |
| Undo, test window | **13 of 13** | not valid: timed out |
| Undo, Notepad, Word, Chrome | **12 of 12** | not valid: timed outAPPS |
| History | **19 of 19** | not valid: timed out |
| Spacing | **15 of 15** | not valid: timed out |
| Slow pasting with the background reader | **21 of 21** | **passes** |
| Scratchpad | **15 of 15** | |
| "Try it" box, hold and toggle | **2 of 2** each | |
| Clean mode | **10 of 10** twice (after a test fix, below) | |
| Dictionary / Snippets / Writing styles | **13 of 13 / 14 of 14 / 12 of 12** | |

Test changes: clipboard checks now wait (up to 5 s) for the restore (`Wait-Clipboard` in `uia.ps1`); the Clean test sets its own clipboard value instead of reading it during the hold. Also fixed: a Scratchpad unit test that saved two notes in the same millisecond. The ChatGPT web check was not run (owner: no ChatGPT interaction); ChatGPT is not part of this change.

### Slow PC: what was found

The broad suites were run with half and then all of the cores kept busy (below normal priority, so the PC stays usable). **Insertion stayed fast** (the paste is confirmed in milliseconds, and the Word and slow-paste tests above pass under load), but **speech recognition became very slow**: 7–58 s from releasing the keys to text, instead of about 2 s. The suites' waits ran out before the text arrived, so their failures are test timeouts, not wrong insertion. Raising the waits to 60 s was not enough at full load.

Thread count, idle PC, 5 s recording (`bench/e2e/threads-probe.ps1`): 7 threads (the automatic setting on this 8-thread CPU) 1.7 s, 4 threads 2.0 s, 2 threads 3.2 s. The same measurement under half load stopped after two dictations (the probe read its result file while the test window was writing it) and has no figures. Likely cause: Whisper's 7 worker threads wait on each other, and one slow thread holds back all of them when other programs share the cores. This is older than today's changes. Measured properly on 21 Nov (`2026-11-21-whisper-threads.md`): 7 threads 43 s median under half load against 3.5 s for 4; a change to the automatic count is recommended there and awaits the owner.

Test leftovers: some test file tabs (`esytype-insert-*.txt`, `esytype-spacing-*.txt` in `D:\AI Projects\Tools\e2e`) were opened in Notepad by the tests and may still be open there; they can be closed without saving.

## Not tested

- Other programs beyond Notepad, Word, Chrome and the test windows (Outlook, Teams, Slack, terminals); a real low-battery run after the fix; very old programs with unusual text controls (they get the conservative fallback).
- The owner's own use.
