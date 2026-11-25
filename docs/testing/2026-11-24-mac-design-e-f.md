# Mac design, milestones E and F, and the frosted pill. Test record

**Date:** 24 November 2026 (tests run 23:02 to 23:59, PC left idle by the owner, on mains) · **Plan:** `docs/plans/mac-parity-gap-analysis.md` (milestones E and F) · **Build:** e2e test build only · **Released in 0.5.0** and installed on your PC on 25 Nov (section 5) · **Nothing downloaded; no dependency added**

## 1. What was built

### Settings (milestone E)
- **Rows in the Mac style** for every section: General, Shortcuts, Recording, Speech, Models, History & Privacy, Permissions, About.
- **General:** theme as Follow Windows / Dark / Light; About you (your name, typing speed for "time saved"); Open at login.
- **Shortcuts: push to talk on one key.**
  - Choose Right Ctrl, Right Alt or Right Shift (off by default). It works alongside the usual shortcuts.
  - **Hold** to dictate.
  - **Two quick taps** start hands-free (the pill says "Hands-free" and shows Stop). **One tap** stops it. Double-tap can be switched off.
  - **The key is swallowed** while it is the push-to-talk key, so it does nothing else. For example, a held Right Alt won't open menus.
  - **How it works:** a low-level keyboard hook on its own thread watches only that key and hands the work to another thread, so typing is never slowed.
- **Recording:**
  - **Sounds:** a soft rising tone on start and a falling one on stop, with volume. Off by default. The tones are made by EsyType and played on the default speaker.
  - **Maximum recording length:** 5, 10, 20 or 30 minutes. A forgotten dictation is stopped and typed when it reaches the limit.
- **Speech: Language and Translate to English.**
  - Works with the Small model only: Tiny and Base understand English only, and the choice is greyed out for them.
  - Clean, Style and the Dictionary's spelling rules apply only to English, so other languages are typed as heard.
- **About:** icon, version, tagline, esyai.co.uk and acknowledgements.
- **Not done, at the owner's choice:** hiding the pill from screen sharing.

### The pill
- **Frosted rounded rectangle:**
  - Windows 11 Acrylic behind a darker glass gradient; the wave is unchanged and vertically centred.
  - **Sizing:** the window is exactly the size of the pill and rounded by Windows, because the system blur ignores window shaping.
  - **Without transparency effects:** a solid fallback.
- **The black box around the pill in 0.4.0 is fixed:** the pill page had inherited the dark colour scheme, which painted its window dark.

**Changed again, 25 Nov (owner):** back to a capsule with a lighter frost. Acrylic is removed. 84% opacity still showed too much through on screen, so it is 94%. See CHANGELOG.

### First-run setup (milestone F)
- **Ten steps,** with small progress capsules, Back on the left and the main action on the right.
- **New steps:**
  - "What should EsyType call you?" (optional, can be skipped)
  - "Light or dark?"
- **Welcome** shows the wave.

## 2. Tests

Test build, own profiles; keys only into the test build's own windows. The owner's Notepad was open, so app suites ran with `-Apps word,chrome` and `history-apps` (always Notepad) was skipped.

| Suite | Result |
|---|---|
| Unit tests | **68 of 68** (new: one-key decisions, tones, settings defaults) |
| **Keys (new, `keys-e2e.ps1`)** | **11 of 11**. Checks, with start and stop sounds on: <ul><li>Hold Right Ctrl dictates and types</li><li>a short tap records nothing</li><li>Right Ctrl is swallowed (Right Ctrl+Q types a plain q)</li><li>a double tap shows "Hands-free" and keeps listening after the key is up</li><li>one tap stops it and types</li><li>the maximum length (7 s in the test) stops and types a forgotten dictation</li><li>no audio errors</li><li>double-tap switched off: two taps record nothing</li><li>Language is greyed out for Base</li><li>Shortcuts shows the one-key choice</li></ul> |
| First run | **34 of 34**, including the Name and Theme steps and the key-capture steps |
| Polish | **25 of 25**, including every button at least 32 px high |
| Scratchpad | **15 of 15** |
| Undo in apps (Word, Chrome) | **8 of 8** |
| Theme | **64 of 64**: AA contrast on every page and Settings section, both themes |
| Navigation / home / Insights / data / settings recovery | **17/17, 12/12, 15/15, 27/27, 10/10** |
| History UI / Dictionary / Snippets / Style | **37/37, 18/18, 14/14, 12/12** |
| Clean / Try it / History / slow paste / Undo / insertion / spacing (Word, Chrome) | **10/10, 2/2, 19/19, 21/21, 13/13, 18/18, 14/14** |

All suites from milestone D's "still to run on an idle PC" list are now done.

### Failures along the way, fixed
- **A real fault, fixed:** the Acknowledgements toggle in Settings ▸ About was 20 px high. It now has a 32 px target.
- **Polish's earlier stop (milestone D)** was the test, not EsyType. The step was the History Edit button, not the Dictionary one. The test looked for rows in the old History list, which is now grouped by day.
- **Other test faults:**
  - First run read page text only from text elements. The Privacy promise and the shortcut refusal sit in list items, so it now reads those too. A bracketing mistake in the new Name and Theme checks is also fixed.
  - Scratchpad expected "cannot be undone"; the dialog says "can't be undone".
  - The full-run script lost its suite list because one suite is called "keys", which clashes with PowerShell's `.Keys`.

## 3. Dictation time

**Conditions:** alternating blocks of 3, A B B A B A A B, on mains on an idle PC: clip `6930_10s`, Base, 4 threads. A = the pre-6.1 test build; B = this build, with start and stop sounds off (the default).

| | Pre-6.1 | This build |
|---|---|---|
| Median (range) | **2.1 s** (2.0–2.2), 12 runs | **2.1 s** (2.0–2.3), 12 runs |
| Block medians | 2.1, 2.1, 2.1, 2.1 | 2.1, 2.1, 2.2, 2.1 |
| Word error rate | 0.069 every run | 0.069 every run |

No regression. The language choice adds nothing for English: Whisper is told "en" as before.

## 4. Not tested

- **Translate and other languages end to end:** no recorded non-English speech is on this PC. The setting and its greying out are tested; the Whisper calls are the library's own.
- **Hearing the sounds:** the test checks that dictation works and nothing fails with sounds on; whether they sound right needs a person.
- **Right Alt and Right Shift:** only Right Ctrl was pressed; the other two differ only in their key code.
- **The frosted look over other windows:** checked by screenshot, not by a suite.

## 5. Release 0.5.0 on your PC (approved by you, 25 Nov)

**Before switching:** quit only your installed EsyType and copied its database and settings to `D:\EsyAI\EsyType\backups\before-0.5.0 2026-11-25 0004`. A copy of that copy was opened and checked: integrity ok, database version 6, 20 dictations. Your live files were unchanged.

**The switch:** ran `EsyType_0.5.0_x64-setup.exe /S /D=D:\EsyAI\EsyType\app` (exit code 0) and started EsyType in the tray.

| Check | Result |
|---|---|
| Database | updated in place from version 6 to 9; integrity ok |
| History | 20 dictations, as before |
| Insights totals | filled in from your History: 20 dictations, 438 words over 5 days |
| `settings.json` | byte-for-byte unchanged |
| Start with Windows | `D:\EsyAI\EsyType\app\esytype.exe --minimized` |
| Apps list | "EsyType" 0.5.0, publisher EsyAI, folder `D:\EsyAI\EsyType\app` |
| The installed program | version 0.5.0, running in the tray |
| Desktop | no shortcut made this time |

**Download:** `download/EsyType_0.5.0_x64-setup.exe`, SHA-256 `2945fe182dd4046077fa5c7fbc032f41c13bdb0fcb324ae89f7da1686544cba2`. Earlier installers stay in `download/`.

**Not yet seen by you:** the new pill and pages on your own dictations. The README screenshots were retaken in the new design afterwards, with demo content.
