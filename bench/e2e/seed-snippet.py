"""Adds a whole-dictation snippet to an EsyType test database: seed-snippet.py <db> <trigger> <text>. Test use only."""
import re, sqlite3, sys

db, trigger, body = sys.argv[1], sys.argv[2], sys.argv[3].replace("\\n", "\n")
key = " ".join(re.findall(r"[\w']+", trigger.lower()))
c = sqlite3.connect(db)
c.execute("INSERT INTO snippets (trigger, trigger_key, body, mode, created_at, updated_at) VALUES (?, ?, ?, 'whole', 1, 1)", (trigger, key, body))
c.commit()
