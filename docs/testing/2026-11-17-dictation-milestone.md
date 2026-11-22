# First dictation milestone: test record

**Date:** 17 November 2026 · **Build:** `src-tauri`, release, development PC (see `2026-11-17-stt-dev-pc.md` for hardware) · **Model:** Base (`ggml-base.en-q5_1.bin`), automatic threads (7 of 8)

## 1. What was tested and how

| Layer | Method |
|---|---|
| Unit tests (7) | `cargo test --release`: thread choice, settings defaults, model lineup, SHA-256, fit checks, resampling, speech gate |
| Model download | Ignored test run against a local HTTP server serving the already-downloaded files (no internet): download, SHA-256 verification, stale partial file, cancellation |
| Microphone | Ignored test: 1.2 s from the default device ("Microphone Array, Intel Smart Sound Technology"); samples arrived at the right rate |
| End to end | `bench/e2e/dictation-e2e.ps1` on the real desktop: real global shortcuts (synthetic key presses), real recording pill, real transcription, real insertion into a separate application. Audio is a recorded LibriSpeech clip injected through a test-only build feature (`e2e`) instead of the microphone. The target is a text window the test creates in its own process. |

## 2. End-to-end results

13 of 13 checks passed for both target types (plain TextBox and RichTextBox).

| Check | TextBox | RichTextBox |
|---|---|---|
| Hold Ctrl+Space, release: text appears in the other application | Pass, 2.3 s after release | Pass, 2.3 s |
| Transcript accuracy on the 10 s clip | 0% word error rate | 0% |
| User's clipboard restored after pasting | Pass | Pass |
| Toggle Ctrl+Shift+Space start/stop | Pass, 2.4 s | Pass, 2.3 s |
| Tap shorter than 0.4 s inserts nothing | Pass | Pass |
| Esc cancels a recording | Pass | Pass |
| Focus moved to another app before the text was ready: nothing typed there | Pass | Pass |
| ...and the transcript is left on the clipboard instead | Pass | Pass |
| Clipboard holds an image: text is typed key by key instead | Pass | Pass |
| ...and the image is still on the clipboard afterwards | Pass | Pass |
| App still running after all checks | Pass | Pass |

Memory: `esytype.exe` working set 288 MB with Base loaded. WebView2's own processes are additional and were not measured.

## 3. Problems found

| Problem | Status |
|---|---|
| **Windows 11 Notepad received only `"""` instead of the sentence through the paste path** (the typing path worked in Notepad). Seen once, in the first test run. | **Open.** Not reproduced in TextBox or RichTextBox. Testing in Notepad was stopped because the test closed a Notepad process, which on Windows 11 can be the user's shared Notepad instance. Needs a manual check by the owner (section 5). Suspect: Notepad's handling of the extra clipboard formats used to keep dictated text out of clipboard history. |
| Test harness: a WinForms multi-line TextBox ignores Ctrl+A, and the window's text file was read while being written | Fixed in the harness |
| A buffer over-run message from the microphone driver when the stream opens | Harmless in the test (recording complete); watch for clipped first words |

## 4. Not tested yet

- Speaking into the real microphone end to end (only the recording layer was tested with the real microphone).
- Gmail, Google Docs, LinkedIn and ChatGPT in Chrome or Edge, Microsoft Word, Notepad (see section 3), terminals, chat apps.
- Responsiveness of the app being typed into during transcription (speech runs below normal priority on a separate thread; not measured).
- Downloading from Hugging Face over the internet (the same code path was tested against a local server).
- An app running as administrator as the target (Windows blocks insertion; the error message path is untested).
- Bluetooth and USB microphones; unplugging during recording.
- Ctrl+Space conflicts with input-method switching and code editors (decision 0009 still open).

## 5. Manual check for the owner

1. Run `src-tauri\target\release\esytype.exe`.
2. Choose a model. Base is preselected; Download fetches 60 MB from Hugging Face.
3. Click into Notepad, Word, Gmail or ChatGPT; hold **Ctrl+Space**, speak, release.
4. Report: did the text appear, how long it took, and anything wrong (especially in Notepad).
