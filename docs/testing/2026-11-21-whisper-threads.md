# Whisper thread count: idle and with other programs running

**Date:** 21 November 2026 · **Asked by:** the owner, after slow dictation was seen on a busy PC (`2026-11-20-insertion-reliability.md`) · **Machine:** development PC, i5-11320H (4 cores, 8 threads), mains power · **Build:** e2e test build, separate folder; production settings not changed · **Nothing downloaded**

## Question

Which automatic thread count gives (in the owner's order of priority) reliable transcription while other programs run, consistent response time, a responsive Windows and EsyType, good accuracy, and fast idle performance? EsyType's automatic setting today is all logical processors but one: **7** on this PC.

## Method

- `bench/e2e/threads-probe.ps1`: the test build dictates the recorded 10 s clip `6930_10s` (LibriSpeech) into its own test window (keys go only there), Base model, Clean mode.
- **Time:** from releasing the keys to the text appearing in the window. Limit 120 s; no text by then counts as a failure.
- **Responsiveness:** during each transcription, every 100 ms, how long the test window (an ordinary app) and EsyType's own window took to answer a no-op message. The worst value is kept.
- **Accuracy:** word error rate against the clip's reference text.
- **Warm-up:** the time until the model is ready after start-up.
- **Conditions:**
  - idle
  - **half load**: 4 processes kept busy at below-normal priority, standing in for other programs (a browser, a build, a video call)
- **Repeats:** 7, 4, 2 threads, then 2, 4, 7 (so order and heat do not favour one setting), 3 dictations each, so **6 per setting per condition**.
- Raw rows: `2026-11-21-whisper-threads.csv`.

## Results (10 s of speech)

| Condition | Threads | Median | Range | Failed (no text in 120 s) | Worst window answer: test app / EsyType | Warm-up |
|---|---|---|---|---|---|---|
| Idle | **7** (today's automatic) | **1.8 s** | 1.8–1.9 s | 0 of 6 | 79 ms / 23 ms | 2.4–2.8 s |
| Idle | **4** | **2.2 s** | 2.0–2.2 s | 0 of 6 | 1 ms / 0 ms | 2.8–2.9 s |
| Idle | 2 | 3.4 s | 3.3–3.5 s | 0 of 6 | 8 ms / 0 ms | 3.9–4.1 s |
| Half load | **7** (today's automatic) | **43 s** | **20–120 s** | **1 of 6** | 28 ms / 4 ms | 2.5–3.3 s |
| Half load | **4** | **3.5 s** | 3.4–3.6 s | 0 of 6 | 27 ms / 2 ms | 4.4–4.5 s |
| Half load | 2 | 4.9 s | 4.9–5.2 s | 0 of 6 | 11 ms / 1 ms | 6.2 s |

- **Accuracy:** every dictation that produced text gave exactly the same text ("Yes, I need repose. Many things have agitated me today, both in mind and body. When you return to-morrow, I shall no longer be the same man."). Word error rate 6.9% in every case. That figure is only the reference's old spellings ("to day", "to morrow"), not a recognition error, so the thread count does not affect accuracy.
- **Responsiveness:**
  - Windows and EsyType answered within 80 ms in every run, under every setting, so no setting froze the PC or the EsyType window.
  - The slow 7-thread runs under load were waiting, not hogging: other programs stayed responsive while the dictation took 20–120 s.
- **Glitch excluded:** one idle 2-thread run is recorded without text. The text arrived at 3.4 s, but the probe's second read of the result file collided with the window writing it. The probe now reads once (fixed in `threads-probe.ps1`). The run's time is included and its text is not.

## Findings

1. **7 threads breaks down when other programs are busy:**
   - median 43 s instead of 1.8 s
   - inconsistent (20–120 s)
   - one dictation in six produced nothing within two minutes
   
   An earlier attempt with 8 threads (the settings file asked for 7,432 because of a probe bug, capped at 8) did not even finish the model's 1 s warm-up within 2 minutes under load.
2. **4 threads (the physical core count) is stable in both conditions:**
   - 2.2 s idle, 3.5 s under half load
   - range within 0.2 s, and no failures
3. **2 threads is slower in both conditions** and gains nothing in stability over 4 at half load.
4. **Cost of 4 instead of 7 when idle:** 0.4 s for 10 s of speech (1.8 → 2.2 s), still within the 2–3 s target. This matches the 17 Nov benchmark (8 threads 15–21% faster than 4, idle only), which is why the default was changed then. That benchmark did not test a busy PC.
5. **Likely cause** (read in the bundled whisper.cpp source, `ggml-cpu.c`):
   - Whisper's worker threads wait for each other at a spinning barrier after every step, so one thread that Windows has paused holds up all of them.
   - With 7 threads on 8 logical processors (4 real cores) and other work running, Windows regularly pauses one of them: it briefly boosts starved low-priority programs and shares cores between hyper-threads.
   - With 4 threads there are free processors for the other work, so the pauses do not stall the step.

## Recommendation (approved by the owner and applied, 21 Nov 2026: decision 0024)

**Automatic = the number of physical cores, never more than logical processors − 1, at least 1.** On this PC: 4 (today 7).

- Meets priorities 1–3 in this test: no failures, consistent times and a responsive PC under load. Priority 4 is unaffected, and priority 5 costs about 0.4 s idle.
- Change: one line in `settings::effective_threads`, using the physical core count EsyType already reads (`hardware.rs`, via the installed `sysinfo` crate), plus its unit test. No new dependency, no download, settings unchanged (a user's manual thread choice is kept).
- **A strategy that adapts to the CPU load at the moment of dictation is not recommended on this evidence:**
  - At half load, going below 4 threads made dictation slower (4.9 s at 2 threads against 3.5 s at 4), not more reliable.
  - The physical-core rule already leaves room for other programs.
  - The load can change during the dictation itself.
  - It would add a CPU measurement before every dictation for no measured gain.
  
  Full load (all 8 processors busy) was not measured in this round. If it shows 4 threads failing too, adapting would be worth reconsidering.

## After the change (production build installed 21 Nov 2026)

The test build with Automatic (no thread count set), 6 dictations per condition (`2026-11-21-whisper-threads-auto.csv`):

| Condition | Median | Range | Failed | Worst window answer: test app / EsyType |
|---|---|---|---|---|
| Idle | 2.2 s | 2.1–2.3 s | 0 of 6 | 1 ms / 0 ms |
| Half load | 3.4 s | 3.3–3.5 s | 0 of 6 | 3 ms / 1 ms |

Same text in all 12 (word error rate 6.9%, the reference's spellings). Unit tests 47 of 47, including the new rule for 1–16 processors with and without hyper-threading and an unknown core count. The owner's settings were not changed: they were already on Automatic, which now means 4 on this PC.

## Not tested

- Full load (all processors busy); battery and power-saving modes; other CPUs, notably hybrid Intel CPUs with efficiency cores, where "physical cores" includes slower cores and may need its own measurement.
- Small and Tiny models (Base only); clips other than 10 s; real speech from the microphone.
