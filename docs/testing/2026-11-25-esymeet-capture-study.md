# EsyMeet milestone 8.1: dual-audio capture. Engineering report

**Date:** 25 November 2026 · **Plan:** `docs/plans/next-generation-audit-and-plan.md`, milestone 8.1 · **Architecture:** `docs/architecture/esymeet-capture.md`
**Boundaries kept:**
- **Isolated:** the capture module `src-tauri/src/capture.rs` is not declared in the app (`main.rs`), so it is built and run only by the probe `bench/meet-capture`.
- **Unchanged:** the installed EsyType 0.5.0 (file written 25 Nov 00:04), the test build (00:19), the dictation engine and its settings.
- **Nothing added:** no download and no new dependency (cpal 0.18 is already EsyType's audio library).
- **No microphone audio kept:** each run's microphone file was deleted right after it was measured.
- **PC-sound files kept outside the repository:** `system.f32` from `long`, `long2`, `tones`, `tones2` and the short runs are in `D:\AI Projects\Tools\bench\results\meet-capture\` (about 230 MB per hour). They hold whatever the PC played during those runs. They can be deleted once this report is accepted; the measurements are in each run's JSON.

**Verdict: 8.1 passes.**
- The device-change test first **failed**: after a Bluetooth switch the PC sound was lost for the rest of the run. The cause was found and fixed, and the fix passed the repeat test (section 8a).
- **One check remains open:** switching the *microphone*. This PC's default microphone never changed during the tests. See section 13.

Labels used below: **Measured** = numbers from these runs. **Observed** = seen, not measured as a number. **Inferred** = worked out from measurements. **Recommended** = advice for later milestones.

## 1. Test environment

| | |
|---|---|
| PC | TIMI Mi NoteBook Ultra, Intel Core i5-11320H (4 cores, 8 threads), 15.8 GB RAM |
| Windows | Windows 11 Home 10.0.26300 |
| Power | Mains for every run (battery status 2) |
| Microphone | Built-in "Microphone Array (Intel Smart Sound Technology for Digital Microphones)", 48 kHz, 2 channels, f32 |
| PC sound | "Speakers (Senary Audio)", 48 kHz, 2 channels, f32, captured by WASAPI loopback |
| Use of the PC | Other programs were open and in use during most runs. The probe always ran in the background, never in front, which also shows capture does not need EsyType in front |

**Runs** (results in `D:\AI Projects\Tools\bench\results\meet-capture\`):

| Run | Length | Code version | What played |
|---|---|---|---|
| `run` | 40 s | A | A spoken sentence 3 times |
| `long` | 60 min | A | The sentence every 5 min (11 times) |
| `tones` | 15 min | B | A 200 ms, 1 kHz tone every 10 s (89 times), played by the probe itself |
| `tones2` | 15 min | C (final) | As `tones` |
| `tones-quick` | 60 s | C | A tone every 5 s (11 times) |
| `long2` | 60 min | C | The sentence every 5 min (section 8) |
| `echo`, `echo2` | 40 s, 70 s | C | The sentence 3 and 6 times; the microphone track transcribed, then deleted |
| Dictation blocks | 4 × 5 dictations | C | None |
| `devices` to `devices4` | 6, 5, 5, 5 min | C, then D and E (section 8a) | The sentence every 20 s while the owner disconnected and reconnected Bluetooth earbuds |
| `tones-final` | 60 s | E (final) | A tone every 5 s, on the earbuds |

**Code versions:**
- **A:** chunks placed by when they arrived.
- **B:** A, plus silence kept up to the clock and late chunks counted.
- **C:** B, with chunks placed by Windows' capture timestamp.
- **D:** C, with each stream opened on its own holder thread.
- **E (final):** D, with the current default device opened as a real device instead of cpal's virtual default device (section 8a).

## 2. Capture architecture (summary)

Two cpal input streams record at the same time:
- **Microphone:** an input stream on the microphone.
- **PC sound:** an input stream opened on the default output device, which Windows serves as loopback.

Their callbacks only mix to mono and send the chunk, with the moment Windows says its first sample was captured. One writer thread per source then:
1. resamples to 16 kHz, keeping its position across chunks;
2. places the chunk on the shared timeline by that capture moment, writing silence for any stretch the source did not send;
3. appends it to its own temporary file.

A capture thread owns the streams. Every 2 s it checks the Windows default devices and reopens a source only for a real failure or a device change. Details: `docs/architecture/esymeet-capture.md`.

## 3. Microphone results (measured)

| | `long` (60 min, A) | `tones2` (15 min, C) |
|---|---|---|
| File length vs wall clock | 3600.139 s vs 3600.107 s (+0.03 s) | 900.111 s vs 900.115 s (−0.004 s) |
| Reopens / device errors | 0 / 0 | 0 / 0 |
| Overrun flags (Xrun) | 4 | 2 |
| Gaps (silence filled in on an open microphone) | 1 (0.105 s, in the first second) | 0 (0.101 s filled at the very start, before the first chunk) |
| Late chunks | not counted in A | 0 |
| Peak, clipped samples | 0.55, 0 | — |
| DC offset | −0.000016 | — |
| Furthest behind the clock during the run | — | 0.07 s |

- **Measured:** the microphone delivered continuously for an hour with no reopen. Its Xrun flags were not followed by any gap after the first second.
- **Observed:** the start always shows about 0.1 s of silence: the time the microphone takes to deliver its first chunk.

## 4. PC sound (loopback) results (measured)

| | `long` (60 min, A) | `tones2` (15 min, C) |
|---|---|---|
| File length vs wall clock | 3600.209 s vs 3600.107 s (+0.10 s) | 900.142 s vs 900.115 s (+0.03 s) |
| Reopens / device errors | 0 / 0 | 0 / 0 |
| Overrun flags (Xrun) | 50 | 13 |
| Silence filled in (nothing playing) | 3532 s of 3600 s | 0.73 s (the probe's tones keep the device running) |
| Late chunks | not counted in A | 0 |
| Peak, clipped samples | 0.48, 0 | — |
| Furthest behind the clock during the run | **187 s** (A: silence filled only when sound returned) | **0.05 s** (C) |

- **Measured:** loopback ran for an hour with no reopen and no lost speech. All 11 sentences were found (section 7).
- **Measured, and fixed during this study:** in version A, the PC-sound file stopped growing while nothing played. Its stretch of silence was written only when sound came back: the file was 187 s behind the clock during one quiet stretch.
  - Nothing was lost or misplaced: the silence was written in the right place later.
  - But a live transcriber reading the file would see "Others" stop for minutes.
  - **Correction:** while a source sends nothing, its writer fills in silence up to 0.5 s behind the clock (`KEEP_UP`). Chunks arrive 10–30 ms late, so they still land where they belong, and any chunk that does not is counted as **late**.
  - **Measured after the fix:** at most 0.05 s behind, 0 late chunks.

## 5. Synchronisation (measured, then explained)

**The 0.85 s seen in the first test was on the PC-sound track, not the microphone.** It was measured from the moment the test told Windows' sound player to play.

### 5.1 Spoken sentence played by Windows' sound player (`run`, `long`; version A)

| | Value |
|---|---|
| Speech found after the play command | 1.09–1.16 s over 14 plays (11 in `long`, 3 in `run`) |
| Trend over the hour | +36 ms per hour (least squares; within the 70 ms spread) |
| Silence at the start of the test sentence's own file | 0.27 s (measured in the WAV) |

### 5.2 Tones played by the probe itself (same process, same clock)

| Version | Tone found in the PC-sound track, after it was handed to Windows | Trend | Tone length (played: 200 ms) |
|---|---|---|---|
| B: placed by arrival | 171–173 ms for tones 1–63, then **122–124 ms for tones 64–89** | one step of about 49 ms | 189–200 ms |
| C: placed by Windows' capture time | **180–182 ms for 88 tones, 190 ms once** | −6 ms per hour | 199–200 ms |
| C, 60 s | 182–183 ms for 11 tones | | 199–200 ms |

cpal's own estimate of the output delay for those tones was 31–40 ms.

**Interpretation (inferred from the measurements above):**
- **Windows' playback start-up.** About 180 ms passes between a program handing audio to Windows and that audio being played, and so captured by loopback.
  - This is the render path on this PC, measured from inside the same process.
  - cpal's 31 ms estimate understates it.
  - It is not a capture delay. In a meeting EsyType plays nothing; the call app's audio is captured when it is actually played.
- **The rest of the 1.1 s was the sound player.** 1.1 s − 0.27 s of silence in the file − about 0.18 s render path leaves about 0.65 s: Windows' simple sound player (`SoundPlayer`) starting up.
  - This is inferred, not measured on its own.
  - It explains why the offset was steady across plays and did not grow.
- **Capture buffering was the variable part, and it is now removed.** Placing chunks by arrival time took on any change in how Windows buffered the stream: the 49 ms step in version B.
  - Placing them by Windows' own capture timestamp (the performance-counter position WASAPI gives for each buffer's first sample) removed the step: 180–182 ms over 15 minutes.
- **No clock drift between the device and the PC clock:**
  - Over 60 minutes, both files ended within 0.03–0.10 s of the wall clock.
  - Their offsets moved by −6 ms per hour (tones) and +36 ms per hour (sentences, within that method's spread).
  - **Continuous drift correction is not needed** for meetings of this length.
- **Microphone against PC sound: measured from echo, not from tones.**
  - The microphone array did not pass the steady tones: only 2–4 of 89 showed a tone-length sound, and some came before the tone was played, so they were room sound.
  - **It does pass speech** (section 7). In `echo2` (70 s, 6 sentences) the speech envelopes of the two tracks were cross-correlated around each play.
  - **Measured: the microphone track is 49–88 ms behind the PC-sound track** (median about 60 ms; correlation 0.38–0.46 each time).
  - **Interpretation (inferred):** the sound travels about 1 ms through the air, so nearly all of this is the microphone's own processing on this laptop.
  - **Not measured:** whether this offset changes over an hour. The tones that measured drift were not heard by the microphone. Both tracks follow the same Windows clock, and both files ended within 0.05 s of the wall clock after an hour.

**Synchronisation approach (recommended):**
- Keep Windows' capture timestamps as the only clock. No fixed calibration offset and no shifting of transcript times.
- **For transcript order** ("You" before "Others"): a 60 ms offset is far inside the about half a second that ordering lines needs. Nothing to correct.
- **For the echo check (9.3):** match microphone speech against PC-sound speech **within a window** (for example 0–250 ms later), measured per meeting from the echo itself, as done here. Do not use a fixed constant: other microphones and headsets will differ.
- **No continuous drift correction:** none was measured over an hour on either track. To re-check over a long real call in 9.3.

## 6. Xrun and error analysis (measured)

**What an Xrun is:**
- cpal reports an **Xrun** when WASAPI marks a buffer with `AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY`: the data may have a glitch.
- The stream itself keeps running.

**In version A's first form, every stream error reopened the stream:**

| | Result |
|---|---|
| In 30 s | 14 reopens of the microphone and 8 of the PC sound |
| Error text, recorded | "A buffer underrun or overrun occurred." |
| Effect | 1.4 s of microphone audio was replaced by silence |

**Now:**
- **Kept running and counted:** Xrun, `DeviceChanged` (Windows moved the stream itself) and `RealtimeDenied`.
- **Reopened:** any other error (device gone, stream invalidated).

| Source | Xruns, `long` (60 min) | Xruns, `tones2` (15 min) | Reopens | Gaps |
|---|---|---|---|---|
| Microphone | 4 | 2 | 0 | 1 at the start (A) / 0 (C) |
| PC sound | 50 | 13 | 0 | not applicable |

- **On the PC sound (observed),** the flags come when sound starts after silence.
  - Each played sentence and tone was complete: tones 199–200 ms long, sentences read back word for word.
  - So these flags mark the restart, not lost speech.
- **No real stream failure** happened in any run, so the reopen path for a genuine failure is **untested** (section 11).

## 7. Audio quality and Whisper (measured)

**Whisper:** Base, 4 threads, today's dictation window, on the PC-sound track around each play.

| Run | Sentences found | Read back exactly ("The quarterly figures are ready, and the launch meeting moves to Thursday afternoon.") |
|---|---|---|
| `run` (40 s) | 3 of 3 | 3 of 3 (0% errors) |
| `long` (60 min) | 11 of 11 | 11 of 11 (0% errors) |
| `long2` (60 min, final) | 11 of 11 | 11 of 11 (0% errors) |
| `echo`, `echo2` | 3 of 3, 6 of 6 | 9 of 9 (0% errors) |

**Levels and format:**

| Check | PC sound | Microphone |
|---|---|---|
| Clipping (samples at ±0.999 or more), both hours | 0 | 0 |
| Peak | 0.48 | 0.55 (`long`), 0.71 (`long2`) |
| Speech level during plays (RMS) | 0.093 every time | 0.0002–0.050 (see below) |
| DC offset | 0 | −0.000016 |
| Sample-rate conversion 48 → 16 kHz | Tone lengths kept (199–200 of 200 ms); self-check: 1 s in gives 1 s out across uneven chunks | Same converter |
| Channels | Stereo averaged to mono. A sound on one channel only would be 6 dB quieter; no effect seen on Whisper | Same |
| Continuity | No tone shortened or lengthened; 0 late chunks; lengths within 0.1 s of the clock after an hour | 0 gaps after the first second |

**The microphone during the plays (measured):**

| Run | Microphone level during each 6 s play (RMS) | Level in minutes without a play (median) | Whisper reading the microphone track during the plays |
|---|---|---|---|
| `long` | 0.0002–0.022 (7 of 11 plays clearly heard) | 0.0011 | not transcribed (file deleted) |
| `long2` | 0.017–0.050 (11 of 11) | 0.0068 | not transcribed (file deleted) |
| `echo` (40 s) | 0.016–0.050 | | the sentence in 3 of 3 plays (word for word in 2, with a few words of other room sound in 1) |
| `echo2` (70 s) | 0.029–0.050 | | **the sentence word for word in 6 of 6 plays** |

**Measured: on this PC the microphone hears the speakers' speech, and Whisper transcribes it.** A single mixed track would therefore contain every remote sentence twice, about 60 ms apart (section 5). That is not safe to assume away.
- The array removes steady tones (section 5) but not speech.
- Why it was heard in only 7 of 11 plays in `long` is not known: speaker volume, headphones or the array's processing may have differed.

The few words of other room sound in `echo` were removed from the stored result. Only the test sentence is kept.

**Recommended: two separate tracks, not one mixed stream.**

| | Two tracks (recommended) | One mixed stream |
|---|---|---|
| Speaker labels | "You" and "Others" come free from the source | Lost: needs a speaker model (a new AI model, not approved) |
| Echo | The microphone's copy of the other side can be found by time and text, and dropped (9.3) | The copy is mixed in about 60 ms later. Whisper read that copy in full from the microphone track in 6 of 6 plays (`echo2`), so a mix would carry the other side twice |
| Two people talking at once | Each track stays clean | Overlapping voices; recognition worse |
| Levels | Each track at its own level | A quiet microphone is drowned by loud speakers, or the reverse |
| Cost | Two transcriptions. At 2 threads a 10 s piece takes about 1.3 s (study 8.0), and people rarely talk at once, so the load is roughly one track's | One transcription |
| Timeline | Shared by construction (section 5) | Not needed |

## 8. Sixty-minute reliability (measured)

| | `long`: version A | `long2`: final version C |
|---|---|---|
| Ran for | 3600.1 s, in the background | 3600.1 s, in the background |
| Sentences found / read exactly | 11 / 11 | 11 / 11 |
| Reopens, device errors | 0, 0 | 0, 0 |
| Microphone gaps | 1 (first second) | 1 (0.101 s, before the first chunk) |
| Late chunks | — | 0 on both |
| Xrun flags (microphone / PC sound) | 4 / 50 | 1 / 60 |
| Sentence found after the play command | 1.09–1.16 s, +36 ms per hour | 1.08–1.15 s, +19 ms per hour |
| Furthest behind the clock during the run (PC sound) | 187 s (no keep-up) | 0.81 s (by design: keep-up at 0.5 s, plus up to 0.25 s between the writer's checks) |
| Files vs wall clock at the end | +0.03 s (microphone), +0.10 s (PC sound) | +0.03 s (microphone), +0.05 s (PC sound) |
| Clipping | 0 | 0 (peaks: PC sound 0.48, microphone 0.71) |
| CPU | 0.81% of one core (29.1 s in an hour) | 0.85% of one core (30.2 s in an hour) |
| Memory (working set / private) | 12.2–12.3 MB / 2.3–2.6 MB, flat from minute 16 to 60 (sampling started late) | 11.9–12.4 MB / 2.3–2.6 MB, flat over the whole hour (120 samples, every 30 s) |
| Handles, threads | 225 throughout; 8–10 | 223–239; 8–17 (Windows' audio threads come and go; no growth) |

**For meetings of 30–120 minutes (inferred from the above):**
- **Memory and threads:**
  - Memory stays flat: each chunk is passed on at once, the resampler keeps under one chunk, and device events are logged only on a change.
  - The two channels are unbounded, but the writers keep up: private memory did not grow.
  - **Recommended for integration:** a bounded channel, so a stalled disk cannot grow memory.
- **Disk:** each source writes 64 kB/s, so both together write about 460 MB an hour. This probe keeps whole files only to measure them.
  - **Recommended for 8.3/9.x:** write short pieces (one per segment, a few seconds to 15 s), transcribe them, keep the text and delete each piece.
  - A meeting then never holds more than about a minute of audio on disk, and no meeting audio is kept, as the plan requires.
  - EsyType's data folder is on C:, which has little free space on this PC: another reason not to keep whole files.
- **Shutdown:** stop joins every thread, flushes and pads both files to the stop time. That happened at the end of each of the 8 runs that ended normally, with no hang.
  - The two captures during the dictation blocks were ended by force, as a crash would end them.
  - Their files were deleted unread, so recovery after a crash is still to test (8.3).
- **Thread safety:** the streams stay on one thread; samples travel by channel; statistics sit behind one mutex, which the callbacks never take.
- **Timestamps over a long meeting:** Windows' capture times use the PC's performance counter, which does not wrap. No drift was seen in an hour.

## 8a. Device changes (measured with the owner, Bluetooth earbuds)

The owner disconnected and reconnected Bluetooth earbuds, the default output, during 5–6 minute runs. A sentence played every 20 s.

| Run | Version | What happened | Sentences captured |
|---|---|---|---|
| `devices` | C | At 92.9 s Windows invalidated the stream (`AUDCLNT_E_DEVICE_INVALIDATED`). Every reopen then failed, every 2 s, until the end. The log grew by one line per attempt | **4 of 17** |
| `devices2` | C + detailed errors | The same. The reopen failed at "Failed to get audio client: Cannot change thread mode after it is set" (`RPC_E_CHANGED_MODE`) | 1 of 14 |
| `devices3` | D (holder thread per stream) | The first switch reopened correctly (17.3 s). After the second (83.5 s), the same failure, even from a fresh thread | 4 of 14 (the 4th partly) |
| **`devices4`** | **E (real device)** | **30.8 s: earbuds disconnected, stream invalidated, reopened on the laptop speakers. 274.4 s: earbuds back as the default, reopened on them** | **14 of 14, all read back exactly** |

**Cause (measured, then traced in cpal 0.18's source):**
- cpal's "default output device" is a virtual device. It is activated through `ActivateAudioInterfaceAsync`, Windows' route for a stream that follows the default device.
- After Windows invalidated a stream, that activation failed with `RPC_E_CHANGED_MODE` for the rest of the process, from any thread.
- A new process could open the same device, and so could a real device from the device list.

**Fixes:**
1. **The real device:** the module looks up the name of the current default, then opens that real device from the list. The virtual default is only the fallback.
2. **A holder thread per stream:** each stream gets clean COM state.
3. **Errors name the step and the device.**
4. **One log line per reason:** a lost device is logged once per reason, not once every 2 s, so the log cannot grow without bound during a long loss.

**Also measured in `devices4`:**
- **The microphone** (built-in, unchanged) stayed open: 2 short gaps, 0.65 s in total, while the Bluetooth connection was switching.
- **The PC-sound track** stayed on one timeline: 300.20 s for 300.16 s of wall time, 0 late chunks.

**Not covered:**
- **A change of microphone:** the earbuds' microphone never became the default. It uses the same lookup-by-name path, but is untested.
- **Wired headphones and USB microphones:** none were used.
- **Speech during a switch:** the module checks every 2 s, so up to about 2 s of PC sound can be missed at the moment of a switch. No sentence fell in that window here.
  - **Recommended for 8.3:** check stream errors every 100 ms, and keep checking the default device every 2 s.

## 9. Dictation with and without capture (measured)

**Conditions:**
- the same test build, 4 threads, clip `6930_10s`, keys only into the probe's own window, on mains
- alternating blocks of 5 dictations: off, on, off, on
- during "on" blocks, the final capture version ran for the whole block

| Block | Dictation times (s) | Median |
|---|---|---|
| Off | 2.7, 2.3, 2.2, 2.3, 2.1 | 2.3 |
| On | 2.3, 2.5, 2.2, 2.2, 2.2 | 2.2 |
| Off | 2.3, 2.4, 2.4, 2.2, 2.3 | 2.3 |
| On | 2.3, 2.3, 2.2, 2.2, 2.2 | 2.2 |
| **All off** (10) | 2.1–2.7 | **2.3** |
| **All on** (10) | 2.2–2.5 | **2.2** |

**Difference:** −0.1 s with capture, half the timer's resolution and inside both ranges. Word error rate was 0.069 in every run, both ways.
- **Not meaningful:** capture does not slow dictation.
- **The earlier 2.1 s against 2.2–2.3 s** came from different times of day: every block today, with or without capture, sat at 2.2–2.3 s.
- **Earlier context:** the two "on" blocks during `long` (version A, 3 dictations each) had medians of 2.2 and 2.3 s.

## 10. CPU and memory (measured)

| Run | CPU (of one core) | Working set | Private memory |
|---|---|---|---|
| `run` (40 s) | 0.74% | — | — |
| `long` (60 min) | 0.81% | 12.2–12.3 MB | 2.3–2.6 MB |
| `tones2` (15 min, the probe also playing tones) | 1.2% (10.9 s) | 12.0–12.4 MB | 2.4–2.7 MB |
| `long2` (60 min, final) | 0.85% | 11.9–12.4 MB | 2.3–2.6 MB |

The figures are for the probe process: both streams, the resampling and the file writing. Integrated, the capture should cost about the same (inferred; to be measured in 8.3).

## 11. Known limitations

- **Device changes:** Bluetooth earbuds in and out work after the fixes (section 8a). Still untested:
  - a change of microphone
  - wired and USB devices
  - the up to 2 s missed at the moment of a switch
- **Microphone-to-loopback offset measured only briefly** (section 5): 6 plays in 70 s; no drift measurement for the microphone.
- **Echo is real** (section 7): the microphone repeats the speakers' speech, 49–88 ms later. EsyMeet must keep the tracks separate and drop echoes (9.3). Its rate on other microphones and headsets is unknown.
- **Default output only:** a call app sending its sound to a non-default device would not be captured.
- **Everything the PC plays is captured:** a video or a notification during a meeting is captured too. Per-app capture needs Windows' process loopback, which cpal does not offer.
- **Whole files in this probe:** to be replaced by short pieces at integration (section 8).
- **The test sentences are synthetic** (Windows' Hazel voice), not a real call. A real call with network audio is tested in 8.2.
- **Which version each measurement used:**
  - The 60-minute measurements on version A came before the two timing fixes. The final timing version's hour is `long2` (version C).
  - Versions D and E changed only how a stream is opened (section 8a). Their streaming path is C's, rechecked in `tones-final` and `devices4`.
- **The playback delay depends on the device:** tones were seen 180 ms after being handed to Windows on the laptop speakers, and 12–13 ms on the earbuds (loopback sees sound when it enters the device's mix). This doesn't affect the timeline.

## 12. Recommended architecture for what follows

All within the approved phases 8–10. Each step is to be approved separately.

1. **8.2 Meeting detection and prompt** (next, as planned):
   - Watch Windows' "microphone in use" record.
   - Show the prompt.
   - Never capture until Start.
   - Test with real Teams, Zoom and Meet calls, which also proves loopback on real call audio.
2. **8.3 Recording session:** integrate `capture.rs` behind Start, Pause and Stop. At that point, change it to:
   - check stream errors every 100 ms, so a switch costs at most a fraction of a second;
   - write short pieces instead of whole files;
   - use a bounded channel;
   - delete each piece's audio once its text is saved;
   - add crash recovery.
3. **9.1 Segmenter:** cut each track at pauses (Silero, already bundled), using the timeline from this study. Use study 8.0's short window, 256-frame margin, on 2 threads.
4. **9.3 Echo:** keep the two tracks separate (section 7). Drop microphone speech that matches PC-sound speech 0–250 ms earlier, with the offset measured per meeting from the echo. Recommend headphones.

## 13. Does 8.1 pass?

| Acceptance criterion | Result |
|---|---|
| Both sources captured reliably | **Pass:** 2 × 60 min and 2 × 15 min with 0 reopens and 0 device errors; every sentence and tone found |
| Synchronised enough for meeting transcription | **Pass:** one Windows clock; PC-sound placement steady to ±1 ms; no drift in an hour. The microphone sits 49–88 ms behind the PC sound (measured from echo) |
| No unexplained audio loss or duplication | **Pass:** tones 199–200 ms of 200; 0 late chunks; the only microphone gap is the first 0.1 s, explained. **The echo duplication is explained** (the microphone hears the speakers) and is why the tracks stay separate; dropping it is 9.3's job |
| Recoverable Xruns do not restart healthy streams | **Pass:** fixed during this study; 0 reopens after the fix |
| Long-duration capture stable | **Pass:** both hours (versions A and final C) |
| Dictation acceptable during capture | **Pass:** 2.2 s with capture against 2.3 s without (section 9) |
| Memory bounded | **Pass:** flat at about 12 MB working set and 2.5 MB private |
| Architecture documented | **Pass:** `docs/architecture/esymeet-capture.md` |
| Limitations recorded | **Pass:** section 11 |
| Device changes (plan: headphones in and out, microphone unplugged) | **Pass for headphones** after a fix: Bluetooth earbuds out and back in, 14 of 14 sentences (section 8a). **Microphone change not tested:** the default microphone never changed |

**Conclusion:** 8.1 **passes**. Every criterion is met on this PC, with one open check: switching the default microphone. It uses the same path as the output switch that passed.

**To close it:** during 8.2's real-call tests, make the earbuds' or a headset's microphone the default once, and confirm the capture follows.
