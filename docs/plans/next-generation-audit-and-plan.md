# EsyType next generation: audit, architecture and roadmap (Phases 6–11)

**Date:** 22 November 2026 · **Brief:** "EsyType master product development prompt" (owner, 22 Nov) · **Status:** **approved 22 Nov** with one addition: frosted (liquid) glass in the app and its pop-ups (section 4.4). Decisions in section 6. No code written yet; production unchanged.

**Measured for this audit**, all on this PC, test tools only, nothing downloaded or installed:
- a 5-second probe that captured the microphone and system audio at the same time
- engine timings
- one accuracy run

Visual mockups: the "EsyType next generation" page published with this report.

## 0. Summary

1. **Most of the brief already exists** and is tested: everything in the brief's section 2, plus the built-in product names (0.3.0), backup and restore, and the recording kit.
   - **Two corrections to the brief:**
     - production is **0.3.0**, not 0.2.0
     - the italic serif you like is **Georgia**, Windows' own font: the planned brand font (Instrument Serif) was never bundled
   - **Biggest gap is real use, not features:** nearly every feature is "completed in automated testing; not yet used by the owner". Your spoken per-app test and the restart check are still open.
2. **Live meeting transcription is feasible on this laptop, but not by simply cutting the audio into 5-second pieces.**
   - Whisper always processes a 30-second window, so a 5-second piece costs as much as a 30-second one: Base 2.6 s, measured on battery.
   - Two audio streams cut every 5 seconds would need more than the whole processor.
   - The engine's "short window" setting cuts Base to **0.40 s per 5-second piece (6× faster).** But on the accuracy set it repeated whole sentences on 15 clips, and ordinary-English errors rose from 0.8% to 19.2%.
   - **Fixing that is the first engineering step for EsyMeet**, measured before anything is built on it. If it can be fixed it may also make everyday dictation faster.
3. **System audio can be captured with the library EsyType already has.**
   - cpal records the speakers' output (WASAPI loopback) when an input stream is opened on an output device.
   - The probe ran it alongside the microphone, both at 48 kHz.
   - Windows sends no system audio while nothing is playing, so timing must come from the clock.
   - Still to prove on day one of Phase 8: that real meeting sound comes through. The probe's quiet tone arrived as digital silence, probably because the output was muted.
4. **Meeting detection needs no new library.**
   - Windows records which program is using the microphone right now; this is the same signal as the taskbar microphone icon.
   - "Teams is using the microphone" is a far better sign of a meeting than "Teams is open". Teams was open on this PC during the audit, but not using the microphone.
5. **Speaker names need care.**
   - Without a new AI model, EsyMeet can label **"You"** (your microphone) and **"Others"** (system audio), and let you rename them.
   - "Speaker 1, Speaker 2" among the other participants needs a speaker-recognition model, which is a new AI model. **Deferred, needs your approval**, as the brief asks.
6. **Insights needs one small database addition.** History can be switched off or trimmed after 30 days, so totals would shrink or vanish. A daily-totals table, with numbers only and no text, keeps them.
7. **Recommendation: start with Phase 6.1** (theme system: light, dark, follow Windows, and the font decision). Then run the engine study (8.0), which only uses test tools, so the riskiest question is answered before EsyMeet is built (section 6).

## 1. Deliverable 1: current state

### What exists (all in `src-tauri/src` and `src`)

| Area | What is there | Where |
|---|---|---|
| Speech engine | whisper.cpp through whisper-rs 0.16. One worker thread, one loaded model, one state, below-normal priority. Greedy, English, no context. Silero VAD as a gate (it skips silence but does not trim). Threads automatic (4 here) | `stt.rs`, `hardware.rs`, `models.rs` |
| Models | Tiny, Base, Small, SHA-256 checked, in `D:\EsyAI\EsyType\models` (confirmed) | `models.rs` |
| Audio | cpal, default or chosen microphone, channels averaged, box-filter to 16 kHz, level meter, microphone test | `audio.rs` |
| Insertion | paste with clipboard restore, typing fallback, wrong-window protection, caret checks, Undo for 60 s | `insert.rs`, `caret.rs`, `undo.rs` |
| Text | Clean (fillers, numbers, voice commands, capitals), Verbatim, Dictionary, 29 built-in product names, Snippets, per-app Styles | `clean.rs`, `dictionary.rs`, `vocabulary.rs`, `snippets.rs` |
| Data | SQLite, schema **v6**, forward-only migrations, WAL. Tables: `transcripts`, `dictionary`, `snippets`, `scratchpad_notes`. Backup and restore. Settings file with recovery from bad values | `history.rs`, `notes.rs`, `backup.rs`, `settings.rs` |
| Windows | tray, global shortcuts (hold, toggle, Esc, Undo, paste last), single instance, start with Windows, per-user NSIS installer (no admin, no downgrades, keeps data, optional delete) | `main.rs`, `installer-hooks.nsh` |
| UI | React, 8 pages (Dictation, History, Dictionary, Snippets, Style, Scratchpad, Settings, Setup), the recording pill, **dark only**, native Windows title bar, accessibility checks (keyboard, forced colours, zoom 200%) | `src/*.tsx`, `styles.css` |
| First run | 8 steps: welcome, privacy, model (with hardware check), download, microphone test, shortcut, try it, ready | `setup.tsx` |
| Tests | 63 unit tests, about 25 end-to-end suites in isolated windows, an accuracy benchmark (220 clips), a recording kit | `bench/` |

**Size:** about 7.2k lines of Rust, 2.2k of TypeScript and a 243-line stylesheet.

### What needs improvement for this brief

- **Typography.**
  - `--et-font-display` asks for Instrument Serif, then Georgia. Instrument Serif is not installed or bundled, so **everyone sees Georgia italic**: the look you like.
  - The interface font asks for Barlow, which is also not bundled, so it falls back to **Segoe UI**.
  - Decision needed (section 4.1).
- **Themes:** dark only (`color-scheme: dark`, colours fixed in `:root`). Light mode means a second set of colour tokens and checking every page.
- **Window:** the standard Windows frame. Windows 11 already rounds its corners; the inside panels are rounded (16 px).
- **Navigation:** the 7-item sidebar has no room yet for EsyMeet or Insights; Settings is at the bottom.
- **Engine:** one worker, so a meeting and a dictation would queue behind each other. No priority and no cancelling.
- **Audio:** microphone only. No system audio, and no continuous capture beyond one dictation.
- **Database:** no meetings tables, and no totals that survive History settings.
- **Onboarding:** no name, no theme choice, nothing about meetings.

## 2. Deliverable 2: proposed architecture

```
                         ┌──────────── EsyType app (one process) ─────────────┐
 Microphone ──cpal──►  Capture A ─┐                                            │
 Speakers ─cpal loopback► Capture B ─┤ native rate → 16 kHz, clock timestamps   │
                                  ▼                                            │
                      Segmenter (Silero VAD per source)                        │
                         cut at pauses: 1.5–12 s; forced cut 15 s, 1 s overlap │
                                  ▼                                            │
 Dictation (hotkey) ─► Speech scheduler: one model in memory, two states       │
                         priority 1 dictation · priority 2 meeting segments    │
                         a meeting segment in progress is cancelled and        │
                         re-queued when you dictate                            │
                                  ▼                         ▼                  │
                       insertion (unchanged)        transcript stitcher        │
                                                    (dedupe overlaps, You/Others,│
                                                     echo check)               │
                                                            ▼                  │
                                          SQLite v7: meetings, meeting_segments │
                                          (+ daily_usage for Insights)         │
                                                            ▼                  │
                                    EsyMeet live view · Meeting history · Insights
 Meeting detector: polls Windows' "microphone in use" record every 2–3 s ─► prompt (never records by itself)
```

### EsyType (dictation)
**Unchanged** except for the scheduler:
- Dictation jumps any queue.
- A meeting segment being transcribed is cancelled (whisper.cpp has an abort callback) and done again afterwards.
- So a meeting never makes dictation wait for more than about a quarter of a second. **To be measured in 9.1.**

### EsyMeet
1. **Detection:** Windows keeps, for each program, the time it last started and stopped using the microphone. "Stopped = 0" means it is using it now.
   - EsyType checks every 2–3 seconds for Teams, Zoom, Webex, Slack and browsers, and **never counts itself**.
   - It shows the prompt once per call. "Not now" stays quiet until that call ends; "Never for this app" is in Settings.
   - **Nothing is captured until you press Start.**
2. **Capture:**
   - two cpal streams (your microphone; the default speakers in loopback), each at its own rate, converted to 16 kHz
   - timestamps from one clock, because loopback sends nothing during silence
   - a new default device (for example, headphones plugged in) re-opens the stream
   - a disconnected microphone is shown, and the meeting continues on system audio
3. **Segments:**
   - Silero (already bundled) finds speech in each stream, and a segment ends at a natural pause, so words are rarely split.
   - Only when someone talks without pausing is a segment cut at 15 seconds with a 1-second overlap. The stitcher then removes the repeated words.
   - **Nothing is ever transcribed twice, and the meeting as a whole is never re-transcribed.**
4. **Live view:**
   - Segments appear as they finish, usually 2–6 seconds after speech **if the engine study succeeds** (section 3.1).
   - A "keeping up" indicator shows the queue: green when up to date; amber when more than 15 seconds behind.
5. **Saving:**
   - Each finished segment is written to SQLite at once.
   - Audio waiting to be transcribed sits in a temporary file. It is deleted when its text is saved, and kept if something fails.
   - If EsyType closes mid-meeting, the next start finishes the leftover audio and marks the meeting "interrupted". No speech is lost silently.
   - **No audio is kept by default.**
6. **Stop:** only the unfinished segment is transcribed. The meeting is saved with its title (the app name and date, editable), duration and timestamps.

**You and Others:**
- Microphone segments are labelled "You", system-audio segments "Others". You can rename them.
- **Echo:** without headphones your microphone also hears the other people. A microphone segment that follows the system audio closely in time is treated as echo and dropped.
  - Measured with test recordings in 9.3. The interface recommends headphones.

### Insights
- **New `daily_usage` table:** per day, words, speaking time, dictations, meetings and meeting minutes. Numbers only, no text.
  - Filled from now on, and once from existing History.
  - Kept when History is off or trimmed; a setting turns it off.
- **App categories** (AI assistants, email, documents, chat) come from program names only, as History already stores them, **never window titles**.

### Profile and theme
- New settings: `user_name`, `display_name`, `theme` (`system` | `dark` | `light`).
- Stored in the settings file, not the database. Existing settings files are read unchanged; the new fields take defaults.

### Kept modular for later
- **Meeting summaries** (Copy for AI only, no model):
  - only copies text to the clipboard, so a later local-AI step can plug into the same meeting record
  - no AI code is written now
- **Speaker separation:** needs a model, so it is a separate approval.

## 3. Deliverable 3: technical risks

### 3.1 Measured on this PC (battery; mains is faster)

| Engine, 4 threads | 5-s piece | 10-s piece | Peak memory |
|---|---|---|---|
| Base, normal 30-s window | 2.55 s | 2.61 s | 261 MB |
| Base, 2 threads | 5.41 s | 5.15 s | 261 MB |
| Small, normal window | 8.42 s | 8.91 s | 500 MB |
| Tiny, normal window | 1.24 s | | |
| **Base, short window** | **0.40 s** | **0.82 s** | |
| Tiny, short window | 0.19 s | 0.39 s | |

**Short window accuracy** (Base, 220 synthetic clips plus 10 LibriSpeech):

| Group | Normal window | Short window |
|---|---|---|
| Ordinary sentences | 0.8% errors | 19.2% |
| Mixed sentences | 1.5% | 63.7% |
| Product sentences | 12.5% | 18.3% |
| LibriSpeech | 3.5% | 3.7% |

Almost all of the extra errors are **whole sentences repeated** (15 clips).

**What this means:**
- **Normal window:** live transcription works only with longer segments (8–15 s) and Base or Tiny, giving **10–20 seconds** from speech to text, not 2–6. Small is out for live use on this laptop.
- **Short window, if the repeats are fixed:** 2–6 seconds is realistic, with both streams using under 20% of the processor.
- **Candidate fixes, each measured with the same benchmark:**
  - one segment per piece
  - no timestamps
  - a token limit
  - a larger window margin
  - dropping a repeated last sentence
- **If none works,** EsyMeet still ships with the 10–20 second delay, stated honestly. **This is study 8.0, bench-only.**

### 3.2 Risk register

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Engine can't keep up (two streams) | High without the short window / high | 8.0 study first; transcribe speech only (people rarely talk over each other); Base or Tiny for meetings; "keeping up" indicator; on battery, warn and lengthen segments |
| Dictation slowed during a meeting | Medium / high (core feature) | priority queue + cancelling the in-flight meeting segment; a second engine state (no second model in memory); dictation-time regression check with a meeting running, idle and half load |
| Memory | Low / medium | one model shared by two states. Expected about +60–100 MB over today, to be measured. Small not offered for meetings |
| Loopback gives no data in silence | Certain (measured) / low | clock timestamps; gaps are silence |
| Loopback content | Not yet proven / high | first task of Phase 8: a real call or video, with audible volume |
| Buffer overruns with two streams | Seen in the probe (5 messages in 5 s) / medium | larger buffers; count and log gaps; never drop already-captured audio |
| Device changes (headphones, Bluetooth, docking) | High / medium | re-open on default-device change; show it in the live view; keep the meeting going on the other stream |
| Your voice twice (echo) | High without headphones / medium | timing-correlation echo check (9.3); headphones hint; never present echo as a second person |
| Speaker identity | Certain / medium | "You" and "Others" only; renaming; no invented names; speaker separation deferred (needs a model) |
| Boundary words | Medium / medium | cut at pauses; overlap only on forced cuts; word-level dedupe tested with synthetic long talks |
| Crash mid-meeting | Low / high | each segment saved at once; temporary audio until saved; recovery at next start |
| Detection false prompts | Medium / low | only microphone-in-use by known apps; once per call; "Never for this app". Browsers: Chrome using the microphone could be Meet or any site. Options: prompt anyway ("Chrome is using your microphone"), **or** check the tab title in memory only, never stored. **Your decision**; the brief says no window titles |
| Detection depends on an undocumented Windows record | Low / medium | fall back to "app running + audio session active"; manual Start always available (tray and EsyMeet page) |
| Consent | n/a | reminder on the prompt and the first meeting; visible recording indicator; the tray icon changes |
| Custom window frame | Medium / medium | keep the native frame (rounded on Windows 11, Snap Layouts, accessibility for free) with a dark or light title bar; frameless only if you still want it after seeing 6.2 |
| Light theme regressions | Medium / low | colour tokens only; forced-colours and zoom suites rerun in both themes; screenshots of every page in both |
| Battery slowdown | Certain / medium | this audit's timings were taken on battery; 8.0 measures mains against battery. Warn in the live view; never drop audio |

## 4. Deliverable 4: UI/UX proposal

**Mockups:** the published page "EsyType next generation" shows the sidebar, Dictation, EsyMeet (live and history), Insights, the meeting prompt and onboarding, in dark and light (switch at the top). They are drawings for discussion, not screenshots of built screens.

### 4.1 Typography (decided: Georgia italic)

| Option | What you get | Cost |
|---|---|---|
| **A. Keep Georgia italic** (recommended) | Exactly today's logo and headings, which you said you like. Georgia is on every Windows PC | Nothing to download |
| B. Bundle Instrument Serif (as designed) | A narrower, more fashionable serif; the look changes | A font download (about 70 KB, open licence); needs your approval |
| UI text | Segoe UI Variable (Windows' own) for navigation, buttons and forms: clean and readable, and already what you see | none |

### 4.2 Sidebar

```
EsyType.                      (serif italic wordmark)
─────────────
● Dictation
● EsyMeet          (live dot while a meeting records)
● Insights
─────────────
  History
  Dictionary
  Snippets
  Style
  Scratchpad
─────────────
  Settings
  [Local · Base · 4 threads]   (status chip, as now)
```

- The three main experiences are on top, tools below, and nothing is removed.
- Light icons; the selected item is a filled rounded pill (not today's outlined box).

### 4.3 Screens (see mockups)

- **Dictation:**
  - big serif heading "Hold Ctrl+Space, speak, release."
  - this week's numbers in a slim strip (words, time saved) linking to Insights
  - Try it
  - last dictation
- **EsyMeet:**
  - empty state "No meetings yet", with a Start button and a privacy note
  - **during a meeting:**
    - red recording dot and timer
    - two activity meters (You, Others)
    - "Keeping up" chip
    - live transcript with "You" and "Others" labels and timestamps
    - Pause, Stop
  - **history:** a searchable list; each meeting opens to its transcript with Copy, Copy for AI and Export
- **Meeting prompt:**
  - a small rounded card at the top of the screen: "Meeting detected · Zoom", with **Start EsyMeet transcription**, **Not now**, and a note to tell participants you are transcribing
  - it never steals keyboard focus
- **Insights:**
  - four number cards: words dictated, average words per minute, time saved (with "how this is worked out"), meetings transcribed
  - activity calendar
  - weekly chart
  - apps by category
  - all from local data, with an empty state that never shows invented numbers
- **Onboarding:** two new steps:
  - "What should EsyType call you?" (name, display name, why it's asked)
  - "Light or dark?" (System, Dark, Light, with a live preview)
  - the privacy step gains one line about meetings

### 4.4 Frosted glass (owner's addition, 22 Nov)

"Liquid glass or frosted glass in the pop-ups and in the app wherever it fits". How it maps onto Windows:

| Where | How | Fallback |
|---|---|---|
| **Main window** | Windows 11 **Mica** behind the window (Tauri `windowEffects`, with a transparent webview background). It tints the window softly from the wallpaper and is cheap: Windows draws it once, not every frame | Windows 10 and older Windows 11 builds: today's solid background |
| **Panels and cards** | Frosted glass in CSS: a translucent tint, blur and saturation of what is behind, a bright 1 px top edge and a soft sheen. Text always sits on a tint of at least about 70%, so contrast stays AA on any wallpaper | Solid panels |
| **Recording pill** | Two options, built and screenshotted on your desktop in 6.3 before one is kept: **A.** Windows **Acrylic** (real blur of what's behind), but Windows only draws it in a rectangle with slightly rounded corners. **B.** Today's capsule shape with the glass tint, edge and sheen, but no blur of what's behind. Tauri's corner-radius option is macOS-only | Solid dark pill, as now |
| **Meeting prompt** (8.2) | As the pill (Acrylic in a rounded rectangle) | Solid card |

**Rules:**
- **Windows' Transparency effects switch:** glass follows it (Settings > Personalisation > Colours). When it is off, everything is solid. Windows also turns it off in battery saver.
- **High contrast** (forced colours): always solid, with system colours, as now.
- **Measured in each milestone:** idle CPU and GPU with the window open, scrolling smoothness, and dictation time (must stay as today: idle 2.0–2.1 s, half load 3.3 s).
- **Acrylic during window dragging:** it is known to lag on some Windows builds, so it is used only on the pill and prompt. They are never dragged.

### 4.5 Themes
- Dark (today's, refined): near-black background, glass panels, violet accent.
- Light: warm white, ink text, the same violet. Every colour comes from tokens, and both themes are checked for contrast (WCAG AA).
- "Follow Windows" is the default; the choice is saved and works after restart.

## 5. Deliverable 5: roadmap (small milestones, each approved separately)

| # | Milestone | Objective | Files | Database | Performance | Acceptance | Risks |
|---|---|---|---|---|---|---|---|
| **6.1** (done in test build, 23 Nov; `docs/testing/2026-11-23-themes.md`) | Theme system, typography and glass materials | Dark, Light, Follow Windows; saved; Georgia kept; every colour as a token; glass tokens (tint, edge, blur) with solid fallback when Windows' Transparency effects are off or in high contrast | `styles.css`, `settings.rs/.tsx`, `main.tsx`, `tauri.conf.json` (title bar) | none (settings: `theme`) | none | every page in both themes; AA contrast; forced colours and zoom suites pass in both; theme kept after restart; full regression | missed colours |
| **6.2** | Shell: new sidebar and window | Sidebar grouping, EsyMeet and Insights placeholders, refined cards and buttons, title bar matching the theme, **Mica** behind the window (Windows 11) | `main.tsx`, `ui.tsx`, `styles.css` | none | none | navigation suite updated and passing; all pages reachable; keyboard order; screenshots | navigation tests need updating |
| **6.3** | Dictation screen and glass pill | Heading, weekly strip, Try it, last dictation; the recording pill in glass, with options A and B (4.4) screenshotted on your desktop and one chosen by you | `main.tsx`, `styles.css` | none | none | Try-it and polish suites pass | small |
| **7.1** | Profile and onboarding | Name, display name, theme step, meeting privacy line; existing users are asked once, can skip, and it can be edited in Settings | `setup.tsx`, `settings.rs/.tsx` | none (settings) | none | first-run suite extended; existing settings untouched (byte-compared) | none significant |
| **8.0** | Engine study (bench only) | Fix or rule out the short-window repeats; measure dictation and meeting timing on mains, battery, idle and half load | `bench/stt-bench`, `bench/accuracy` | none | measurement only | a setting is accepted only if ordinary English is no worse than 0.8% and LibriSpeech no worse than 3.5%, on the synthetic set **and your recordings** | may find no fix (then 10–20 s delay) |
| **8.1** | Dual capture | Microphone + loopback, clock timestamps, device changes, temporary audio; a debug view in the test build only | `audio.rs` (new capture session), `main.rs` | none | +1 audio thread; about 2% CPU (to measure) | 60-minute capture with a video playing: no gaps beyond logged overruns; headphones plug and unplug; microphone unplugged; dictation unaffected (timing suite) | loopback content, Bluetooth |
| **8.2** | Meeting detection and prompt | Microphone-in-use watcher, prompt card, Not now, Never for this app, consent note | new `meeting_detect.rs`, prompt window like the pill | none | a registry read every 2–3 s (negligible) | Teams, Zoom, Chrome Meet test calls; never prompts for EsyType itself; never records without Start | browser decision (section 3.2) |
| **8.3** | Recording session (no text yet) | Start, Pause, Resume, Stop, timer, meters, tray state, recovery of unsaved audio | `main.rs`, new `meeting.rs`, EsyMeet page | **v7:** `meetings` (id, title, app, started_at, ended_at, duration_ms, status, created_at) | as 8.1 | kill the process mid-meeting → next start recovers; pause stops capture | none new |
| **9.1** | Segmenter and scheduler | VAD segments per source, the priority queue, cancelling, second engine state | `stt.rs`, new `segmenter.rs` | none | **measured:** dictation time with a meeting running stays within 10% of today's (idle 2.0–2.1 s, half load 3.3 s) | timing suite with meeting load; long synthetic talks: no lost or doubled words at boundaries | engine study result |
| **9.2** | Live transcript and saving | Live view, keeping-up indicator, each segment saved at once | `meeting.rs`, EsyMeet page | **v8:** `meeting_segments` (meeting_id, source, start_ms, end_ms, text, speaker_label) | as 9.1 | text visible within the measured delay; crash test loses nothing; a 60-minute meeting is not re-transcribed at Stop | none new |
| **9.3** | You, Others and echo | Labels, renaming, echo check | `meeting.rs` | none | small | test recordings with and without headphones: echo found, none of your own lines dropped wrongly | false echo calls |
| **10** | Meeting history | List, search, transcript view, Copy, Copy for AI, export (TXT, Markdown, JSON), delete, retention | new page, `meeting.rs` | full-text index (bundled SQLite, to confirm) | none | search, copy, export round-trip; delete really deletes; History is not mixed with meetings | none |
| **11.1** | Usage totals | `daily_usage` filled live and once from History; setting to turn it off | `history.rs`, `main.rs` | **v9:** `daily_usage` | none | totals equal History sums before trimming; survive History off or trim | privacy expectations |
| **11.2** | Insights page | Cards, calendar, weekly chart, app categories, meeting stats, "how time saved is worked out" | new page | none | none | numbers checked against seeded data; empty state honest | none |
| 12 | AI meeting intelligence | **Not started**; needs separate approval and a model decision | | | | | |

Every milestone:
- uses a separate test build and isolated test windows
- passes the full regression on a quiet PC
- adds a test record in `docs/testing`
- is released to your PC only with your approval, through the installer

## 6. Deliverable 6: recommendation

**Start with 6.1, the theme system and typography.**
- **Every new screen depends on it.** EsyMeet, Insights and onboarding would otherwise be built twice: dark-only now, then again for light.
- **Lowest risk to what works:** stylesheet and one setting, nothing near the engine, audio or insertion.
- **You see the result at once.** The font question is settled first, so nothing is built on the wrong typeface.

**Then, before any EsyMeet code, the engine study 8.0** (test tools only):
- It decides whether EsyMeet shows text after 2–6 seconds or after 10–20.
- If the short window can be fixed, it may also cut everyday dictation time.
- It works best with your recordings from the recording kit (15 minutes, still to do).

**Decided by you, 22 Nov:**
1. **Georgia italic** stays the brand serif (nothing downloaded).
2. **Native window frame**, with Mica behind it.
3. **Frosted glass** in the window, panels, pill and meeting prompt (section 4.4), solid when Windows' Transparency effects are off.
4. **Usage totals are kept** when History is off (numbers only; a setting turns them off).
5. **6.1 approved**, then the rest of the roadmap as proposed.

**Still open, decided when needed:**
- the pill's shape (A or B, with screenshots in 6.3)
- how browser meetings are detected (8.2)

**Nothing has been implemented; production is unchanged.**
