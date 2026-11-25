# EsyMeet audio capture (plan milestone 8.1)

**Status:** built and tested outside the app (25 Nov 2026). **Not yet part of EsyType:** `src-tauri/src/capture.rs` is not declared in `main.rs`, so the installed 0.5.0 and the test build do not contain it. The probe `bench/meet-capture` compiles the same file. It joins the app in plan milestone 8.3 (the recording session), after the owner approves.
**Test record:** `docs/testing/2026-11-25-esymeet-capture-study.md`. Measured results there; this page describes the design and marks what was measured.

## 1. What it does

It records the two sides of a meeting at the same time, each into its own file on one shared timeline:

| Source | What | How |
|---|---|---|
| **Microphone** ("You") | The chosen microphone, or the Windows default | cpal input stream on the input device |
| **PC sound** ("Others") | Everything the default speakers or headphones play: the call's other participants | cpal input stream **on the output device**, which on Windows is WASAPI loopback. The output's own format is used |

Both are written as **16 kHz mono 32-bit float**, the format Whisper takes, to `mic.f32` and `system.f32` in the session folder.

**No new library and no new permission:** cpal is already EsyType's audio library. Loopback needs no driver, and Windows shows no prompt for it. The microphone uses the same Windows microphone permission as dictation.

## 2. Threads and data flow

```
 cpal callback (mic) ─┐ copies samples, notes Windows' capture time of the first sample
                      ├─► channel ─► writer thread (mic):    resample → clock check → append to mic.f32
 cpal callback (PC)  ─┘           ─► writer thread (system): resample → clock check → append to system.f32
                                         │ stats: samples, padding, gaps, overruns, level, device events
 capture thread: owns both cpal streams; every 2 s compares the Windows default devices with the open ones,
                 reopens on a change or a stream error, retries a lost device; on stop pads both files to the end
```

- **Callbacks do almost nothing:** they mix the frame to mono, note the capture time Windows reports for the buffer and send the chunk. No locks, no disk.
- **The capture thread owns the streams.** cpal streams must stay on the thread that made them, as in `audio.rs`.
- **One writer per source.** A slow disk delays only that source's file, never the callback.

## 3. One timeline for both sources

**The clock is Windows' own capture time.**
- For every buffer, WASAPI reports when its first sample was captured, on the PC's performance counter. cpal passes it to the callback as the capture timestamp.
- The callback turns it into an `Instant`: now, minus the age Windows reports. The chunk is placed there: sample = (capture time − session start) × 16000.
- If the file is more than **0.1 s** behind that point, silence is written first.

**Why not the arrival time** (the first design): Windows' buffering changes now and then. Placed by arrival, tones moved by a step of about 49 ms in the middle of a 15-minute run. Placed by capture time, they stayed within ±1 ms (180–182 ms after the test handed them to Windows, which is the playback path, not a capture delay). *Measured.*

**Silence keeps up.** Windows sends **no loopback data while nothing is playing**.
- So while a source sends nothing, its writer fills in silence up to **0.5 s** behind the clock (`KEEP_UP`).
- A live reader therefore sees both files advance together. *Measured: at most 0.05 s behind; without this, 187 s behind during a quiet stretch.*
- A chunk that arrives after its place was already filled is appended and counted as **late**. *Measured: 0.*

**Result:** sample *N* of either file is *N* / 16000 s after the session started. Both files end within 0.1 s of the wall clock after an hour (*measured*), so no drift correction is needed.

**The microphone against the loopback** (*measured* from echo, 6 sentences): the same speech sits **49–88 ms later** in the microphone track, mostly the laptop microphone's own processing.
- This is fine for ordering lines.
- The echo check (9.3) should match within a window measured per meeting, not a fixed constant: other microphones will differ.
- Not yet measured over an hour.

**Ends and gaps:**
- A microphone unplugged and plugged back in resumes at the right time, with silence for the missing stretch.
- On stop, both files are padded to the stop time.

## 4. Resampling

Devices run at 48 kHz (this PC), 44.1 kHz or others. Each writer keeps a **box-filter resampler that carries its position across chunks**: one second in gives one second out, whatever the chunk sizes.

- It is the same filter as dictation's `resample_to_16k`, made stateful.
- If a reopened device runs at another rate, a new resampler starts.

## 5. Devices

| Event | What happens |
|---|---|
| The Windows default device changes (headphones plugged in, Bluetooth connects) | Within 2 s the source is reopened on the new default. It is logged in the source's events |
| A stream reports a real error (device gone, stream invalidated) | Reopened. If it cannot be opened, the source is **lost**: the other source keeps going, and the lost one is retried every 2 s |
| Windows flags a **discontinuity** (cpal `Xrun`), moves the stream itself (`DeviceChanged`) or refuses real-time priority | **Counted, not reopened.** The stream carries on. *Measured: reopening on these cost 1.4 s of microphone audio in 30 s in the first version; now 0 reopens in 2.5 hours of runs* |
| A chosen microphone that is not connected | The Windows default is used, as in dictation |
| Neither source can be opened | `start` fails with a message |

**Discontinuities on the PC-sound stream are normal:** Windows flags them when sound starts again after silence (50 in an hour). Every tone and sentence was still complete. On the microphone they are rare (2–4 in 15–60 minutes), with no gap after the first second. *Measured.*

**Not yet tested:** device changes and real stream failures did not happen in any run, so the reopen and retry paths are unproven. They need someone to plug and unplug a device.

## 6. Files and crash safety

- Each file is written through a buffer and **flushed about once a second**, so a crash loses at most about one second.
- **In this probe the files are whole:** 64 kB/s per source, about 460 MB an hour for both, kept only so they can be measured.
- **Required at integration (8.3):**
  - **Short pieces:** one temporary file per segment.
  - **Delete when done:** each piece is deleted once its text is saved, and kept if anything fails.
  - **Bounded:** a bounded channel, so a stalled disk cannot grow memory. *Measured so far: private memory flat at about 2.5 MB over an hour.*
  - **Crash recovery:** finishes what is left at the next start.
- **No audio is kept by default.** That is the plan's rule, applied when this is integrated.
- **Not encrypted.** The files sit in EsyType's own data folder, like the History database.

## 7. Interface (for 8.3)

```rust
capture::start(dir: &Path, mic: Option<String>) -> Result<Capture, String>
Capture::stats(&self) -> [Stats; 2]      // [microphone, PC sound]: device, format, samples, padded, gaps,
                                        // reopens, xruns, late, live, level, events
Capture::stop(self) -> [Stats; 2]       // pads both files to the stop time
```

`level` drives the live view's two meters. `live` and `events` drive "microphone disconnected" and similar notes.

## 8. Two tracks, not one mix

The two sources stay **separate tracks**, transcribed separately, for these reasons:
- **Labels:** "You" and "Others" come from the source, with no speaker model.
- **Echo:** the microphone's copy of the other side can be found by time and dropped (9.3), instead of being mixed in and written twice.
- **Overlap:** two people talking at once stay clean.
- **Levels:** each track keeps its own level.

The cost is two transcriptions. Measured in study 8.0, that fits on 2 threads. Trade-offs in the test record, section 7.

## 9. Limits known now

- **The default output only:** a call app set to play through a non-default device is not heard. Windows' own call routing ("default communications device") is usually the same device. To check with real calls in 8.2.
- **Everything the PC plays** is captured, not only the call: a video or a notification sound during a meeting is captured too. Per-app capture needs Windows' process loopback (Windows 10 2004+), which cpal does not offer; deferred.
- **Exclusive-mode programs** (some audio tools) can block loopback. Not expected for call apps.
- **The "You" side hears the speakers.** *Measured on this PC:* the built-in array removes steady tones but not speech. Whisper read the speakers' sentence word for word from the microphone track in 6 of 6 plays. That is why the tracks stay separate and echoes are dropped in 9.3. The interface will recommend headphones.
- **Performance (measured):** under 1% of one core, about 12 MB working set and 2.5 MB private memory. Dictation took 2.2 s with capture against 2.3 s without, so it is unaffected.
