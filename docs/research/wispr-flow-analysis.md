# Wispr Flow product analysis

**Subject:** Wispr Flow for Windows, version 1.6.1483 as installed on the development PC
**Researched:** 15 November 2026
**Purpose:** understand the workflow and feature set that EsyType competes with, so EsyType can implement its own versions independently and improve on them

---

## 1. Scope and method

### What was examined

| Source | How | Label used below |
|---|---|---|
| Public marketing site `wisprflow.ai` (home, pricing) | REA `inspect-web-page` with accessibility text (`ev_b7da5dc6…`), plus a plain page read | **Site** |
| Public help centre `docs.wisprflow.ai` (22 articles, listed in section 10) | Fetched as ordinary public web pages | **Docs** |
| Installed app footprint | Folder names and sizes, process count and memory from Windows. No file contents were opened. | **Measured** |
| The sidebar list in the project brief | Taken from the brief, which describes the user's screenshot | **Brief** |

### What was deliberately not done

Per the project brief: no account data was accessed, nothing was decompiled, the application bundle was not unpacked, and no application code or assets were read or copied. Runtime identification below rests only on the names of files that sit in the install folder.

### What is still missing

**The screenshots mentioned in the brief were not attached to the conversation.** Everything visual about the signed-in desktop window (exact layout, colours, spacing, the recording pill's appearance) is therefore not described here. Section 9 lists what the screenshots are needed for. Nothing in EsyType's design depends on copying those visuals, so this does not block the architecture.

### Reading the labels

- **Observed** means stated by Wispr's own public pages or measured on this PC.
- **Assumption** means my inference; each is marked.
- Latency and accuracy were not tested. No performance claim about Wispr Flow is made here.

---

## 2. Product summary

**Observed (Site, Docs)**

- A voice-to-text product "that turns speech into clear, polished writing in every app", plus a meeting Notetaker in the same app. Platforms: Mac, Windows, iPhone, Android.
- **Audio is processed in the cloud.** The security overview states: "Wispr Flow processes dictated audio in the cloud to turn speech into text."
- **An account is required.** Setup begins with "Sign in via browser" (Google, Apple, Microsoft, SSO, or email and password).
- **Pricing:** Free with "limited words per week"; Pro at $15 per user per month ($12 billed annually) for unlimited dictation; Growth at $23 ($18 annually); Enterprise custom.
- **Data defaults:** "Improve the model for everyone" and "Dictation cloud storage" are both on by default for Free and Pro. Even with model improvement off, the docs state that Flow "still uploads dictation details such as word count, duration, app, URL, timestamp, app version, microphone, detected language and edit statistics."
- **Requirements (Windows dictation):** Windows 10 or 11, x64, 8 GB RAM recommended, "about 200 MB free". Virtual machines and remote desktop environments are listed as not supported.

**Measured on this PC**

| Measure | Value |
|---|---|
| Install folder | 920 MB total: 598 MB application folder, 319 MB cached update packages |
| User data folder | 106 MB |
| Running processes | 12 (11 main, 1 helper) |
| Memory while running | about 1,185 MB working set, about 800 MB private |
| Runtime | Chromium/Electron-style layout with a Squirrel updater (judged from file names such as `resources.pak`, `v8_context_snapshot.bin`, `libGLESv2.dll`, `Update.exe`) |

These four facts define EsyType's opening: **cloud processing, mandatory account, weekly word cap on the free tier, and a heavy footprint.** EsyType's brief is the inverse on every one.

---

## 3. Feature-by-feature analysis

Each feature has the same five parts: what the user sees, how it behaves, the workflow, what EsyType implements independently, and how EsyType improves on it.

### 3.1 Application structure

- **Sees.** A tray icon, a main window called the Hub, and a small floating Flow Bar that sits over other apps. (Docs)
- **Behaves.** The Hub holds history, personalisation, settings and help. Dictation itself happens through the Flow Bar and shortcuts while another app has focus. The tray icon menu offers Open Wispr Flow, Shortcuts, Help centre and Talk to support. (Docs)
- **Workflow.** Launch at login → lives in the tray → user dictates anywhere → opens the Hub occasionally to manage words, snippets and settings.
- **EsyType implements.** The same three surfaces because they are the natural shape of the problem: tray, main window, floating recording widget.
- **EsyType improves.** One lightweight native shell instead of a browser runtime with 12 processes. Target to verify by measurement: install under 30 MB before models, idle memory under 100 MB with the speech model unloaded. These are targets, not results.

### 3.2 Sidebar navigation

- **Sees.** A left sidebar. The brief lists: Dictation, Notetaker, Insights, Dictionary, Snippets, Style, Transforms, Scratchpad, Settings, Help. (Brief) The docs confirm Home, Meetings, Insights, Dictionary, Snippets, Style, Transforms and Scratchpad pages, with Settings and Help at the bottom. (Docs)
- **Behaves.** Some entries depend on plan and organisation policy (Meetings needs Notetaker access; Scratchpad can be disabled by an organisation). (Docs)
- **EsyType implements.** The ten entries required by the brief, in that order.
- **EsyType improves.** No entry is ever locked behind a plan or sign-in. An entry whose capability is not installed (for example Transforms without the optional language model) stays visible and explains what to install, rather than disappearing.

### 3.3 Dictation workflow

- **Sees.** The user clicks into a text field in any app, holds a shortcut, speaks, and releases. Formatted text appears in the focused field. (Docs)
- **Behaves.** (Docs)
  - Two modes: **Push to talk** (hold) and **Hands-free** (press once to start, again to stop, or double-tap the push-to-talk key within half a second).
  - A tap shorter than half a second does not paste; Flow cancels shortly after. Pressing another app shortcut within one second of starting also cancels.
  - A start sound plays once the microphone is actually recording.
  - Sessions warn at 19 minutes and stop at 20, transcribing what was captured.
  - Esc cancels. A cancellation notice offers Undo.
  - Text goes to "the field that is focused at that moment", meaning focus at the time of insertion.
- **EsyType implements.** Hold-to-talk and toggle modes, an accidental-tap guard, an audible and visible "recording has really started" cue, cancel, and a long-session cap sized to local memory rather than a fixed 20 minutes.
- **EsyType improves.**
  1. **Wrong-window protection.** EsyType records which window and control had focus when recording started. If focus has moved to a different application by the time text is ready, it does not paste blindly; it shows the text with "Insert here" and "Copy". This is a hard requirement in the brief ("never silently insert text into the wrong application").
  2. **Works offline**, including on a plane or behind a corporate firewall.
  3. **No word cap.**

### 3.4 Floating recording interface (the Flow Bar)

- **Sees.** "A small floating bubble showing your dictation status: resting, recording, or processing." (Docs)
- **Behaves.** (Docs)
  - Shown at all times by default; can be hidden for an hour or turned off in Settings → System.
  - Draggable. While dragging, an overlay shows bottom, left and right drop zones and the bar snaps to the chosen screen edge. Default is bottom.
  - Follows the display the cursor is on, not the focused window.
  - Clicking it starts hands-free dictation. In hands-free mode it shows a stop control; on Windows "✓ finishes dictation and X cancels".
  - Plain push-to-talk shows no stop or cancel button.
  - Includes a language picker.
- **EsyType implements.** The pill defined in the brief: Cancel on the left, animated waveform in the centre, Stop on the right, with Ready, Recording, Processing, Inserting and Error states, a duration readout, and free dragging.
- **EsyType improves.**
  1. **Hidden when idle by default.** The brief asks for minimal screen space and for the widget to disappear after insertion. An always-visible bubble is an option, not the default.
  2. **Buttons in both modes.** Cancel and Stop are always present, so a user who forgets the shortcut can still finish with the mouse.
  3. **Free placement that is remembered per monitor**, instead of three edge docks.
  4. **A waveform drawn from real microphone level** in the ESYAI fluted-bar style (see the brand analysis), so the widget also proves the right microphone is live.
  5. **Visible progress during transcription** with elapsed time, since local inference time varies with hardware.

### 3.5 Global shortcuts

- **Observed defaults on Windows.** (Docs)

| Action | Wispr Flow default |
|---|---|
| Push to talk | Ctrl + Win (some first-time Windows users are given Caps Lock) |
| Hands-free | Ctrl + Win + Space, or double-tap push to talk |
| Cancel | Esc |
| Paste last transcript | Alt + Shift + Z |
| Command Mode | Ctrl + Win + Alt |
| Transform: Polish | Win + Alt + 1 |
| Transform: Prompt Engineer | Win + Alt + 2 |
| Transform: view changes | Win + Alt + O |

- **Behaves.** Up to four bindings per action; mouse buttons can be bound; a modifier on its own is an accepted binding; changes apply immediately; bindings are per device. (Docs)
- **EsyType implements.** The brief's defaults (Ctrl + Space push to talk, Ctrl + Shift + Space toggle), rebinding, conflict detection, Esc to cancel, and a "paste last transcript" shortcut.
- **EsyType improves and one caution.**
  - **Caution on the brief's default.** Ctrl + Space is already used by Windows for switching input method on systems with more than one keyboard language, and by VS Code, Visual Studio and JetBrains IDEs for code completion. A global hook on it would break those. The architecture document proposes how to handle this (detect the conflict at first run and offer an alternative such as Ctrl + Win-style modifier-only chords or Right Alt). The final default is the user's decision.
  - Because Wispr Flow is installed on the development PC and holds Ctrl + Win, EsyType must not default to that chord.
  - EsyType will tell the user when a chosen shortcut cannot be registered, rather than accepting it silently.

### 3.6 Microphone management

- **Sees.** Settings → General → Microphone → Change, with a device list, an Auto-detect option and a live level meter. (Docs)
- **Behaves.** Recommends built-in or wired microphones over Bluetooth. Setup includes a "Test your microphone" step with "No microphone found" and "In use by another app" states. (Docs)
- **EsyType implements.** Device enumeration, default-device following, a live level meter, a test recording with playback, and hot-plug handling.
- **EsyType improves.** Shows the capture format in plain terms and warns specifically when a Bluetooth headset has dropped to its low-quality hands-free profile, which is the usual cause of poor recognition on Bluetooth. (Assumption about cause; to be verified in testing.)

### 3.7 Transcription processing

- **Observed.** Cloud processing. 100+ languages, with one language detected per dictation rather than per word. Users pick the languages they speak to narrow detection. (Docs)
- **Observed clean-up pipeline.** (Docs)
  - **Auto Cleanup** levels: None ("pastes exactly what you said, including mistakes"), Light (default: "cleans up filler words and grammar"), Medium ("edits for clarity and conciseness").
  - **Smart Formatting:** punctuation, capitalisation, spoken lists ("one… two…") turned into real lists.
  - **Backtrack:** self-corrections such as "at 2, actually 3" are resolved to "at 3".
  - **Context Awareness** (on by default): "reads text near your cursor" and classifies the active app or website, and "uses names and context visible on screen, such as email recipients".
- **EsyType implements.** Three modes that map closely: Verbatim, Clean, and AI Enhanced. Clean covers punctuation, capitalisation, filler removal, number formatting, spoken lists and a rule-based version of backtrack. AI Enhanced uses the optional local language model.
- **EsyType improves.**
  1. **Everything runs on the device.** No audio, text or context leaves the PC.
  2. **Clean mode needs no language model**, so it works on 4 GB and 8 GB machines.
  3. **Review before insertion for AI Enhanced**, as the brief requires, with the verbatim text one click away. Wispr's own docs carry a warning that rewrites can alter links and list formatting; a local small model will make more mistakes than a cloud one, so review is essential rather than optional.
  4. **No screen reading by default.** EsyType uses only the foreground process name and window title to choose a style. Reading surrounding text is a separate, clearly labelled opt-in.
- **Honest gap.** A cloud model will usually beat a small local Whisper model on accuracy, on accents and on mixed-language speech. EsyType's answer is speed, privacy, a personal dictionary and no limits, not a claim of equal accuracy. This must be measured, not asserted.

### 3.8 Automatic text insertion

- **Observed.** Text is pasted into the focused field. On Mac the docs describe paste-and-restore of the clipboard, with the transcript able to remain on the clipboard for "up to about 7 seconds" in slower apps. A "Paste Last Transcript" shortcut re-pastes after a failure. Special notes exist for Outlook, IDEs, terminals, remote desktops, notification reply boxes and browser address bars, which signals that insertion varies by target. (Docs)
- **Assumption.** The Windows build also uses clipboard paste as its main route. Not verified.
- **EsyType implements.** Its own insertion engine with an ordered strategy: clipboard paste with full clipboard save and restore as the default, simulated Unicode typing as the fallback for targets that reject paste, and a copy-to-clipboard notice when both fail.
- **EsyType improves.** Target verification before pasting (3.3), restoring every clipboard format it can rather than text only, an insertion log the user can read, and a per-application override for stubborn apps.

### 3.9 Transcription history

- **Sees.** Home shows transcript history grouped by date, with search; hovering an entry reveals copy and flag. (Docs)
- **Behaves.** "Dictation history is stored on the device where you dictated, and deletion is permanent." Cloud copies may also exist when cloud storage is on. (Docs)
- **EsyType implements.** Local history with search, copy, edit, delete, timestamps and clear all.
- **EsyType improves.** History exists only on the device, can be switched off entirely, can auto-expire after a chosen number of days, and stores both the verbatim and final text so a bad clean-up is always recoverable. Audio is not kept unless the user turns that on.

### 3.10 Writing styles

- **Sees.** A Style page with a card per app category. (Docs)
- **Behaves.** Four categories chosen automatically from the target app: Personal messages, Work messages, Email, Other. Four styles: Formal ("caps + punctuation"), Casual ("caps + less punctuation"), very casual ("no caps + less punctuation"), Excited ("more exclamations"). Style also decides whether a final full stop is kept in messaging apps. English only. (Docs)
- **EsyType implements.** The brief's styles: Professional, Casual, Formal, Concise, Custom.
- **EsyType improves.** A manual per-application rule list the user can read and edit (for example "Slack → Casual"), instead of an opaque classifier. The punctuation-level effects are done by rules, so styles work without the language model; only tone rewriting needs it.

### 3.11 Personal dictionary

- **Sees.** A Dictionary page with Add new. (Docs)
- **Behaves.** Two entry types: a word or phrase to recognise, and a correction that replaces a recurring wrong spelling. 60 characters per field. Duplicates blocked. Import supported. The site says Flow also "learns your unique words and names automatically". Shared team dictionaries on paid plans. (Docs, Site)
- **EsyType implements.** Words, names, company and technical terms, corrections, add, edit, delete, import and export.
- **EsyType improves.**
  - Export as well as import, in plain CSV or JSON, because the data belongs to the user.
  - Dictionary terms are fed to the recogniser as a prompt hint and also applied as post-recognition corrections. How much the hint helps is a research question for the engine phase.
  - "Learn from my correction": when the user edits a history entry, EsyType offers to save the change as a correction. Nothing is learned silently.

### 3.12 Snippets

- **Sees.** A Snippets page: a spoken trigger and an expansion. (Docs)
- **Behaves.** Speaking the trigger inserts the expansion. Triggers up to 60 characters; expansions up to 4,000 characters including formatting; bulk import up to 1,000 items. Docs advise distinctive triggers such as "my email signature". (Docs)
- **EsyType implements.** Trigger and expansion pairs matched against the transcript after recognition, with import and export.
- **EsyType improves.** Placeholders such as today's date and clipboard contents, and an explicit choice of whether a trigger must be the whole utterance or may appear inside a sentence, which avoids accidental expansion.

### 3.13 Text transformations

- **Sees.** A Transforms page with cards for Polish and Prompt Engineer, and room for eight custom prompts. A second feature, Command Mode, takes a spoken instruction about selected text. (Docs)
- **Behaves.** Select 1 to 3,000 words in any app and press the transform shortcut; the rewrite replaces the selection. Afterwards the Flow Bar offers See changes, Retry, Undo, Copy and a rating. If auto-paste is off the result opens in Scratchpad. Command Mode is off by default, paid, and can also run a web search. (Docs)
- **EsyType implements.** The brief's six transforms (Rewrite, Summarise, Improve grammar, Make professional, Convert to email, Make concise) plus custom prompts, all on the optional local model.
- **EsyType improves.** A side-by-side before-and-after review is the default, not an afterthought, and the original is never overwritten until the user accepts. No web search and no network access.
- **Honest gap.** A 0.5B to 1.5B local model cannot match a large cloud model on long or subtle rewrites. Transform length limits and expectations must be set from benchmarks, and the feature must be labelled optional.

### 3.14 Insights and statistics

- **Sees.** An Insights page whose default tab is "Your usage". (Docs)
- **Behaves.** Tiles: words per minute, fixes made, total words dictated, desktop usage by category (personal messages, work messages, emails, AI prompts, documents, other) and by app, and an activity heatmap with current and longest streaks. Speed uses speech duration excluding silence when available. A "Top X%" ranking appears. (Docs)
- **EsyType implements.** Total words, average words per minute, daily and weekly usage, transcription count and history charts, all computed from the local database.
- **EsyType improves.** Adds numbers only a local product can show honestly: average transcription time on this machine and time saved versus typing. No rankings against other users, because there is no server to compare with.

### 3.15 Settings

- **Observed groups.** General (Shortcuts, Microphone, My languages), System (launch at login, Flow Bar visibility, notifications), Account, Plans and Billing, Data and Privacy (storage, export, delete), Experimental (Command Mode). (Docs)
- **EsyType implements.** General, Dictation, Models, Shortcuts, Microphone, Appearance, Data and Privacy, About.
- **EsyType improves.** No Account and no Billing pages at all. A Models page that Wispr cannot have: installed models, sizes, hardware fit, download, verify and delete. A Data and Privacy page that lists every network request the app can make.

### 3.16 Notetaker

- **Observed.** Records meetings on the device without a bot joining the call, identifies speakers, answers questions across meetings, and exposes notes to other AI tools. On Windows it requires 16 GB RAM and 2 GB free storage, and uses "roughly 300 MB per hour" while recording and uploading. (Site, Docs)
- **EsyType implements for the first release.** A sidebar entry and an honest Coming Soon page describing meeting recording, transcription, summaries, action items, speaker identification and searchable history. No working controls.
- **EsyType improves later.** Fully local meeting transcription. This needs system-audio capture, long-form segmentation and speaker diarisation, each a substantial piece of work; the architecture leaves room for it and no more.

### 3.17 Installation experience

- **Observed.** A downloaded installer; Flow launches from Start and places an icon in the system tray. A Squirrel-style updater keeps downloaded update packages on disk (319 MB on this PC). (Docs, Measured)
- **EsyType implements.** A signed Windows installer with Start menu and optional desktop shortcuts, a clean uninstaller that keeps user data unless asked, and model downloads handled inside the app's first-run wizard.
- **EsyType improves.** A small installer, models stored once in a user-chosen location (important on machines with a small system drive), and updates that never touch models or the database.

### 3.18 Onboarding

- **Observed sequence.** Install → sign in via browser → grant microphone access → answer setup questions and review the privacy notice → test microphone → set shortcut and choose Push to talk or Hands-free → choose languages → practice demos in a demo window → choose data preference → the Hub opens. Quitting mid-setup resumes later. (Docs)
- **EsyType implements.** The brief's six steps: Welcome, Hardware detection, Speech model, optional AI clean-up, Installation, Finish.
- **EsyType improves.** No sign-in step and no data-preference step, because there is nothing to consent to. Two ideas worth carrying over as concepts: a **microphone test** and a **practice dictation in a safe demo box** before the user tries it in a real app. Both fit inside the Finish step.

---

## 4. Feature comparison

| Capability | Wispr Flow (observed) | EsyType (planned) |
|---|---|---|
| Speech recognition | Cloud | Local, on the device |
| Works offline | No | Yes, after model download |
| Account | Required | None |
| Free-tier limit | Limited words per week | None |
| Price | Free tier; $12 to $15 per month for unlimited | To be decided by ESYAI; no usage metering is technically needed |
| Telemetry | Usage details uploaded even with model improvement off | None |
| Install size | 920 MB measured on this PC | Small shell plus chosen model (target; to be measured) |
| Memory while running | About 1.2 GB working set measured | Model-dependent (target; to be measured) |
| Push to talk and toggle | Yes | Yes |
| Floating widget | Always-on bubble, edge docks | On-demand pill, free placement |
| Cancel and stop buttons | Hands-free mode only | Always |
| Wrong-window protection | Pastes to whatever has focus | Verifies the original target first |
| Clean-up levels | None, Light, Medium | Verbatim, Clean, AI Enhanced |
| Review before insertion | After the fact (See changes, Undo) | Before insertion for AI Enhanced |
| Dictionary | Words and corrections, import, auto-learn | Words and corrections, import and export, learn on request |
| Snippets | Spoken trigger, 4,000-character expansion | Spoken trigger, placeholders, match-mode choice |
| Styles | Four styles by automatic app category | Five styles with user-editable per-app rules |
| Transforms | Polish, Prompt Engineer, eight custom, cloud | Six built-in plus custom, optional local model |
| Command Mode (spoken instruction) | Yes, paid | Not in first release |
| Screen context | Reads text near the cursor by default | Off by default; process and title only |
| History | Local, optional cloud copy | Local only, optional expiry |
| Insights | WPM, totals, heatmap, per-app, ranking | WPM, totals, daily and weekly, local speed stats |
| Scratchpad | Rich text, images, tabs, sync | Simple local writing area |
| Notetaker | Shipping | Coming Soon page only |
| Languages | 100+, automatic detection | Depends on chosen model (English-only or multilingual) |
| Mobile apps | iPhone and Android | None |
| Team features | Shared dictionary, admin, SSO | None in first release |

---

## 5. Where Wispr Flow is stronger

Stated plainly so the roadmap is realistic.

1. **Accuracy and language coverage** from large cloud models, including accents and switching languages between dictations.
2. **Rewrite quality** in Auto Cleanup, Transforms and Command Mode.
3. **Maturity of text insertion** across awkward targets, visible in the number of app-specific help articles.
4. **Cross-device sync and mobile keyboards.**
5. **Notetaker** is already shipping.
6. **Team and compliance features** for business buyers.

## 6. Where EsyType can win

1. **Privacy that is structural, not a setting.** There is no server, so there is nothing to opt out of.
2. **No account, no cap, no subscription meter.**
3. **Offline and firewall-friendly.** Wispr's docs list virtual machines and remote desktops as unsupported and devote an article to corporate network problems.
4. **Footprint.** A native shell against a 920 MB, 12-process install.
5. **Predictability.** Verbatim mode, review before insertion, wrong-window protection.
6. **Ownership.** Import and export for everything, plain local files.
7. **Brand.** A recording widget that is an animated form of the ESYAI mark.

---

## 7. Behaviours worth adopting as concepts

These are interaction ideas described in public documentation. EsyType implements each from scratch.

| Idea | Why it is good |
|---|---|
| Ignore taps shorter than about half a second | Prevents accidental empty dictations |
| Double-tap the push-to-talk key to lock hands-free | One shortcut covers both modes |
| Play the start cue only when the microphone is really capturing | Users stop losing their first word |
| "Paste last transcript" shortcut | Recovery when insertion fails |
| Undo offered on the cancel notice | Forgiving of mis-presses |
| Hard cap on session length that transcribes instead of discarding | No lost work |
| Corrections as a second dictionary entry type | Fixes recurring errors cheaply |
| Advise distinctive snippet triggers | Avoids accidental expansion |
| Microphone test and practice box in onboarding | First success happens in a safe place |
| Resume onboarding after quitting | Model downloads may be interrupted |

## 8. Behaviours EsyType deliberately does differently

| Wispr Flow behaviour | EsyType position |
|---|---|
| Sign-in before first use | No sign-in exists |
| Cloud storage and model-improvement switches on by default | No such switches; nothing is uploaded |
| Reads on-screen text for context by default | Off by default |
| Always-visible floating bubble | Hidden until recording |
| Pastes into whatever is focused when processing ends | Checks the original target |
| Weekly word limit on the free tier | No limits |
| Automatic vocabulary learning | Learns only when the user confirms |

---

## 9. What the user's screenshots are still needed for

When the screenshots are supplied, this document should be extended with:

1. The Hub's actual sidebar order, grouping and iconography.
2. The Home (dashboard) card layout: which statistics appear and where.
3. The recording pill's size, proportions and states on Windows.
4. Settings page density and control types.
5. Empty states for Dictionary, Snippets and Scratchpad.

These are layout references only. The brief's hierarchy applies: ESYAI supplies the visual identity, Wispr Flow supplies workflow inspiration, and EsyType's interface is original.

---

## 10. Sources

Public pages read on 15 November 2026.

- `wisprflow.ai` (home) and `wisprflow.ai/pricing`
- Help centre articles under `docs.wisprflow.ai/articles/`:
  - Set up Wispr Flow for your first dictation
  - Supported devices and system requirements
  - Starting your first dictation
  - Use Flow hands-free
  - Customize keyboard and mouse shortcuts
  - Connect and choose a microphone for Flow
  - Create and use snippets
  - Teach Flow your words with the dictionary
  - How to setup Flow Styles
  - How do I use Smart Formatting & Backtrack
  - Move and Dock the Flow Bar on Desktop
  - Snooze the Dictation Bubble
  - How to use Command Mode
  - Rewrite text with Transforms and custom prompts
  - Use and organize notes in Scratchpad
  - Navigating the Wispr Flow App: Desktop, iOS, and Android
  - Your Usage tab: Track your dictation stats in Wispr Flow
  - Context Awareness
  - Manage data sharing, cloud storage and local history
  - Security and privacy overview
  - Configure your network for Wispr Flow
  - Use Flow with multiple languages

Saved copies of these pages and the REA Evidence record are in `D:\AI Projects\Tools\rea-evidence\wisprflow\`, outside the app source.
