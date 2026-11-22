"""Reads or manipulates an EsyType history database for history-e2e.ps1. Test use only.

  rows <db>              print all entries as JSON
  lock <db> <seconds>    hold an exclusive write lock, then release it
  newer <db>             create a database that claims schema version 99
  contains <db> <word>   exit 0 if <word> appears in the database or its WAL file (raw bytes)
"""
import json, os, sqlite3, sys, time

cmd, db = sys.argv[1], sys.argv[2]
if cmd == "rows":
    c = sqlite3.connect(db)
    c.row_factory = sqlite3.Row
    print(json.dumps([dict(r) for r in c.execute("SELECT * FROM transcripts ORDER BY id")]))
elif cmd == "lock":
    c = sqlite3.connect(db, isolation_level=None)
    c.execute("BEGIN EXCLUSIVE")
    print("locked", flush=True)
    time.sleep(float(sys.argv[3]))
    c.execute("ROLLBACK")
elif cmd == "newer":
    c = sqlite3.connect(db)
    c.execute("CREATE TABLE future (x)")
    c.execute("PRAGMA user_version = 99")
    c.commit()
elif cmd == "seed":
    # seed <db> <text> <age_days> [app]: adds an entry as if dictated <age_days> ago (the app must have created the schema)
    text, age = sys.argv[3], float(sys.argv[4])
    app = sys.argv[5] if len(sys.argv) > 5 else None
    c = sqlite3.connect(db)
    c.execute("INSERT INTO transcripts (created_at, raw_text, final_text, mode, model, audio_ms, processing_ms, outcome, app, word_count)"
              " VALUES (?, ?, ?, 'verbatim', 'base', 5000, 1500, 'pasted', ?, ?)",
              (int((time.time() - age * 86400) * 1000), text.lower(), text, app, len(text.split())))
    c.commit()
elif cmd == "contains":
    word = sys.argv[3].encode()
    found = any(os.path.exists(p) and word in open(p, "rb").read() for p in (db, db + "-wal"))
    sys.exit(0 if found else 1)
