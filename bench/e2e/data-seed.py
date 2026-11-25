"""Test data for data-e2e.ps1 (test use only). The app must have created the schema.

  readme <db>            demo content for the README screenshots (ui-screenshots.ps1 -Demo)
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
elif cmd == "usage":
    # four days of usage totals: today, yesterday, two days ago (a 3-day streak) and five days ago;
    # 12,400 words in 100 minutes of speech: "12.4K" and 124 wpm
    c = sqlite3.connect(sys.argv[2])
    for d in (0, 1, 2, 5):
        c.execute("INSERT INTO usage_days (day, dictations, words, audio_ms) VALUES (date('now', 'localtime', ?), 10, 3100, 1500000)", (f"-{d} days",))
    c.commit()
elif cmd == "insights":
    # usage on days counted back from today; prints the values Insights should show (insights-e2e.ps1)
    import datetime
    c = sqlite3.connect(sys.argv[2])
    today = datetime.date.today()
    words = {0: 300, 1: 200, 2: 100, 5: 400, 9: 250, 40: 1000, 100: 600, 130: 700}
    for off, w in words.items():
        c.execute("INSERT INTO usage_days (day, dictations, words, audio_ms, processing_ms) VALUES (?, 3, ?, ?, 1000)", ((today - datetime.timedelta(off)).isoformat(), w, w * 400))
    apps = {0: [("Email", 200), ("Chat", 100)], 1: [("Browser", 200)], 2: [("Documents", 100)], 5: [("Code", 400)]}
    for off, kinds in apps.items():
        for k, w in kinds:
            c.execute("INSERT INTO usage_apps (day, kind, words) VALUES (?, ?, ?)", ((today - datetime.timedelta(off)).isoformat(), k, w))
    c.commit()
    week_start = today - datetime.timedelta(today.weekday())
    first = week_start - datetime.timedelta(17 * 7)
    in_week = {k: v for k, v in words.items() if today - datetime.timedelta(k) >= week_start}
    active = {k: v for k, v in words.items() if today - datetime.timedelta(k) >= first}
    kinds = {}
    for off, ks in apps.items():
        if today - datetime.timedelta(off) >= week_start:
            for k, w in ks:
                kinds[k] = kinds.get(k, 0) + w
    total_k = sum(kinds.values())
    total = sum(words.values()); audio = total * 400; proc = 1000 * len(words)
    saved = lambda wpm: max(0, total / wpm * 60000 - audio - proc)
    dur = lambda ms: (lambda m: f"{m // 60} h {m % 60} min" if m >= 60 else f"{m} min")(round(ms / 60000))
    span = lambda n: sum(v for k, v in words.items() if k < n)
    print(json.dumps({
        "words": f"{total:,}", "wpm": str(round(total / (audio / 60000))), "saved40": dur(saved(40)), "saved45": dur(saved(45)),
        "span": {str(n): [f"{span(n):,}", f"{round(span(n) / n):,}"] for n in (7, 30, 90)},
        "week": f"{sum(in_week.values()):,}", "active": len(active), "busiest": f"{max(active.values()):,}",
        "per_active": f"{round(sum(active.values()) / len(active)):,}", "streak": 3,
        "kinds": {k: round(w / total_k * 100) for k, w in kinds.items()},
        "busiest_tip": (lambda d: f"{d.strftime('%a')} {d.day} {d.strftime('%b')}: {max(active.values()):,} words")(today - datetime.timedelta(max(active, key=active.get))),
    }))
elif cmd == "readme":
    # demo content for the README screenshots: everyday dictations, words, snippets, notes and four months of usage
    import datetime, random
    c = sqlite3.connect(sys.argv[2])
    now = int(time.time() * 1000); hour = 3600 * 1000
    rows = [
        (0.2, "OUTLOOK.EXE", "professional", "Hi Sam, thanks for sending the Q3 figures. I'll review them this afternoon and come back to you by Friday."),
        (0.9, "slack.exe", "casual", "Running five minutes late, start without me"),
        (1.6, "WINWORD.EXE", "standard", "The new design brings Insights, a frosted recording pill and push to talk on a single key."),
        (2.4, "chrome.exe", "standard", "Summarise this article in three bullet points and suggest a title."),
        (26, "OUTLOOK.EXE", "professional", "Could we move Thursday's call to 3 pm? Everything else on the agenda stays the same."),
        (27.5, "Code.exe", "standard", "Refactor the settings loader so a damaged file falls back to the defaults."),
        (29, "WINWORD.EXE", "standard", "Meeting notes: the launch is on 2 December. Priya owns the website, Tom the newsletter."),
    ]
    for ago, app, style, text in rows:
        words = len(text.split())
        c.execute("INSERT INTO transcripts (created_at, raw_text, final_text, mode, language, model, audio_ms, processing_ms, outcome, app, word_count, style)"
                  " VALUES (?, ?, ?, 'clean', 'en', 'base', ?, 1900, 'pasted', ?, ?, ?)", (now - int(ago * hour), text, text, words * 420, app, words, style))
    dic = [("word", "EsyType", None, "Brand", "Our product name"), ("word", "Kubernetes", None, "Technical", ""), ("word", "Siobhan", None, "Name", "Says shi-VAWN"),
           ("correction", "e s y a i", "EsyAI", "Brand", ""), ("correction", "q three", "Q3", "Abbreviation", "")]
    for kind, term, rep, cat, note in dic:
        c.execute("INSERT INTO dictionary (kind, term, term_key, replacement, created_at, updated_at, uses, category, description, enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)",
                  (kind, term, term.lower(), rep, now, now, len(term) % 5 + 1, cat, note))
    for trig, body, mode, cat in [("my email signature", "Kind regards,\nAlex Morgan\n{date}", "whole", "Email"),
                                  ("my address", "1 High Street, London", "whole", "Personal"),
                                  ("meeting link", "https://meet.example.com/alex", "anywhere", "Work")]:
        c.execute("INSERT INTO snippets (trigger, trigger_key, body, mode, created_at, updated_at, uses, category, enabled) VALUES (?, ?, ?, ?, ?, ?, 2, ?, 1)",
                  (trig, trig, body, mode, now, now, cat))
    for body, ago in [("Launch post ideas\n\n- Speak, it types: no account, no cloud\n- Push to talk on one key\n- Insights: words per day and time saved", 1), ("Shopping list\nMilk, coffee, lemons", 30)]:
        c.execute("INSERT INTO scratchpad_notes (body, created_at, updated_at) VALUES (?, ?, ?)", (body, now - ago * hour, now - ago * hour))
    rnd = random.Random(7); today = datetime.date.today()
    for off in range(0, 120):
        if off > 2 and rnd.random() < 0.35:
            continue   # days off; the last three days make a streak
        w = rnd.randint(250, 1400) if off % 7 not in (5, 6) else rnd.randint(40, 300)
        c.execute("INSERT INTO usage_days (day, dictations, words, audio_ms, processing_ms) VALUES (?, ?, ?, ?, ?)",
                  ((today - datetime.timedelta(off)).isoformat(), max(1, w // 25), w, w * 420, max(1, w // 25) * 1900))
        if off < 7:
            for k, share in (("Email", 0.4), ("Documents", 0.25), ("Chat", 0.2), ("Browser", 0.1), ("Code", 0.05)):
                c.execute("INSERT INTO usage_apps (day, kind, words) VALUES (?, ?, ?)", ((today - datetime.timedelta(off)).isoformat(), k, int(w * share)))
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
