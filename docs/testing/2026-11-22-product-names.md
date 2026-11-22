# Built-in product names (recognition plan, Proposal A). Test record

**Date:** 22 November 2026 · **Plan:** `docs/plans/recognition-accuracy-plan.md` (approved as recommended: "openai" only, "Versal" kept, EsyType and EsyAI not auto-corrected from "easy type" and "Easy AI") · **Build:** e2e test build only · **Released in 0.3.0** and installed on your PC (section 5) · **Nothing downloaded; no dependency added**

## 1. What was built

- **`src-tauri/src/vocabulary.rs`**: a fixed list of 29 product names with the forms Whisper writes instead.
  - Two kinds of rule only:
    - forms that are not English words ("chat GPT", "Superbase", "Versal", "N8N", "github", "node.js")
    - phrases whose context makes the product certain ("Microsoft co-pilot", "power automate")
  - Never listed:
    - names that are also everyday words (Claude, Gemini, Notion, Python, Excel, React, Teams, Canva)
    - spaced forms made of two ordinary words ("word press", "power point", "air table", "java script", "type script")
- **Matching** (`dictionary.rs`), through the Dictionary's own matcher, after your entries:
  - On the same words, your entry wins.
  - A dot inside a name now joins a phrase ("node.js", "make.com"); a full stop followed by a space still never does.
  - Built-in names never span a comma. Your own entries still may (one comma, as before).
  - Built-in names are never put into the hint.
- **Setting:** `builtin_vocabulary`, on by default. Your settings file is not rewritten; the setting appears in it only when settings are next saved.
- **Dictionary page:** a "Built-in product names" panel with the switch "Correct common product names" and a read-only list. The list can't be edited, deleted, exported or imported. Clean and Verbatim both use it, like your Dictionary. History keeps the engine's original text.

## 2. Measured (Base, the same 220 clips as the plan's baseline, through the app's own matcher and Clean code)

| | Without the list | With the list |
|---|---|---|
| Product names spelled exactly (Verbatim) | 148/250 (59%) | **200/250 (80%)** |
| Product names spelled exactly (Clean) | 149/250 | **201/250** |
| British/US voices / Indian English voices | 91/150, 57/100 | **124/150, 76/100** |
| Product sentences, word errors | 12.5% | **8.6%** |
| Mixed everyday and product sentences | 1.5% | **0.0%** |
| Ordinary sentences with look-alike words | 0.8% | 0.8%: **0 of 70 clips changed** |
| LibriSpeech | 3.5% | 3.5%: **0 of 10 clips changed** |
| Brand spelled where none was said | 0 | 0 |
| Time and memory | | no change: text rules take well under 1 ms |

- **All 46 changed product clips were read one by one; every change is right.** Two examples: "Microsoft Co-pilot" → "Microsoft Copilot" and "node.js" → "Node.js".
- **Still missed** (not safe to fix by rule):
  - Claude heard as "claw", "cloth" or "clogged"; DALL-E as "dolly"; "mid-journey"
  - EsyType and EsyAI as "easy type" and "Easy AI"
  - garbled forms: "J-mini", "power or to make", "Jevoscript"
- The real matcher scores 3 names lower than the plan's Python estimate (203), because "open AI" and "air table" were left out as decided, and "Co. Pilot" (a full stop and a space) is not joined.

## 3. Tests

| Test | Result |
|---|---|
| Unit tests | **63 of 63** (4 new): real engine output from the benchmark corrected; 16 ordinary sentences left alone (including "the co-pilot landed", "type the word, press enter", "plug it into the power point", "It's easy. Type it."); your entries win and stay out of the hint; the list is well formed |
| Measurement test (`vocabulary::measure_saved_transcripts`, run on request) | Writes the four variants above for `bench/accuracy/score.py` |
| `dictionary-e2e.ps1` | **18 of 18** (5 new). A spoken "chat GPT" is typed as ChatGPT after Delete all, and History keeps "chat GPT". Switched off: saved, and no longer corrected. Switched on again. The list shows on the page. Exports hold only your own entries |
| Full regression | see section 4 |

## 4. Full regression (quiet PC, on mains, final build)

| Suite | Result |
|---|---|
| Unit tests | **63 of 63** |
| Polish ×2 / data / first run / navigation / settings recovery | **25/25, 25/25, 27/27, 32/32, 14/14, 10/10** |
| History UI / Dictionary / Snippets / Scratchpad / Style / Clean / Try it | **33/33, 18/18, 14/14, 15/15, 12/12, 10/10, 2/2** |
| History / Undo / slow paste / insertion / Undo in apps / spacing (Word, Chrome) | **19/19, 13/13, 21/21, 18/18, 8/8, 14/14** |
| Dictation time, Automatic threads | Idle **2.0 s and 2.1 s** medians (2.0–2.1 s). Half load **3.3 s twice** (3.2–3.4 s), 12 of 12 with text. Unchanged |

- **Not run:**
  - the Notepad steps and `history-apps` (Notepad was open)
  - ChatGPT (owner rule)
  - the five oldest suites
- **An earlier attempt was spoiled by Windows Update installing** (`TiWorker`): dictations took up to 80 s and windows lost the front. It was stopped and repeated once the update had finished.
- **A test Notepad window** (`esytype-history-20261122-163819.txt`) was left open by that attempt. It was not closed by the tests, because Notepad runs all its windows in one process.

## 5. Release 0.3.0 on your PC (approved by you, 22 Nov)

**Before switching:** a backup from a copy of your files, `D:\EsyAI\EsyType\backups\EsyType backup 2026-11-22 2017.esytype-backup` (6 dictations), checked by restoring it into a separate test profile (6 back). Your live files were unchanged.

**The switch:** quit only your installed EsyType, ran `EsyType_0.3.0_x64-setup.exe /S /D=D:\EsyAI\EsyType\app`, started EsyType in the tray.

- **The first attempt stopped with exit code 2 and changed nothing** (0.2.0 stayed, data unchanged). The installer had started 2 seconds after EsyType was quit, probably while it was still closing. The second attempt waited 5 seconds and checked that no EsyType was running: exit code 0.

| Check | Result |
|---|---|
| `settings.json` | byte-for-byte unchanged |
| History | 6 entries; schema 6 |
| Start with Windows | `D:\EsyAI\EsyType\app\esytype.exe --minimized` |
| Apps list | "EsyType" 0.3.0, publisher EsyAI, folder `D:\EsyAI\EsyType\app` |
| Start menu | one shortcut, pointing at the installed program |
| The installed program | version 0.3.0; the same as the build apart from the 3-byte bundle-type marker |
| Running | in the tray, no window shown |
| Desktop | the silent install made a shortcut. Removed, as agreed for your PC |
