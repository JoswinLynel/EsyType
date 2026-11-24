//! Local dictation history in SQLite (%LOCALAPPDATA%\EsyAI\EsyType\esytype.db).
//! Text only: audio is never stored. Every failure here is reported to the caller and must never
//! interrupt dictation.
use rusqlite::{params, Connection};
use serde::Serialize;
use std::path::{Path, PathBuf};

/// One entry per schema version, applied in order and never edited once released (forward-only).
const MIGRATIONS: &[&str] = &[
    // v1: history
    "CREATE TABLE transcripts (
        id            INTEGER PRIMARY KEY,
        created_at    INTEGER NOT NULL,          -- Unix time, milliseconds, UTC
        raw_text      TEXT,                      -- exactly what the engine heard; NULL when the user turned this off
        final_text    TEXT NOT NULL,             -- what was inserted
        edited_text   TEXT,                      -- the user's later correction, if any
        mode          TEXT NOT NULL,             -- 'verbatim' | 'clean'
        language      TEXT NOT NULL DEFAULT 'en',
        model         TEXT NOT NULL,
        audio_ms      INTEGER NOT NULL,
        processing_ms INTEGER NOT NULL,
        outcome       TEXT NOT NULL,             -- 'pasted' | 'typed' | 'copied' | 'failed'
        app           TEXT,                      -- executable name only, e.g. WINWORD.EXE; never window titles
        word_count    INTEGER NOT NULL
    );
    CREATE INDEX transcripts_created_at ON transcripts(created_at);",
    // v2: personal dictionary (see dictionary.rs)
    "CREATE TABLE dictionary (
        id           INTEGER PRIMARY KEY,
        kind         TEXT NOT NULL CHECK (kind IN ('word', 'correction')),
        term         TEXT NOT NULL,             -- the word, or what is heard for a correction
        term_key     TEXT NOT NULL,             -- term in lower case, for duplicate checks
        replacement  TEXT,                      -- what to write (corrections only)
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL,
        uses         INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER
    );
    CREATE UNIQUE INDEX dictionary_kind_term ON dictionary(kind, term_key);",
    // v3: snippets (see snippets.rs)
    "CREATE TABLE snippets (
        id           INTEGER PRIMARY KEY,
        trigger      TEXT NOT NULL,             -- as entered
        trigger_key  TEXT NOT NULL UNIQUE,      -- lower-case words only, for matching and duplicate checks
        body         TEXT NOT NULL,             -- the text to insert, up to 4,000 characters
        mode         TEXT NOT NULL CHECK (mode IN ('whole', 'anywhere')),
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL,
        uses         INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER
    );",
    // v4: the writing style used for each dictation (NULL: Verbatim or none)
    "ALTER TABLE transcripts ADD COLUMN style TEXT;",
    // v5: dictations removed again with Undo (kept in History, marked)
    "ALTER TABLE transcripts ADD COLUMN undone INTEGER NOT NULL DEFAULT 0;",
    // v6: Scratchpad notes (see notes.rs); kept until the user deletes them
    "CREATE TABLE scratchpad_notes (
        id         INTEGER PRIMARY KEY,
        body       TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
    );",
    // v7: usage totals per local day, numbers only (no text), kept even when History is off or trimmed;
    // started from the History already on this PC
    "CREATE TABLE usage_days (
        day        TEXT PRIMARY KEY,           -- local date, YYYY-MM-DD
        dictations INTEGER NOT NULL,
        words      INTEGER NOT NULL,
        audio_ms   INTEGER NOT NULL
    );
    INSERT INTO usage_days (day, dictations, words, audio_ms)
        SELECT date(created_at / 1000, 'unixepoch', 'localtime'), count(*), sum(word_count), sum(audio_ms) FROM transcripts GROUP BY 1;",
    // v8: processing time per day (for Time saved) and words per kind of app per day (Insights), from the program's
    // name only; both started from the History already on this PC. The kinds must match app_kind() (tested).
    "ALTER TABLE usage_days ADD COLUMN processing_ms INTEGER NOT NULL DEFAULT 0;
    UPDATE usage_days SET processing_ms = coalesce((SELECT sum(processing_ms) FROM transcripts t
        WHERE date(t.created_at / 1000, 'unixepoch', 'localtime') = usage_days.day), 0);
    CREATE TABLE usage_apps (
        day   TEXT NOT NULL,                   -- local date, YYYY-MM-DD
        kind  TEXT NOT NULL,                   -- Email, Chat, Documents, Code, Notes, Browser or Other
        words INTEGER NOT NULL,
        PRIMARY KEY (day, kind)
    );
    INSERT INTO usage_apps (day, kind, words)
        SELECT date(created_at / 1000, 'unixepoch', 'localtime'), CASE
            WHEN lower(app) IN ('outlook.exe', 'olk.exe', 'hxoutlook.exe', 'thunderbird.exe', 'mailspring.exe') THEN 'Email'
            WHEN lower(app) IN ('slack.exe', 'teams.exe', 'ms-teams.exe', 'whatsapp.exe', 'discord.exe', 'telegram.exe', 'signal.exe', 'zoom.exe', 'skype.exe') THEN 'Chat'
            WHEN lower(app) IN ('winword.exe', 'wordpad.exe', 'soffice.bin', 'swriter.exe', 'powerpnt.exe', 'excel.exe', 'acrobat.exe', 'acrord32.exe') THEN 'Documents'
            WHEN lower(app) IN ('code.exe', 'cursor.exe', 'devenv.exe', 'idea64.exe', 'pycharm64.exe', 'rider64.exe', 'sublime_text.exe', 'windowsterminal.exe', 'wt.exe') THEN 'Code'
            WHEN lower(app) IN ('onenote.exe', 'obsidian.exe', 'notion.exe', 'evernote.exe', 'notepad.exe', 'notepad++.exe', 'microsoft.notes.exe') THEN 'Notes'
            WHEN lower(app) LIKE 'esytype%' THEN 'Notes'
            WHEN lower(app) IN ('chrome.exe', 'msedge.exe', 'firefox.exe', 'brave.exe', 'opera.exe', 'vivaldi.exe', 'arc.exe') THEN 'Browser'
            ELSE 'Other' END, sum(word_count)
        FROM transcripts GROUP BY 1, 2;",
];

/// Kinds of app for Insights, by the program's file name only (never window titles or what was written). A browser is
/// one kind for every website. EsyType itself (the Scratchpad) counts as Notes.
const APP_KINDS: &[(&str, &[&str])] = &[
    ("Email", &["outlook.exe", "olk.exe", "hxoutlook.exe", "thunderbird.exe", "mailspring.exe"]),
    ("Chat", &["slack.exe", "teams.exe", "ms-teams.exe", "whatsapp.exe", "discord.exe", "telegram.exe", "signal.exe", "zoom.exe", "skype.exe"]),
    ("Documents", &["winword.exe", "wordpad.exe", "soffice.bin", "swriter.exe", "powerpnt.exe", "excel.exe", "acrobat.exe", "acrord32.exe"]),
    ("Code", &["code.exe", "cursor.exe", "devenv.exe", "idea64.exe", "pycharm64.exe", "rider64.exe", "sublime_text.exe", "windowsterminal.exe", "wt.exe"]),
    ("Notes", &["onenote.exe", "obsidian.exe", "notion.exe", "evernote.exe", "notepad.exe", "notepad++.exe", "microsoft.notes.exe"]),
    ("Browser", &["chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "opera.exe", "vivaldi.exe", "arc.exe"]),
];

pub fn app_kind(exe: Option<&str>) -> &'static str {
    let Some(e) = exe.map(|e| e.to_lowercase()) else { return "Other" };
    if e.starts_with("esytype") {
        return "Notes";
    }
    APP_KINDS.iter().find(|(_, list)| list.contains(&e.as_str())).map(|(k, _)| *k).unwrap_or("Other")
}

/// The schema version this EsyType writes.
pub fn latest_schema() -> i64 {
    MIGRATIONS.len() as i64
}

#[cfg(test)]
pub fn migration(i: usize) -> &'static str {
    MIGRATIONS[i]
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct Usage {
    pub words: i64,
    pub audio_ms: i64,
    pub processing_ms: i64,
    pub dictations: i64,
    /// First day with a dictation, YYYY-MM-DD.
    pub since: Option<String>,
    pub streak: i64,
    pub dictionary: i64,
    pub snippets: i64,
}

/// Days in a row with dictation, ending today, or yesterday if nothing yet today. `days`: day numbers, newest first.
pub fn streak(days: &[i64], today: i64) -> i64 {
    let Some(&first) = days.first() else { return 0 };
    if first != today && first != today - 1 {
        return 0;
    }
    let mut n = 1;
    while (n as usize) < days.len() && days[n as usize] == first - n {
        n += 1;
    }
    n
}

pub fn db_path() -> PathBuf {
    crate::settings::data_dir().join("esytype.db")
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct Entry {
    pub id: i64,
    pub created_at: i64,
    pub raw_text: Option<String>,
    pub final_text: String,
    pub edited_text: Option<String>,
    pub mode: String,
    pub language: String,
    pub model: String,
    pub audio_ms: i64,
    pub processing_ms: i64,
    pub outcome: String,
    pub app: Option<String>,
    pub word_count: i64,
    pub style: Option<String>,
    pub undone: bool,
}

pub struct History {
    pub(crate) conn: Connection,
    path: PathBuf,
}

pub(crate) fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

pub(crate) fn err(e: impl std::fmt::Display) -> String {
    format!("History database error: {e}")
}

impl History {
    /// Opens (creating if needed) and migrates the database. A database written by a newer EsyType is
    /// left untouched and an error is returned, so an older version can never damage it.
    pub fn open(path: &Path) -> Result<History, String> {
        let existed = path.exists();
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(err)?;
        }
        let mut conn = Connection::open(path).map_err(err)?;
        // Version first: switching the journal mode would already modify a newer database's file.
        let version: i64 = conn.pragma_query_value(None, "user_version", |r| r.get(0)).map_err(err)?;
        let latest = MIGRATIONS.len() as i64;
        if version > latest {
            return Err(format!("The history database was created by a newer version of EsyType (schema {version}, this version knows {latest}). History is off until EsyType is updated; nothing was changed."));
        }
        conn.pragma_update(None, "secure_delete", true).map_err(err)?; // deleted text is overwritten, not left in free pages
        conn.pragma_update(None, "journal_mode", "WAL").map_err(err)?;
        conn.pragma_update(None, "foreign_keys", true).map_err(err)?;
        if version < latest {
            // Backup only while upgrading an existing database, removed as soon as the upgrade succeeds, so it
            // can never outlive a deletion or the retention period.
            let backup = if existed && version > 0 {
                let b = backup_path(path, version);
                conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_| Ok(())).ok();
                std::fs::copy(path, &b).map_err(err)?;
                Some(b)
            } else {
                None
            };
            for (i, sql) in MIGRATIONS.iter().enumerate().skip(version as usize) {
                let tx = conn.transaction().map_err(err)?;
                tx.execute_batch(sql).map_err(err)?;
                tx.pragma_update(None, "user_version", (i + 1) as i64).map_err(err)?;
                tx.commit().map_err(err)?;
            }
            if let Some(b) = backup {
                let _ = std::fs::remove_file(b);
            }
        }
        Ok(History { conn, path: path.to_path_buf() })
    }

    #[cfg(test)]
    #[allow(clippy::too_many_arguments)]
    pub fn add(&self, raw_text: Option<&str>, final_text: &str, mode: &str, model: &str, audio_ms: i64, processing_ms: i64, outcome: &str, app: Option<&str>) -> Result<i64, String> {
        self.add_styled(raw_text, final_text, mode, None, model, audio_ms, processing_ms, outcome, app)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn add_styled(&self, raw_text: Option<&str>, final_text: &str, mode: &str, style: Option<&str>, model: &str, audio_ms: i64, processing_ms: i64, outcome: &str, app: Option<&str>) -> Result<i64, String> {
        let words = final_text.split_whitespace().count() as i64;
        self.conn
            .execute(
                "INSERT INTO transcripts (created_at, raw_text, final_text, mode, language, model, audio_ms, processing_ms, outcome, app, word_count, style)
                 VALUES (?1, ?2, ?3, ?4, 'en', ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                params![now_ms(), raw_text, final_text, mode, model, audio_ms, processing_ms, outcome, app, words, style],
            )
            .map_err(err)?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Counts a finished dictation in today's usage totals (numbers only), whether or not History is on.
    // shortcut: a dictation later undone still counts; subtract it in mark_undone if Insights needs exact figures.
    pub fn add_usage(&self, words: i64, audio_ms: i64, processing_ms: i64, kind: &str) -> Result<(), String> {
        self.conn
            .execute_batch("BEGIN")
            .and_then(|_| self.conn.execute(
                "INSERT INTO usage_days (day, dictations, words, audio_ms, processing_ms) VALUES (date('now', 'localtime'), 1, ?1, ?2, ?3)
                 ON CONFLICT(day) DO UPDATE SET dictations = dictations + 1, words = words + ?1, audio_ms = audio_ms + ?2, processing_ms = processing_ms + ?3",
                params![words, audio_ms, processing_ms],
            ))
            .and_then(|_| self.conn.execute(
                "INSERT INTO usage_apps (day, kind, words) VALUES (date('now', 'localtime'), ?1, ?2)
                 ON CONFLICT(day, kind) DO UPDATE SET words = words + ?2",
                params![kind, words],
            ))
            .and_then(|_| self.conn.execute_batch("COMMIT"))
            .map_err(|e| { let _ = self.conn.execute_batch("ROLLBACK"); err(e) })
    }

    /// For Insights: every day with dictation in the last 140 days, oldest first; words per kind of app this week
    /// (from Monday); today's and this week's first local dates.
    pub fn insights(&self) -> Result<serde_json::Value, String> {
        let mut st = self.conn.prepare("SELECT day, dictations, words, audio_ms, processing_ms FROM usage_days WHERE day >= date('now', 'localtime', '-140 days') ORDER BY day").map_err(err)?;
        let days: Vec<serde_json::Value> = st
            .query_map([], |r| Ok(serde_json::json!({ "day": r.get::<_, String>(0)?, "dictations": r.get::<_, i64>(1)?, "words": r.get::<_, i64>(2)?, "audio_ms": r.get::<_, i64>(3)?, "processing_ms": r.get::<_, i64>(4)? })))
            .map_err(err)?
            .collect::<Result<_, _>>()
            .map_err(err)?;
        let (today, week): (String, String) = self.conn.query_row("SELECT date('now', 'localtime'), date('now', 'localtime', '-6 days', 'weekday 1')", [], |r| Ok((r.get(0)?, r.get(1)?))).map_err(err)?;
        let mut st = self.conn.prepare("SELECT kind, sum(words) FROM usage_apps WHERE day >= ?1 GROUP BY kind HAVING sum(words) > 0 ORDER BY 2 DESC").map_err(err)?;
        let apps: Vec<serde_json::Value> = st
            .query_map(params![week], |r| Ok(serde_json::json!({ "kind": r.get::<_, String>(0)?, "words": r.get::<_, i64>(1)? })))
            .map_err(err)?
            .collect::<Result<_, _>>()
            .map_err(err)?;
        Ok(serde_json::json!({ "days": days, "apps_week": apps, "today": today, "week_start": week }))
    }

    /// All-time totals, the current day streak and how many Dictionary words and snippets there are.
    pub fn usage(&self) -> Result<Usage, String> {
        let (words, audio_ms, dictations, since, processing_ms): (i64, i64, i64, Option<String>, i64) = self
            .conn
            .query_row("SELECT coalesce(sum(words), 0), coalesce(sum(audio_ms), 0), coalesce(sum(dictations), 0), min(day), coalesce(sum(processing_ms), 0) FROM usage_days", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
            .map_err(err)?;
        let today: i64 = self.conn.query_row("SELECT CAST(julianday(date('now', 'localtime')) AS INTEGER)", [], |r| r.get(0)).map_err(err)?;
        let mut st = self.conn.prepare("SELECT CAST(julianday(day) AS INTEGER) FROM usage_days WHERE dictations > 0 ORDER BY day DESC").map_err(err)?;
        let days: Vec<i64> = st.query_map([], |r| r.get(0)).map_err(err)?.collect::<Result<_, _>>().map_err(err)?;
        let (dictionary, snippets): (i64, i64) = self
            .conn
            .query_row("SELECT (SELECT count(*) FROM dictionary), (SELECT count(*) FROM snippets)", [], |r| Ok((r.get(0)?, r.get(1)?)))
            .map_err(err)?;
        Ok(Usage { words, audio_ms, processing_ms, dictations, since, streak: streak(&days, today), dictionary, snippets })
    }

    /// Newest first. `query` matches the inserted or edited text, case-insensitively.
    pub fn list(&self, query: &str, limit: i64, offset: i64) -> Result<(Vec<Entry>, i64), String> {
        // shortcut: LIKE scans every row; fine for tens of thousands of dictations, switch to FTS5 if search gets slow.
        let like = format!("%{}%", query.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_"));
        let filter = "(?1 = '%%' OR final_text LIKE ?1 ESCAPE '\\' OR edited_text LIKE ?1 ESCAPE '\\')";
        let total: i64 = self.conn.query_row(&format!("SELECT COUNT(*) FROM transcripts WHERE {filter}"), params![like], |r| r.get(0)).map_err(err)?;
        let mut st = self
            .conn
            .prepare(&format!(
                "SELECT id, created_at, raw_text, final_text, edited_text, mode, language, model, audio_ms, processing_ms, outcome, app, word_count, style, undone
                 FROM transcripts WHERE {filter} ORDER BY created_at DESC, id DESC LIMIT ?2 OFFSET ?3"
            ))
            .map_err(err)?;
        let rows = st
            .query_map(params![like, limit, offset], |r| {
                Ok(Entry {
                    id: r.get(0)?,
                    created_at: r.get(1)?,
                    raw_text: r.get(2)?,
                    final_text: r.get(3)?,
                    edited_text: r.get(4)?,
                    mode: r.get(5)?,
                    language: r.get(6)?,
                    model: r.get(7)?,
                    audio_ms: r.get(8)?,
                    processing_ms: r.get(9)?,
                    outcome: r.get(10)?,
                    app: r.get(11)?,
                    word_count: r.get(12)?,
                    style: r.get(13)?,
                    undone: r.get::<_, i64>(14)? != 0,
                })
            })
            .map_err(err)?;
        Ok((rows.collect::<Result<Vec<_>, _>>().map_err(err)?, total))
    }

    pub fn mark_undone(&self, id: i64) -> Result<(), String> {
        self.conn.execute("UPDATE transcripts SET undone = 1 WHERE id = ?1", params![id]).map_err(err)?;
        Ok(())
    }

    /// Executable names in History, most recently used first.
    pub fn recent_apps(&self) -> Result<Vec<String>, String> {
        let mut st = self.conn.prepare("SELECT app FROM transcripts WHERE app IS NOT NULL GROUP BY app ORDER BY MAX(created_at) DESC LIMIT 20").map_err(err)?;
        let rows = st.query_map([], |r| r.get::<_, String>(0)).map_err(err)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(err)
    }

    pub fn edit(&self, id: i64, text: &str) -> Result<(), String> {
        let edited = if text.trim().is_empty() { None } else { Some(text) };
        self.conn.execute("UPDATE transcripts SET edited_text = ?2 WHERE id = ?1", params![id, edited]).map_err(err)?;
        self.flush_log(); // the replaced edit should not stay readable in the log
        Ok(())
    }

    pub fn delete(&self, id: i64) -> Result<(), String> {
        self.conn.execute("DELETE FROM transcripts WHERE id = ?1", params![id]).map_err(err)?;
        self.flush_log();
        Ok(())
    }

    /// Deletes entries older than `days` (0 = keep until deleted). Returns how many were removed.
    pub fn purge(&self, days: u32) -> Result<usize, String> {
        if days == 0 {
            return Ok(0);
        }
        let cutoff = now_ms() - days as i64 * 86_400_000;
        let n = self.conn.execute("DELETE FROM transcripts WHERE created_at < ?1", params![cutoff]).map_err(err)?;
        if n > 0 {
            self.flush_log();
        }
        Ok(n)
    }

    /// Copies the write-ahead log into the database and empties it, so text that was just deleted or
    /// overwritten (zeroed by secure_delete) does not linger in the -wal file.
    pub(crate) fn flush_log(&self) {
        let _ = self.conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_| Ok(()));
    }

    /// Removes the original transcripts kept alongside the inserted text (when the user turns that option off).
    pub fn forget_raw(&self) -> Result<(), String> {
        self.conn.execute("UPDATE transcripts SET raw_text = NULL", []).map_err(err)?;
        self.flush_log();
        Ok(())
    }

    /// Deletes all history so it cannot be recovered from the database file, its write-ahead log or backups.
    pub fn clear_all(&self) -> Result<(), String> {
        self.conn.execute("DELETE FROM transcripts", []).map_err(err)?;
        self.conn.execute_batch("VACUUM;").map_err(err)?;
        self.conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_| Ok(())).map_err(err)?;
        remove_backups(&self.path);
        Ok(())
    }
}

impl History {
    /// Delete all EsyType data: History, Dictionary, Snippets and notes, so none of it can be recovered from the
    /// database file, its log or upgrade backups.
    pub fn clear_everything(&self) -> Result<(), String> {
        self.conn
            .execute_batch("DELETE FROM transcripts; DELETE FROM dictionary; DELETE FROM snippets; DELETE FROM scratchpad_notes; DELETE FROM usage_days; DELETE FROM usage_apps; VACUUM;")
            .map_err(err)?;
        self.conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_| Ok(())).map_err(err)?;
        remove_backups(&self.path);
        Ok(())
    }

    /// History as CSV or JSON: all entries, or those matching `query`. Returns the text and how many entries.
    pub fn export(&self, query: &str, json: bool) -> Result<(String, usize), String> {
        let (list, _) = self.list(query, i64::MAX, 0)?;
        let rows: Vec<serde_json::Value> = list
            .iter()
            .map(|e| {
                serde_json::json!({
                    "time": iso_utc(e.created_at),
                    "text": e.edited_text.as_deref().unwrap_or(&e.final_text),
                    "inserted": e.final_text,
                    "original": e.raw_text,
                    "mode": e.mode,
                    "style": e.style,
                    "program": e.app,
                    "outcome": e.outcome,
                    "model": e.model,
                    "speech_seconds": e.audio_ms as f64 / 1000.0,
                    "processing_seconds": e.processing_ms as f64 / 1000.0,
                    "undone": e.undone,
                })
            })
            .collect();
        if json {
            return Ok((serde_json::to_string_pretty(&rows).unwrap_or_default(), rows.len()));
        }
        let cols = ["time", "text", "inserted", "original", "mode", "style", "program", "outcome", "model", "speech_seconds", "processing_seconds", "undone"];
        let q = |s: &str| if s.contains([',', '"', '\n', '\r']) { format!("\"{}\"", s.replace('"', "\"\"")) } else { s.to_string() };
        let mut out = format!("\u{feff}{}\r\n", cols.join(",")); // the byte-order mark makes Excel read UTF-8
        for r in &rows {
            let cells: Vec<String> = cols
                .iter()
                .map(|c| match &r[*c] {
                    serde_json::Value::Null => String::new(),
                    serde_json::Value::String(s) => q(s),
                    v => v.to_string(),
                })
                .collect();
            out.push_str(&cells.join(","));
            out.push_str("\r\n");
        }
        Ok((out, rows.len()))
    }
}

/// Unix milliseconds as "2026-11-21T14:30:05Z" (UTC, so exports sort and compare the same everywhere).
pub fn iso_utc(ms: i64) -> String {
    let secs = ms.div_euclid(1000);
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // civil-from-days (Howard Hinnant's algorithm)
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", rem / 3600, rem % 3600 / 60, rem % 60)
}

fn backup_path(db: &Path, version: i64) -> PathBuf {
    db.with_extension(format!("db.bak-v{version}"))
}

/// Upgrade backups exist only briefly; delete-all also removes any left behind by an interrupted upgrade.
fn remove_backups(db: &Path) {
    let (Some(dir), Some(name)) = (db.parent(), db.file_name().and_then(|n| n.to_str())) else { return };
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            if e.file_name().to_string_lossy().starts_with(&format!("{name}.bak-v")) {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_db(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("esytype-history-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("esytype.db")
    }

    #[test]
    fn usage_totals_streak_and_backfill() {
        assert_eq!(streak(&[], 100), 0);
        assert_eq!(streak(&[100, 99, 98, 96], 100), 3);
        assert_eq!(streak(&[99, 98], 100), 2, "nothing yet today keeps yesterday's streak");
        assert_eq!(streak(&[98, 97], 100), 0);
        // an older database: its History becomes the starting totals
        let p = temp_db("usage");
        {
            let c = Connection::open(&p).unwrap();
            for sql in &MIGRATIONS[..6] { c.execute_batch(sql).unwrap(); }
            c.pragma_update(None, "user_version", 6).unwrap();
            c.execute("INSERT INTO transcripts (created_at, final_text, mode, model, audio_ms, processing_ms, outcome, word_count) VALUES (?1, 'one two three', 'clean', 'base', 3000, 1, 'pasted', 3)", params![now_ms()]).unwrap();
        }
        let h = History::open(&p).unwrap();
        let u = h.usage().unwrap();
        assert_eq!((u.words, u.audio_ms, u.dictations, u.streak), (3, 3000, 1, 1));
        h.add_usage(5, 2000, 400, "Chat").unwrap();
        h.clear_all().unwrap(); // clearing History keeps the totals
        let u = h.usage().unwrap();
        assert_eq!((u.words, u.audio_ms, u.dictations, u.streak), (8, 5000, 2, 1));
        h.clear_everything().unwrap(); // Delete all EsyType data removes them
        assert_eq!(h.usage().unwrap().dictations, 0);
    }

    #[test]
    fn app_kinds_backfill_matches_app_kind() {
        let p = temp_db("kinds");
        let mut exes: Vec<&str> = APP_KINDS.iter().flat_map(|(_, l)| l.iter().copied()).collect();
        exes.extend(["ESYTYPE.EXE", "esytype-e2e.exe", "unknown.exe", "WINWORD.EXE"]);
        {
            let c = Connection::open(&p).unwrap();
            for sql in &MIGRATIONS[..6] { c.execute_batch(sql).unwrap(); }
            for (i, e) in exes.iter().enumerate() {
                c.execute("INSERT INTO transcripts (created_at, final_text, mode, model, audio_ms, processing_ms, outcome, app, word_count) VALUES (?1, 'x', 'clean', 'base', 1000, 100, 'pasted', ?2, ?3)", params![now_ms(), e, 1i64 << i]).unwrap();
            }
            c.execute("INSERT INTO transcripts (created_at, final_text, mode, model, audio_ms, processing_ms, outcome, app, word_count) VALUES (?1, 'x', 'clean', 'base', 1000, 100, 'pasted', NULL, 1)", params![now_ms()]).unwrap();
            c.execute_batch(MIGRATIONS[6]).unwrap(); // v7 on a History made before it, as on a real upgrade
            c.pragma_update(None, "user_version", 7).unwrap();
        }
        let h = History::open(&p).unwrap();
        let mut want: std::collections::BTreeMap<&str, i64> = Default::default();
        for (i, e) in exes.iter().enumerate() { *want.entry(app_kind(Some(e))).or_default() += 1i64 << i; }
        *want.entry(app_kind(None)).or_default() += 1;
        let mut st = h.conn.prepare("SELECT kind, sum(words) FROM usage_apps GROUP BY kind").unwrap();
        let got: std::collections::BTreeMap<String, i64> = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(|x| x.unwrap()).collect();
        assert_eq!(got, want.iter().map(|(k, v)| (k.to_string(), *v)).collect(), "the SQL kinds and app_kind() agree");
        assert_eq!(app_kind(Some("esytype-e2e.exe")), "Notes");
        assert_eq!(app_kind(Some("Slack.exe")), "Chat");
        let u = h.usage().unwrap();
        assert_eq!(u.processing_ms, 100 * (exes.len() as i64 + 1), "processing time filled from History");
        h.add_usage(3, 1000, 200, "Email").unwrap();
        let i = h.insights().unwrap();
        assert!(i["apps_week"].as_array().unwrap().iter().any(|a| a["kind"] == "Email" && a["words"] == want["Email"] + 3), "this week: History's Email words and the new 3");
        assert_eq!(i["days"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn export_and_clear_everything() {
        assert_eq!(iso_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso_utc(1_763_735_405_000), "2025-11-21T14:30:05Z");
        assert_eq!(iso_utc(951_782_400_000), "2000-02-29T00:00:00Z");
        let p = temp_db("export");
        let h = History::open(&p).unwrap();
        h.add(Some("um raw"), "Hello, \"you\"\nthere", "clean", "base", 1500, 250, "pasted", Some("WINWORD.EXE")).unwrap();
        h.add(None, "Plain", "verbatim", "base", 1000, 100, "typed", None).unwrap();
        let (csv, n) = h.export("", false).unwrap();
        assert_eq!(n, 2);
        assert!(csv.starts_with("\u{feff}time,text,inserted,original,"));
        assert!(csv.contains("\"Hello, \"\"you\"\"\nthere\""), "quoted, doubled quotes, line break kept: {csv}");
        assert!(csv.contains(",um raw,clean,,WINWORD.EXE,pasted,base,1.5,0.25,false\r\n"), "{csv}");
        assert!(csv.contains("Plain,Plain,,verbatim,,,typed,base,1.0,0.1,false\r\n"), "{csv}");
        let (json, n) = h.export("plain", true).unwrap();
        assert_eq!(n, 1);
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!((v[0]["text"].as_str(), v[0]["original"].is_null()), (Some("Plain"), true));
        h.conn.execute("INSERT INTO scratchpad_notes (body, created_at, updated_at) VALUES ('secret note', 1, 1)", []).unwrap();
        h.clear_everything().unwrap();
        for t in ["transcripts", "dictionary", "snippets", "scratchpad_notes"] {
            let c: i64 = h.conn.query_row(&format!("SELECT COUNT(*) FROM {t}"), [], |r| r.get(0)).unwrap();
            assert_eq!(c, 0, "{t}");
        }
        drop(h);
        assert!(!std::fs::read(&p).unwrap().windows(11).any(|w| w == b"secret note"), "not recoverable from the file");
    }

    #[test]
    fn creates_schema_and_round_trips() {
        let p = temp_db("roundtrip");
        let h = History::open(&p).unwrap();
        let v: i64 = h.conn.pragma_query_value(None, "user_version", |r| r.get(0)).unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
        let id = h.add(Some("hello world"), "Hello world.", "verbatim", "base", 1200, 800, "pasted", Some("WINWORD.EXE")).unwrap();
        h.add(None, "Second note about 50% off", "verbatim", "base", 900, 700, "typed", None).unwrap();
        let (all, total) = h.list("", 50, 0).unwrap();
        assert_eq!((all.len(), total), (2, 2));
        assert_eq!(all[1].id, id); // newest first
        assert_eq!(all[1].word_count, 2);
        assert_eq!(all[0].raw_text, None); // raw retention off for that entry
        assert_eq!(h.list("HELLO", 50, 0).unwrap().1, 1); // case-insensitive
        assert_eq!(h.list("50%", 50, 0).unwrap().1, 1); // % is matched literally
        assert_eq!(h.list("5_%", 50, 0).unwrap().1, 0); // _ is matched literally
        h.edit(id, "Hello, world!").unwrap();
        assert_eq!(h.list("world!", 50, 0).unwrap().0[0].edited_text.as_deref(), Some("Hello, world!"));
        h.edit(id, "  ").unwrap(); // empty edit = undo: back to the inserted text
        assert_eq!(h.list("Hello world.", 50, 0).unwrap().0[0].edited_text, None);
        h.delete(id).unwrap();
        assert_eq!(h.list("", 50, 0).unwrap().1, 1);
        // Reopening an up-to-date database changes nothing
        drop(h);
        assert_eq!(History::open(&p).unwrap().list("", 50, 0).unwrap().1, 1);
    }

    #[test]
    fn retention_and_raw_text_controls() {
        let h = History::open(&temp_db("retention")).unwrap();
        h.add(Some("old"), "Old.", "verbatim", "base", 1, 1, "pasted", None).unwrap();
        h.conn.execute("UPDATE transcripts SET created_at = created_at - 31 * 86400000", []).unwrap();
        h.add(Some("new"), "New.", "verbatim", "base", 1, 1, "pasted", None).unwrap();
        assert_eq!(h.purge(0).unwrap(), 0); // keep until deleted
        assert_eq!(h.purge(90).unwrap(), 0);
        assert_eq!(h.purge(30).unwrap(), 1);
        assert_eq!(h.list("", 50, 0).unwrap().0[0].final_text, "New.");
        h.forget_raw().unwrap();
        assert_eq!(h.list("", 50, 0).unwrap().0[0].raw_text, None);
    }

    #[test]
    fn clear_all_leaves_nothing_behind() {
        let p = temp_db("clear");
        let h = History::open(&p).unwrap();
        h.add(Some("secret words"), "Secret words.", "verbatim", "base", 1, 1, "pasted", None).unwrap();
        std::fs::write(backup_path(&p, 1), b"old backup").unwrap();
        h.clear_all().unwrap();
        assert_eq!(h.list("", 50, 0).unwrap().1, 0);
        assert!(!backup_path(&p, 1).exists(), "backups removed");
        drop(h);
        let bytes = std::fs::read(&p).unwrap();
        let wal = std::fs::read(p.with_extension("db-wal")).unwrap_or_default();
        let find = |b: &[u8]| b.windows(12).any(|w| w == b"secret words");
        assert!(!find(&bytes) && !find(&wal), "deleted text is not recoverable from the files");
    }

    #[test]
    fn removed_text_leaves_no_trace_in_the_files() {
        let p = temp_db("traces");
        let h = History::open(&p).unwrap();
        let keep = h.add(Some("raw zebra phrase"), "Kept entry.", "verbatim", "base", 1, 1, "pasted", None).unwrap();
        let gone = h.add(None, "Delete walrus phrase.", "verbatim", "base", 1, 1, "pasted", None).unwrap();
        h.edit(keep, "First edit badger phrase").unwrap();
        h.edit(keep, "Second edit.").unwrap();
        h.delete(gone).unwrap();
        h.forget_raw().unwrap();
        let files = || [std::fs::read(&p).unwrap(), std::fs::read(p.with_extension("db-wal")).unwrap_or_default()].concat();
        for word in [&b"walrus"[..], b"badger", b"zebra"] {
            assert!(!files().windows(word.len()).any(|w| w == word), "{}", String::from_utf8_lossy(word));
        }
        assert!(files().windows(6).any(|w| w == b"Second"), "the remaining text is still there");
    }

    #[test]
    fn upgrade_from_v1_keeps_history() {
        let p = temp_db("upgrade");
        {
            let c = Connection::open(&p).unwrap();
            c.execute_batch(MIGRATIONS[0]).unwrap();
            c.pragma_update(None, "user_version", 1).unwrap();
            c.execute(
                "INSERT INTO transcripts (created_at, final_text, mode, model, audio_ms, processing_ms, outcome, word_count) VALUES (1, 'kept from v1', 'verbatim', 'base', 1, 1, 'pasted', 3)",
                [],
            )
            .unwrap();
        }
        let h = History::open(&p).unwrap();
        let v: i64 = h.conn.pragma_query_value(None, "user_version", |r| r.get(0)).unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
        assert_eq!(h.list("", 10, 0).unwrap().0[0].final_text, "kept from v1");
        assert!(h.dict_list().unwrap().is_empty());
        assert!(!backup_path(&p, 1).exists(), "upgrade backup removed after success");
    }

    #[test]
    fn upgrade_from_v2_keeps_history_and_dictionary() {
        let p = temp_db("upgrade2");
        {
            let c = Connection::open(&p).unwrap();
            c.execute_batch(MIGRATIONS[0]).unwrap();
            c.execute_batch(MIGRATIONS[1]).unwrap();
            c.pragma_update(None, "user_version", 2).unwrap();
            c.execute(
                "INSERT INTO transcripts (created_at, final_text, mode, model, audio_ms, processing_ms, outcome, word_count) VALUES (1, 'kept from v2', 'clean', 'base', 1, 1, 'pasted', 3)",
                [],
            )
            .unwrap();
            c.execute("INSERT INTO dictionary (kind, term, term_key, created_at, updated_at) VALUES ('word', 'EsyType', 'esytype', 1, 1)", []).unwrap();
        }
        let h = History::open(&p).unwrap();
        let v: i64 = h.conn.pragma_query_value(None, "user_version", |r| r.get(0)).unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
        assert_eq!(h.list("", 10, 0).unwrap().0[0].final_text, "kept from v2");
        assert_eq!(h.dict_list().unwrap()[0].term, "EsyType");
        assert!(h.snip_list().unwrap().is_empty());
        assert!(!backup_path(&p, 2).exists(), "upgrade backup removed after success");
    }

    #[test]
    fn upgrade_from_v3_keeps_everything_and_records_style() {
        let p = temp_db("upgrade3");
        {
            let c = Connection::open(&p).unwrap();
            for m in &MIGRATIONS[..3] {
                c.execute_batch(m).unwrap();
            }
            c.pragma_update(None, "user_version", 3).unwrap();
            c.execute(
                "INSERT INTO transcripts (created_at, final_text, mode, model, audio_ms, processing_ms, outcome, word_count) VALUES (1, 'kept from v3', 'clean', 'base', 1, 1, 'pasted', 3)",
                [],
            )
            .unwrap();
            c.execute("INSERT INTO snippets (trigger, trigger_key, body, mode, created_at, updated_at) VALUES ('my sig', 'my sig', 'Regards', 'whole', 1, 1)", []).unwrap();
        }
        let h = History::open(&p).unwrap();
        let v: i64 = h.conn.pragma_query_value(None, "user_version", |r| r.get(0)).unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
        let old = &h.list("", 10, 0).unwrap().0[0];
        assert_eq!((old.final_text.as_str(), old.style.as_deref()), ("kept from v3", None));
        assert_eq!(h.snip_list().unwrap()[0].body, "Regards");
        h.add_styled(None, "New.", "clean", Some("casual"), "base", 1, 1, "pasted", None).unwrap();
        assert_eq!(h.list("New", 10, 0).unwrap().0[0].style.as_deref(), Some("casual"));
        assert!(!backup_path(&p, 3).exists());
        let id = h.list("New", 10, 0).unwrap().0[0].id;
        assert!(!h.list("New", 10, 0).unwrap().0[0].undone);
        h.mark_undone(id).unwrap();
        assert!(h.list("New", 10, 0).unwrap().0[0].undone, "schema v5: undone mark");
        assert!(h.notes("").unwrap().is_empty(), "schema v6: notes table");
    }

    #[test]
    fn newer_database_is_left_untouched() {
        let p = temp_db("newer");
        let c = Connection::open(&p).unwrap();
        c.pragma_update(None, "user_version", 99).unwrap();
        drop(c);
        let before = std::fs::read(&p).unwrap();
        assert!(History::open(&p).is_err());
        assert_eq!(std::fs::read(&p).unwrap(), before);
    }
}
