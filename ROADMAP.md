# EsyType roadmap

Last updated: 20 November 2026. Detailed tasks are in `TODO.md`; what is built and tested is in `IMPLEMENTATION_STATUS.md`.

## Product direction (owner decision, 20 November 2026)

EsyType stays lightweight, fast, private and fully local:

- **Speech recognition:** Whisper (Tiny, Base, Small), on this PC.
- **Text processing:** rule-based **Clean** mode by default, **Verbatim** as the alternative.
- **No AI enhancement for the foreseeable future:** no local language model, no cloud AI, no additional model downloads, and nothing in EsyType requires AI. AI Enhancement (old Phase 5) is **deferred**, not cancelled and not in progress; its architecture is not being prepared (decision 0022).

## Now: make the existing features dependable

The priority is reliability, not new features. In order:

1. Dictation and speech recognition
2. Clean mode and Verbatim
3. Personal Dictionary
4. Snippets
5. Writing styles
6. Undo last dictation
7. History
8. Scratchpad

All seven Phase 4 steps are built and pass automated tests. Before the product is called validated:

- The two insertion bugs (Word pasting the user's clipboard on a busy PC; no space after text typed by hand) are fixed and pass automated tests (20 Nov 2026); the owner has not used the fix yet.
- Open: on a heavily loaded PC speech recognition slows from about 2 s to 7–58 s. The other features' suites pass on an idle PC but have not been confirmed under load.
- The owner's own checks are still open: the spoken per-app test and a real Windows restart.
- Improvements to the Dictionary, Snippets, Writing styles and Scratchpad continue, as rules, without AI.

No major new feature starts until these are resolved and the documents are up to date.

## Next: Phase 5, product polish and first-run experience (owner, 21 Nov 2026)

Plan approved by the owner (`docs/plans/phase-5-audit-and-plan.md`). Five milestones, one at a time:
1. Foundation: sidebar, a Settings page, shared states, and a fix for a settings-file defect. **Done and installed (21 Nov 2026).**
2. First-run wizard. **Done and installed (21 Nov 2026).**
3. Settings and data management: export/import, backup/restore, data and privacy page. **Done and installed (21 Nov 2026).**
4. Page polish, accessibility and the app icon. **Done and installed (22 Nov 2026).**
5. Windows installer. **Done; your PC switched to it (22 Nov 2026).**

## Later

| Phase | State |
|---|---|
| AI enhancement (formerly Phase 5) | **Deferred** (owner decision, 20 Nov 2026; decision 0022) |
| Advanced interface remainder (dashboard, insights) | Not started; wizard, settings and accessibility moved into Phase 5 |
| Testing and release remainder (updates, signing, licences, user documentation) | Not started; installer moved into Phase 5 |
