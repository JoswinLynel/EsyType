//! User settings, stored as JSON in %LOCALAPPDATA%\EsyAI\EsyType.
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct Settings {
    /// "tiny" | "base" | "small"
    pub model: String,
    /// Input device name; None = Windows default device.
    pub mic: Option<String>,
    /// 0 = automatic.
    pub threads: u32,
    pub ptt: String,
    pub toggle: String,
    /// Where speech models are stored; None = %LOCALAPPDATA%\EsyAI\EsyType\models.
    pub models_dir: Option<String>,
    pub start_with_windows: bool,
    /// Off: dictations are not written to the history database at all.
    pub history_enabled: bool,
    /// Days to keep history; 0 = keep until deleted. The window offers 30, 90 (default) and 0.
    pub history_retention_days: u32,
    /// Store the program's executable name (e.g. WINWORD.EXE) with each entry. Never window titles.
    pub history_record_app: bool,
    /// Keep the engine's original transcript next to the inserted text.
    pub history_keep_raw: bool,
    /// "clean" (rules tidy the text) or "verbatim" (exactly what the engine heard).
    pub text_mode: String,
    /// Clean mode: also remove "you know", "I mean", "like", "sort of", "kind of" when set off by commas.
    pub clean_fillers_extended: bool,
    /// Clean mode: zero to nine as words in plain counts ("three apples").
    pub clean_small_numbers_as_words: bool,
    /// Give the dictionary's words to the speech engine as a hint (initial prompt).
    pub dictionary_hint: bool,
    /// Correct common product names with the built-in list (vocabulary.rs), after the user's own Dictionary.
    pub builtin_vocabulary: bool,
    /// Writing style for programs without a rule: standard, professional, formal, casual, concise or custom.
    pub style_default: String,
    /// Program (executable name) -> style. Matched case-insensitively.
    pub style_rules: Vec<StyleRule>,
    /// What the Custom style changes.
    pub style_custom: crate::clean::Style,
    /// Shortcut for Undo last dictation ("" for none).
    pub undo_shortcut: String,
    /// Shortcut that pastes the last dictation again ("" for none).
    pub paste_last_shortcut: String,
    /// Show Undo (and Use original) on the pill after a dictation.
    pub undo_on_pill: bool,
    /// Programs where Undo is never offered (executable names), besides consoles and terminals.
    pub undo_never: Vec<String>,
    /// First-run setup finished. None = a settings file from before the setup existed (see `settle_setup`).
    pub setup_done: Option<bool>,
    /// "system" (follow Windows' app mode), "dark" or "light". Anything else is treated as "system".
    pub theme: String,
    /// Optional; its first word greets you on the Dictation page. Kept only in this file.
    pub user_name: String,
    /// Your typing speed in words a minute (10-150), for Insights' Time saved.
    pub typing_wpm: u32,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct StyleRule {
    pub app: String,
    pub style: String,
}

pub const STYLES: &[&str] = &["standard", "professional", "formal", "casual", "concise", "custom"];

/// Starter rules (owner decision, 20 Nov 2026); the user can change or delete them.
fn starter_rules() -> Vec<StyleRule> {
    [
        ("OUTLOOK.EXE", "professional"),
        ("olk.exe", "professional"),
        ("WINWORD.EXE", "professional"),
        ("ms-teams.exe", "casual"),
        ("Teams.exe", "casual"),
        ("slack.exe", "casual"),
        ("WhatsApp.exe", "casual"),
        ("Discord.exe", "casual"),
        ("Telegram.exe", "casual"),
        ("Messenger.exe", "casual"),
    ]
    .iter()
    .map(|(a, s)| StyleRule { app: a.to_string(), style: s.to_string() })
    .collect()
}

/// Off: measured 19 Nov 2026 (docs/testing/2026-11-19-dictionary.md), the hint spelled names right far more often but
/// cost ~40% speed, 0.8 points of accuracy on ordinary speech and sometimes inserted a dictionary word wrongly.
pub const DICTIONARY_HINT_DEFAULT: bool = false;

impl Settings {
    /// The style name for a program: its rule, else the default.
    pub fn style_name(&self, exe: Option<&str>) -> String {
        exe.and_then(|e| self.style_rules.iter().find(|r| r.app.eq_ignore_ascii_case(e)))
            .map(|r| r.style.clone())
            .unwrap_or_else(|| self.style_default.clone())
    }

    /// What that style changes; None for Standard.
    pub fn style(&self, name: &str) -> Option<crate::clean::Style> {
        if name == "custom" { Some(self.style_custom) } else { crate::clean::Style::preset(name) }
    }

    pub fn clean(&self) -> Option<crate::clean::Options> {
        (self.text_mode != "verbatim").then_some(crate::clean::Options {
            extended_fillers: self.clean_fillers_extended,
            small_numbers_as_words: self.clean_small_numbers_as_words,
        })
    }
}

impl Default for Settings {
    fn default() -> Self {
        // Shortcuts as specified in the brief, kept by decision 0009 (owner, 21 Nov 2026).
        Self {
            model: "base".into(),
            mic: None,
            threads: 0,
            ptt: "Ctrl+Space".into(),
            toggle: "Ctrl+Shift+Space".into(),
            models_dir: None,
            start_with_windows: true,
            history_enabled: true,
            history_retention_days: 90,
            history_record_app: true,
            history_keep_raw: true,
            text_mode: "clean".into(),
            clean_fillers_extended: false,
            clean_small_numbers_as_words: true,
            dictionary_hint: DICTIONARY_HINT_DEFAULT,
            builtin_vocabulary: true,
            style_default: "standard".into(),
            style_rules: starter_rules(),
            style_custom: crate::clean::Style::default(),
            undo_shortcut: "Ctrl+Alt+Z".into(),
            paste_last_shortcut: "Alt+Shift+Z".into(),
            undo_on_pill: true,
            undo_never: ["WindowsTerminal.exe", "OpenConsole.exe", "mintty.exe", "alacritty.exe", "wezterm-gui.exe", "wsl.exe"].iter().map(|s| s.to_string()).collect(),
            setup_done: None,
            theme: "system".into(),
            user_name: String::new(),
            typing_wpm: 40,
        }
    }
}

/// Decides `setup_done` when it was never recorded: someone who already has a model installed has set EsyType up
/// (existing users never see the wizard); anyone else has not. Returns true when it changed. Kept in memory until the
/// next save, so an older settings file is not rewritten just by starting.
pub fn settle_setup(s: &mut Settings, any_model_installed: bool) -> bool {
    if s.setup_done.is_some() {
        return false;
    }
    s.setup_done = Some(any_model_installed);
    true
}

/// Why a shortcut cannot be used, or None. Checked before a changed shortcut is saved; Windows' own registration
/// check (another program holding it) comes after.
pub fn shortcut_problem(text: &str) -> Option<String> {
    let tokens: Vec<String> = text.split('+').map(|t| t.trim().to_ascii_lowercase()).filter(|t| !t.is_empty()).collect();
    let is_mod = |t: &str| matches!(t, "ctrl" | "control" | "alt" | "option" | "shift");
    if tokens.iter().any(|t| matches!(t.as_str(), "win" | "super" | "meta" | "cmd" | "command")) {
        return Some("Windows keeps most shortcuts with the Windows key for itself. Choose one without it.".into());
    }
    let keys: Vec<&String> = tokens.iter().filter(|t| !is_mod(t)).collect();
    let [key] = keys.as_slice() else {
        return Some("A shortcut needs one key besides Ctrl, Alt or Shift.".into());
    };
    let has = |m: &[&str]| tokens.iter().any(|t| m.contains(&t.as_str()));
    let (ctrl, alt, shift) = (has(&["ctrl", "control"]), has(&["alt", "option"]), has(&["shift"]));
    let function = key.strip_prefix('f').and_then(|n| n.parse::<u8>().ok()).is_some_and(|n| (1..=24).contains(&n));
    if matches!(key.as_str(), "escape" | "esc") {
        return Some("Esc is kept for cancelling a dictation.".into());
    }
    if !function && !ctrl && !alt {
        return Some(if shift { "Shift with a key types capitals and symbols. Add Ctrl or Alt." } else { "A single key would be taken from every program. Add Ctrl or Alt, or use a function key such as F9." }.into());
    }
    let system = (alt && !ctrl && matches!(key.as_str(), "tab" | "f4" | "space")) || (ctrl && alt && matches!(key.as_str(), "delete" | "del"));
    if system {
        return Some(format!("Windows uses {text} itself."));
    }
    None
}

/// One value a settings import or restore would change.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Change {
    pub key: String,
    pub from: serde_json::Value,
    pub to: serde_json::Value,
}

/// A value an import leaves as it is, and why.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Skipped {
    pub key: String,
    pub why: String,
}

/// Settings that belong to this PC: never taken from another PC's file.
const THIS_PC: [&str; 2] = ["mic", "models_dir"];

/// Applies the values of `incoming` (a settings object from an export or a backup) to `current`, one at a time:
/// unreadable and unknown values are skipped and named; this PC's microphone and model folder are kept; a speech
/// model is taken only if it is downloaded here (`installed`). Nothing is saved: the caller shows the changes first.
pub fn import(incoming: &serde_json::Map<String, serde_json::Value>, current: &Settings, installed: impl Fn(&str) -> bool) -> (Settings, Vec<Change>, Vec<Skipped>) {
    let serde_json::Value::Object(mut cur) = serde_json::to_value(current).expect("settings serialize") else { unreachable!() };
    let (mut changes, mut skipped) = (vec![], vec![]);
    let skip = |key: &str, why: &str| Skipped { key: key.into(), why: why.into() };
    for (k, v) in incoming {
        if k == "setup_done" {
            continue;
        }
        let Some(before) = cur.get(k).cloned() else {
            skipped.push(skip(k, "not known to this version of EsyType"));
            continue;
        };
        if before == *v {
            continue;
        }
        if THIS_PC.contains(&k.as_str()) {
            skipped.push(skip(k, "kept: it belongs to this PC"));
            continue;
        }
        let mut trial = cur.clone();
        trial.insert(k.clone(), v.clone());
        if serde_json::from_value::<Settings>(serde_json::Value::Object(trial.clone())).is_err() {
            skipped.push(skip(k, "could not be read"));
            continue;
        }
        if k == "model" && !v.as_str().is_some_and(&installed) {
            skipped.push(skip(k, "that speech model is not downloaded on this PC"));
            continue;
        }
        changes.push(Change { key: k.clone(), from: before, to: v.clone() });
        cur = trial;
    }
    (serde_json::from_value(serde_json::Value::Object(cur)).expect("checked value by value"), changes, skipped)
}

/// The settings object inside an exported settings file; an error in words for anything else.
pub fn parse_export(text: &str) -> Result<serde_json::Map<String, serde_json::Value>, String> {
    let v: serde_json::Value = serde_json::from_str(text.trim_start_matches('\u{feff}')).map_err(|_| "This file is not an EsyType settings file. Nothing was changed.".to_string())?;
    match (v.get("esytype_settings"), v.get("settings")) {
        (Some(_), Some(serde_json::Value::Object(m))) => Ok(m.clone()),
        _ => Err("This file is not an EsyType settings file. Nothing was changed.".into()),
    }
}

/// The data folder is named after the product: "EsyType", or "EsyType Test" for the installer tests' separate product
/// (docs/plans/installer-plan.md, section 6), so those tests never see your data.
pub fn data_dir() -> PathBuf {
    let name = if cfg!(feature = "installer-test") { "EsyType Test" } else { "EsyType" };
    PathBuf::from(std::env::var_os("LOCALAPPDATA").expect("LOCALAPPDATA is set on Windows")).join("EsyAI").join(name)
}

fn file() -> PathBuf {
    data_dir().join("settings.json")
}

/// What went wrong reading settings.json: the settings that went back to their defaults (empty = the whole file could
/// not be read) and where the original was kept. Shown in the window; never written anywhere.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Problem {
    pub reset: Vec<String>,
    pub kept: Option<String>,
}

/// Reads the settings. A missing file gives the defaults. A damaged one never silently becomes the defaults that the
/// next save would write over it: readable values are kept, the rest reset one by one, and the original is copied
/// aside first.
pub fn load() -> (Settings, Option<Problem>) {
    load_from(&file())
}

fn load_from(path: &std::path::Path) -> (Settings, Option<Problem>) {
    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return (Settings::default(), None),
        Err(_) => return (Settings::default(), Some(Problem { reset: vec![], kept: None })),
    };
    if let Ok(s) = serde_json::from_slice::<Settings>(&bytes) {
        return (s, None);
    }
    let (settings, reset) = match serde_json::from_slice::<serde_json::Value>(&bytes) {
        Ok(serde_json::Value::Object(map)) => salvage(map),
        _ => (Settings::default(), vec![]),
    };
    (settings, Some(Problem { reset, kept: keep_damaged(path, &bytes) }))
}

/// Keeps each value that still reads as a setting; returns the names of the ones that do not.
fn salvage(map: serde_json::Map<String, serde_json::Value>) -> (Settings, Vec<String>) {
    let mut good = serde_json::Map::new();
    let mut reset = vec![];
    for (k, v) in map {
        let mut trial = good.clone();
        trial.insert(k.clone(), v.clone());
        if serde_json::from_value::<Settings>(serde_json::Value::Object(trial)).is_ok() {
            good.insert(k, v);
        } else {
            reset.push(k);
        }
    }
    (serde_json::from_value(serde_json::Value::Object(good)).unwrap_or_default(), reset)
}

/// Copies the unreadable file to settings.damaged-<date>-<time>.json beside it; keeps the newest five such copies.
fn keep_damaged(path: &std::path::Path, bytes: &[u8]) -> Option<String> {
    let dir = path.parent()?;
    let c = crate::snippets::Clock::now();
    let stamp = format!("{:04}-{:02}-{:02}-{:02}{:02}", c.year, c.month, c.day, c.hour, c.minute);
    let copy = (1..1000)
        .map(|n| dir.join(if n == 1 { format!("settings.damaged-{stamp}.json") } else { format!("settings.damaged-{stamp}-{n}.json") }))
        .find(|p| !p.exists())?;
    std::fs::write(&copy, bytes).ok()?;
    let mut old: Vec<_> = std::fs::read_dir(dir)
        .ok()?
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with("settings.damaged-"))
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    old.sort();
    for (_, p) in old.iter().rev().skip(5) {
        let _ = std::fs::remove_file(p);
    }
    Some(copy.to_string_lossy().into_owned())
}

pub fn save(s: &Settings) -> Result<(), String> {
    std::fs::create_dir_all(data_dir()).map_err(|e| e.to_string())?;
    let tmp = file().with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(s).unwrap()).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, file()).map_err(|e| e.to_string()) // atomic replace: a crash never leaves half a file
}

/// Threads for whisper.cpp. Automatic = one per physical core, at most all logical processors but one: Whisper's
/// threads wait for each other at every step, so with other programs busy 7 threads on 4 cores took a median 43 s
/// for 10 s of speech, 4 threads 3.5 s (idle 1.8 s against 2.2 s; docs/testing/2026-11-21-whisper-threads.md).
/// Unknown core count: half the logical processors (most PCs have two per core).
pub fn effective_threads(setting: u32, logical: usize, physical: Option<usize>) -> i32 {
    let n = if setting > 0 { (setting as usize).min(logical) } else { physical.unwrap_or(logical / 2).min(logical.saturating_sub(1)) };
    n.max(1) as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    fn damaged_dir(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("esytype-settings-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }
    fn copies(d: &std::path::Path) -> usize {
        std::fs::read_dir(d).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().starts_with("settings.damaged-")).count()
    }

    #[test]
    fn setup_flag_for_existing_and_new_users() {
        let mut s = Settings::default();
        assert!(settle_setup(&mut s, true));
        assert_eq!(s.setup_done, Some(true)); // existing user with a model: no wizard
        let mut s = Settings::default();
        assert!(settle_setup(&mut s, false));
        assert_eq!(s.setup_done, Some(false)); // new user
        assert!(!settle_setup(&mut s, true)); // a recorded answer is kept, even once a model is downloaded
        assert_eq!(s.setup_done, Some(false));
        let old: Settings = serde_json::from_str(r#"{"model":"base","ptt":"Ctrl+F8"}"#).unwrap();
        assert_eq!(old.setup_done, None);
    }

    #[test]
    fn importing_settings() {
        let mut current = Settings::default();
        current.mic = Some("Desk mic".into());
        current.models_dir = Some("D:\\models".into());
        let file = r#"{"esytype_settings":1,"settings":{"ptt":"Ctrl+F8","threads":"three","mic":"Other mic","models_dir":"C:\\x",
            "model":"small","text_mode":"verbatim","future_thing":5,"setup_done":false,"history_retention_days":90}}"#;
        let incoming = parse_export(file).unwrap();
        let (s, changes, skipped) = import(&incoming, &current, |id| id == "base");
        assert_eq!((s.ptt.as_str(), s.text_mode.as_str(), s.threads), ("Ctrl+F8", "verbatim", 0));
        assert_eq!((s.mic.as_deref(), s.models_dir.as_deref(), s.model.as_str()), (Some("Desk mic"), Some("D:\\models"), "base"));
        assert_eq!(s.setup_done, current.setup_done);
        let keys = |v: Vec<String>| v.join(",");
        assert_eq!(keys(changes.iter().map(|c| c.key.clone()).collect()), "ptt,text_mode", "unchanged values are not listed");
        assert_eq!(changes[0].from, serde_json::json!("Ctrl+Space"));
        assert_eq!(
            keys(skipped.iter().map(|x| format!("{}:{}", x.key, &x.why[..6])).collect()),
            "future_thing:not kn,mic:kept: ,model:that s,models_dir:kept: ,threads:could "
        );
        // the same model downloaded here: taken
        let (s, _, _) = import(&incoming, &current, |id| id == "small");
        assert_eq!(s.model, "small");
        // not a settings export
        assert!(parse_export(r#"{"model":"base"}"#).is_err());
        assert!(parse_export("not json").is_err());
        assert!(parse_export(r#"{"esytype_settings":1,"settings":[1]}"#).is_err());
    }

    #[test]
    fn shortcut_rules() {
        for ok in ["Ctrl+Space", "Ctrl+Shift+Space", "Ctrl+Alt+Z", "Alt+Shift+Z", "F9", "F24", "Ctrl+F8", "Ctrl+Alt+D", "Alt+KeyD", "Ctrl+Digit5"] {
            assert_eq!(shortcut_problem(ok), None, "{ok}");
        }
        for bad in ["Space", "A", "Shift+A", "Shift+Space", "Ctrl", "Ctrl+Shift", "Ctrl+A+B", "Win+D", "Super+Space", "Ctrl+Escape", "Esc", "Alt+Tab", "Alt+F4", "Alt+Space", "Ctrl+Alt+Delete", ""] {
            assert!(shortcut_problem(bad).is_some(), "{bad}");
        }
    }

    #[test]
    fn reading_settings() {
        let d = damaged_dir("read");
        let f = d.join("settings.json");
        // missing: defaults, nothing reported
        assert_eq!(load_from(&f), (Settings::default(), None));
        // valid, with an unknown field from a newer version: read as is
        std::fs::write(&f, r#"{"model":"small","ptt":"Ctrl+F8","from_the_future":1}"#).unwrap();
        let (s, p) = load_from(&f);
        assert_eq!((s.model.as_str(), s.ptt.as_str(), p), ("small", "Ctrl+F8", None));
        assert_eq!(copies(&d), 0);
        // one value of the wrong type: only it is reset; the original is copied aside and itself left untouched
        let one = r#"{"model":"small","threads":"3","ptt":"Ctrl+F8","history_enabled":false}"#;
        std::fs::write(&f, one).unwrap();
        let (s, p) = load_from(&f);
        assert_eq!((s.model.as_str(), s.threads, s.ptt.as_str(), s.history_enabled), ("small", 0, "Ctrl+F8", false));
        let p = p.unwrap();
        assert_eq!(p.reset, vec!["threads".to_string()]);
        assert_eq!(std::fs::read_to_string(p.kept.unwrap()).unwrap(), one);
        assert_eq!(std::fs::read_to_string(&f).unwrap(), one);
        // several wrong values
        std::fs::write(&f, r#"{"ptt":5,"model":"tiny","start_with_windows":"yes","undo_never":"x"}"#).unwrap();
        let (s, p) = load_from(&f);
        let mut reset = p.unwrap().reset;
        reset.sort();
        assert_eq!((s.model.as_str(), s.ptt.as_str()), ("tiny", "Ctrl+Space"));
        assert_eq!(reset, vec!["ptt".to_string(), "start_with_windows".to_string(), "undo_never".to_string()]);
        // not JSON, empty, not an object: defaults, the whole file reported and kept
        for bad in ["{\"model\":\"small\",", "", "[1,2]"] {
            std::fs::write(&f, bad).unwrap();
            let (s, p) = load_from(&f);
            let p = p.unwrap();
            assert_eq!((s, p.reset.len()), (Settings::default(), 0));
            assert_eq!(std::fs::read_to_string(p.kept.unwrap()).unwrap(), bad);
        }
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn damaged_copies_are_capped() {
        let d = damaged_dir("cap");
        let f = d.join("settings.json");
        std::fs::write(&f, "not json").unwrap();
        for _ in 0..8 {
            assert!(load_from(&f).1.unwrap().kept.is_some());
        }
        assert_eq!(copies(&d), 5);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn threads() {
        assert_eq!(effective_threads(0, 8, Some(4)), 4); // 4 cores, 8 threads (the dev PC)
        assert_eq!(effective_threads(0, 8, None), 4);
        assert_eq!(effective_threads(0, 4, Some(4)), 3); // no hyper-threading: still one processor left free
        assert_eq!(effective_threads(0, 16, Some(8)), 8);
        assert_eq!(effective_threads(0, 2, Some(1)), 1);
        assert_eq!(effective_threads(0, 1, Some(1)), 1);
        assert_eq!(effective_threads(0, 1, None), 1);
        assert_eq!(effective_threads(4, 8, Some(4)), 4); // a manual choice is kept
        assert_eq!(effective_threads(16, 8, Some(4)), 8);
    }
    #[test]
    fn missing_fields_take_defaults() {
        let s: Settings = serde_json::from_str(r#"{"model":"tiny"}"#).unwrap();
        assert_eq!(s.model, "tiny");
        assert_eq!(s.ptt, "Ctrl+Space");
        assert!(s.history_enabled && s.history_record_app && s.history_keep_raw);
        assert_eq!(s.history_retention_days, 90);
        assert_eq!(s.text_mode, "clean");
        assert_eq!(s.style_default, "standard");
        assert_eq!(s.theme, "system", "older settings files follow Windows' light or dark mode");
        assert_eq!(s.user_name, "", "older settings files have no name");
        assert_eq!(s.style_name(Some("outlook.exe")), "professional", "rules match any case");
        assert_eq!(s.style_name(Some("Slack.exe")), "casual");
        assert_eq!(s.style_name(Some("notepad.exe")), "standard");
        assert_eq!(s.style_name(None), "standard");
        assert!(s.style("standard").is_none() && s.style("formal").is_some_and(|f| f.expand_contractions));
        assert!(!s.clean_fillers_extended && s.clean_small_numbers_as_words);
    }
    #[test]
    fn settings_from_before_history_keep_their_values() {
        // The owner's settings.json as written by the stabilisation build.
        let old = r#"{"model":"base","mic":null,"threads":0,"ptt":"Ctrl+Space","toggle":"Ctrl+Shift+Space","start_with_windows":true,"models_dir":"D:\\EsyAI\\EsyType\\models"}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert_eq!(s.models_dir.as_deref(), Some(r"D:\EsyAI\EsyType\models"));
        assert_eq!((s.model.as_str(), s.threads, s.start_with_windows), ("base", 0, true));
        assert_eq!(s, Settings { models_dir: s.models_dir.clone(), ..Settings::default() });
    }
}
