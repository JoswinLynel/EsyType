//! Personal dictionary: words to spell exactly and corrections (heard -> write), stored in the history database
//! (schema v2). Matching is pure and in memory, so a dictation never waits for the database.
use crate::history::{err, now_ms, History};
use rusqlite::params;
use serde::{Deserialize, Serialize};

pub const MAX_LEN: usize = 60;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct Entry {
    #[serde(default)]
    pub id: i64,
    /// "word" or "correction"
    pub kind: String,
    pub term: String,
    #[serde(default)]
    pub replacement: Option<String>,
    #[serde(default)]
    pub uses: i64,
}

/// Checks and tidies an entry before it is stored or imported.
pub fn validate(kind: &str, term: &str, replacement: Option<&str>) -> Result<(String, String, Option<String>), String> {
    let kind = kind.trim().to_lowercase();
    let term = term.split_whitespace().collect::<Vec<_>>().join(" ");
    let replacement = replacement.map(|r| r.split_whitespace().collect::<Vec<_>>().join(" ")).filter(|r| !r.is_empty());
    if term.is_empty() || !term.chars().any(|c| c.is_alphanumeric()) {
        return Err("Enter a word or phrase.".into());
    }
    if term.chars().count() > MAX_LEN || replacement.as_ref().is_some_and(|r| r.chars().count() > MAX_LEN) {
        return Err(format!("Keep each part to {MAX_LEN} characters or fewer."));
    }
    match kind.as_str() {
        "word" => Ok((kind, term, None)),
        "correction" => {
            let r = replacement.ok_or("Enter what to write instead.")?;
            if r == term {
                return Err("The correction is the same as what is heard.".into());
            }
            Ok((kind, term, Some(r)))
        }
        _ => Err(format!("Unknown kind \"{kind}\": use word or correction.")),
    }
}

impl History {
    pub fn dict_list(&self) -> Result<Vec<Entry>, String> {
        let mut st = self.conn.prepare("SELECT id, kind, term, replacement, uses FROM dictionary ORDER BY term_key").map_err(err)?;
        let rows = st
            .query_map([], |r| Ok(Entry { id: r.get(0)?, kind: r.get(1)?, term: r.get(2)?, replacement: r.get(3)?, uses: r.get(4)? }))
            .map_err(err)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(err)
    }

    pub fn dict_add(&self, kind: &str, term: &str, replacement: Option<&str>) -> Result<i64, String> {
        let (kind, term, replacement) = validate(kind, term, replacement)?;
        let now = now_ms();
        match self.conn.execute(
            "INSERT INTO dictionary (kind, term, term_key, replacement, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
            params![kind, term, term.to_lowercase(), replacement, now],
        ) {
            Ok(_) => Ok(self.conn.last_insert_rowid()),
            Err(rusqlite::Error::SqliteFailure(e, _)) if e.code == rusqlite::ErrorCode::ConstraintViolation => Err(format!("\"{term}\" is already in the dictionary.")),
            Err(e) => Err(err(e)),
        }
    }

    pub fn dict_update(&self, id: i64, kind: &str, term: &str, replacement: Option<&str>) -> Result<(), String> {
        let (kind, term, replacement) = validate(kind, term, replacement)?;
        match self.conn.execute(
            "UPDATE dictionary SET kind = ?2, term = ?3, term_key = ?4, replacement = ?5, updated_at = ?6 WHERE id = ?1",
            params![id, kind, term, term.to_lowercase(), replacement, now_ms()],
        ) {
            Ok(_) => Ok(()),
            Err(rusqlite::Error::SqliteFailure(e, _)) if e.code == rusqlite::ErrorCode::ConstraintViolation => Err(format!("\"{term}\" is already in the dictionary.")),
            Err(e) => Err(err(e)),
        }
    }

    pub fn dict_delete(&self, id: i64) -> Result<(), String> {
        self.conn.execute("DELETE FROM dictionary WHERE id = ?1", params![id]).map_err(err)?;
        self.flush_log();
        Ok(())
    }

    pub fn dict_clear(&self) -> Result<(), String> {
        self.conn.execute("DELETE FROM dictionary", []).map_err(err)?;
        self.flush_log();
        Ok(())
    }

    /// Counts that these entries changed a dictation (for the page and the hint's priority).
    pub fn dict_used(&self, ids: &[i64]) -> Result<(), String> {
        let now = now_ms();
        for id in ids {
            self.conn.execute("UPDATE dictionary SET uses = uses + 1, last_used_at = ?2 WHERE id = ?1", params![id, now]).map_err(err)?;
        }
        Ok(())
    }

    /// Adds entries, skipping duplicates and invalid rows. Returns (added, skipped as duplicates, problems).
    pub fn dict_import(&self, entries: &[Entry]) -> Result<(usize, usize, Vec<String>), String> {
        let (mut added, mut dup, mut bad) = (0, 0, vec![]);
        for (k, e) in entries.iter().enumerate() {
            match self.dict_add(&e.kind, &e.term, e.replacement.as_deref()) {
                Ok(_) => added += 1,
                Err(m) if m.ends_with("already in the dictionary.") => dup += 1,
                Err(m) => bad.push(format!("Entry {}: {m}", k + 1)),
            }
        }
        Ok((added, dup, bad))
    }
}

// ---------- import and export ----------

pub fn to_csv(entries: &[Entry]) -> String {
    let q = |s: &str| if s.contains([',', '"', '\n', '\r']) { format!("\"{}\"", s.replace('"', "\"\"")) } else { s.to_string() };
    let mut out = String::from("\u{feff}kind,term,replacement\r\n"); // the byte-order mark makes Excel read UTF-8
    for e in entries {
        out.push_str(&format!("{},{},{}\r\n", e.kind, q(&e.term), q(e.replacement.as_deref().unwrap_or(""))));
    }
    out
}

pub fn to_json(entries: &[Entry]) -> String {
    let plain: Vec<_> = entries.iter().map(|e| serde_json::json!({ "kind": e.kind, "term": e.term, "replacement": e.replacement })).collect();
    serde_json::to_string_pretty(&plain).unwrap_or_default()
}

/// Rows of a CSV file (RFC 4180: quotes, doubled quotes, line breaks inside quotes).
pub(crate) fn csv_rows(text: &str) -> Vec<Vec<String>> {
    let mut rows = vec![];
    let (mut row, mut field, mut quoted) = (vec![], String::new(), false);
    let mut c = text.trim_start_matches('\u{feff}').chars().peekable();
    while let Some(ch) = c.next() {
        match (ch, quoted) {
            ('"', true) if c.peek() == Some(&'"') => {
                field.push('"');
                c.next();
            }
            ('"', true) => quoted = false,
            ('"', false) if field.is_empty() => quoted = true,
            (',', false) => row.push(std::mem::take(&mut field)),
            ('\r', false) => {}
            ('\n', false) => {
                row.push(std::mem::take(&mut field));
                rows.push(std::mem::take(&mut row));
            }
            _ => field.push(ch),
        }
    }
    if !field.is_empty() || !row.is_empty() {
        row.push(field);
        rows.push(row);
    }
    rows.into_iter().filter(|r| r.iter().any(|f| !f.trim().is_empty())).collect()
}

/// Reads CSV with a header (kind,term,replacement; or term,replacement where a filled replacement means a
/// correction) or JSON (a list of {kind, term, replacement}).
pub fn parse_import(text: &str) -> Result<Vec<Entry>, String> {
    let t = text.trim_start_matches('\u{feff}').trim_start();
    if t.starts_with('[') {
        return serde_json::from_str::<Vec<Entry>>(t).map_err(|e| format!("The JSON file could not be read: {e}"));
    }
    let rows = csv_rows(t);
    let header: Vec<String> = rows.first().ok_or("The file is empty.")?.iter().map(|h| h.trim().to_lowercase()).collect();
    let col = |name: &str| header.iter().position(|h| h == name);
    let term = col("term").ok_or("The CSV needs a header row with a \"term\" column (and optionally \"kind\" and \"replacement\").")?;
    let (kind, repl) = (col("kind"), col("replacement"));
    Ok(rows[1..]
        .iter()
        .map(|r| {
            let get = |i: Option<usize>| i.and_then(|i| r.get(i)).map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
            let replacement = get(repl);
            let kind = get(kind).unwrap_or_else(|| if replacement.is_some() { "correction".into() } else { "word".into() });
            Entry { id: 0, kind, term: get(Some(term)).unwrap_or_default(), replacement, uses: 0 }
        })
        .collect())
}

// ---------- matching ----------

struct Rule {
    words: Vec<String>,
    write: String,
    id: i64,
}

/// The dictionary compiled for matching; rebuilt whenever an entry changes.
#[derive(Default)]
pub struct Matcher {
    rules: Vec<Rule>,
    /// Rule indexes by first word, longest phrase first.
    first: std::collections::HashMap<String, Vec<usize>>,
    hint: String,
}

/// Placeholders standing in for matched terms while Clean runs (Unicode private use, treated as words by Clean).
const PLACEHOLDER: u32 = 0xF0000;

fn key_words(s: &str) -> Vec<String> {
    s.split(|c: char| !(c.is_alphanumeric() || c == '\'' || c == '’')).filter(|w| !w.is_empty()).map(|w| w.to_lowercase().replace('’', "'")).collect()
}

/// A word in the text: (start, end, lower-case key).
fn text_words(s: &str) -> Vec<(usize, usize, String)> {
    let mut out = vec![];
    let mut start = None;
    for (i, ch) in s.char_indices().chain([(s.len(), ' ')]) {
        let part = ch.is_alphanumeric() || ch == '\'' || ch == '’';
        match (part, start) {
            (true, None) => start = Some(i),
            (false, Some(st)) => {
                let w = &s[st..i];
                out.push((st, i, w.to_lowercase().replace('’', "'")));
                start = None;
            }
            _ => {}
        }
    }
    out
}

impl Matcher {
    /// Words become spelling rules; corrections map what is heard to what is written. Longest phrases first; for
    /// phrases of the same length, earlier entries first (the user's own before the built-in list).
    /// The hint lists the written forms of the user's own entries, most used first, within Whisper's prompt budget.
    pub fn new(entries: &[Entry]) -> Matcher {
        let mut rules: Vec<Rule> = entries
            .iter()
            .filter_map(|e| {
                let write = if e.kind == "correction" { e.replacement.clone()? } else { e.term.clone() };
                let words = key_words(&e.term);
                (!words.is_empty()).then_some(Rule { words, write, id: e.id })
            })
            .collect();
        rules.sort_by(|a, b| b.words.len().cmp(&a.words.len()));
        let mut first: std::collections::HashMap<String, Vec<usize>> = Default::default();
        for (k, r) in rules.iter().enumerate() {
            first.entry(r.words[0].clone()).or_default().push(k);
            if r.words.len() == 1 {
                first.entry(format!("{}'s", r.words[0])).or_default().push(k); // possessive of a one-word term
            }
        }
        let mut by_use: Vec<&Entry> = entries.iter().filter(|e| e.id >= 0).collect(); // built-in names are not hints
        by_use.sort_by(|a, b| b.uses.cmp(&a.uses).then(b.id.cmp(&a.id)));
        let mut hint = String::new();
        let mut seen = std::collections::HashSet::new();
        for e in by_use {
            let w = if e.kind == "correction" { e.replacement.clone().unwrap_or_default() } else { e.term.clone() };
            // shortcut: Whisper's prompt holds about 224 tokens; 600 characters stays well inside it. Count tokens if
            // users with long dictionaries see the hint cut short.
            if w.is_empty() || !seen.insert(w.to_lowercase()) || hint.len() + w.len() + 2 > 600 {
                continue;
            }
            hint.push_str(if hint.is_empty() { "Glossary: " } else { ", " });
            hint.push_str(&w);
        }
        if !hint.is_empty() {
            hint.push('.');
        }
        Matcher { rules, first, hint }
    }

    /// Text for the speech engine's initial prompt ("" when the dictionary is empty).
    pub fn hint(&self) -> &str {
        &self.hint
    }

    /// Applies the dictionary. With `protect`, matched terms become placeholders (for Clean); `restore` puts the
    /// written forms back. Returns the text, the written forms by placeholder index, and the entries used.
    pub fn apply(&self, text: &str, protect: bool) -> (String, Vec<String>, Vec<i64>) {
        let words = text_words(text);
        let (mut out, mut last, mut written, mut used) = (String::new(), 0usize, vec![], vec![]);
        let mut i = 0;
        while i < words.len() {
            let candidates = self.first.get(&words[i].2).map(|v| v.as_slice()).unwrap_or(&[]);
            let hit = candidates.iter().map(|&k| &self.rules[k]).find(|r| {
                r.words.len() <= words.len() - i
                    && r.words.iter().enumerate().all(|(k, w)| {
                        let tw = &words[i + k].2;
                        // the last word may carry a possessive: "esytype's"
                        tw == w || (k + 1 == r.words.len() && (tw.strip_suffix("'s") == Some(w.as_str())))
                    })
                    // only spaces, hyphens, one comma (the user's own entries only) or a dot inside a name ("node.js")
                    // between the words of a phrase; never a full stop and a space
                    && (1..r.words.len()).all(|k| {
                        let gap = &text[words[i + k - 1].1..words[i + k].0];
                        let commas = if r.id < 0 { 0 } else { 1 }; // built-in names (negative ids) never span a comma
                        gap == "." || (gap.chars().all(|c| c == ' ' || c == '-' || c == ',') && gap.matches(',').count() <= commas)
                    })
            });
            let Some(r) = hit else {
                i += 1;
                continue;
            };
            let (start, end) = (words[i].0, words[i + r.words.len() - 1].1);
            let possessive = words[i + r.words.len() - 1].2.ends_with("'s") && !r.words.last().unwrap().ends_with("'s");
            let mut w = r.write.clone();
            // A written form in lower case starts a sentence with a capital ("kubectl" -> "Kubectl"); mixed case
            // ("iPhone") is kept as entered.
            let sentence_start = text[..start].trim_end().is_empty() || text[..start].trim_end().ends_with(['.', '!', '?', '\n']);
            if sentence_start && w.chars().all(|c| !c.is_uppercase()) {
                let mut c = w.chars();
                w = c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default();
            }
            if possessive {
                let last_word = &text[words[i + r.words.len() - 1].0..end];
                let cut = last_word.char_indices().rev().nth(1).map_or(0, |(p, _)| p);
                w.push_str(&last_word[cut..]); // "'s" with the apostrophe as written
            }
            out.push_str(&text[last..start]);
            if protect {
                out.push(char::from_u32(PLACEHOLDER + written.len() as u32).unwrap_or('\u{FFFD}'));
            } else {
                out.push_str(&w);
            }
            written.push(w);
            if !used.contains(&r.id) {
                used.push(r.id);
            }
            last = end;
            i += r.words.len();
        }
        out.push_str(&text[last..]);
        (out, written, used)
    }
}

/// Puts written forms back in place of placeholders.
pub fn restore(text: &str, written: &[String]) -> String {
    text.chars()
        .map(|c| {
            let k = (c as u32).wrapping_sub(PLACEHOLDER) as usize;
            if (c as u32) >= PLACEHOLDER && k < written.len() { written[k].clone() } else { c.to_string() }
        })
        .collect()
}

pub fn is_placeholder(c: char) -> bool {
    (PLACEHOLDER..PLACEHOLDER + 0xFFFD).contains(&(c as u32))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn e(kind: &str, term: &str, r: Option<&str>) -> Entry {
        Entry { id: 0, kind: kind.into(), term: term.into(), replacement: r.map(Into::into), uses: 0 }
    }

    fn dict() -> Matcher {
        let mut v = vec![
            e("word", "EsyType", None),
            e("word", "Siobhan", None),
            e("word", "iPhone", None),
            e("word", "kubectl", None),
            e("word", "Twenty One Pilots", None),
            e("word", "Dr Okonkwo", None),
            e("correction", "easy type", Some("EsyType")),
            e("correction", "jay son", Some("JSON")),
            e("correction", "new york", Some("New York")),
            e("correction", "new york times", Some("New York Times")),
            e("correction", "shivon", Some("Siobhan")),
        ];
        for (k, x) in v.iter_mut().enumerate() {
            x.id = k as i64 + 1;
        }
        Matcher::new(&v)
    }

    fn run(s: &str) -> String {
        dict().apply(s, false).0
    }

    const CASES: &[(&str, &str)] = &[
        ("I use esytype daily.", "I use EsyType daily."),
        ("ESYTYPE works.", "EsyType works."),
        ("I use easy type daily.", "I use EsyType daily."),
        ("I use easy-type daily.", "I use EsyType daily."),
        ("I use easy, type daily.", "I use EsyType daily."),
        ("Easy type is great.", "EsyType is great."),
        ("easytype is different.", "easytype is different."),
        ("It's easy. Type it.", "It's easy. Type it."),
        ("Send the jay son file.", "Send the JSON file."),
        ("Shivon called.", "Siobhan called."),
        ("I met siobhan.", "I met Siobhan."),
        ("Buy an iphone.", "Buy an iPhone."),
        ("iphone sales rose.", "iPhone sales rose."),
        ("Run kubectl now.", "Run kubectl now."),
        ("kubectl failed.", "Kubectl failed."),
        ("I read the new york times.", "I read the New York Times."),
        ("Esytype’s menu.", "EsyType’s menu."),
        ("I live in new york.", "I live in New York."),
        ("I saw twenty one pilots.", "I saw Twenty One Pilots."),
        ("Ask dr okonkwo.", "Ask Dr Okonkwo."),
        ("Esytype's settings.", "EsyType's settings."),
        ("easy type's menu.", "EsyType's menu."),
        ("The typewriter is easy.", "The typewriter is easy."),
        ("Nothing to change here.", "Nothing to change here."),
        ("", ""),
    ];

    #[test]
    fn matching_table() {
        let bad: Vec<String> = CASES.iter().filter(|(i, w)| run(i) != *w).map(|(i, w)| format!("{i:?}: want {w:?}, got {:?}", run(i))).collect();
        assert!(bad.is_empty(), "{}", bad.join("\n"));
    }

    #[test]
    fn protects_terms_from_clean() {
        let d = dict();
        let (t, written, used) = d.apply("i saw twenty one pilots and paid twenty five pounds.", true);
        let cleaned = crate::clean::apply(&t, &crate::clean::Options::default());
        assert_eq!(restore(&cleaned, &written), "I saw Twenty One Pilots and paid £25.");
        assert_eq!(used, vec![5]);
        let (t, w, _) = d.apply("easy type is fine", true);
        assert_eq!(restore(&crate::clean::apply(&t, &crate::clean::Options::default()), &w), "EsyType is fine");
    }

    #[test]
    fn hint_lists_written_forms_most_used_first() {
        let mut v = vec![e("word", "Siobhan", None), e("correction", "easy type", Some("EsyType")), e("word", "EsyType", None)];
        v[0].uses = 1;
        v[1].uses = 5;
        let m = Matcher::new(&v);
        assert_eq!(m.hint(), "Glossary: EsyType, Siobhan.");
        assert_eq!(Matcher::new(&[]).hint(), "");
        let many: Vec<Entry> = (0..200).map(|k| e("word", &format!("Term{k:03}"), None)).collect();
        assert!(Matcher::new(&many).hint().len() <= 601);
    }

    #[test]
    fn validation() {
        assert!(validate("word", "  EsyType  ", None).is_ok_and(|v| v.1 == "EsyType"));
        assert!(validate("word", "", None).is_err());
        assert!(validate("word", "---", None).is_err());
        assert!(validate("correction", "easy type", None).is_err());
        assert!(validate("correction", "same", Some("same")).is_err());
        assert!(validate("word", &"x".repeat(61), None).is_err());
        assert!(validate("other", "x", None).is_err());
    }

    #[test]
    fn csv_and_json_round_trip() {
        let v = vec![
            e("word", "Café \"Noir\", Ltd", None),
            e("correction", "line\nbreak", Some("Zoë, Ltd")),
            e("correction", "jay son", Some("JSON")),
        ];
        let back = parse_import(&to_csv(&v)).unwrap();
        assert_eq!(back, v);
        assert_eq!(parse_import(&to_json(&v)).unwrap(), v);
        // two-column CSV without kind; blank lines ignored
        let two = parse_import("term,replacement\r\nEsyType,\r\n\r\neasy type,EsyType\r\n").unwrap();
        assert_eq!(two, vec![e("word", "EsyType", None), e("correction", "easy type", Some("EsyType"))]);
        assert!(parse_import("word,thing\nx,y").is_err());
    }

    #[test]
    fn storage_with_duplicates_and_import() {
        let dir = std::env::temp_dir().join(format!("esytype-dict-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let h = History::open(&dir.join("esytype.db")).unwrap();
        let id = h.dict_add("word", "EsyType", None).unwrap();
        assert!(h.dict_add("word", "esytype", None).unwrap_err().contains("already"));
        h.dict_add("correction", "esytype", Some("EsyType")).unwrap(); // a different kind is allowed
        h.dict_update(id, "word", "EsyTypes", None).unwrap();
        h.dict_used(&[id, id]).unwrap();
        let l = h.dict_list().unwrap();
        assert_eq!(l.iter().find(|x| x.id == id).map(|x| (x.term.as_str(), x.uses)), Some(("EsyTypes", 2)));
        let (added, dup, bad) = h.dict_import(&[e("word", "Siobhan", None), e("word", "ESYTYPES", None), e("correction", "x", None)]).unwrap();
        assert_eq!((added, dup, bad.len()), (1, 1, 1));
        h.dict_delete(id).unwrap();
        assert_eq!(h.dict_list().unwrap().len(), 2);
        h.dict_clear().unwrap();
        assert!(h.dict_list().unwrap().is_empty());
        // history is untouched by dictionary operations
        h.add(None, "kept", "clean", "base", 1, 1, "pasted", None).unwrap();
        h.dict_clear().unwrap();
        assert_eq!(h.list("", 10, 0).unwrap().1, 1);
    }

    #[test]
    fn fast_with_a_large_dictionary() {
        let many: Vec<Entry> = (0..1000).map(|k| e("correction", &format!("heard {k} thing"), Some("written"))).collect();
        let m = Matcher::new(&many);
        let text = "This is about sixty seconds of ordinary dictated speech with nothing in the dictionary at all. ".repeat(10);
        // best of three: one run can be slowed by other tests running in parallel or by battery power saving
        let best = (0..3)
            .map(|_| {
                let t = std::time::Instant::now();
                let _ = m.apply(&text, true);
                t.elapsed()
            })
            .min()
            .unwrap();
        assert!(best.as_millis() < 2, "{best:?}");
    }
}
