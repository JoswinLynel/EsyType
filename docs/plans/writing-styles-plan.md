# Writing styles: implementation plan (Phase 4, step 5)

**Status:** approved with the recommended defaults and built, 20 November 2026. Test record: `docs/testing/2026-11-20-writing-styles.md`.
**Scope:** English. Rules only, on this PC; no AI model, no downloads, no network.

## 1. What the user gets, and what rules cannot do

A **Style** tab. A style adjusts how Clean-mode text is finished, and EsyType picks the style from the app you are dictating into.

| Style | What it changes | Example: you say "yeah I'm gonna send it tomorrow" |
|---|---|---|
| **Standard** | Nothing beyond Clean | Yeah I'm gonna send it tomorrow. |
| **Professional** | Casual spoken forms → written forms ("gonna" → "going to", "wanna" → "want to", "yeah" → "yes", "ok" → "OK"); full stop at the end | Yes, I'm going to send it tomorrow. |
| **Formal** | Professional, plus unambiguous contractions expanded ("I'm" → "I am", "don't" → "do not", "can't" → "cannot") | Yes, I am going to send it tomorrow. |
| **Casual** | No full stop at the end of a one-sentence message, as people write in chat | Yeah I'm gonna send it tomorrow |
| **Concise** | Wordy stock phrases shortened ("in order to" → "to", "due to the fact that" → "because", "at this point in time" → "now"); hedges dropped when set off by commas ("basically,", "actually,") | Yeah I'm gonna send it tomorrow. |
| **Custom** | Your own choice of the switches above | |

**Honest limit:** rules change spellings, contractions, stock phrases and punctuation. They do not change tone or rewrite sentences: "Professional" will not turn a blunt sentence into a polite one. That needs the optional local language model (Phase 5, AI Enhanced), which will use the same style names.

Not changed by any style: snippet text, dictionary terms, anything in Verbatim mode, and words where a rule would be ambiguous ("it's" can mean "it is" or "it has", so it is left alone).

## 2. Choosing the style per app

- A **rule list** you can read and edit: *program → style*, e.g. `OUTLOOK.EXE → Professional`, `slack.exe → Casual`.
- A **default style** for programs without a rule: Standard (proposed).
- **Starter rules** (proposed, editable): Outlook and Word → Professional; Teams, Slack, WhatsApp, Discord, Telegram and Messenger → Casual.
- The program is identified by its **executable name only**, the same way History does, read at the moment of dictation. It is needed even when History's "note which program" is off; it is then used and forgotten, never stored.
- **Browsers** (Chrome, Edge, Firefox) get one style for every site, because telling Gmail from ChatGPT needs the window title (see decision 4).
- Add a rule from a list of programs you have dictated into (from History, when it records program names) or by typing the executable name.

## 3. How it works

```
speech → Snippets → Dictionary → Clean → Style (Clean mode only) → snippet text and terms put back → insert
```

- The style runs on Clean's word tokens, so it shares Clean's protection of snippets and dictionary terms.
- The style used is shown on the pill ("Done · Casual") and saved in History with the entry.
- Settings live in `settings.json` (default style, rules, Custom switches), so styles keep working if the database is unavailable. History gains a `style` column (schema v4, forward-only, with the usual backup and protection).

## 4. Interface

A **Style** tab:
- the six styles as cards, each with a before/after example;
- the default style for other programs;
- the rule list (program, style, Delete), with Add from recent programs or by name;
- Custom's switches: spoken forms → written forms; expand contractions; shorten stock phrases; drop hedges; final full stop (always / never / leave as is);
- a "try it" box: type or paste a sentence and see it in each style.

## 5. Order of work and tests

1. Style engine in the Clean module (pure). A table of at least 60 cases across the styles, including the leave-alone cases ("it's", "I'd", quotes, names, snippet and dictionary placeholders, multi-sentence messages for Casual), and Verbatim unaffected. Speed under 2 ms.
2. Settings, rule matching (case-insensitive executable names), schema v4 with an upgrade test (v3 → v4 keeps everything).
3. Pipeline, pill label, History column.
4. Style page; UI Automation test (pick default, add and delete a rule, Custom switches, try-it box).
5. End to end with spoken audio into the test window: a rule for the test window's program switches the style; the default applies without a rule; Verbatim is untouched; snippets and dictionary terms are unchanged.
6. Install the production copy (upgrade checked on the owner's database); docs.

## 6. Decisions for the owner

1. **Styles:** Standard, Professional, Formal, Casual, Concise, Custom as above (recommended).
2. **Default for programs without a rule:** Standard, i.e. Clean as today (recommended), or Professional.
3. **Starter rules:** pre-filled as in section 2, editable (recommended), or start with an empty list.
4. **Browsers:** executable name only, so one style for all websites (recommended for privacy), or also read the window title at the moment of dictation (never stored) so rules can say e.g. "Gmail → Professional, ChatGPT → Casual".
5. **Styles apply in Clean mode only;** Verbatim stays exactly what was heard, plus Dictionary and Snippets (recommended).
