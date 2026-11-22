# Milestone stabilisation: test record

**Dates:** 17–19 November 2026 · **Machine:** development PC (i5-11320H, 15.8 GB RAM, Iris Xe, Intel Smart Sound microphone array) · **Model:** Base (`ggml-base.en-q5_1.bin`), automatic threads (7)

Two kinds of test are reported separately and must not be confused:

| Kind | What it proves | What it cannot prove |
|---|---|---|
| **Automated, injected audio** (`e2e` test build) | Shortcuts, pill, transcription, insertion, clipboard, focus, restarts, all with exact reference transcripts | Anything about the microphone or how well a person's voice is recognised |
| **Real microphone** | The capture path and real-world recognition | Nothing yet beyond the capture path (section 2) |

All test scripts are in `bench/e2e/`. They type only into windows they create, send keys only while the intended window is in front, and stop themselves otherwise.

## 1. Automated results (injected audio)

| Area | Script | Result |
|---|---|---|
| Insertion into real apps | `realmic-e2e.ps1 -Inject` | **Notepad 2/2, Word 2/2, Chrome text area 2/2, ChatGPT 1/1, own test window 2/2.** Word error 2.5–7.9% per 14 s clip. Chrome and ChatGPT confirmed by screenshot (Chrome's page fields are not exposed to UI Automation in time). The ChatGPT text was left in the message box and never sent. |
| Wrong-window protection | `realmic-e2e.ps1`, `dictation-e2e.ps1` | **Pass.** When focus moved to another app during transcription, nothing was typed and the transcript went to the clipboard. It also triggered unprompted once during a test when another window took focus, and behaved correctly. |
| Clipboard preservation | `clipboard-vad-e2e.ps1` | **6 of 6 clipboard types identical byte for byte afterwards**, and every dictation was pasted: text from a .NET app, Unicode text, HTML with text, image, file list, empty clipboard. |
| Voice activity detection | `clipboard-vad-e2e.ps1` | **Silence and noise insert nothing**; real speech after them still transcribes. |
| Accuracy through the app | `accuracy-e2e.ps1` | **3.8% word error rate** on 9 of the 10 benchmark clips (19 errors in 499 words), against 3.4% for whisper.cpp alone in the benchmark. The 10th clip (60 s) was transcribed but not typed because focus moved; the wrong-window guard worked. Release-to-text: about 2 s for 5–15 s of speech, 4 s for 30 s, 6 s for 60 s. |
| Restart and persistence | `restart-e2e.ps1` | **8 of 8.** Settings and a custom model folder survive restarts; a Windows-login start (`--minimized`) shows no window, does not take focus, and dictates from the tray. |
| Reliability | `reliability-e2e.ps1` | See section 4. |
| Unit tests | `cargo test` | 7 of 7, plus ignored tests for download/move (local server) and microphone |

## 2. Real-microphone results

| Test | Result |
|---|---|
| Recording from the built-in microphone (1.2 s) | **Pass.** Samples arrive at the right rate from "Microphone Array (Intel Smart Sound Technology)". |
| Natural speech played through the laptop speakers into the microphone, 14 s clips, into the test window and Notepad | **Not a valid test on this laptop.** Transcripts were invented text ("[speaking in foreign language]", a repeated sentence, rows of dots) at 100% speaker and microphone volume. The microphone array's echo cancellation almost certainly removes the laptop's own speaker output. It did expose a real problem, now fixed: Whisper invents text from near-silence (see 3.3). |
| **A person speaking into the real microphone** | **Open.** The owner reported on 19 November 2026 that general use works; the per-app spoken check (Notepad, Word, Chrome, ChatGPT) is still to be done by the owner. |

## 3. Problems found and fixed

| # | Problem | Cause | Fix | Verified by |
|---|---|---|---|---|
| 3.1 | The recording pill never hid after its first appearance | The pill is shown with a raw Win32 call so it never takes focus; Tauri's own `hide()` then thought it was already hidden | Hide with the matching raw call | `clipboard-vad-e2e.ps1`: pill hidden about 2.7 s after release |
| 3.2 | Almost every dictation was typed key by key instead of pasted | Clipboards filled by normal apps carry extra formats, so the "text only" rule rarely passed | Save and restore every memory-backed clipboard format byte for byte; type only for formats that cannot be copied | 6 of 6 clipboard types, all pasted |
| 3.3 | Whisper inserted invented text for silence or noise | Whisper hallucinates on non-speech audio; the energy gate passed background noise | Bundled Silero VAD (0.9 MB, MIT) as a no-speech gate; non-speech tokens suppressed; output that is only annotations or punctuation dropped | Silence and noise insert nothing; accuracy 3.8% |
| 3.4 | After a Windows-login start, keyboard focus went to EsyType's invisible pill | Tauri focuses new windows unless told otherwise | Pill and hidden main window created without focus | `restart-e2e.ps1` |
| 3.5 | Consecutive dictations were glued together ("…suit.In his…") | Each insertion is independent | A dictation into the same window within 10 minutes of the previous one gets a leading space (heuristic: EsyType cannot see the text at the caret) | `restart-e2e.ps1` |
| 3.6 | A chosen microphone that is unplugged gave no feedback | | Falls back to the Windows default, with a "Default mic" note on the pill and a warning in the window | Code path only (needs a removable microphone to test) |

**The "Windows 11 Notepad paste issue" was not an EsyType bug.** My tests rewrote scratch files that were open in Notepad with unsaved edits. Notepad then showed a "Keep unsaved changes?" prompt that held keyboard focus, so every later paste in that Notepad window went nowhere. After clearing it (choosing "Keep changes" on the test's own scratch file), Notepad passed 4 of 4. A standalone probe also confirmed that Notepad accepts EsyType's paste with and without the history-exclusion markers and at any timing.

## 4. Reliability (final build)

`reliability-e2e.ps1` against the final test build, 19 November 2026. The app's own event trace is the authority here; the harness's pass/fail counting for two checks was unreliable on a live desktop (see below).

| Check | Result |
|---|---|
| 20 repeated dictations plus mouse-stop, cancel-restart and tray cases | **23 dictations and 1 cancel gave exactly 23 inserts, all pasted** (app trace). The test window grew by exactly one transcript (151 characters, including the leading space) per dictation: no doubles, no losses. |
| Stop to text inserted (app trace, 10 s clip) | Median **1.47 s**, minimum 1.39 s, maximum 2.70 s |
| Memory | 410 MB idle, 413 MB after 23 dictations (esytype.exe plus its WebView2 processes): **no growth** |
| CPU | About 2.8 cores busy on average while transcribing (automatic setting: 7 threads), idle otherwise |
| Responsiveness during transcription | Target app answered within **11 ms**, EsyType's window within **6 ms** (slowest replies) |
| Focus | 8 of 8 samples kept focus on the target while the pill was shown; clicking the pill's Stop button with the mouse did not take focus |
| Single instance | Second launch exited immediately |
| Close button | Window hides to the tray; EsyType keeps running and dictating |
| Cancel then immediate restart | Correct in the app trace (one cancel, one insert) |

Harness note: the script's "cancel then restart" and "20 repeats" pass/fail lines reported failures because its before-snapshot of the test window did not refresh between rounds (all timings read 0.0 s). The window contents and the app trace both show the correct behaviour above. Earlier runs of this harness had other bookkeeping faults (reading a half-written file, clearing that did not take effect); each was traced to the harness, never to the app.

**Peak memory** for Base alone was 345 MB in the benchmark; the whole app with its user interface uses about 410 MB.

## 5. Product-readiness changes

| Item | Status |
|---|---|
| Model storage configurable; future downloads go there | Done. Base moved from C: to `D:\EsyAI\EsyType\models` (copy, SHA-256 check, delete); no model files remain on C:. Move logic tested end to end against a local server. |
| System tray icon (Open, Quit; closing the window keeps EsyType running) | Done and tested |
| Single instance (second launch focuses the first) | Done and tested |
| Start with Windows | Done: on by default, switchable in the window; starts hidden in the tray. **A real Windows restart has not been done.** |
| Settings and model persist across restarts | Done and tested |

## 6. Not tested yet

- **A person speaking** into the real microphone, end to end (the most important remaining check).
- A real Windows restart (the login-style start was simulated with `--minimized`).
- Bluetooth and USB microphones; unplugging during recording; no microphone at all.
- Gmail, Google Docs, LinkedIn, Microsoft Edge; apps running as administrator.
- The 10-minute spacing heuristic in mixed real use (stray or missing spaces).
- Real download from Hugging Face over the internet (same code path tested against a local server).
