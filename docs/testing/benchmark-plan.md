# Benchmark and test plan

**Status:** plan only. No test in this file has been run. Results will be added as dated files beside this one (for example `2026-11-xx-stt-dev-pc.md`) and never edited into the plan.

## 1. Speech recognition benchmark

**Question to answer first:** can 10 to 15 seconds of speech be transcribed in 2 to 3 seconds, warm, on a CPU-only laptop, and with which model?

| Dimension | Values |
|---|---|
| Clip length | 5, 10, 15, 30, 60 seconds |
| Models | Whisper Tiny, Base, Small, Medium; English-only and multilingual; full precision, Q8, Q5; distil-small.en; Parakeet TDT 0.6B v3 int8 |
| Back end | CPU; Vulkan on the integrated GPU |
| Threads | 2, 4, 8 |
| State | Cold (includes model load) and warm |
| Background load | Idle, and with other programs busy (added 21 Nov 2026: idle-only results chose a thread count that fails under load) |
| Options | Default window and shortened window for short clips; greedy and beam 5 |

**Recorded per run:** model load time, transcription time, real-time factor, peak memory of the process, average CPU use, word error rate against a reference transcript.

**Audio set:** recorded by the owner in a normal room with the laptop microphone, a USB microphone and a Bluetooth headset; plus public-domain read speech for a repeatable reference. Includes names and technical terms to test the dictionary.

**Machine for the first run:** the development PC (i5-11320H, 4 cores and 8 threads, 15.8 GB RAM, Intel Iris Xe, no discrete GPU).

## 2. Hardware classes

| Class | How it will be tested |
|---|---|
| 16 GB, CPU-only | Development PC, directly |
| 8 GB and 4 GB | Not available as hardware. Approximated by limiting the process's memory and thread count on the development PC, and reported as **simulated**, not as a real result. Real machines are needed before any claim is made. |
| 32 GB or a discrete GPU | Not available. Untested until hardware is. |

## 3. Functional tests

| Area | Cases |
|---|---|
| Microphone | Built-in, USB, Bluetooth; unplug during recording; change default device; microphone in use by another app; no microphone |
| Shortcuts | Hold, toggle, double-tap lock, cancel; rebinding; conflict warning; behaviour with an elevated window in front |
| Pill | Each of the five states; drag and remembered position; second monitor; different display scaling |
| Insertion | Word, Notepad, Chrome and Edge (Gmail, Google Docs, LinkedIn, ChatGPT), Windows Terminal, VS Code, Slack, Teams |
| Text | Unicode (accents, non-Latin scripts, emoji), multi-line, very long text, text containing quotes and tabs |
| Clipboard | Text, image and file contents restored after insertion; nothing added to clipboard history |
| Safety | Focus moved to another app during processing: text must not be pasted there |
| Cancellation | During recording, transcription, enhancement and download |
| Offline | Network adapter disabled: full dictation works; downloads fail with a clear message |
| Downloads | Interrupted connection, resume, wrong hash, disk full |
| Recovery | Deleted or truncated model file is detected and repaired |
| Data | Delete one entry, clear history, delete all data; database migration after an update |

## 4. Reporting rules

- A target is not reported as met until it is measured on real hardware.
- Simulated results are labelled as simulated.
- Failures are recorded with the same detail as passes.
- Speed settings (threads, window) are measured idle and under load, with repeats; report the median and range, never a single run.
