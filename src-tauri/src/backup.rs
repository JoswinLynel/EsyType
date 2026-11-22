//! Backups (Phase 5, Milestone 3; docs/plans/data-management-plan.md): one `.esytype-backup` file, an SQLite copy of
//! the database made with VACUUM INTO (consistent even while EsyType runs), plus a `backup_info` table holding the
//! settings and what the file contains. Not encrypted; speech models are not included.
//!
//! Restore checks the whole file before anything is touched, makes a safety copy (itself a backup) first, and puts
//! the safety copy back if the replacement fails part-way.
use crate::history::{err, History};
use rusqlite::{params, Connection, OpenFlags};
use serde::Serialize;
use std::path::{Path, PathBuf};

pub const EXT: &str = "esytype-backup";
const SAFETY_KEEP: usize = 3;
const TABLES: [&str; 4] = ["transcripts", "dictionary", "snippets", "scratchpad_notes"];

#[derive(Serialize, Clone, Debug, PartialEq, Default)]
pub struct Counts {
    pub transcripts: i64,
    pub dictionary: i64,
    pub snippets: i64,
    pub notes: i64,
}

#[derive(Serialize, Clone, Debug)]
pub struct Info {
    pub app_version: String,
    pub schema: i64,
    /// Unix time, milliseconds.
    pub made_at: i64,
    pub counts: Counts,
    /// The settings as saved in the backup (JSON object text).
    #[serde(skip)]
    pub settings_json: String,
    /// The speech model the backup's settings use.
    pub model: String,
}

fn counts(conn: &Connection) -> Result<Counts, String> {
    let n = |t: &str| -> Result<i64, String> {
        let exists: i64 = conn.query_row("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1", params![t], |r| r.get(0)).map_err(err)?;
        if exists == 0 { Ok(0) } else { conn.query_row(&format!("SELECT COUNT(*) FROM {t}"), [], |r| r.get(0)).map_err(err) }
    };
    Ok(Counts { transcripts: n(TABLES[0])?, dictionary: n(TABLES[1])?, snippets: n(TABLES[2])?, notes: n(TABLES[3])? })
}

/// Writes a backup of `h` and `settings_json` to `to` (which must not exist yet). Written to a temporary name
/// first, so a half-written file never carries the backup's name.
pub fn make(h: &History, settings_json: &str, to: &Path) -> Result<Counts, String> {
    let part = to.with_extension(format!("{EXT}.partial"));
    let _ = std::fs::remove_file(&part);
    let result = (|| {
        h.conn.execute("VACUUM INTO ?1", params![part.to_string_lossy()]).map_err(err)?;
        let c = Connection::open(&part).map_err(err)?;
        c.pragma_update(None, "journal_mode", "DELETE").map_err(err)?; // one self-contained file
        let schema: i64 = c.pragma_query_value(None, "user_version", |r| r.get(0)).map_err(err)?;
        let counts = counts(&c)?;
        c.execute_batch("CREATE TABLE backup_info (key TEXT PRIMARY KEY, value TEXT NOT NULL);").map_err(err)?;
        let info = [
            ("format", "1".to_string()),
            ("app_version", env!("CARGO_PKG_VERSION").to_string()),
            ("schema", schema.to_string()),
            ("made_at", crate::history::now_ms().to_string()),
            ("counts", serde_json::to_string(&counts).unwrap()),
            ("settings", settings_json.to_string()),
        ];
        for (k, v) in info {
            c.execute("INSERT INTO backup_info (key, value) VALUES (?1, ?2)", params![k, v]).map_err(err)?;
        }
        drop(c);
        std::fs::rename(&part, to).map_err(|e| format!("Could not save the backup: {e}"))?;
        Ok(counts)
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&part);
    }
    result
}

/// Reads and checks a backup without changing it: a readable SQLite file, intact, with backup_info, a schema this
/// EsyType knows, and counts that match its contents.
pub fn read(path: &Path) -> Result<Info, String> {
    let not = "This file is not an EsyType backup, or it is damaged. Nothing was changed.";
    let c = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX).map_err(|_| not.to_string())?;
    let ok: String = c.query_row("PRAGMA integrity_check", [], |r| r.get(0)).map_err(|_| not.to_string())?;
    if ok != "ok" {
        return Err(not.into());
    }
    let get = |k: &str| -> Result<String, String> {
        c.query_row("SELECT value FROM backup_info WHERE key = ?1", params![k], |r| r.get::<_, String>(0)).map_err(|_| not.to_string())
    };
    let schema: i64 = get("schema")?.parse().map_err(|_| not.to_string())?;
    let file_schema: i64 = c.pragma_query_value(None, "user_version", |r| r.get(0)).map_err(|_| not.to_string())?;
    if schema != file_schema {
        return Err(not.into());
    }
    if schema > crate::history::latest_schema() {
        return Err(format!("This backup was made by a newer version of EsyType ({}). Update EsyType to restore it. Nothing was changed.", get("app_version")?));
    }
    let counts: Counts = serde_json::from_str::<serde_json::Value>(&get("counts")?)
        .ok()
        .and_then(|v| Some(Counts { transcripts: v["transcripts"].as_i64()?, dictionary: v["dictionary"].as_i64()?, snippets: v["snippets"].as_i64()?, notes: v["notes"].as_i64()? }))
        .ok_or_else(|| not.to_string())?;
    if counts != self::counts(&c)? {
        return Err(not.into());
    }
    let settings_json = get("settings")?;
    let model = serde_json::from_str::<serde_json::Value>(&settings_json).ok().and_then(|v| v["model"].as_str().map(String::from)).unwrap_or_default();
    Ok(Info { app_version: get("app_version")?, schema, made_at: get("made_at")?.parse().map_err(|_| not.to_string())?, counts, settings_json, model })
}

/// Puts a checked backup's data in place of the database at `db` (whose connection must be closed). The copy is
/// prepared beside it and swapped in at the end; the caller reopens it (which upgrades an older schema).
pub fn replace(backup: &Path, db: &Path) -> Result<(), String> {
    let tmp = db.with_extension("db.restoring");
    let _ = std::fs::remove_file(&tmp);
    std::fs::copy(backup, &tmp).map_err(|e| format!("Could not copy the backup: {e}"))?;
    let prepared = (|| {
        let c = Connection::open(&tmp).map_err(err)?;
        c.execute_batch("DROP TABLE IF EXISTS backup_info;").map_err(err)?;
        Ok::<_, String>(())
    })();
    if let Err(e) = prepared {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    for side in ["db-wal", "db-shm"] {
        let _ = std::fs::remove_file(db.with_extension(side));
    }
    std::fs::rename(&tmp, db).map_err(|e| format!("Could not replace the database: {e}"))
}

pub fn safety_dir() -> PathBuf {
    crate::settings::data_dir().join("before-restore")
}

/// A new safety-copy path in `dir` ("before-restore-<date>-<time>.esytype-backup", numbered if taken).
pub fn safety_path(dir: &Path) -> PathBuf {
    let c = crate::snippets::Clock::now();
    let stamp = format!("{:04}-{:02}-{:02}-{:02}{:02}", c.year, c.month, c.day, c.hour, c.minute);
    (1..1000)
        .map(|n| dir.join(if n == 1 { format!("before-restore-{stamp}.{EXT}") } else { format!("before-restore-{stamp}-{n}.{EXT}") }))
        .find(|p| !p.exists())
        .unwrap_or_else(|| dir.join(format!("before-restore.{EXT}")))
}

/// Safety copies, newest first.
pub fn safety_copies(dir: &Path) -> Vec<PathBuf> {
    let mut list: Vec<_> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().ends_with(&format!(".{EXT}")))
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    list.sort();
    list.into_iter().rev().map(|(_, p)| p).collect()
}

/// Keeps the newest three safety copies.
pub fn prune_safety(dir: &Path) {
    for p in safety_copies(dir).into_iter().skip(SAFETY_KEEP) {
        let _ = std::fs::remove_file(p);
    }
}

/// Removes every safety copy (they hold History text): after Delete all history, and turning off kept originals.
pub fn remove_safety(dir: &Path) {
    for p in safety_copies(dir) {
        let _ = std::fs::remove_file(p);
    }
    let _ = std::fs::remove_dir(dir);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("esytype-backup-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }
    fn fill(h: &History) {
        h.add(Some("raw one"), "First, dictation.", "clean", "base", 1000, 200, "pasted", Some("WINWORD.EXE")).unwrap();
        h.add(None, "Second \"quoted\"\nline", "verbatim", "base", 1000, 200, "pasted", None).unwrap();
        h.conn.execute("INSERT INTO dictionary (kind, term, term_key, created_at, updated_at) VALUES ('word', 'EsyType', 'esytype', 1, 1)", []).unwrap();
        h.conn.execute("INSERT INTO snippets (trigger, trigger_key, body, mode, created_at, updated_at) VALUES ('my sig', 'my sig', 'Regards', 'whole', 1, 1)", []).unwrap();
        h.conn.execute("INSERT INTO scratchpad_notes (body, created_at, updated_at) VALUES ('Note', 1, 1)", []).unwrap();
    }

    #[test]
    fn round_trip_and_safety() {
        let d = dir("roundtrip");
        let db = d.join("esytype.db");
        let h = History::open(&db).unwrap();
        fill(&h);
        let b = d.join(format!("b.{EXT}"));
        let c = make(&h, r#"{"model":"small","ptt":"Ctrl+F8"}"#, &b).unwrap();
        assert_eq!(c, Counts { transcripts: 2, dictionary: 1, snippets: 1, notes: 1 });
        assert!(!b.with_extension(format!("{EXT}.partial")).exists());
        let info = read(&b).unwrap();
        assert_eq!((info.counts.clone(), info.model.as_str(), info.schema), (c.clone(), "small", crate::history::latest_schema()));
        // change the live data, then restore
        h.clear_all().unwrap();
        h.add(None, "after", "clean", "base", 1, 1, "pasted", None).unwrap();
        drop(h);
        replace(&b, &db).unwrap();
        let h = History::open(&db).unwrap();
        assert_eq!(counts(&h.conn).unwrap(), c);
        let has_info: i64 = h.conn.query_row("SELECT COUNT(*) FROM sqlite_master WHERE name = 'backup_info'", [], |r| r.get(0)).unwrap();
        assert_eq!(has_info, 0, "backup_info is not carried into the live database");
        let (list, _) = h.list("", 10, 0).unwrap();
        assert!(list.iter().any(|e| e.final_text == "Second \"quoted\"\nline"));
        // safety copies: newest three kept, all removable
        let sd = d.join("before-restore");
        std::fs::create_dir_all(&sd).unwrap();
        for i in 0..5 {
            std::fs::write(sd.join(format!("before-restore-{i}.{EXT}")), b"x").unwrap();
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        prune_safety(&sd);
        assert_eq!(safety_copies(&sd).len(), 3);
        assert!(safety_copies(&sd)[0].ends_with(format!("before-restore-4.{EXT}")));
        remove_safety(&sd);
        assert!(!sd.exists());
    }

    #[test]
    fn refuses_bad_files() {
        let d = dir("refuse");
        let h = History::open(&d.join("esytype.db")).unwrap();
        fill(&h);
        let b = d.join(format!("b.{EXT}"));
        make(&h, "{}", &b).unwrap();
        // not SQLite at all
        let junk = d.join("junk");
        std::fs::write(&junk, b"hello").unwrap();
        assert!(read(&junk).unwrap_err().contains("not an EsyType backup"));
        // truncated
        let bytes = std::fs::read(&b).unwrap();
        let cut = d.join("cut");
        std::fs::write(&cut, &bytes[..bytes.len() / 2]).unwrap();
        assert!(read(&cut).is_err());
        // an ordinary EsyType database (no backup_info)
        assert!(read(&d.join("esytype.db")).is_err());
        // counts that do not match
        let tampered = d.join("tampered");
        std::fs::copy(&b, &tampered).unwrap();
        Connection::open(&tampered).unwrap().execute("DELETE FROM dictionary", []).unwrap();
        assert!(read(&tampered).is_err());
        // a newer schema
        let newer = d.join("newer");
        std::fs::copy(&b, &newer).unwrap();
        {
            let c = Connection::open(&newer).unwrap();
            c.pragma_update(None, "user_version", 99).unwrap();
            c.execute("UPDATE backup_info SET value = '99' WHERE key = 'schema'", []).unwrap();
        }
        assert!(read(&newer).unwrap_err().contains("newer version"));
        // the original is still fine and unchanged by the reads
        assert_eq!(read(&b).unwrap().counts.dictionary, 1);
    }

    #[test]
    fn older_schema_backup_is_upgraded() {
        let d = dir("older");
        let b = d.join(format!("old.{EXT}"));
        {
            let c = Connection::open(&b).unwrap();
            c.execute_batch(crate::history::migration(0)).unwrap(); // a v1 database: History only
            c.pragma_update(None, "user_version", 1).unwrap();
            c.execute("INSERT INTO transcripts (created_at, final_text, mode, model, audio_ms, processing_ms, outcome, word_count) VALUES (1, 'old', 'clean', 'base', 1, 1, 'pasted', 1)", []).unwrap();
            c.execute_batch("CREATE TABLE backup_info (key TEXT PRIMARY KEY, value TEXT NOT NULL);").unwrap();
            for (k, v) in [("schema", "1"), ("app_version", "0.1.0"), ("made_at", "1"), ("counts", r#"{"transcripts":1,"dictionary":0,"snippets":0,"notes":0}"#), ("settings", "{}")] {
                c.execute("INSERT INTO backup_info VALUES (?1, ?2)", params![k, v]).unwrap();
            }
        }
        assert_eq!(read(&b).unwrap().schema, 1);
        let db = d.join("esytype.db");
        History::open(&db).unwrap();
        replace(&b, &db).unwrap();
        let h = History::open(&db).unwrap();
        let v: i64 = h.conn.pragma_query_value(None, "user_version", |r| r.get(0)).unwrap();
        assert_eq!(v, crate::history::latest_schema());
        assert_eq!(h.list("", 10, 0).unwrap().0[0].final_text, "old");
    }
}
