# Insertion reliability: test record

**Date:** 19 November 2026 · **Machine:** development PC · **Build:** `e2e` test build (injected audio), built in `D:\AI Projects\Tools\e2e\target`, never in the production folder · **Script:** `bench/e2e/insertion-e2e.ps1`

## Result: 24 of 24, plus ChatGPT in Chrome 15 of 15

| Path | Inserted | Outcome in History | Your clipboard afterwards |
|---|---|---|---|
| Test window (WinForms rich text box) | Yes, confirmed by the target 5–8 ms after the paste key | `pasted` | Put back exactly |
| Window with no text field | No: pill shows "Not typed: The app didn't take the text." with a **Copy** button; Copy puts the dictation on the clipboard | `failed` | Put back exactly (Copy is your choice) |
| Clipboard too large to copy exactly (68 MB) | Yes, typed | `typed` | Untouched (68 MB still there) |
| You switch windows during transcription | Nothing typed in either window | `copied` | Holds the dictation, **without** the leading space |
| Word (new document) | Yes, confirmed (97 ms) | `pasted` | Put back exactly |
| Chrome (test profile, local text area) | Yes, confirmed (11 ms) | `pasted` | Put back exactly |
| ChatGPT in Chrome (test profile, logged out; never sent) | Yes, confirmed (40 ms); screenshot checked | `pasted` | Put back exactly |
| Notepad, a tab opened about a second earlier | Yes, confirmed (7 ms) | `pasted` | Put back exactly |

The clipboard check uses a fresh random marker text before every dictation. History regression after the change: `history-e2e.ps1` 19 of 19. Unit tests 14 of 14.

## What was wrong, and the fix

**1. EsyType could report success when nothing was inserted.** It sent Ctrl+V, waited a fixed 500 ms and restored the clipboard, without knowing whether the program took the text.

Fix: the text is put on the clipboard as a *promise* (Windows delayed rendering) owned by a hidden EsyType window. Windows asks EsyType for the text at the moment a program pastes, so EsyType knows when the target took it, and the user's clipboard is restored right after (not after a guess). If the target never asks within 3 seconds, the outcome is `failed`: the user's clipboard is restored, the pill warns and offers Copy, History keeps the text.

**2. A background program read the clipboard on every Ctrl+V.** On this PC some program opens the clipboard and reads it within 16–290 ms whenever Ctrl+V is pressed, even into a window with no text field. It opens the clipboard without a window, so Windows does not say which program it is (Word and Chrome read the same way). With Ctrl+V this made a failed paste look successful.

What was tried: identifying the reader with Windows' wait-chain diagnostics works but costs 20–30 ms per thread (0.4–1.3 s for Word or Chrome). The reader holds the clipboard meanwhile, so the real paste then failed in Word and the test window. Abandoned.

Fix: EsyType now pastes with **Shift+Insert**, the standard alternative paste key. The background reader does not react to it; Word, Chrome, ChatGPT, Notepad and WinForms all paste with it. In addition:
- requests that arrive before the paste key is sent are refused (programs that read every new clipboard never receive the dictated text);
- a request from a program identified as someone other than the target is refused.

**3. Leading space in copied text.** When you dictate into the same window within 10 minutes, EsyType adds a space so the dictations do not run together. When the window had changed, that spaced text was copied to the clipboard, space included. Now the copied text has no leading space (the window was not typed into, so the space is not needed).

**4. The Notepad failure from earlier testing** (a just-opened tab ignored the paste in 2 of 5 runs) did not recur in any run with the new method: Notepad asked for the text within 9 ms in every run, including tabs opened about a second earlier. The original cause was not proven. If it happens again, EsyType now reports `failed` and offers Copy instead of claiming success.

## Production and test builds are now separate

On 19 November a plain `cargo build` in the project folder replaced the file the owner's EsyType ran from with a development build (fixed the same day). To make that impossible:
- Production is installed to `D:\EsyAI\EsyType\app` by `scripts/install-local.ps1` (verified copy of the release build and the voice-activity model; refuses a test build or a running EsyType). The Start menu shortcut and the start-with-Windows entry point there.
- Builds go to `src-tauri\target` (release) and `D:\AI Projects\Tools\e2e\target` (test); neither is ever run as the production copy.
- Test builds never change the Windows startup entry and have their own app identity.

Checked after a full test run: start-with-Windows entry `D:\EsyAI\EsyType\app\esytype.exe --minimized`, Start menu shortcut to the same file, settings unchanged, production copy still running.

## An error during testing

The ChatGPT step first located its window by title and matched the owner's **ChatGPT desktop app** instead of the Chrome test window. In four runs it pasted the test sentence into the owner's draft message (never sent). The owner was told immediately; the test now accepts only a window owned by a Chrome process started with its own test profile, and the rerun used the right window.

## Limits

- A program that reads with Shift+Insert-triggered hooks, or a target that only pastes with Ctrl+V, would need a per-app setting (none found so far; architecture section 7.3).
- `typed` cannot be confirmed: Windows accepted the keystrokes, but whether the program showed them is unknown.
- Programs running as administrator cannot receive keystrokes from EsyType; that shows as `failed` with Copy.
- Not yet tested with a person speaking (owner check), Edge, Gmail, Google Docs, Slack, Teams, VS Code or terminals.
