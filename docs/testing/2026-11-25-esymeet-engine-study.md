# EsyMeet study 8.0: can the engine keep up with a meeting? Test record

**Date:** 25 November 2026 · **Plan:** `docs/plans/next-generation-audit-and-plan.md`, milestone 8.0 (bench only) · **App: not changed** · **Nothing downloaded; no dependency added** · **On mains**, Base (`ggml-base.en-q5_1`), EsyType's engine settings (`ESYTYPE_BENCH_APP=1`)

## 1. The question

Whisper normally works on a 30-second window, so a 5-second piece costs as much as a 30-second one: about 2.1 s on this laptop. With that, meeting text would appear 10–20 s after speech.

Shrinking the window to the length of the piece ("short window") is about 6× faster. In the November audit, though, it repeated whole sentences, and errors on ordinary sentences rose from 0.8% to 19.2%. The plan listed five candidate fixes, to be measured before any EsyMeet code is written.

**Bar (from the plan):** a setting is accepted only if ordinary English stays at 0.8% or better and LibriSpeech at 3.5% or better. Your own recordings are to be checked too.

## 2. Accuracy: 220 synthetic clips and 10 LibriSpeech clips, one run each

| Condition | Ordinary | Mixed | Product | LibriSpeech | Names exact (of 250) | Time per clip (ordinary) |
|---|---|---|---|---|---|---|
| Today's window (30 s) | 0.8% | 1.5% | 12.5% | 3.5% | 148 | 2.04 s |
| Short window, margin 64 frames (the November setting) | 19.2% | 63.7% | 18.3% | 3.7% | 135 | 0.27 s |
| + one segment | 19.0% | 63.7% | 20.8% | 11.3% | 136 | 0.29 s |
| + no timestamps | 75.3% | 20.7% | 101.2% | 5.3% | 133 | 0.85 s |
| + token limit (5 per second) | 17.5% | 19.3% | 20.0% | 11.3% | 136 | 0.23 s |
| + drop a repeated sentence | 0.8% | 1.5% | 13.0% | 3.7% | 135 | 0.26 s |
| **Margin 128 frames (2.6 s)** | **0.8%** | 1.5% | 12.9% | **3.4%** | 138 | 0.29 s |
| **Margin 256 frames (5.1 s)** | **0.8%** | 1.5% | 12.5% | **3.4%** | 141 | 0.42 s |
| Margin 256 + drop a repeated sentence | 0.8% | 1.5% | 12.5% | 3.4% | 141 | 0.45 s |
| Margin 384 frames | 0.6% | 1.5% | 12.8% | 3.4% | 141 | 0.59 s |
| Margin 512 frames | 0.6% | 1.5% | 12.6% | 3.4% | 140 | 0.76 s |

1500 frames = 30 s. Results: `D:\AI Projects\Tools\bench\results\short-window\*.jsonl`; scored with `bench/accuracy/score.py`.

**What this shows:**
- **The repeats came from too small a margin.** With 64 frames (1.3 s) of room after the speech, the model "fills" the rest of the window by repeating the sentence. From 128 frames up, the repeats are gone and accuracy equals today's on ordinary sentences, mixed sentences and LibriSpeech.
- **One segment, no timestamps and a token limit make things worse.** Dropping a repeated sentence hides the repeats, but product sentences get worse (13.0%).
- **The cost: product names.** Every short-window setting spells slightly fewer product names exactly: 138–141 of 250, against 148 today. Product sentences overall stay at 12.5–12.9%.

## 3. Speed of meeting-sized pieces (median of 6 runs, two voices)

| Piece | Today's window, 4 threads | Short window (256), 4 threads | Today's window, 2 threads | Short window (256), 2 threads |
|---|---|---|---|---|
| 5 s | 2.15 s | 0.54 s | 3.19 s | 0.78 s |
| 10 s | 2.11 s | 0.94 s | 3.24 s | 1.33 s |
| 15 s | 2.24 s | 1.32 s | 3.34 s | 1.87 s |

All ranges were within ±0.2 s. **With 2 threads, a 10-second piece takes 1.3 s, about 13% of real time.** Both streams together (your microphone and the other people's audio) fit comfortably, with two cores left for dictation and everything else.

## 4. Decision

- **EsyMeet uses the short window with a 256-frame margin, Base, 2 threads.**
  - It meets the plan's bar on the synthetic set and LibriSpeech.
  - Text can follow speech by about 2–6 seconds (a pause ends a piece, then about 1 s to transcribe it), not 10–20 seconds.
  - Pieces of 30 s or more use the normal window anyway.
- **Dictation stays as it is.** The short window would cut dictation from about 2.1 s to about 0.5 s, but it spells 7 fewer product names of 250. Whether that trade is worth it for dictation is a separate decision for you, with your own recordings; nothing changes now.
- **Still open: your own recordings.** The plan's bar also asks for your voice: the recording kit (`docs/testing/recording-kit.md`, about 15 minutes). The result above is on synthetic voices and LibriSpeech only.

## 5. Bench changes

- `bench/stt-bench`: options for the margin, one segment, no timestamps, a token limit and dropping repeated sentences (environment variables; documented at the top of `main.rs`). New self-check for dropping repeated sentences.
- `bench/accuracy/run.ps1`: the conditions above (`short`, `short-margin`, `short-m128` … `short-margin-dedup`).
