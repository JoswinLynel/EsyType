# EsyMeet 8.2: meeting detection and the "Start transcription?" prompt. Plan for approval

**Date:** 25 November 2026 · **Parent plan:** `docs/plans/next-generation-audit-and-plan.md`, milestone 8.2 · **Before it:** 8.0 (engine) and 8.1 (capture), both done outside the app
**Status:** proposed. Nothing is built until the owner approves the defaults in section 6.

## 1. What 8.2 does

When a meeting app or a browser starts using the microphone, EsyType shows a small prompt:

```
 ●  Meeting detected · Zoom            [ Start transcription ]  [ Not now ]
    Let people know you're transcribing.
```

- **It never records by itself.** Nothing is captured until Start is pressed.
- **It never takes the keyboard:** the caret stays in the meeting, like the pill.
- **It is quiet for everything else:** dictation apps, games, screen recorders and EsyType's own dictation never prompt.

## 2. How it knows a meeting started (measured on this PC, read-only)

**Windows' own record.** Windows keeps a record of microphone use for every app, the same one behind the taskbar's microphone icon. It is in the registry at `HKCU\…\CapabilityAccessManager\ConsentStore\microphone`.
- **Each app has two times:** when it last started and last stopped using the microphone.
- **"Stopped = 0" means "using it now".**
- **Desktop apps** are listed by their program path (`NonPackaged`); **Store apps**, such as the new Teams, by package name.

**On this PC the record lists, among others:**
- **Meeting-capable apps:** Zoom, Discord, Chrome, Edge, Brave.
- **Non-meeting apps:** Wispr Flow, OBS, Voice Access, a game, a sound tool.

**So the rule is an allow-list of meeting apps, not "any app using the microphone".**

**Watching:**
- **Notification:** a Windows notification on that registry key (`RegNotifyChangeKeyValue`) wakes EsyType the moment a value changes, with a 2-second check as a fallback.
- **Cost:** no polling cost while nothing happens; to be measured.

**Privacy:**
- **Read:** only program file names and those two times, from Windows' own record.
- **Never read:** window titles, meeting names or participants.
- **Stored:** nothing, except the apps the owner chooses to never prompt for.

**Precedent and risk:**
- **Precedent:** the record is how Windows' own privacy page shows "currently in use". Meeting-detection tools rely on the same keys.
- **Risk:** it is not a documented API. If Windows changes it, detection stops and nothing else breaks, so the prompt simply doesn't appear.

## 3. The rules

| Situation | What happens |
|---|---|
| An allow-listed app starts using the microphone and keeps it for **5 s** | Prompt: "Meeting detected · <app>" |
| The microphone is used for under 5 s (a sound check, voice search) | Nothing |
| **Not now** | Quiet for that app until it stops using the microphone (the call ends); the next call prompts again |
| No answer | The prompt fades after **30 s**. The tray menu shows "Start meeting transcription" while the call lasts |
| The call ends while the prompt shows | The prompt disappears |
| **Start transcription** | Starts the meeting session (8.3; see section 5) |
| Two meeting apps at once | One prompt, naming the first |
| EsyType's own dictation, or a dictation during a call | Never prompts. Dictation is unaffected |
| An app the owner chose "Never" for | Never prompts |
| Detection switched off in Settings | Never prompts |
| A meeting app EsyType doesn't know | No prompt. EsyMeet's page still has Start (from 8.3) |

**The allow-list (proposed):**
- **Meeting apps:** Microsoft Teams (new and classic), Zoom, Webex, Slack (huddles), Skype, GoTo Meeting, RingCentral.
- **Browsers** (Google Meet and other web meetings): Chrome, Edge, Firefox, Brave, Opera, Vivaldi.
- **Discord: off by default.** It is often gaming voice chat.

**What a browser prompt says:** it cannot name the website, because tabs aren't read. It says "Meeting detected · Chrome".

## 4. What it looks like

- **Shape and look:** a capsule like the recording pill, with the same light frost, dark in both themes.
- **Where:** at the **top centre** of the main screen, so it never covers the pill at the bottom.
- **Content:** a small EsyMeet icon, "Meeting detected · <app>", **Start transcription** (the main button) and **Not now**. Underneath: "Let people know you're transcribing."
- **Accessibility:**
  - announced to screen readers
  - every button at least 32 px
  - AA contrast
  - reduced motion: no slide-in
- **Settings, new section "Meetings":**
  - "Detect meetings" on/off
  - the allow-list as switches, Discord off by default
  - apps set to "Never", with Remove
  - a privacy line saying what is read and that nothing is recorded until Start

## 5. One question of order

Start needs a recording session to start, and that is milestone 8.3. Two ways:

- **A (recommended):** build and test 8.2 now in the test build, then build 8.3. **Release them together**, so the first prompt you see on your PC actually records when you press Start.
- **B:** release 8.2 alone. Start would open the EsyMeet page, which would say recording comes in the next update. That is a prompt that can't do anything yet.

## 6. Defaults for you to approve

| # | Decision | Proposed |
|---|---|---|
| 1 | Release 8.2 alone or with 8.3 | **With 8.3** (section 5) |
| 2 | "Detect meetings" on by default | **On**: it only reads which app uses the microphone, and never records by itself |
| 3 | Browsers prompt | **Yes** (you said browser meetings are fine) |
| 4 | Discord prompts | **Off by default** (can be switched on) |
| 5 | Microphone time before prompting | **5 s** |
| 6 | Prompt fades after | **30 s** (then the tray offers Start while the call lasts) |
| 7 | Where it appears | **Top centre** |
| 8 | Wording | "Meeting detected · <app>" · "Start transcription" · "Not now" · "Let people know you're transcribing." |

## 7. Files

**New:**
- `src-tauri/src/meeting_detect.rs`: reads the record, the allow-list, the decision rules (as pure functions), and the registry watcher.
- `prompt.html` and `src/prompt.tsx`: the prompt window, built like the pill's (never activated, transparent, capsule).

**Changed:**
- `main.rs`: start the watcher, the prompt window, tray entry and commands.
- `settings.rs` / `settings.tsx`: the Meetings section; new settings `meet_detect` (on), `meet_apps` (the switches) and `meet_never` (a list).
- `styles.css`.

**No database change.**

## 8. Tests

**Automated, in the test build, keys only into the tests' own windows:**

| Test | Checks |
|---|---|
| **Unit** | Reading the record from sample registry data: desktop and Store apps, "in use", times. The allow-list: known paths for Teams new and classic, Zoom, browsers; never EsyType; never Wispr Flow, OBS or a game. The rules: 5 s minimum, Not now until the call ends, Never, detection off, two apps at once, the call ending while prompting |
| **New suite `meeting-e2e.ps1`** | A small **test program of our own** uses the microphone. Only the test build counts it as a meeting app, through a test setting. It checks:<ul><li>the prompt appears within the time limit and names it</li><li>it does **not** take focus: text typed into the test's window keeps arriving there</li><li>Not now: no second prompt until the program stops and starts again</li><li>Never: no prompt, the app listed in Settings, Remove brings prompts back</li><li>detection off: no prompt</li><li>the same program not on the list: no prompt</li><li>a dictation during the "call": no prompt and the dictation types normally</li><li>the prompt fades after 30 s, and the tray shows Start while the program holds the microphone</li></ul> |
| **Theme, polish, forced colours** | The prompt and the Meetings section in both themes: AA contrast, 32 px targets, high contrast |
| **Full regression** | Every existing suite on an idle PC |
| **Dictation time** | A/B against 0.5.1, alternating blocks, with the watcher running |
| **Cost** | CPU of the watcher over 30 minutes, idle and with a call running |

**With you (needs a real call; a meeting app or a browser, both fine):**
- **One real call** each in a meeting app and in a browser (Google Meet or Teams on the web). Check:
  - the prompt appears and names the app
  - Not now holds for that call
  - nothing records
- **The microphone switch left over from 8.1:** during the call, set a headset or the earbuds' microphone as the default once. With 8.3, check that the capture follows it.

**Not tested automatically:** Teams, Zoom and Webex themselves (they would need accounts and real calls), and Windows 10 (no Windows 10 PC).

## 9. Risks

| Risk | Mitigation |
|---|---|
| Windows changes the record | Detection silently stops; EsyMeet's Start still works. A unit test with the record's current layout, and the real-call test, catch it |
| Browsers prompt for voice search or a site's microphone test | The 5 s minimum; Not now; Never per browser |
| An app keeps the microphone open between calls (some meeting apps do) | Prompt once per "in use" stretch; Not now covers that stretch |
| The prompt appears during a screen share | It is small and at the top. Hiding it from screen sharing was skipped at your request (E); revisit if it bothers you |

**After 8.2 (and 8.3):** 9.1–9.3 bring the live transcript, then 10 brings meeting history.
