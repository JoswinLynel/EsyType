//! Scratchpad notes: plain text, saved in the local database (schema v6), kept until the user deletes them.
//! Independent of History: its on/off, retention and delete-all do not touch notes.
use crate::history::{err, now_ms, History};
use rusqlite::params;
use serde::Serialize;

pub const MAX_CHARS: usize = 100_000;
pub const MAX_NOTES: i64 = 1000;

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct Summary {
    pub id: i64,
    /// The first non-empty line, shortened.
    pub title: String,
    pub words: usize,
    pub updated_at: i64,
}

pub fn title(body: &str) -> String {
    let line = body.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or("");
    if line.is_empty() {
        return "Empty note".into();
    }
    let t: String = line.chars().take(60).collect();
    if line.chars().count() > 60 { format!("{t}…") } else { t }
}

impl History {
    /// Newest first; `query` matches anywhere in the text, any case.
    pub fn notes(&self, query: &str) -> Result<Vec<Summary>, String> {
        let like = format!("%{}%", query.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_"));
        let mut st = self
            .conn
            .prepare("SELECT id, body, updated_at FROM scratchpad_notes WHERE body LIKE ?1 ESCAPE '\\' ORDER BY updated_at DESC, id DESC")
            .map_err(err)?;
        let rows = st
            .query_map(params![like], |r| {
                let body: String = r.get(1)?;
                Ok(Summary { id: r.get(0)?, title: title(&body), words: body.split_whitespace().count(), updated_at: r.get(2)? })
            })
            .map_err(err)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(err)
    }

    pub fn note(&self, id: i64) -> Result<String, String> {
        self.conn.query_row("SELECT body FROM scratchpad_notes WHERE id = ?1", params![id], |r| r.get(0)).map_err(err)
    }

    pub fn note_create(&self, body: &str) -> Result<i64, String> {
        let n: i64 = self.conn.query_row("SELECT COUNT(*) FROM scratchpad_notes", [], |r| r.get(0)).map_err(err)?;
        if n >= MAX_NOTES {
            return Err(format!("You have {MAX_NOTES} notes, the most EsyType keeps. Delete some first."));
        }
        check(body)?;
        let now = now_ms();
        self.conn.execute("INSERT INTO scratchpad_notes (body, created_at, updated_at) VALUES (?1, ?2, ?2)", params![body, now]).map_err(err)?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn note_save(&self, id: i64, body: &str) -> Result<(), String> {
        check(body)?;
        let n = self.conn.execute("UPDATE scratchpad_notes SET body = ?2, updated_at = ?3 WHERE id = ?1", params![id, body, now_ms()]).map_err(err)?;
        if n == 0 { Err("That note no longer exists.".into()) } else { Ok(()) }
    }

    pub fn note_delete(&self, id: i64) -> Result<(), String> {
        self.conn.execute("DELETE FROM scratchpad_notes WHERE id = ?1", params![id]).map_err(err)?;
        self.flush_log();
        Ok(())
    }

    pub fn note_clear(&self) -> Result<(), String> {
        self.conn.execute("DELETE FROM scratchpad_notes", []).map_err(err)?;
        self.flush_log();
        Ok(())
    }
}

fn check(body: &str) -> Result<(), String> {
    if body.chars().count() > MAX_CHARS {
        return Err(format!("A note can hold up to {MAX_CHARS} characters. Split it into two notes."));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn titles() {
        assert_eq!(title(""), "Empty note");
        assert_eq!(title("\n\n  Shopping list\nmilk"), "Shopping list");
        assert_eq!(title(&"a".repeat(70)), format!("{}…", "a".repeat(60)));
    }

    #[test]
    fn storage() {
        let dir = std::env::temp_dir().join(format!("esytype-notes-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let h = History::open(&dir.join("esytype.db")).unwrap();
        let a = h.note_create("").unwrap();
        let b = h.note_create("Second note\nwith two lines").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5)); // a later change, not the same millisecond
        h.note_save(a, "First note about tea").unwrap();
        assert_eq!(h.note(a).unwrap(), "First note about tea");
        let l = h.notes("").unwrap();
        assert_eq!(l.len(), 2);
        assert_eq!(l[0].id, a, "newest change first");
        assert_eq!((l[0].title.as_str(), l[0].words), ("First note about tea", 4));
        assert_eq!(h.notes("TWO LINES").unwrap()[0].id, b, "search any case, any line");
        assert_eq!(h.notes("50%").unwrap().len(), 0, "% is matched literally");
        assert!(h.note_save(a, &"x".repeat(MAX_CHARS + 1)).is_err());
        assert!(h.note_save(9999, "x").is_err());
        h.note_delete(b).unwrap();
        assert_eq!(h.notes("").unwrap().len(), 1);
        // History's delete-all and retention leave notes alone
        h.clear_all().unwrap();
        h.purge(1).unwrap();
        assert_eq!(h.notes("").unwrap().len(), 1);
        h.note_clear().unwrap();
        assert!(h.notes("").unwrap().is_empty());
    }
}
