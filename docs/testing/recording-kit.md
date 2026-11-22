# Recording kit: your voice for the accuracy benchmark

**Plan:** `docs/plans/recognition-accuracy-plan.md`, Proposal C · **Built:** 22 November 2026 · **Test tool only:** EsyType itself is not changed · **Nothing downloaded**

The accuracy numbers so far come from computer voices, which are cleaner than real speech. This kit records you reading a short script once, so every later change can be measured on your real voice, microphone and room before it ships.

**Privacy:** the recordings stay on this PC, in `D:\AI Projects\Tools\bench\audio\owner`. They are never uploaded or put in the repository. Delete that folder at any time to remove them.

## Recording (about 15 minutes)

1. Sit where and how you normally dictate. Use the microphone you normally use.
2. Open PowerShell and run:

```powershell
& "D:\AI Projects\Tools\bench\target\release\esytype-record.exe" record "D:\AI Projects\Projects\EsyType\bench\accuracy\owner-script.json" "D:\AI Projects\Tools\bench\audio\owner"
```

3. For each sentence: press **Enter**, read it, press **Enter**.
   - After each one you see how long it was and how loud. Press **Enter** to keep it, **r** to record it again, or **q** to stop for now.
   - If it says the take was too loud (clipped) or very quiet, record it again.
4. Stopped part-way? Run the same command again: finished sentences are skipped.

**Two short silent recordings** run by themselves:
- 5 seconds of your room at the start
- 15 seconds of TV, radio or tap noise on its own in the noisy section

**To use another microphone:** run `esytype-record.exe list`, then add `--mic "name"` to the command.

**To redo particular sentences:** add `--only e03,q02`.

### The 12 sections

| Section | Sentences | What to do |
|---|---|---|
| Everyday conversation | 10 | as you would talk to a friend |
| Your own accent | 6 | your normal voice; don't change it |
| Fast speech | 5 | quickly, as when in a hurry |
| Slow speech | 4 | slowly, as if thinking |
| Quiet speech | 5 | softly, at your normal distance |
| Natural pauses | 5 | stop for a second where you see … |
| A noisy room | 6 | TV, radio or tap on at an everyday volume |
| Numbers, dates and money | 7 | the way you naturally say them |
| Product names | 8 | as you normally say them |
| Technical terms | 6 | |
| A long dictation | 1 | about 90 seconds, in one go |
| Mixed casual and professional | 7 | |

## What happens next (done by Claude)

```powershell
& "D:\AI Projects\Tools\bench\target\release\esytype-record.exe" convert "D:\AI Projects\Tools\bench\audio\owner"
& "D:\AI Projects\Projects\EsyType\bench\accuracy\run.ps1" -Set owner
python -I "D:\AI Projects\Projects\EsyType\bench\accuracy\score.py" "D:\AI Projects\Tools\bench\results\owner" "D:\AI Projects\Tools\bench\audio\owner" --script "D:\AI Projects\Projects\EsyType\bench\accuracy\owner-script.json"
```

1. **`convert`** makes 16 kHz copies with EsyType's own conversion code, so the benchmark hears exactly what the app hears. The originals keep the microphone's own rate (48 kHz here), so a better conversion can be tested against them later.
2. **`run.ps1 -Set owner`** transcribes them with the app's engine settings.
3. **`score.py --script`** scores them:
   - word and character error rates by section
   - product names spelled exactly
   - brand names written where none was said
   - any words written for the silent recordings
4. From these: the real-voice baseline, then the Proposal D candidates, each kept only if your recordings show a measurable gain:
   - quiet-speech gate
   - 16 kHz conversion
   - Small model for accents
   - level normalisation

## How the kit was checked (22 Nov)

- **Self-tests (3, all pass):**
  - WAV files are written and read back unchanged
  - levels are measured correctly
  - the too-loud and too-quiet advice fires when it should
  - the app's own 16 kHz conversion
- **This PC's microphone:** "Microphone Array (Intel Smart Sound Technology)", 48 kHz, 2 channels.
  - A 5-second room take and a short take were recorded, saved, listed in `takes.json` and converted.
  - Those test recordings were then deleted.
- **End to end with a computer voice:** five script sentences, including the 90-second dictation, read at 48 kHz, went through `convert`, `run.ps1 -Set owner` and `score.py`.
  - Everyday sentence and long dictation: 0% word errors.
  - "Superbase" and "Versal" come out raw, as expected: scoring is of the engine's own text, before the built-in names.
- **Bug found and fixed:** a `takes.json` saved by Windows PowerShell (with a byte-order mark) was read as empty, and `convert` reported 0 converted. The recorder now accepts it, and `convert` stops with a clear message if no takes are listed.
- **To check with your recordings:** in the 5-second room test, the engine wrote "There is a meeting." The take was not silent (loudest −15 dB), so either something was audible or the engine invented words. The benchmark does not run EsyType's voice gate, which normally drops silence. Your two silent recordings will show which.

## Limits

- **Numbers:** the scorer spells digits out but does not read "£" or ":".
  - "£249.99" said as "two hundred and forty-nine pounds ninety-nine" counts as a few word errors even when it is written well.
  - Read the numbers section's examples rather than its error rate alone. A scorer for Clean output, where numbers are formatted, comes next.
- **One take each:** every sentence is read once.
  - A result is trusted only when it holds across the whole set, never from one sentence.
