"""Test data for data-e2e.ps1 (test use only). The app must have created the schema.

  many <db>              three dictations, three dictionary words, three snippets, two notes (polish-e2e.ps1)
  seed <db>              two dictations, one dictionary correction, one snippet, one note
  counts <db>            JSON counts of each kind
  newer <src> <dst>      a copy of backup <src> claiming schema 99
  edit-settings <src> <dst>   an exported settings file with Hold to talk Ctrl+F6, Verbatim, another microphone,
                              an unreadable thread count and an unknown value
"""
import json, shutil, sqlite3, sys, time

cmd = sys.argv[1]
if cmd == "seed":
    c = sqlite3.connect(sys.argv[2])
    now = int(time.time() * 1000)
    for text in ("The kiwis are ripe.", "Meet me at noon."):
        c.execute("INSERT INTO transcripts (created_at, raw_text, final_text, mode, language, model, audio_ms, processing_ms, outcome, app, word_count)"
                  " VALUES (?, ?, ?, 'clean', 'en', 'base', 1000, 200, 'pasted', 'WINWORD.EXE', 4)", (now, text, text))
    c.execute("INSERT INTO dictionary (kind, term, term_key, replacement, created_at, updated_at) VALUES ('correction', 'princess', 'princess', 'Princesa', ?, ?)", (now, now))
    c.execute("INSERT INTO snippets (trigger, trigger_key, body, mode, created_at, updated_at) VALUES ('my sign off', 'my sign off', 'Kind regards', 'whole', ?, ?)", (now, now))
    c.execute("INSERT INTO scratchpad_notes (body, created_at, updated_at) VALUES ('Shopping list', ?, ?)", (now, now))
    c.commit()
elif cmd == "many":
    c = sqlite3.connect(sys.argv[2])
    now = int(time.time() * 1000)
    for i, text in enumerate(("First dictation here.", "Second dictation here.", "Third dictation here.")):
        c.execute("INSERT INTO transcripts (created_at, raw_text, final_text, mode, language, model, audio_ms, processing_ms, outcome, app, word_count)"
                  " VALUES (?, ?, ?, 'clean', 'en', 'base', 1000, 200, 'pasted', 'WINWORD.EXE', 3)", (now - i * 1000, text, text))
    for w in ("Alpha", "Bravo", "Charlie"):
        c.execute("INSERT INTO dictionary (kind, term, term_key, replacement, created_at, updated_at) VALUES ('word', ?, ?, NULL, ?, ?)", (w, w.lower(), now, now))
    for t in ("sign off one", "sign off two", "sign off three"):
        c.execute("INSERT INTO snippets (trigger, trigger_key, body, mode, created_at, updated_at) VALUES (?, ?, 'Kind regards', 'whole', ?, ?)", (t, t, now, now))
    for b in ("Shopping list", "Ideas"):
        c.execute("INSERT INTO scratchpad_notes (body, created_at, updated_at) VALUES (?, ?, ?)", (b, now, now))
    c.commit()
elif cmd == "query":
    print(json.dumps(sqlite3.connect(sys.argv[2]).execute(sys.argv[3]).fetchall()))
elif cmd == "counts":
    c = sqlite3.connect(sys.argv[2])
    print(json.dumps({t: c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in ("transcripts", "dictionary", "snippets", "scratchpad_notes")}))
elif cmd == "newer":
    shutil.copy(sys.argv[2], sys.argv[3])
    c = sqlite3.connect(sys.argv[3])
    c.execute("PRAGMA user_version = 99")
    c.execute("UPDATE backup_info SET value = '99' WHERE key = 'schema'")
    c.commit()
elif cmd == "edit-settings":
    d = json.load(open(sys.argv[2], encoding="utf-8-sig"))
    d["settings"].update({"ptt": "Ctrl+F6", "text_mode": "verbatim", "mic": "Another microphone", "threads": "three", "from_the_future": 1})
    json.dump(d, open(sys.argv[3], "w", encoding="utf-8"))
