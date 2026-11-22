//! Snippets: a spoken trigger inserts saved text. Stored in the history database (schema v3); matching is pure
//! and in memory. Snippets match on what the engine heard, before the Dictionary and Clean; the inserted text is
//! protected from both, so it goes in exactly as written (with {date}, {time} and {day} filled in).
use crate::history::{err, now_ms, History};
use rusqlite::params;
use serde::{Deserialize, Serialize};

pub const MAX_TRIGGER: usize = 60;
pub const MAX_BODY: usize = 4000;
pub const MAX_SNIPPETS: i64 = 1000;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct Snippet {
    #[serde(default)]
    pub id: i64,
    pub trigger: String,
    #[serde(alias = "text")]
    pub body: String,
    /// "whole" (the dictation is only the trigger) or "anywhere"
    #[serde(default = "whole")]
    pub mode: String,
    #[serde(default)]
    pub uses: i64,
}

fn whole() -> String {
    "whole".into()
}

/// Lower-case words of a text, without punctuation or fillers ("Um, my e-mail signature." -> my e mail signature).
fn key_words(s: &str) -> Vec<String> {
    s.split(|c: char| !(c.is_alphanumeric() || c == '\'' || c == '’'))
        .filter(|w| !w.is_empty())
        .map(|w| w.to_lowercase().replace('’', "'"))
        .filter(|w| !crate::clean::FILLERS.contains(&w.as_str()))
        .collect()
}

pub fn validate(trigger: &str, body: &str, mode: &str) -> Result<(String, String, String, String), String> {
    let trigger = trigger.split_whitespace().collect::<Vec<_>>().join(" ");
    let body = body.replace("\r\n", "\n");
    let mode = mode.trim().to_lowercase();
    let key = key_words(&trigger);
    if key.is_empty() {
        return Err("Enter a trigger to say.".into());
    }
    if trigger.chars().count() > MAX_TRIGGER {
        return Err(format!("Keep the trigger to {MAX_TRIGGER} characters or fewer."));
    }
    if body.trim().is_empty() {
        return Err("Enter the text to insert.".into());
    }
    if body.chars().count() > MAX_BODY {
        return Err(format!("Keep the text to {MAX_BODY} characters or fewer."));
    }
    match mode.as_str() {
        "whole" => {}
        "anywhere" if key.len() >= 2 => {}
        "anywhere" => return Err("A trigger used anywhere in a sentence needs at least two words, so it cannot fire by accident.".into()),
        _ => return Err(format!("Unknown match \"{mode}\": use whole or anywhere.")),
    }
    Ok((trigger, body, mode, key.join(" ")))
}

impl History {
    pub fn snip_list(&self) -> Result<Vec<Snippet>, String> {
        let mut st = self.conn.prepare("SELECT id, trigger, body, mode, uses FROM snippets ORDER BY trigger_key").map_err(err)?;
        let rows = st
            .query_map([], |r| Ok(Snippet { id: r.get(0)?, trigger: r.get(1)?, body: r.get(2)?, mode: r.get(3)?, uses: r.get(4)? }))
            .map_err(err)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(err)
    }

    pub fn snip_add(&self, trigger: &str, body: &str, mode: &str) -> Result<i64, String> {
        let (trigger, body, mode, key) = validate(trigger, body, mode)?;
        let n: i64 = self.conn.query_row("SELECT COUNT(*) FROM snippets", [], |r| r.get(0)).map_err(err)?;
        if n >= MAX_SNIPPETS {
            return Err(format!("You have {MAX_SNIPPETS} snippets, the most EsyType keeps. Delete some first."));
        }
        let now = now_ms();
        match self.conn.execute(
            "INSERT INTO snippets (trigger, trigger_key, body, mode, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
            params![trigger, key, body, mode, now],
        ) {
            Ok(_) => Ok(self.conn.last_insert_rowid()),
            Err(rusqlite::Error::SqliteFailure(e, _)) if e.code == rusqlite::ErrorCode::ConstraintViolation => Err(format!("A snippet for \"{trigger}\" already exists.")),
            Err(e) => Err(err(e)),
        }
    }

    pub fn snip_update(&self, id: i64, trigger: &str, body: &str, mode: &str) -> Result<(), String> {
        let (trigger, body, mode, key) = validate(trigger, body, mode)?;
        match self.conn.execute(
            "UPDATE snippets SET trigger = ?2, trigger_key = ?3, body = ?4, mode = ?5, updated_at = ?6 WHERE id = ?1",
            params![id, trigger, key, body, mode, now_ms()],
        ) {
            Ok(_) => Ok(()),
            Err(rusqlite::Error::SqliteFailure(e, _)) if e.code == rusqlite::ErrorCode::ConstraintViolation => Err(format!("A snippet for \"{trigger}\" already exists.")),
            Err(e) => Err(err(e)),
        }
    }

    pub fn snip_delete(&self, id: i64) -> Result<(), String> {
        self.conn.execute("DELETE FROM snippets WHERE id = ?1", params![id]).map_err(err)?;
        self.flush_log();
        Ok(())
    }

    pub fn snip_clear(&self) -> Result<(), String> {
        self.conn.execute("DELETE FROM snippets", []).map_err(err)?;
        self.flush_log();
        Ok(())
    }

    pub fn snip_used(&self, ids: &[i64]) -> Result<(), String> {
        let now = now_ms();
        for id in ids {
            self.conn.execute("UPDATE snippets SET uses = uses + 1, last_used_at = ?2 WHERE id = ?1", params![id, now]).map_err(err)?;
        }
        Ok(())
    }

    /// Adds snippets, skipping existing triggers and invalid rows: (added, duplicates, problems).
    pub fn snip_import(&self, list: &[Snippet]) -> Result<(usize, usize, Vec<String>), String> {
        let (mut added, mut dup, mut bad) = (0, 0, vec![]);
        for (k, s) in list.iter().enumerate() {
            match self.snip_add(&s.trigger, &s.body, &s.mode) {
                Ok(_) => added += 1,
                Err(m) if m.ends_with("already exists.") => dup += 1,
                Err(m) => bad.push(format!("Snippet {}: {m}", k + 1)),
            }
        }
        Ok((added, dup, bad))
    }
}

// ---------- import and export ----------

pub fn to_csv(list: &[Snippet]) -> String {
    let q = |s: &str| if s.contains([',', '"', '\n', '\r']) { format!("\"{}\"", s.replace('"', "\"\"")) } else { s.to_string() };
    let mut out = String::from("\u{feff}trigger,mode,text\r\n");
    for s in list {
        out.push_str(&format!("{},{},{}\r\n", q(&s.trigger), s.mode, q(&s.body.replace('\n', "\r\n"))));
    }
    out
}

pub fn to_json(list: &[Snippet]) -> String {
    let plain: Vec<_> = list.iter().map(|s| serde_json::json!({ "trigger": s.trigger, "mode": s.mode, "text": s.body })).collect();
    serde_json::to_string_pretty(&plain).unwrap_or_default()
}

/// CSV with a header (trigger, text, optional mode) or JSON (a list of {trigger, text, mode}).
pub fn parse_import(text: &str) -> Result<Vec<Snippet>, String> {
    let t = text.trim_start_matches('\u{feff}').trim_start();
    if t.starts_with('[') {
        return serde_json::from_str::<Vec<Snippet>>(t).map_err(|e| format!("The JSON file could not be read: {e}"));
    }
    let rows = crate::dictionary::csv_rows(t);
    let header: Vec<String> = rows.first().ok_or("The file is empty.")?.iter().map(|h| h.trim().to_lowercase()).collect();
    let col = |names: &[&str]| header.iter().position(|h| names.contains(&h.as_str()));
    let trigger = col(&["trigger"]).ok_or("The CSV needs a header row with \"trigger\" and \"text\" columns (and optionally \"mode\").")?;
    let body = col(&["text", "body", "expansion"]).ok_or("The CSV needs a \"text\" column.")?;
    let mode = col(&["mode"]);
    Ok(rows[1..]
        .iter()
        .map(|r| {
            let get = |i: Option<usize>| i.and_then(|i| r.get(i)).cloned().unwrap_or_default();
            let m = get(mode).trim().to_lowercase();
            Snippet { id: 0, trigger: get(Some(trigger)).trim().into(), body: get(Some(body)).replace("\r\n", "\n"), mode: if m.is_empty() { whole() } else { m }, uses: 0 }
        })
        .collect())
}

// ---------- placeholders ----------

/// Local date and time, for {date}, {time} and {day}.
#[derive(Clone, Copy, Debug)]
pub struct Clock {
    pub year: u16,
    pub month: u16,
    pub day: u16,
    /// 0 = Sunday
    pub weekday: u16,
    pub hour: u16,
    pub minute: u16,
}

impl Clock {
    pub fn now() -> Clock {
        let t = unsafe { windows::Win32::System::SystemInformation::GetLocalTime() };
        Clock { year: t.wYear, month: t.wMonth, day: t.wDay, weekday: t.wDayOfWeek, hour: t.wHour, minute: t.wMinute }
    }
}

const MONTHS: [&str; 12] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const DAYS: [&str; 7] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

pub fn fill(body: &str, c: &Clock) -> String {
    body.replace("{date}", &format!("{} {} {}", c.day, MONTHS[(c.month.clamp(1, 12) - 1) as usize], c.year))
        .replace("{time}", &format!("{:02}:{:02}", c.hour, c.minute))
        .replace("{day}", DAYS[(c.weekday % 7) as usize])
}

// ---------- matching ----------

/// Snippet text stands in as one of these while the Dictionary and Clean run (Unicode private use, plane 16; the
/// Dictionary uses plane 15).
const PLACEHOLDER: u32 = 0x100000;

pub fn is_placeholder(c: char) -> bool {
    (PLACEHOLDER..PLACEHOLDER + 0xFFFD).contains(&(c as u32))
}

struct Rule {
    words: Vec<String>,
    body: String,
    id: i64,
}

#[derive(Default)]
pub struct Matcher {
    whole: std::collections::HashMap<String, (String, i64)>,
    /// "anywhere" rules by first word, longest first
    anywhere: std::collections::HashMap<String, Vec<Rule>>,
}

impl Matcher {
    pub fn new(list: &[Snippet]) -> Matcher {
        let mut m = Matcher::default();
        for s in list {
            let words = key_words(&s.trigger);
            if words.is_empty() {
                continue;
            }
            if s.mode == "anywhere" {
                m.anywhere.entry(words[0].clone()).or_default().push(Rule { words, body: s.body.clone(), id: s.id });
            } else {
                m.whole.insert(words.join(" "), (s.body.clone(), s.id));
            }
        }
        for v in m.anywhere.values_mut() {
            v.sort_by(|a, b| b.words.len().cmp(&a.words.len()));
        }
        m
    }

    /// Replaces triggers with placeholders. Returns the text, the filled-in snippet texts by placeholder index, and
    /// the snippets used. A whole-dictation trigger replaces the entire dictation.
    pub fn apply(&self, text: &str, clock: &Clock) -> (String, Vec<String>, Vec<i64>) {
        if let Some((body, id)) = self.whole.get(&key_words(text).join(" ")) {
            return (placeholder(0), vec![fill(body, clock)], vec![*id]);
        }
        if self.anywhere.is_empty() {
            return (text.to_string(), vec![], vec![]);
        }
        // words of the text with positions
        let mut words: Vec<(usize, usize, String)> = vec![];
        let mut start = None;
        for (i, ch) in text.char_indices().chain([(text.len(), ' ')]) {
            let part = ch.is_alphanumeric() || ch == '\'' || ch == '’';
            match (part, start) {
                (true, None) => start = Some(i),
                (false, Some(s)) => {
                    words.push((s, i, text[s..i].to_lowercase().replace('’', "'")));
                    start = None;
                }
                _ => {}
            }
        }
        let (mut out, mut last, mut bodies, mut used) = (String::new(), 0, vec![], vec![]);
        let mut i = 0;
        while i < words.len() {
            let hit = self.anywhere.get(&words[i].2).and_then(|rules| {
                rules.iter().find(|r| {
                    r.words.len() <= words.len() - i
                        && r.words.iter().enumerate().all(|(k, w)| &words[i + k].2 == w)
                        && (1..r.words.len()).all(|k| {
                            let gap = &text[words[i + k - 1].1..words[i + k].0];
                            gap.chars().all(|c| c == ' ' || c == '-' || c == ',') && gap.matches(',').count() <= 1
                        })
                })
            });
            let Some(r) = hit else {
                i += 1;
                continue;
            };
            out.push_str(&text[last..words[i].0]);
            out.push_str(&placeholder(bodies.len()));
            bodies.push(fill(&r.body, clock));
            if !used.contains(&r.id) {
                used.push(r.id);
            }
            last = words[i + r.words.len() - 1].1;
            i += r.words.len();
        }
        out.push_str(&text[last..]);
        (out, bodies, used)
    }
}

fn placeholder(k: usize) -> String {
    char::from_u32(PLACEHOLDER + k as u32).unwrap_or('\u{FFFD}').to_string()
}

pub fn restore(text: &str, bodies: &[String]) -> String {
    text.chars()
        .map(|c| {
            let k = (c as u32).wrapping_sub(PLACEHOLDER) as usize;
            if is_placeholder(c) && k < bodies.len() { bodies[k].clone() } else { c.to_string() }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const CLOCK: Clock = Clock { year: 2026, month: 11, day: 20, weekday: 5, hour: 14, minute: 5 };

    fn s(trigger: &str, body: &str, mode: &str) -> Snippet {
        Snippet { id: 0, trigger: trigger.into(), body: body.into(), mode: mode.into(), uses: 0 }
    }

    fn matcher() -> Matcher {
        let mut v = vec![
            s("my email signature", "Kind regards,\nJo Smith\nDirector", "whole"),
            s("my address", "1 High Street\nLondon", "whole"),
            s("today's update", "Update for {date}:", "whole"),
            s("meeting link", "https://meet.example.com/jo", "anywhere"),
            s("meeting link backup", "https://backup.example.com/jo", "anywhere"),
            s("company number", "Company No. 01234567 (UK)", "anywhere"),
        ];
        for (k, x) in v.iter_mut().enumerate() {
            x.id = k as i64 + 1;
        }
        Matcher::new(&v)
    }

    /// The whole pipeline after the engine: snippets, then the Dictionary (none here), Clean, then restore.
    fn run(text: &str) -> String {
        let (t, bodies, _) = matcher().apply(text, &CLOCK);
        let cleaned = crate::clean::apply(&t, &crate::clean::Options::default());
        restore(&cleaned, &bodies)
    }

    const CASES: &[(&str, &str)] = &[
        // whole dictation
        ("My email signature.", "Kind regards,\nJo Smith\nDirector"),
        ("my email signature", "Kind regards,\nJo Smith\nDirector"),
        ("MY EMAIL SIGNATURE!", "Kind regards,\nJo Smith\nDirector"),
        ("Um, my email signature.", "Kind regards,\nJo Smith\nDirector"),
        ("My email, signature.", "Kind regards,\nJo Smith\nDirector"),
        ("My address.", "1 High Street\nLondon"),
        ("Today's update.", "Update for 20 November 2026:"),
        ("Please send my email signature to Sam.", "Please send my email signature to Sam."),
        ("My email signature is out of date.", "My email signature is out of date."),
        ("My address is wrong.", "My address is wrong."),
        ("Address.", "Address."),
        // anywhere
        ("Join us at meeting link today.", "Join us at https://meet.example.com/jo today."),
        ("Meeting link.", "https://meet.example.com/jo."),
        ("Use the meeting link backup if it fails.", "Use the https://backup.example.com/jo if it fails."),
        ("Our company number is on file.", "Our Company No. 01234567 (UK) is on file."),
        ("Meeting, link please.", "https://meet.example.com/jo please."),
        ("The meeting. Link it.", "The meeting. Link it."),
        ("A meetings link.", "A meetings link."),
        // snippet text untouched by Clean, the rest still cleaned
        ("Um, the company number, twenty five pounds.", "The Company No. 01234567 (UK), £25."),
        // more whole-dictation variants
        ("My email signature...", "Kind regards,
Jo Smith
Director"),
        ("Uh, my address.", "1 High Street
London"),
        ("My address?", "1 High Street
London"),
        ("My Address!!", "1 High Street
London"),
        ("my-address", "1 High Street
London"),
        ("  my address  ", "1 High Street
London"),
        ("Er, um, my address.", "1 High Street
London"),
        ("Hmm. My address.", "1 High Street
London"),
        ("Today’s update.", "Update for 20 November 2026:"),
        ("Today's update", "Update for 20 November 2026:"),
        ("My address, please.", "My address, please."),
        ("Todays update.", "Todays update."),
        ("My email signature. My address.", "My email signature. My address."),
        ("my e-mail signature", "My e-mail signature"),
        ("My email.", "My email."),
        ("Signature.", "Signature."),
        // more anywhere cases
        ("Meeting link", "https://meet.example.com/jo"),
        ("MEETING LINK today", "https://meet.example.com/jo today"),
        ("Send the meeting link.", "Send the https://meet.example.com/jo."),
        ("Send the meeting-link.", "Send the https://meet.example.com/jo."),
        ("Join meeting link.", "Join https://meet.example.com/jo."),
        ("meeting link meeting link", "https://meet.example.com/jo https://meet.example.com/jo"),
        ("Is the meeting link backup ready?", "Is the https://backup.example.com/jo ready?"),
        ("Um, meeting link.", "https://meet.example.com/jo."),
        ("i'll share the meeting link.", "I'll share the https://meet.example.com/jo."),
        ("Company number twenty five.", "Company No. 01234567 (UK) 25."),
        ("The meeting linked us.", "The meeting linked us."),
        ("The company numbers are fine.", "The company numbers are fine."),
        ("Link the meeting.", "Link the meeting."),
        // nothing to do
        ("Nothing here.", "Nothing here."),
        ("", ""),
    ];

    #[test]
    fn matching_table() {
        let bad: Vec<String> = CASES.iter().filter(|(i, w)| run(i) != *w).map(|(i, w)| format!("{i:?}\n  want {w:?}\n  got  {:?}", run(i))).collect();
        assert!(bad.is_empty(), "{} of {} wrong:\n{}", bad.len(), CASES.len(), bad.join("\n"));
    }

    #[test]
    fn placeholders() {
        assert_eq!(fill("{day} {date} at {time}", &CLOCK), "Friday 20 November 2026 at 14:05");
        assert_eq!(fill("no placeholders", &CLOCK), "no placeholders");
        let c = Clock { year: 2027, month: 1, day: 3, weekday: 0, hour: 9, minute: 0 };
        assert_eq!(fill("{date} {time} {day}", &c), "3 January 2027 09:00 Sunday");
    }

    #[test]
    fn used_ids() {
        let m = matcher();
        assert_eq!(m.apply("Join meeting link and company number.", &CLOCK).2, vec![4, 6]);
        assert_eq!(m.apply("My address.", &CLOCK).2, vec![2]);
        assert!(m.apply("Nothing.", &CLOCK).2.is_empty());
    }

    #[test]
    fn validation() {
        assert!(validate("my sig", "x", "whole").is_ok());
        assert!(validate("", "x", "whole").is_err());
        assert!(validate("um", "x", "whole").is_err(), "a filler alone is not a trigger");
        assert!(validate("my sig", " ", "whole").is_err());
        assert!(validate("link", "x", "anywhere").is_err(), "one word anywhere is too risky");
        assert!(validate("my link", "x", "anywhere").is_ok());
        assert!(validate("my sig", &"x".repeat(4001), "whole").is_err());
        assert!(validate(&"w ".repeat(31), "x", "whole").is_err());
        assert!(validate("my sig", "x", "sometimes").is_err());
        assert_eq!(validate("  My   Sig ", "a\r\nb", "WHOLE").unwrap(), ("My Sig".into(), "a\nb".into(), "whole".into(), "my sig".into()));
    }

    #[test]
    fn csv_and_json_round_trip() {
        let v = vec![s("my sig", "Kind regards,\n\"Jo\", Ltd", "whole"), s("meeting link", "https://x.example/a,b", "anywhere")];
        assert_eq!(parse_import(&to_csv(&v)).unwrap(), v);
        assert_eq!(parse_import(&to_json(&v)).unwrap(), v);
        let simple = parse_import("trigger,text\nmy sig,Regards\n").unwrap();
        assert_eq!(simple, vec![s("my sig", "Regards", "whole")]);
        assert!(parse_import("name,value\na,b").is_err());
    }

    #[test]
    fn storage() {
        let dir = std::env::temp_dir().join(format!("esytype-snip-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let h = History::open(&dir.join("esytype.db")).unwrap();
        let id = h.snip_add("My signature", "Regards", "whole").unwrap();
        assert!(h.snip_add("my, signature!", "Other", "whole").unwrap_err().contains("already exists"));
        h.snip_update(id, "my sign off", "Regards,\nJo", "whole").unwrap();
        h.snip_used(&[id]).unwrap();
        let l = h.snip_list().unwrap();
        assert_eq!((l[0].trigger.as_str(), l[0].body.as_str(), l[0].uses), ("my sign off", "Regards,\nJo", 1));
        let (a, d, b) = h.snip_import(&[s("meeting link", "x", "anywhere"), s("My sign off", "y", "whole"), s("link", "z", "anywhere")]).unwrap();
        assert_eq!((a, d, b.len()), (1, 1, 1));
        h.snip_delete(id).unwrap();
        assert_eq!(h.snip_list().unwrap().len(), 1);
        h.snip_clear().unwrap();
        assert!(h.snip_list().unwrap().is_empty());
    }

    #[test]
    fn fast_with_many_snippets() {
        let many: Vec<Snippet> = (0..1000).map(|k| s(&format!("trigger number {k} please"), "x", if k % 2 == 0 { "whole" } else { "anywhere" })).collect();
        let m = Matcher::new(&many);
        let text = "This is about sixty seconds of ordinary dictated speech with no trigger in it at all. ".repeat(10);
        // best of three: one run can be slowed by other tests running in parallel or by battery power saving
        let best = (0..3)
            .map(|_| {
                let t = std::time::Instant::now();
                let _ = m.apply(&text, &CLOCK);
                t.elapsed()
            })
            .min()
            .unwrap();
        assert!(best.as_millis() < 2, "{best:?}");
    }
}
