#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
//! EsyType: hold a shortcut, speak, release; the words are transcribed locally and typed where you were.
/// Timestamped event log, compiled into test builds only. Defined before the modules so they can use it.
macro_rules! trace {
    ($($a:tt)*) => {
        #[cfg(feature = "e2e")]
        eprintln!("[{:?}] {}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() % 100_000, format!($($a)*));
    };
}

mod audio;
mod clean;
mod dictionary;
mod vocabulary;
mod snippets;
mod undo;
mod hardware;
mod backup;
mod history;
mod insert;
mod caret;
mod notes;
mod models;
mod settings;
mod stt;

use serde_json::json;
use settings::Settings;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

/// Presses shorter than this are treated as accidental taps and discarded.
const MIN_HOLD: Duration = Duration::from_millis(400);

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Hold,
    Toggle,
}

struct Dictation {
    recording: audio::Recording,
    mode: Mode,
    started: Instant,
    target: isize,
    /// Executable name of the target program, only when the user allows it.
    exe: Option<String>,
    /// Executable name used to choose the writing style; read at the start, never stored.
    program: Option<String>,
}

struct Shared {
    settings: Mutex<Settings>,
    keys: Mutex<(Shortcut, Shortcut)>,
    engine: stt::Engine,
    loaded: Mutex<Option<String>>,
    dictation: Mutex<Option<Dictation>>,
    busy: AtomicBool,
    downloading: Mutex<Option<String>>,
    cancel_download: Arc<AtomicBool>,
    last: Mutex<serde_json::Value>,
    /// Window and time of the last insertion, to space consecutive dictations apart.
    last_insert: Mutex<Option<(isize, Instant)>>,
    /// None when the database could not be opened; dictation works without it.
    history: Mutex<Option<history::History>>,
    history_error: Mutex<Option<String>>,
    /// The dictionary, compiled for matching; dictation never reads the database for it.
    dict: Mutex<dictionary::Matcher>,
    /// Snippets, compiled for matching, likewise.
    snippets: Mutex<snippets::Matcher>,
    /// The tray's "Clean mode" tick, kept in step with the window's setting.
    tray_clean: Mutex<Option<tauri::menu::CheckMenuItem<tauri::Wry>>>,
    /// Set while EsyType waits for the page to save before quitting.
    flush: Mutex<Option<std::sync::mpsc::Sender<()>>>,
    /// What Undo needs about the last dictation; in memory only.
    last_undo: Mutex<Option<undo::Last>>,
    /// Undo and Paste last shortcuts (None when not set or not available).
    extra_keys: Mutex<(Option<Shortcut>, Option<Shortcut>)>,
    /// settings.json could not be read in full at start-up; shown until dismissed.
    settings_problem: Mutex<Option<settings::Problem>>,
    /// Bumped on every pause or resume of the shortcuts, so a stale 20-second restore does nothing.
    pause_gen: AtomicU64,
    mic_testing: AtomicBool,
    /// The tray shows the recording dot.
    tray_recording: AtomicBool,
    /// Bumped each time the pill shows a new state, so a hide timer from an earlier state does nothing.
    pill_gen: AtomicU64,
}

fn escape() -> Shortcut {
    "Escape".parse().unwrap()
}

/// The bundled Silero voice activity model: next to the executable in builds, in src-tauri during development.
fn vad_model() -> Option<std::path::PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    [dir.join("resources/ggml-silero-v6.2.0.bin"), dir.join("../../resources/ggml-silero-v6.2.0.bin")].into_iter().find(|p| p.exists())
}

fn logical() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1)
}

fn physical() -> Option<usize> {
    sysinfo::System::physical_core_count().ok()
}

// ---------- recording pill ----------

/// Pill states during which the tray icon shows the red recording dot.
fn tray_recording(state: &str) -> bool {
    matches!(state, "listening" | "recording" | "processing" | "inserting")
}

fn set_tray(app: &AppHandle, state: &str) {
    #[cfg(feature = "e2e")]
    if std::env::var_os("ESYTYPE_TEST_NO_TRAY").is_some() {
        return; // timing comparisons: the dictation path without the tray change
    }
    let rec = tray_recording(state);
    if app.state::<Shared>().tray_recording.swap(rec, Ordering::SeqCst) == rec {
        return;
    }
    // Queued on the main thread: the dictation thread never waits for the tray.
    let a = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(t) = a.tray_by_id("main") {
            let icon = if rec { Some(tauri::include_image!("icons/tray-recording.png")) } else { a.default_window_icon().cloned() };
            let _ = t.set_icon(icon);
            let _ = t.set_tooltip(Some(if rec { "EsyType · Recording" } else { TRAY_TIP }));
        }
        trace!("tray: {}", if rec { "recording" } else { "rest" });
    });
}

const TRAY_TIP: &str = "EsyType: hold your shortcut to dictate";

fn pill(app: &AppHandle, state: &str, message: &str) {
    set_tray(app, state);
    if state != "hidden" {
        app.state::<Shared>().pill_gen.fetch_add(1, Ordering::SeqCst);
    }
    if let Some(w) = app.get_webview_window("pill") {
        let _ = w.emit("pill", json!({ "state": state, "message": message }));
        // Shown without activating (so the caret stays in the user's document) and hidden with the same raw
        // Win32 call: Tauri does not know the window was shown, so its own hide() would do nothing.
        if let Ok(h) = w.hwnd() {
            use windows::Win32::UI::WindowsAndMessaging::{ShowWindow, SW_HIDE, SW_SHOWNOACTIVATE};
            let cmd = if state == "hidden" { SW_HIDE } else { SW_SHOWNOACTIVATE };
            unsafe {
                let _ = ShowWindow(windows::Win32::Foundation::HWND(h.0 as _), cmd);
            }
        }
    }
}

/// Hides the pill after `ms`, unless it has shown anything since (a later dictation keeps its own pill and timer).
fn hide_pill_after(app: &AppHandle, ms: u64) {
    let app = app.clone();
    let gen = app.state::<Shared>().pill_gen.load(Ordering::SeqCst);
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(ms));
        let s = app.state::<Shared>();
        if s.pill_gen.load(Ordering::SeqCst) == gen && s.dictation.lock().unwrap().is_none() && !s.busy.load(Ordering::SeqCst) {
            pill(&app, "hidden", "");
        }
    });
}

/// Light or dark for the main window. WebView2 takes its colour scheme from the window, so the page's
/// `prefers-color-scheme` follows, and so does the title bar. "system" follows Windows' app mode, also when it changes.
fn apply_theme(app: &AppHandle, theme: &str) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_theme(match theme { "dark" => Some(tauri::Theme::Dark), "light" => Some(tauri::Theme::Light), _ => None });
    }
}

/// Windows' "Transparency effects" switch (Settings > Personalisation > Colours), which also goes off in battery saver.
/// The window uses frosted glass only while it is on.
/// Small things the window remembers between launches (last page, last Settings section, folded banners), kept in
/// EsyType's data folder rather than the webview's storage, so each profile has its own.
fn ui_state_path() -> std::path::PathBuf {
    settings::data_dir().join("ui-state.json")
}
static UI_STATE: Mutex<()> = Mutex::new(());

#[tauri::command]
fn ui_state() -> serde_json::Value {
    let _g = UI_STATE.lock();
    std::fs::read_to_string(ui_state_path()).ok().and_then(|s| serde_json::from_str(&s).ok()).filter(|v: &serde_json::Value| v.is_object()).unwrap_or_else(|| json!({}))
}

#[tauri::command]
fn ui_remember(key: String, value: String) -> Result<(), String> {
    if key.len() > 64 || value.len() > 256 {
        return Err("Too long.".into());
    }
    let mut v = ui_state();
    let _g = UI_STATE.lock();
    v[key] = json!(value);
    let p = ui_state_path();
    let tmp = p.with_extension("json.tmp");
    std::fs::write(&tmp, v.to_string()).and_then(|_| std::fs::rename(&tmp, &p)).map_err(|e| e.to_string())
}

/// Whether Windows' microphone privacy switches let desktop apps use the microphone (Settings, Privacy, Microphone).
/// A missing value means Windows has not been asked to block it.
#[tauri::command]
fn microphone_allowed() -> bool {
    use windows::core::{HSTRING, PCWSTR};
    use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_SZ};
    let read = |key: &str| -> Option<String> {
        let mut buf = [0u16; 32];
        let mut n = std::mem::size_of_val(&buf) as u32;
        let k = HSTRING::from(key);
        let r = unsafe { RegGetValueW(HKEY_CURRENT_USER, PCWSTR(k.as_ptr()), windows::core::w!("Value"), RRF_RT_REG_SZ, None, Some(buf.as_mut_ptr() as *mut _), Some(&mut n)) };
        r.is_ok().then(|| String::from_utf16_lossy(&buf[..(n as usize / 2).saturating_sub(1)]))
    };
    let base = r"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
    [read(base), read(&format!(r"{base}\NonPackaged"))].iter().all(|v| v.as_deref() != Some("Deny"))
}

#[tauri::command]
fn open_mic_privacy() -> Result<(), String> {
    std::process::Command::new("explorer.exe").arg("ms-settings:privacy-microphone").spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
fn transparency_effects() -> bool {
    // Test builds only: lets the theme test see the solid fallback without touching the Windows setting.
    #[cfg(feature = "e2e")]
    if let Ok(v) = std::env::var("ESYTYPE_TEST_TRANSPARENCY") {
        return v != "0";
    }
    use windows::core::w;
    use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD};
    let mut v: u32 = 1;
    let mut n = std::mem::size_of::<u32>() as u32;
    let r = unsafe {
        RegGetValueW(HKEY_CURRENT_USER, w!(r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"), w!("EnableTransparency"),
            RRF_RT_REG_DWORD, None, Some(&mut v as *mut u32 as *mut _), Some(&mut n))
    };
    r.is_err() || v != 0 // no value recorded: Windows' default, which is on
}

fn create_pill(app: &AppHandle) -> tauri::Result<()> {
    let (w, h) = (320.0, 64.0);
    let win = WebviewWindowBuilder::new(app, "pill", WebviewUrl::App("pill.html".into()))
        .title("EsyType recording")
        .inner_size(w, h)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .focusable(false)
        .focused(false) // never take focus, not even when Windows starts EsyType at login
        .visible(false)
        .build()?;
    // Clicking (or pressing through accessibility tools) a button on the pill must not activate it: the keys that
    // Undo sends belong to the window the user dictated into.
    if let Ok(h) = win.hwnd() {
        use windows::Win32::UI::WindowsAndMessaging::{GetWindowLongPtrW, SetWindowLongPtrW, GWL_EXSTYLE, WS_EX_NOACTIVATE};
        unsafe {
            let ex = GetWindowLongPtrW(windows::Win32::Foundation::HWND(h.0 as _), GWL_EXSTYLE);
            SetWindowLongPtrW(windows::Win32::Foundation::HWND(h.0 as _), GWL_EXSTYLE, ex | WS_EX_NOACTIVATE.0 as isize);
        }
    }
    if let Some(m) = win.primary_monitor()? {
        let sf = m.scale_factor();
        let area = m.work_area();
        let x = area.position.x + ((area.size.width as f64 - w * sf) / 2.0) as i32;
        let y = area.position.y + area.size.height as i32 - ((h + 24.0) * sf) as i32;
        win.set_position(tauri::PhysicalPosition::new(x, y))?;
    }
    Ok(())
}

// ---------- dictation pipeline ----------

/// `pressed` is when the shortcut went down: hold length counts from there, not from when recording got going.
fn start(app: &AppHandle, mode: Mode, pressed: Instant) {
    trace!("start");
    let s = app.state::<Shared>();
    if s.busy.load(Ordering::SeqCst) || s.dictation.lock().unwrap().is_some() {
        return;
    }
    if s.loaded.lock().unwrap().is_none() {
        pill(app, "error", "No speech model is ready yet. Open EsyType to choose one.");
        hide_pill_after(app, 3500);
        return;
    }
    let target = insert::foreground();
    pill(app, "listening", "");
    let mic = s.settings.lock().unwrap().mic.clone();
    let (a1, a2) = (app.clone(), app.clone());
    match audio::start(mic, move |l| { let _ = a1.emit_to("pill", "level", l); }, move || pill(&a2, "recording", "")) {
        Ok(recording) => {
            if recording.fell_back {
                trace!("microphone fallback");
                let _ = app.emit_to("pill", "note", "Chosen microphone not found: using the Windows default");
            }
            let program = insert::process_name(target);
            let exe = if s.settings.lock().unwrap().history_record_app { program.clone() } else { None };
            *s.dictation.lock().unwrap() = Some(Dictation { recording, mode, started: pressed, target, exe, program });
            let _ = app.global_shortcut().register(escape());
        }
        Err(e) => {
            pill(app, "error", &e);
            hide_pill_after(app, 4000);
        }
    }
}

fn take(app: &AppHandle) -> Option<Dictation> {
    let d = app.state::<Shared>().dictation.lock().unwrap().take();
    if d.is_some() {
        let _ = app.global_shortcut().unregister(escape());
    }
    d
}

fn cancel(app: &AppHandle) {
    trace!("cancel");
    if let Some(d) = take(app) {
        std::thread::spawn(move || drop(d.recording.finish()));
        pill(app, "hidden", "");
    }
}

fn stop(app: &AppHandle) {
    trace!("stop");
    let Some(d) = take(app) else { return };
    let s = app.state::<Shared>();
    s.busy.store(true, Ordering::SeqCst);
    pill(app, "processing", "");
    let app = app.clone();
    std::thread::spawn(move || {
        let s = app.state::<Shared>();
        let mut save = None;
        let mut style_used: Option<String> = None;
        #[allow(clippy::type_complexity)]
        let result = (|| -> Result<Option<(String, insert::Outcome, f64, f64, Option<String>, Option<String>)>, String> {
            let pcm = d.recording.finish()?;
            let audio_s = pcm.len() as f64 / 16000.0;
            let t = Instant::now();
            let hint = if s.settings.lock().unwrap().dictionary_hint { s.dict.lock().unwrap().hint().to_string() } else { String::new() };
            let raw = s.engine.transcribe(pcm, &hint)?;
            let secs = t.elapsed().as_secs_f64();
            if raw.is_empty() {
                return Ok(None);
            }
            // Clean mode tidies the text; the engine's original is kept for History and the pill's Original button.
            // Snippets match what was heard, then the Dictionary (in both modes); snippet text and dictionary terms
            // are protected from Clean's rules and put back at the end.
            let clean = s.settings.lock().unwrap().clean();
            let (snip_text, bodies, snip_used) = s.snippets.lock().unwrap().apply(&raw, &snippets::Clock::now());
            let (dict_text, written, used) = s.dict.lock().unwrap().apply(&snip_text, clean.is_some());
            // The writing style for this program (Clean mode only); Standard changes nothing beyond Clean.
            let text = match &clean {
                Some(o) => {
                    let st = s.settings.lock().unwrap().clone();
                    let name = st.style_name(d.program.as_deref());
                    let styled = clean::apply_styled(&dict_text, o, st.style(&name).as_ref());
                    style_used = Some(name);
                    dictionary::restore(&styled, &written)
                }
                None => dict_text,
            };
            let text = snippets::restore(&text, &bodies);
            // A snippet's {cursor}: the marker is removed and the caret moved back to it after a confirmed paste.
            let (text, cursor_back) = match text.find("{cursor}") {
                Some(i) => {
                    let after = text[i + 8..].replace("{cursor}", "");
                    (format!("{}{after}", &text[..i]), undo::cursor_steps(&after))
                }
                None => (text, None),
            };
            if text.is_empty() {
                return Err("Nothing left to type: Clean mode removed it all (for example after \"scratch that\").".into());
            }
            let mode = if clean.is_some() { "clean" } else { "verbatim" };
            pill(&app, "inserting", "");
            trace!("insert {} chars", text.len());
            // A leading space when the character before the cursor needs one (text typed by hand included). If the
            // app does not let EsyType read it, only when directly continuing EsyType's own dictation in that window:
            // within the input watch's minute, with no key press or click in between (one would mean the cursor may
            // have moved or a space been typed: then no space, never a doubled one). The shortcut press that started
            // this dictation is itself recorded, hence the margin.
            let follows = matches!(*s.last_insert.lock().unwrap(), Some((w, t)) if w == d.target && t.elapsed() < undo::MAX_AGE)
                && undo::watching()
                && undo::first_user_input().is_none_or(|t| t + Duration::from_millis(300) >= d.started);
            let before = caret::before_cursor(d.target);
            trace!("before the cursor: {}", match before { None => "cannot read", Some(None) => "start", Some(Some(c)) if c.is_whitespace() => "space or line break", Some(Some(_)) => "a character" });
            let spaced = if caret::needs_space(before, follows, &text) { format!(" {text}") } else { text };
            // An insertion error is reported like an unconfirmed paste: the text is kept and offered for copying.
            let (outcome, why) = match insert::insert(&spaced, d.target) {
                Ok(o) => (o, None),
                Err(e) => (insert::Outcome::Failed, Some(e)),
            };
            let text = spaced.trim().to_string();
            // Saved to history whatever the outcome, so the words are not lost.
            let original = (text != raw).then(|| raw.clone());
            if matches!(outcome, insert::Outcome::Pasted | insert::Outcome::Typed) {
                *s.last_insert.lock().unwrap() = Some((d.target, Instant::now()));
                if outcome == insert::Outcome::Pasted && insert::foreground() == d.target {
                    if let Some(n) = cursor_back.filter(|n| *n > 0) {
                        let _ = insert::press_left(n);
                    }
                }
                *s.last_undo.lock().unwrap() = Some(undo::Last {
                    target: d.target,
                    ended: Instant::now(),
                    undoable: true,
                    typed: outcome == insert::Outcome::Typed,
                    program: d.program.clone(),
                    console: insert::is_console(d.target),
                    raw: raw.clone(),
                    text: text.clone(),
                    leading_space: spaced.starts_with(' '),
                    history_id: None,
                });
                undo::watch();
            } else {
                *s.last_undo.lock().unwrap() = None;
            }
            save = Some((raw, text.clone(), format!("{outcome:?}").to_lowercase(), mode, secs, audio_s, used, snip_used));
            trace!("inserted {:?}", outcome);
            Ok(Some((text, outcome, secs, audio_s, why, original)))
        })();
        s.busy.store(false, Ordering::SeqCst);
        match result {
            Ok(Some((text, outcome, secs, audio_s, why, original))) => {
                let cleaned = original.is_some();
                let v = json!({ "text": text, "outcome": outcome, "seconds": secs, "audio_seconds": audio_s, "original": original });
                *s.last.lock().unwrap() = v.clone();
                let _ = app.emit("transcript", v);
                if outcome == insert::Outcome::Copied {
                    pill(&app, "error", "You switched windows, so nothing was typed. The text is copied: press Ctrl+V.");
                    hide_pill_after(&app, 5000);
                } else if outcome == insert::Outcome::Failed {
                    // The user's clipboard is untouched; copying is their choice (the pill's Copy button).
                    trace!("not confirmed: {why:?}");
                    pill(&app, "unsure", why.as_deref().unwrap_or("The app didn't take the text."));
                    hide_pill_after(&app, 10_000);
                } else {
                    let offer = undo_offered(&app);
                    trace!("undo offered on the pill: {offer}");
                    let _ = app.emit_to("pill", "actions", json!({ "undo": offer }));
                    if cleaned {
                        pill(&app, "cleaned", &style_label(style_used.as_deref())); // offers the original for a few seconds
                        hide_pill_after(&app, 6000);
                    } else {
                        pill(&app, "done", &style_label(style_used.as_deref()));
                        hide_pill_after(&app, if offer { 5000 } else { 700 });
                    }
                }
            }
            Ok(None) => {
                pill(&app, "error", "No speech heard.");
                hide_pill_after(&app, 2000);
            }
            Err(e) => {
                pill(&app, "error", &e);
                hide_pill_after(&app, 5000);
            }
        }
        // Last, after the user has their text and EsyType is ready again: a slow or locked database waits here.
        if let Some((raw, text, name, mode, secs, audio_s, used, snip_used)) = save {
            let id = record(&app, &raw, &text, &name, mode, style_used.as_deref(), secs, audio_s, d.exe.as_deref(), &used, &snip_used);
            if let Some(l) = s.last_undo.lock().unwrap().as_mut().filter(|l| l.text == text) {
                l.history_id = id;
            }
        }
    });
}

/// "Casual" for the pill; nothing for Standard or Verbatim.
fn style_label(name: Option<&str>) -> String {
    match name {
        Some(n) if n != "standard" => n[..1].to_uppercase() + &n[1..],
        _ => String::new(),
    }
}

/// Writes a finished dictation to history when history is on. A database problem is logged and shown in the
/// window, never passed back to the dictation.
#[allow(clippy::too_many_arguments)]
fn record(app: &AppHandle, raw: &str, final_text: &str, outcome: &str, mode: &str, style: Option<&str>, secs: f64, audio_s: f64, exe: Option<&str>, used: &[i64], snip_used: &[i64]) -> Option<i64> {
    let s = app.state::<Shared>();
    let st = s.settings.lock().unwrap().clone();
    // Usage totals (numbers only) are kept even with History off (owner's decision, 22 Nov).
    if let Some(h) = s.history.lock().ok().as_ref().and_then(|g| g.as_ref()) {
        let kind = if st.history_record_app { history::app_kind(exe) } else { "Other" }; // the "note the program" switch applies here too
        if let Err(e) = h.add_usage(final_text.split_whitespace().count() as i64, (audio_s * 1000.0) as i64, (secs * 1000.0) as i64, kind) {
            eprintln!("usage: {e}");
        }
    }
    if !st.history_enabled {
        let _ = app.emit("usage", ());
        return None; // history off: no transcription text is written anywhere
    }
    let model = s.loaded.lock().unwrap().clone().unwrap_or_default();
    let r = {
        let Ok(guard) = s.history.lock() else { return None };
        let h = guard.as_ref()?;
        h.add_styled(st.history_keep_raw.then_some(raw), final_text, mode, style, &model, (audio_s * 1000.0) as i64, (secs * 1000.0) as i64, outcome, exe).and_then(|id| {
            h.purge(st.history_retention_days)?;
            // Dictionary and snippet use counts are kept only while History is on, like everything else about dictations.
            if !used.is_empty() {
                h.dict_used(used)?;
            }
            if !snip_used.is_empty() {
                h.snip_used(snip_used)?;
            }
            Ok(id)
        })
    };
    match r {
        Ok(id) => {
            *s.history_error.lock().unwrap() = None;
            if !used.is_empty() {
                reload_dictionary(app); // use counts set the hint's order
            }
            let _ = app.emit("history", ());
            Some(id)
        }
        Err(e) => {
            eprintln!("history: {e}");
            *s.history_error.lock().unwrap() = Some(e);
            None
        }
    }
}

// ---------- undo, restore original, paste last ----------

/// Whether the pill should show Undo for the last dictation (the full check runs when it is pressed).
fn undo_offered(app: &AppHandle) -> bool {
    let s = app.state::<Shared>();
    let st = s.settings.lock().unwrap().clone();
    let last = s.last_undo.lock().unwrap().clone();
    st.undo_on_pill && undo::check(last.as_ref(), Instant::now(), last.as_ref().map_or(0, |l| l.target), None, &st.undo_never).is_ok()
}

fn refuse(app: &AppHandle, why: &str) {
    trace!("undo refused: {why}");
    let _ = app.emit_to("pill", "actions", json!({ "undo": false }));
    pill(app, "error", &format!("Can't undo: {why}"));
    hide_pill_after(app, 4500);
}

/// The guards, after handing focus back to the dictated-into window if EsyType's own pill or window took it (a
/// button pressed through accessibility tools can activate the pill).
fn undo_allowed(app: &AppHandle) -> Result<undo::Last, String> {
    let s = app.state::<Shared>();
    let never = s.settings.lock().unwrap().undo_never.clone();
    let last = s.last_undo.lock().unwrap().clone();
    if let Some(l) = &last {
        use windows::Win32::Foundation::HWND;
        use windows::Win32::UI::WindowsAndMessaging::{GetWindowThreadProcessId, SetForegroundWindow};
        std::thread::sleep(Duration::from_millis(100)); // let a button press finish activating, if it does
        for _ in 0..5 {
            let fg = insert::foreground();
            let mut pid = 0u32;
            unsafe { GetWindowThreadProcessId(HWND(fg as _), Some(&mut pid)) };
            if fg == l.target || pid != std::process::id() {
                break; // the target, or another program the user chose: never taken back from them
            }
            // Windows lets a program change the foreground window only right after a key press: one Alt tap, sent
            // only while EsyType's own pill is in front, and marked as EsyType's own input.
            insert::tap_alt();
            unsafe {
                let _ = SetForegroundWindow(HWND(l.target as _));
            }
            std::thread::sleep(Duration::from_millis(120));
        }
    }
    #[cfg(feature = "e2e")]
    {
        let fg = insert::foreground();
        trace!("undo request: foreground {fg} ({:?}), target {:?}", insert::process_name(fg), last.as_ref().map(|l| l.target));
    }
    if !undo::watching() {
        return Err("EsyType cannot tell whether you typed since, so it will not guess. Use Ctrl+Z yourself.".into());
    }
    undo::check(last.as_ref(), Instant::now(), insert::foreground(), undo::first_user_input(), &never)?;
    Ok(last.expect("checked"))
}

/// Sends the app's own Undo once, after the guards in undo::check.
fn do_undo(app: &AppHandle) {
    let s = app.state::<Shared>();
    let l = match undo_allowed(app) {
        Ok(l) => l,
        Err(why) => return refuse(app, &why),
    };
    if let Err(e) = insert::send_undo() {
        return refuse(app, &e);
    }
    trace!("undo sent");
    *s.last_undo.lock().unwrap() = None;
    *s.last_insert.lock().unwrap() = None; // the text is gone: the next dictation needs no leading space
    if let Some(id) = l.history_id {
        let _ = with_history(app, |h| h.mark_undone(id));
        let _ = app.emit("history", ());
    }
    let _ = app.emit_to("pill", "actions", json!({ "undo": false }));
    pill(app, "undone", if l.typed { "Undone. Typed text may need Ctrl+Z again." } else { "Undone" });
    hide_pill_after(app, 2500);
}

/// Replaces Clean's text with what the engine heard: Undo, then paste the original.
fn do_restore_original(app: &AppHandle) {
    let s = app.state::<Shared>();
    let l = match undo_allowed(app) {
        Ok(l) => l,
        Err(why) => return refuse(app, &why),
    };
    if l.raw == l.text {
        return refuse(app, "the text is already what was heard.");
    }
    if let Err(e) = insert::send_undo() {
        return refuse(app, &e);
    }
    trace!("restore original: undo sent");
    let original = if l.leading_space { format!(" {}", l.raw) } else { l.raw.clone() };
    match insert::insert(&original, l.target) {
        Ok(o @ (insert::Outcome::Pasted | insert::Outcome::Typed)) => {
            if let Some(id) = l.history_id {
                let _ = with_history(app, |h| h.edit(id, &l.raw));
                let _ = app.emit("history", ());
            }
            *s.last_undo.lock().unwrap() = Some(undo::Last { ended: Instant::now(), typed: o == insert::Outcome::Typed, text: l.raw.clone(), ..l });
            undo::watch();
            let _ = app.emit_to("pill", "actions", json!({ "undo": false }));
            pill(app, "undone", "Original restored");
            hide_pill_after(app, 2500);
        }
        _ => {
            *s.last_undo.lock().unwrap() = None;
            pill(app, "unsure", "The original could not be typed. It is in History.");
            hide_pill_after(app, 8000);
        }
    }
}

/// Pastes the most recent dictation again where the cursor is now (recovery after "Not typed").
fn paste_last(app: &AppHandle) {
    let s = app.state::<Shared>();
    let text = s.last.lock().unwrap()["text"].as_str().unwrap_or_default().to_string();
    if text.is_empty() {
        pill(app, "error", "Nothing to paste yet.");
        return hide_pill_after(app, 2500);
    }
    let target = insert::foreground();
    pill(app, "inserting", "");
    match insert::insert(&text, target) {
        Ok(o @ (insert::Outcome::Pasted | insert::Outcome::Typed)) => {
            *s.last_undo.lock().unwrap() = Some(undo::Last {
                target,
                ended: Instant::now(),
                undoable: true,
                typed: o == insert::Outcome::Typed,
                program: insert::process_name(target),
                console: insert::is_console(target),
                raw: text.clone(),
                text,
                leading_space: false,
                history_id: None,
            });
            undo::watch();
            let offer = undo_offered(app);
            let _ = app.emit_to("pill", "actions", json!({ "undo": offer }));
            pill(app, "done", "pasted again");
            hide_pill_after(app, if offer { 5000 } else { 1500 });
        }
        Ok(insert::Outcome::Copied) => {
            pill(app, "error", "The window changed. The text is copied: press Ctrl+V.");
            hide_pill_after(app, 5000);
        }
        r => {
            pill(app, "unsure", r.err().as_deref().unwrap_or("The app didn't take the text."));
            hide_pill_after(app, 10_000);
        }
    }
}

#[tauri::command]
fn pill_undo(app: AppHandle) {
    std::thread::spawn(move || do_undo(&app));
}

#[tauri::command]
fn pill_use_original(app: AppHandle) {
    std::thread::spawn(move || do_restore_original(&app));
}

/// Virtual-key codes for a shortcut's keys (modifiers, and the main key where known).
fn shortcut_vks(sc: &Shortcut) -> Vec<i32> {
    use tauri_plugin_global_shortcut::{Code, Modifiers};
    let mut v = vec![];
    for (m, vk) in [(Modifiers::CONTROL, 0x11), (Modifiers::SHIFT, 0x10), (Modifiers::ALT, 0x12), (Modifiers::SUPER, 0x5B)] {
        if sc.mods.contains(m) {
            v.push(vk);
        }
    }
    let name = format!("{:?}", sc.key);
    let main = match sc.key {
        Code::Space => Some(0x20),
        _ if name.len() == 4 && name.starts_with("Key") => name.chars().last().map(|c| c as i32), // KeyA -> 'A'
        _ if name.len() == 6 && name.starts_with("Digit") => name.chars().last().map(|c| c as i32),
        _ if name.starts_with('F') => name[1..].parse::<i32>().ok().filter(|n| (1..=24).contains(n)).map(|n| 0x6F + n),
        _ => None,
    };
    v.extend(main);
    v
}

/// Hold-to-talk release, watched by EsyType itself: the shortcut library misses the release while EsyType's own
/// window is in front (its check waits for a "never pressed" answer that Windows does not give then). Stops when any
/// of the shortcut's keys is let go; the library's own release event may arrive too, and stopping twice is harmless.
fn watch_hold_release(app: &AppHandle, sc: Shortcut) {
    use windows::Win32::UI::Input::KeyboardAndMouse::GetAsyncKeyState;
    let vks = shortcut_vks(&sc);
    if vks.is_empty() {
        return;
    }
    let app = app.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_millis(30));
        let s = app.state::<Shared>();
        let held = match s.dictation.lock().unwrap().as_ref() {
            Some(d) if d.mode == Mode::Hold => d.started.elapsed(),
            _ => return, // already stopped or cancelled
        };
        let all_down = vks.iter().all(|vk| unsafe { GetAsyncKeyState(*vk) } as u16 & 0x8000 != 0);
        if !all_down {
            trace!("hold released (watched): {:?}", vks.iter().map(|vk| (*vk, unsafe { GetAsyncKeyState(*vk) } as u16)).collect::<Vec<_>>());
            if held < MIN_HOLD { cancel(&app) } else { stop(&app) }
            return;
        }
    });
}

fn on_shortcut(app: &AppHandle, sc: &Shortcut, state: ShortcutState) {
    let now = Instant::now();
    trace!("shortcut {:?} {:?}", sc, state);
    let s = app.state::<Shared>();
    let (ptt, toggle) = *s.keys.lock().unwrap();
    let (undo_key, paste_key) = *s.extra_keys.lock().unwrap();
    let current = s.dictation.lock().unwrap().as_ref().map(|d| (d.mode, d.started.elapsed()));
    if Some(*sc) == undo_key {
        if state == ShortcutState::Pressed && current.is_none() {
            let app = app.clone();
            std::thread::spawn(move || do_undo(&app));
        }
    } else if Some(*sc) == paste_key {
        if state == ShortcutState::Pressed && current.is_none() {
            let app = app.clone();
            std::thread::spawn(move || paste_last(&app));
        }
    } else if *sc == escape() {
        if state == ShortcutState::Pressed {
            cancel(app);
        }
    } else if *sc == ptt {
        match (state, current) {
            (ShortcutState::Pressed, None) => {
                start(app, Mode::Hold, now);
                watch_hold_release(app, ptt);
            }
            (ShortcutState::Released, Some((Mode::Hold, held))) if held < MIN_HOLD => cancel(app),
            (ShortcutState::Released, Some((Mode::Hold, _))) => stop(app),
            _ => {}
        }
    } else if *sc == toggle && state == ShortcutState::Pressed {
        match current {
            None => start(app, Mode::Toggle, now),
            Some(_) => stop(app),
        }
    }
}

// ---------- model loading ----------

fn load_model(app: &AppHandle, id: String) {
    let app = app.clone();
    std::thread::spawn(move || {
        let s = app.state::<Shared>();
        let Some(m) = models::find(&id) else { return };
        if !models::installed(m) {
            return;
        }
        *s.loaded.lock().unwrap() = None;
        let _ = app.emit("status", json!({ "engine": "loading", "model": id }));
        let threads = settings::effective_threads(s.settings.lock().unwrap().threads, logical(), physical());
        match s.engine.load(models::path(m), threads) {
            Ok(()) => {
                *s.loaded.lock().unwrap() = Some(id.clone());
                trace!("model ready");
                let _ = app.emit("status", json!({ "engine": "ready", "model": id }));
            }
            Err(e) => {
                let _ = app.emit("status", json!({ "engine": "error", "model": id, "error": e }));
            }
        }
    });
}

// ---------- commands for the main window and pill ----------

#[tauri::command]
fn get_status(app: AppHandle) -> serde_json::Value {
    let s = app.state::<Shared>();
    let hw = hardware::detect();
    let list: Vec<_> = models::MODELS
        .iter()
        .map(|m| {
            let installed = models::installed(m);
            json!({ "model": m, "installed": installed, "fit": hardware::fit(m, &hw, installed) })
        })
        .collect();
    let settings = s.settings.lock().unwrap().clone();
    let (data_bytes, models_bytes) = data_sizes();
    let (ptt, toggle) = *s.keys.lock().unwrap();
    let shortcuts_ok = app.global_shortcut().is_registered(ptt) && app.global_shortcut().is_registered(toggle);
    // One lock, released before anything else is read (locking twice in one expression deadlocks).
    let hint_words = {
        let d = s.dict.lock().unwrap();
        if d.hint().is_empty() { 0 } else { d.hint().matches(", ").count() + 1 }
    };
    json!({
        "settings": settings,
        "models": list,
        "recommended": hardware::recommend(&hw),
        "hardware": hw,
        "mics": audio::list_inputs(),
        "loaded": *s.loaded.lock().unwrap(),
        "threads_auto": settings::effective_threads(0, logical(), physical()),
        "threads_effective": settings::effective_threads(settings.threads, logical(), physical()),
        "downloading": *s.downloading.lock().unwrap(),
        "shortcuts_ok": shortcuts_ok,
        "last": *s.last.lock().unwrap(),
        "models_dir": models::dir(),
        "models_dir_default": models::default_dir(),
        "history_available": s.history.lock().map(|h| h.is_some()).unwrap_or(false),
        "history_error": *s.history_error.lock().unwrap(),
        "dictionary_hint_words": hint_words,
        "settings_problem": *s.settings_problem.lock().unwrap(),
        "data_dir": settings::data_dir(),
        "version": env!("CARGO_PKG_VERSION"),
        "data_bytes": data_bytes,
        "models_bytes": models_bytes,
        // Time of the newest restore safety copy (Undo restore), Unix ms.
        "undo_restore": backup::safety_copies(&backup::safety_dir()).first()
            .and_then(|p| p.metadata().ok()?.modified().ok()?.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_millis() as u64),
        "download_source": models::source(),
    })
}

#[tauri::command]
fn save_settings(app: AppHandle, new: Settings) -> Result<(), String> {
    let s = app.state::<Shared>();
    if models::find(&new.model).is_none() {
        return Err("Unknown model.".into());
    }
    let old = s.settings.lock().unwrap().clone();
    let mut new = new;
    let known = |n: &str| settings::STYLES.contains(&n);
    if !known(&new.style_default) || new.style_rules.iter().any(|r| !known(&r.style) || r.app.trim().is_empty()) {
        return Err("Unknown writing style or empty program name.".into());
    }
    new.models_dir = old.models_dir.clone(); // changed only by set_models_dir, which moves the files
    for (text, before) in [(&new.ptt, &old.ptt), (&new.toggle, &old.toggle), (&new.undo_shortcut, &old.undo_shortcut), (&new.paste_last_shortcut, &old.paste_last_shortcut)] {
        if text != before && !text.trim().is_empty() {
            if let Some(why) = settings::shortcut_problem(text) {
                return Err(format!("{text}: {why}"));
            }
        }
    }
    let ptt: Shortcut = new.ptt.parse().map_err(|_| format!("\"{}\" is not a valid shortcut.", new.ptt))?;
    let toggle: Shortcut = new.toggle.parse().map_err(|_| format!("\"{}\" is not a valid shortcut.", new.toggle))?;
    if ptt == toggle {
        return Err("The two shortcuts must be different.".into());
    }
    if (ptt, toggle) != *s.keys.lock().unwrap() {
        register_keys(&app, ptt, toggle)?;
    }
    if new.undo_shortcut != old.undo_shortcut || new.paste_last_shortcut != old.paste_last_shortcut {
        let parsed: Vec<Option<Shortcut>> = [&new.undo_shortcut, &new.paste_last_shortcut]
            .iter()
            .map(|k| if k.trim().is_empty() { Ok(None) } else { k.parse::<Shortcut>().map(Some).map_err(|_| format!("\"{k}\" is not a valid shortcut.")) })
            .collect::<Result<_, _>>()?;
        let all: Vec<Shortcut> = parsed.iter().flatten().copied().chain([ptt, toggle]).collect();
        if (1..all.len()).any(|i| all[..i].contains(&all[i])) {
            return Err("Each shortcut must be different.".into());
        }
        register_extra_keys(&app, &new.undo_shortcut, &new.paste_last_shortcut)?;
    }
    if new.start_with_windows != old.start_with_windows {
        apply_autostart(&app, new.start_with_windows)?;
    }
    if let Some(h) = s.history.lock().unwrap().as_ref() {
        if old.history_keep_raw && !new.history_keep_raw {
            h.forget_raw()?; // turning it off also removes the originals already kept
            backup::remove_safety(&backup::safety_dir()); // including those in restore safety copies
        }
        if new.history_retention_days != old.history_retention_days {
            h.purge(new.history_retention_days)?;
        }
    }
    settings::save(&new)?;
    *s.settings.lock().unwrap() = new.clone();
    if let Some(item) = s.tray_clean.lock().unwrap().as_ref() {
        let _ = item.set_checked(new.clean().is_some());
    }
    if new.builtin_vocabulary != old.builtin_vocabulary {
        reload_dictionary(&app);
    }
    if new.theme != old.theme {
        apply_theme(&app, &new.theme);
    }
    if new.threads != old.threads {
        s.engine.set_threads(settings::effective_threads(new.threads, logical(), physical()));
    }
    if new.model != old.model || s.loaded.lock().unwrap().is_none() {
        load_model(&app, new.model);
    }
    Ok(())
}

/// Why a shortcut cannot be used (None if it can), for the capture box; saving checks again.
#[tauri::command]
fn check_shortcut(text: String) -> Option<String> {
    settings::shortcut_problem(&text).or_else(|| text.parse::<Shortcut>().err().map(|_| format!("{text} is not a shortcut EsyType can use.")))
}

/// Takes EsyType's shortcuts away from Windows while the window captures new keys (otherwise Windows hands the
/// current ones to EsyType and the window never sees them). Always restored: by the window, or after 20 seconds.
#[tauri::command]
fn pause_shortcuts(app: AppHandle, on: bool) {
    let s = app.state::<Shared>();
    let generation = s.pause_gen.fetch_add(1, Ordering::SeqCst) + 1;
    set_shortcuts_paused(&app, on);
    if on {
        let app = app.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(20));
            if app.state::<Shared>().pause_gen.load(Ordering::SeqCst) == generation {
                set_shortcuts_paused(&app, false);
                let _ = app.emit_to("main", "shortcuts-resumed", ());
            }
        });
    }
}

fn set_shortcuts_paused(app: &AppHandle, paused: bool) {
    let s = app.state::<Shared>();
    let (ptt, toggle) = *s.keys.lock().unwrap();
    let (undo_key, paste_key) = *s.extra_keys.lock().unwrap();
    let gs = app.global_shortcut();
    for k in [Some(ptt), Some(toggle), undo_key, paste_key].into_iter().flatten() {
        if paused {
            let _ = gs.unregister(k);
        } else if !gs.is_registered(k) {
            if let Err(e) = gs.register(k) {
                eprintln!("shortcut {k:?} could not be registered again: {e}");
            }
        }
    }
}

/// Records 3 seconds from `mic` (None = Windows default), sending levels to the window as "mic-level", and says
/// whether speech was heard. Nothing is kept or transcribed.
#[tauri::command]
async fn mic_test(app: AppHandle, mic: Option<String>) -> Result<serde_json::Value, String> {
    let s = app.state::<Shared>();
    if s.dictation.lock().unwrap().is_some() || s.busy.load(Ordering::SeqCst) {
        return Err("Finish the dictation first.".into());
    }
    if s.mic_testing.swap(true, Ordering::SeqCst) {
        return Err("A microphone test is already running.".into());
    }
    let a = app.clone();
    let r = tauri::async_runtime::spawn_blocking(move || {
        let loudest = Arc::new(Mutex::new(0f32));
        let l = loudest.clone();
        let rec = audio::start(mic, move |v| {
            let mut m = l.lock().unwrap();
            *m = m.max(v);
            let _ = a.emit_to("main", "mic-level", v);
        }, || {})?;
        let fell_back = rec.fell_back;
        std::thread::sleep(Duration::from_secs(3));
        drop(rec.finish()?); // discarded: the test only needs the levels
        let loudest = *loudest.lock().unwrap();
        Ok::<_, String>(json!({ "verdict": audio::verdict(loudest), "loudest": loudest, "fell_back": fell_back }))
    })
    .await
    .map_err(|e| e.to_string())
    .and_then(|r| r);
    app.state::<Shared>().mic_testing.store(false, Ordering::SeqCst);
    r
}

/// Finishing setup hides the window: EsyType waits in the tray.
#[tauri::command]
fn hide_window(app: AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.hide();
    }
}

/// Registers the Undo and Paste last shortcuts in place of the previous ones ("" means none).
fn register_extra_keys(app: &AppHandle, undo_key: &str, paste_key: &str) -> Result<(), String> {
    let s = app.state::<Shared>();
    let gs = app.global_shortcut();
    let (old_u, old_p) = *s.extra_keys.lock().unwrap();
    for k in [old_u, old_p].into_iter().flatten() {
        let _ = gs.unregister(k);
    }
    let mut keys = (None, None);
    let mut problems = vec![];
    for (slot, text) in [(0, undo_key), (1, paste_key)] {
        if text.trim().is_empty() {
            continue;
        }
        match text.parse::<Shortcut>() {
            Ok(k) if gs.register(k).is_ok() => {
                if slot == 0 { keys.0 = Some(k) } else { keys.1 = Some(k) }
            }
            _ => problems.push(format!("\"{text}\" could not be registered; another app may be using it.")),
        }
    }
    *s.extra_keys.lock().unwrap() = keys;
    if problems.is_empty() { Ok(()) } else { Err(problems.join(" ")) }
}

/// Replaces the registered shortcuts; on failure the previous ones are put back.
fn register_keys(app: &AppHandle, ptt: Shortcut, toggle: Shortcut) -> Result<(), String> {
    let s = app.state::<Shared>();
    let gs = app.global_shortcut();
    let (old_ptt, old_toggle) = *s.keys.lock().unwrap();
    // Only the shortcuts that change are re-registered, so one held by another program does not stop the other
    // from being changed.
    let pairs: Vec<(Shortcut, Shortcut)> = [(old_ptt, ptt), (old_toggle, toggle)].into_iter().filter(|(o, n)| o != n).collect();
    for (o, _) in &pairs {
        let _ = gs.unregister(*o);
    }
    let mut added = vec![];
    for (_, n) in &pairs {
        if let Err(e) = gs.register(*n) {
            for a in &added {
                let _ = gs.unregister(*a);
            }
            for (o, _) in &pairs {
                let _ = gs.register(*o);
            }
            return Err(format!("That shortcut could not be registered; another app may be using it. ({e})"));
        }
        added.push(*n);
    }
    *s.keys.lock().unwrap() = (ptt, toggle);
    Ok(())
}

#[tauri::command]
fn download_model(app: AppHandle, id: String) -> Result<(), String> {
    let s = app.state::<Shared>();
    let m = *models::find(&id).ok_or("Unknown model.")?;
    {
        let mut d = s.downloading.lock().unwrap();
        if d.is_some() {
            return Err("A download is already in progress.".into());
        }
        *d = Some(id.clone());
    }
    s.cancel_download.store(false, Ordering::SeqCst);
    let cancel = s.cancel_download.clone();
    let app = app.clone();
    std::thread::spawn(move || {
        let mut last_pct = u64::MAX;
        let r = models::download(&m, &cancel, |done, total| {
            let pct = done * 100 / total.max(1);
            if pct != last_pct {
                last_pct = pct;
                let _ = app.emit("download", json!({ "id": m.id, "done": done, "total": total }));
            }
        });
        let s = app.state::<Shared>();
        *s.downloading.lock().unwrap() = None;
        match r {
            Ok(()) => {
                let _ = app.emit("download", json!({ "id": m.id, "finished": true }));
                // The downloaded model becomes the active one: the user chose it.
                let mut new = s.settings.lock().unwrap().clone();
                new.model = m.id.into();
                let _ = settings::save(&new);
                *s.settings.lock().unwrap() = new;
                load_model(&app, m.id.into());
            }
            Err(e) => {
                let _ = app.emit("download", json!({ "id": m.id, "error": e }));
            }
        }
    });
    Ok(())
}

/// Moves installed models to `path` (verified copy, then delete) and makes it the download folder.
#[tauri::command]
fn set_models_dir(app: AppHandle, path: String) -> Result<String, String> {
    let s = app.state::<Shared>();
    if s.downloading.lock().unwrap().is_some() || s.dictation.lock().unwrap().is_some() || s.busy.load(Ordering::SeqCst) {
        return Err("Wait for the current download or dictation to finish.".into());
    }
    let to = std::path::PathBuf::from(path.trim());
    let moved = models::move_to(&to)?;
    let mut new = s.settings.lock().unwrap().clone();
    new.models_dir = if to == models::default_dir() { None } else { Some(to.to_string_lossy().into_owned()) };
    settings::save(&new)?;
    models::set_dir(new.models_dir.as_ref().map(Into::into));
    *s.settings.lock().unwrap() = new;
    Ok(if moved.is_empty() { "Folder changed. No models needed moving.".into() } else { format!("Moved {} and verified the copies.", moved.join(", ")) })
}

fn apply_autostart(app: &AppHandle, on: bool) -> Result<(), String> {
    use tauri_plugin_autostart::ManagerExt;
    // Test builds register under the same startup name as the installed EsyType, so changing it here would
    // switch off (or redirect) the user's real start-with-Windows entry.
    if cfg!(feature = "e2e") {
        return Ok(());
    }
    let a = app.autolaunch();
    if on { a.enable() } else { a.disable() }.map_err(|e| format!("Could not change the Windows startup setting: {e}"))
}

fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

fn create_tray(app: &AppHandle) -> tauri::Result<()> {
    use tauri::menu::{CheckMenuItem, Menu, MenuItem};
    use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
    let open = MenuItem::with_id(app, "open", "Open EsyType", true, None::<&str>)?;
    let pad = MenuItem::with_id(app, "scratchpad", "Open Scratchpad", true, None::<&str>)?;
    let prefs = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
    let on = app.state::<Shared>().settings.lock().unwrap().clean().is_some();
    let clean = CheckMenuItem::with_id(app, "clean", "Clean mode", true, on, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit EsyType", true, None::<&str>)?;
    *app.state::<Shared>().tray_clean.lock().unwrap() = Some(clean.clone());
    TrayIconBuilder::with_id("main")
        .icon(app.default_window_icon().cloned().expect("app icon"))
        .tooltip(TRAY_TIP)
        .menu(&Menu::with_items(app, &[&open, &pad, &prefs, &clean, &quit])?)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, e| match e.id().as_ref() {
            "open" => show_main(app),
            "scratchpad" => {
                show_main(app);
                let _ = app.emit_to("main", "open-tab", "scratchpad");
            }
            "settings" => {
                show_main(app);
                let _ = app.emit_to("main", "open-tab", "settings");
            }
            "clean" => {
                let s = app.state::<Shared>();
                let mut new = s.settings.lock().unwrap().clone();
                new.text_mode = if new.text_mode == "verbatim" { "clean".into() } else { "verbatim".into() };
                let _ = save_settings(app.clone(), new);
                let _ = app.emit("settings", ());
            }
            "quit" => quit_app(app),
            _ => {}
        })
        .on_tray_icon_event(|tray, e| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                show_main(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}

/// Runs `f` on the history database, or explains why history is unavailable.
fn with_history<T>(app: &AppHandle, f: impl FnOnce(&history::History) -> Result<T, String>) -> Result<T, String> {
    let s = app.state::<Shared>();
    let guard = s.history.lock().map_err(|_| "History is unavailable.".to_string())?;
    match guard.as_ref() {
        Some(h) => f(h),
        None => Err(s.history_error.lock().unwrap().clone().unwrap_or_else(|| "History is unavailable.".into())),
    }
}

#[tauri::command]
fn usage_summary(app: AppHandle) -> Result<history::Usage, String> {
    with_history(&app, |h| h.usage())
}

#[tauri::command]
fn insights_data(app: AppHandle) -> Result<serde_json::Value, String> {
    with_history(&app, |h| {
        let mut v = h.insights()?;
        v["usage"] = json!(h.usage()?);
        Ok(v)
    })
}

#[tauri::command]
fn history_list(app: AppHandle, query: String, offset: i64, show: Option<String>) -> Result<serde_json::Value, String> {
    let days = app.state::<Shared>().settings.lock().unwrap().history_retention_days;
    // Expired entries go before anything is shown, even if EsyType has been idle since they expired.
    with_history(&app, |h| {
        h.purge(days)?;
        let (items, total) = h.list_shown(&query, show.as_deref().unwrap_or(""), 50, offset.max(0))?;
        Ok(json!({ "items": items, "total": total, "stats": h.stats()? }))
    })
}

#[tauri::command]
fn history_edit(app: AppHandle, id: i64, text: String) -> Result<(), String> {
    with_history(&app, |h| h.edit(id, &text))
}

#[tauri::command]
fn history_delete(app: AppHandle, id: i64) -> Result<(), String> {
    with_history(&app, |h| h.delete(id))
}

/// Rebuilds the in-memory dictionary after a change; dictation only ever reads this copy.
fn reload_dictionary(app: &AppHandle) {
    if let Ok(list) = with_history(app, |h| h.dict_enabled()) {
        let builtins = app.state::<Shared>().settings.lock().unwrap().builtin_vocabulary;
        *app.state::<Shared>().dict.lock().unwrap() = dictionary_matcher(list, builtins);
    }
}

/// The user's Dictionary, then (when on) the built-in product names: on the same words the user's entry wins.
fn dictionary_matcher(mut list: Vec<dictionary::Entry>, builtins: bool) -> dictionary::Matcher {
    if builtins {
        list.extend(vocabulary::entries());
    }
    dictionary::Matcher::new(&list)
}

/// The built-in product names, each with the forms it corrects (read-only, for the Dictionary page).
#[tauri::command]
fn vocabulary_names() -> Vec<(&'static str, Vec<&'static str>)> {
    vocabulary::names()
}

#[tauri::command]
fn dict_list(app: AppHandle) -> Result<Vec<serde_json::Value>, String> {
    with_history(&app, |h| with_meta(h.dict_list()?, h.meta("dictionary")?, |e| e.id))
}

/// Each entry with its category, note and on/off (Mac design: Dictionary and Snippets).
fn with_meta<T: serde::Serialize>(list: Vec<T>, meta: std::collections::HashMap<i64, serde_json::Value>, id: impl Fn(&T) -> i64) -> Result<Vec<serde_json::Value>, String> {
    Ok(list
        .into_iter()
        .map(|e| {
            let mut v = json!(e);
            if let (Some(o), Some(m)) = (v.as_object_mut(), meta.get(&id(&e)).and_then(|m| m.as_object())) {
                o.extend(m.clone());
            }
            v
        })
        .collect())
}

#[tauri::command]
fn dict_meta(app: AppHandle, id: i64, category: String, description: String, enabled: bool) -> Result<(), String> {
    with_history(&app, |h| h.set_meta("dictionary", id, &category, &description, enabled))?;
    reload_dictionary(&app);
    Ok(())
}

#[tauri::command]
fn snip_meta(app: AppHandle, id: i64, category: String, enabled: bool) -> Result<(), String> {
    with_history(&app, |h| h.set_meta("snippets", id, &category, "", enabled))?;
    reload_snippets(&app);
    Ok(())
}

#[tauri::command]
fn dict_add(app: AppHandle, kind: String, term: String, replacement: Option<String>) -> Result<(), String> {
    with_history(&app, |h| h.dict_add(&kind, &term, replacement.as_deref()))?;
    reload_dictionary(&app);
    Ok(())
}

#[tauri::command]
fn dict_update(app: AppHandle, id: i64, kind: String, term: String, replacement: Option<String>) -> Result<(), String> {
    with_history(&app, |h| h.dict_update(id, &kind, &term, replacement.as_deref()))?;
    reload_dictionary(&app);
    Ok(())
}

#[tauri::command]
fn dict_delete(app: AppHandle, id: i64) -> Result<(), String> {
    with_history(&app, |h| h.dict_delete(id))?;
    reload_dictionary(&app);
    Ok(())
}

#[tauri::command]
fn dict_clear(app: AppHandle) -> Result<(), String> {
    with_history(&app, |h| h.dict_clear())?;
    reload_dictionary(&app);
    Ok(())
}

/// Imports CSV or JSON text (read by the window's file picker): adds new entries, skips duplicates.
#[tauri::command]
fn dict_import(app: AppHandle, text: String, dry: Option<bool>) -> Result<serde_json::Value, String> {
    let entries = dictionary::parse_import(&text)?;
    // dry: what the import would do, for the preview; nothing changes
    let (added, duplicates, problems) = with_history(&app, |h| h.trial(!dry.unwrap_or(false), |h| h.dict_import(&entries)))?;
    reload_dictionary(&app);
    Ok(json!({ "added": added, "duplicates": duplicates, "problems": problems }))
}

/// Writes the dictionary to the Downloads folder as CSV or JSON and returns the file's path.
#[tauri::command]
fn dict_export(app: AppHandle, format: String) -> Result<String, String> {
    let list = with_history(&app, |h| h.dict_list())?;
    let (body, ext) = if format == "json" { (dictionary::to_json(&list), "json") } else { (dictionary::to_csv(&list), "csv") };
    save_export("EsyType dictionary", ext, &body)
}

#[tauri::command]
fn snip_export(app: AppHandle, format: String) -> Result<String, String> {
    let list = with_history(&app, |h| h.snip_list())?;
    let (body, ext) = if format == "json" { (snippets::to_json(&list), "json") } else { (snippets::to_csv(&list), "csv") };
    save_export("EsyType snippets", ext, &body)
}

/// Saves an export in the Downloads folder without overwriting an earlier one; returns its path.
fn save_export(name: &str, ext: &str, body: &str) -> Result<String, String> {
    let path = export_path(name, ext)?;
    std::fs::write(&path, body).map_err(|e| format!("Could not write {}: {e}", path.display()))?;
    Ok(path.to_string_lossy().into_owned())
}

/// A new file name in the Downloads folder (never an existing one).
fn export_path(name: &str, ext: &str) -> Result<std::path::PathBuf, String> {
    #[allow(unused_mut)]
    let mut dir = std::env::var_os("USERPROFILE").map(|p| std::path::PathBuf::from(p).join("Downloads"));
    #[cfg(feature = "e2e")]
    if let Some(d) = std::env::var_os("ESYTYPE_EXPORT_DIR") {
        dir = Some(d.into()); // tests never write into the owner's Downloads folder
    }
    let dir = dir.filter(|d| d.is_dir()).ok_or("The Downloads folder was not found.")?;
    let mut path = dir.join(format!("{name}.{ext}"));
    let mut n = 2;
    while path.exists() {
        path = dir.join(format!("{name} ({n}).{ext}"));
        n += 1;
    }
    Ok(path)
}

fn reload_snippets(app: &AppHandle) {
    if let Ok(list) = with_history(app, |h| h.snip_enabled()) {
        *app.state::<Shared>().snippets.lock().unwrap() = snippets::Matcher::new(&list);
    }
}

#[tauri::command]
fn snip_list(app: AppHandle) -> Result<Vec<serde_json::Value>, String> {
    with_history(&app, |h| with_meta(h.snip_list()?, h.meta("snippets")?, |s| s.id))
}

#[tauri::command]
fn snip_add(app: AppHandle, trigger: String, body: String, mode: String) -> Result<(), String> {
    with_history(&app, |h| h.snip_add(&trigger, &body, &mode))?;
    reload_snippets(&app);
    Ok(())
}

#[tauri::command]
fn snip_update(app: AppHandle, id: i64, trigger: String, body: String, mode: String) -> Result<(), String> {
    with_history(&app, |h| h.snip_update(id, &trigger, &body, &mode))?;
    reload_snippets(&app);
    Ok(())
}

#[tauri::command]
fn snip_delete(app: AppHandle, id: i64) -> Result<(), String> {
    with_history(&app, |h| h.snip_delete(id))?;
    reload_snippets(&app);
    Ok(())
}

#[tauri::command]
fn snip_clear(app: AppHandle) -> Result<(), String> {
    with_history(&app, |h| h.snip_clear())?;
    reload_snippets(&app);
    Ok(())
}

#[tauri::command]
fn snip_import(app: AppHandle, text: String, dry: Option<bool>) -> Result<serde_json::Value, String> {
    let list = snippets::parse_import(&text)?;
    let (added, duplicates, problems) = with_history(&app, |h| h.trial(!dry.unwrap_or(false), |h| h.snip_import(&list)))?;
    reload_snippets(&app);
    Ok(json!({ "added": added, "duplicates": duplicates, "problems": problems }))
}

/// The snippet text with {date}, {time} and {day} filled in now, for the page's preview.
#[tauri::command]
fn snip_preview(body: String) -> String {
    snippets::fill(&body, &snippets::Clock::now())
}

/// A sentence as each style would finish it, for the Style page's examples and try-it box.
#[tauri::command]
fn style_preview(app: AppHandle, text: String) -> serde_json::Value {
    let st = app.state::<Shared>().settings.lock().unwrap().clone();
    let o = st.clean().unwrap_or_default();
    let out: serde_json::Map<String, serde_json::Value> =
        settings::STYLES.iter().map(|n| (n.to_string(), json!(clean::apply_styled(&text, &o, st.style(n).as_ref())))).collect();
    serde_json::Value::Object(out)
}

/// Programs dictated into recently (from History, when it records program names), for adding style rules.
#[tauri::command]
fn recent_apps(app: AppHandle) -> Vec<String> {
    with_history(&app, |h| h.recent_apps()).unwrap_or_default()
}

#[tauri::command]
fn notes_list(app: AppHandle, query: String) -> Result<Vec<notes::Summary>, String> {
    with_history(&app, |h| h.notes(&query))
}

#[tauri::command]
fn note_get(app: AppHandle, id: i64) -> Result<String, String> {
    with_history(&app, |h| h.note(id))
}

#[tauri::command]
fn note_create(app: AppHandle, body: String) -> Result<i64, String> {
    with_history(&app, |h| h.note_create(&body))
}

#[tauri::command]
fn note_save(app: AppHandle, id: i64, body: String) -> Result<(), String> {
    with_history(&app, |h| h.note_save(id, &body))
}

#[tauri::command]
fn note_delete(app: AppHandle, id: i64) -> Result<(), String> {
    with_history(&app, |h| h.note_delete(id))
}

#[tauri::command]
fn notes_clear(app: AppHandle) -> Result<(), String> {
    with_history(&app, |h| h.note_clear())
}

/// Saves a note to Downloads as .txt or .md, named after its first line.
#[tauri::command]
fn note_export(app: AppHandle, id: i64, format: String) -> Result<String, String> {
    let body = with_history(&app, |h| h.note(id))?;
    let safe: String = notes::title(&body).chars().filter(|c| !"\\/:*?\"<>|…".contains(*c)).take(40).collect();
    save_export(&format!("EsyType note - {}", safe.trim()), if format == "md" { "md" } else { "txt" }, &body)
}

/// The page tells EsyType it has saved everything (asked before quitting).
#[tauri::command]
fn flushed(app: AppHandle) {
    if let Some(tx) = app.state::<Shared>().flush.lock().unwrap().take() {
        let _ = tx.send(());
    }
}

/// Asks the page to save open work, waits briefly, then quits.
fn quit_app(app: &AppHandle) {
    let (tx, rx) = std::sync::mpsc::channel();
    *app.state::<Shared>().flush.lock().unwrap() = Some(tx);
    let _ = app.emit_to("main", "flush", ());
    let app = app.clone();
    std::thread::spawn(move || {
        let _ = rx.recv_timeout(Duration::from_millis(1500));
        insert::wait_until_restored(Duration::from_secs(4)); // a paste that just finished puts the user's clipboard back
        app.exit(0);
    });
}

/// Opens File Explorer with an exported file selected.
#[tauri::command]
fn dismiss_settings_problem(app: AppHandle) {
    *app.state::<Shared>().settings_problem.lock().unwrap() = None;
}

/// Opens one of EsyType's own folders in Explorer.
#[tauri::command]
fn open_folder(which: String) -> Result<(), String> {
    let dir = match which.as_str() {
        "data" => settings::data_dir(),
        "models" => models::dir(),
        _ => return Err("Unknown folder.".into()),
    };
    std::process::Command::new("explorer.exe").arg(dir).spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
fn show_in_folder(path: String) -> Result<(), String> {
    if !std::path::Path::new(&path).is_file() {
        return Err("The file is no longer there.".into());
    }
    std::process::Command::new("explorer.exe").arg(format!("/select,{path}")).spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
fn history_clear(app: AppHandle) -> Result<(), String> {
    with_history(&app, |h| h.clear_all())?;
    backup::remove_safety(&backup::safety_dir()); // restore safety copies hold History text too
    Ok(())
}

// ---------- settings and data management (Phase 5, Milestone 3) ----------

fn date_stamp(minutes: bool) -> String {
    let c = snippets::Clock::now();
    if minutes { format!("{:04}-{:02}-{:02} {:02}{:02}", c.year, c.month, c.day, c.hour, c.minute) } else { format!("{:04}-{:02}-{:02}", c.year, c.month, c.day) }
}

#[tauri::command]
fn history_export(app: AppHandle, query: String, format: String) -> Result<serde_json::Value, String> {
    let json = format == "json";
    let (body, count) = with_history(&app, |h| h.export(&query, json))?;
    let path = save_export(&format!("EsyType history {}", date_stamp(false)), if json { "json" } else { "csv" }, &body)?;
    Ok(json!({ "path": path, "count": count }))
}

#[tauri::command]
fn settings_export(app: AppHandle) -> Result<String, String> {
    let settings = app.state::<Shared>().settings.lock().unwrap().clone();
    let body = json!({ "esytype_settings": 1, "app_version": env!("CARGO_PKG_VERSION"), "exported": history::iso_utc(history::now_ms()), "settings": settings });
    save_export(&format!("EsyType settings {}", date_stamp(false)), "json", &serde_json::to_string_pretty(&body).unwrap())
}

fn installed_model(id: &str) -> bool {
    models::find(id).is_some_and(models::installed)
}

/// What importing a settings file would change, without changing anything.
#[tauri::command]
fn settings_import_preview(app: AppHandle, text: String) -> Result<serde_json::Value, String> {
    let incoming = settings::parse_export(&text)?;
    let current = app.state::<Shared>().settings.lock().unwrap().clone();
    let (_, changes, skipped) = settings::import(&incoming, &current, installed_model);
    Ok(json!({ "changes": changes, "skipped": skipped }))
}

/// Applies a settings file; returns a note when shortcuts had to be kept as they were.
#[tauri::command]
fn settings_import_apply(app: AppHandle, text: String) -> Result<Option<String>, String> {
    let incoming = settings::parse_export(&text)?;
    let current = app.state::<Shared>().settings.lock().unwrap().clone();
    let (new, _, _) = settings::import(&incoming, &current, installed_model);
    apply_settings(&app, new)
}

/// Saves settings through the usual checks. If a shortcut cannot be registered, everything else is still applied
/// with the shortcuts kept as they were, and the reason is returned as a note.
fn apply_settings(app: &AppHandle, new: Settings) -> Result<Option<String>, String> {
    let old = app.state::<Shared>().settings.lock().unwrap().clone();
    let keys = |s: &Settings| (s.ptt.clone(), s.toggle.clone(), s.undo_shortcut.clone(), s.paste_last_shortcut.clone());
    match save_settings(app.clone(), new.clone()) {
        Ok(()) => Ok(None),
        Err(e) if keys(&new) != keys(&old) => {
            let mut kept = new;
            (kept.ptt, kept.toggle, kept.undo_shortcut, kept.paste_last_shortcut) = keys(&old);
            save_settings(app.clone(), kept)?;
            Ok(Some(format!("Your shortcuts were kept as they were: {e}")))
        }
        Err(e) => Err(e),
    }
}

fn refuse_while_busy(app: &AppHandle) -> Result<(), String> {
    let s = app.state::<Shared>();
    if s.dictation.lock().unwrap().is_some() || s.busy.load(Ordering::SeqCst) || s.downloading.lock().unwrap().is_some() {
        return Err("Wait for the current dictation or download to finish.".into());
    }
    Ok(())
}

#[tauri::command]
fn backup_now(app: AppHandle) -> Result<serde_json::Value, String> {
    let settings = serde_json::to_string(&*app.state::<Shared>().settings.lock().unwrap()).unwrap();
    let path = export_path(&format!("EsyType backup {}", date_stamp(true)), backup::EXT)?;
    let counts = with_history(&app, |h| backup::make(h, &settings, &path))?;
    Ok(json!({ "path": path, "counts": counts }))
}

fn pending_restore() -> std::path::PathBuf {
    settings::data_dir().join(format!("restore-pending.{}", backup::EXT))
}

/// Checks a chosen backup file (sent as raw bytes) and says what it holds; nothing is changed.
#[tauri::command]
fn backup_check(request: tauri::ipc::Request<'_>) -> Result<backup::Info, String> {
    let tauri::ipc::InvokeBody::Raw(bytes) = request.body() else { return Err("No file was received.".into()) };
    let p = pending_restore();
    std::fs::create_dir_all(settings::data_dir()).map_err(|e| e.to_string())?;
    std::fs::write(&p, bytes).map_err(|e| format!("Could not read the backup: {e}"))?;
    backup::read(&p).inspect_err(|_| {
        let _ = std::fs::remove_file(&p);
    })
}

/// Forgets a checked backup the user decided not to restore (it holds their History text).
#[tauri::command]
fn backup_forget() {
    let _ = std::fs::remove_file(pending_restore());
}

#[tauri::command]
fn restore_backup(app: AppHandle) -> Result<Option<String>, String> {
    let p = pending_restore();
    let r = restore_from(&app, &p, true);
    let _ = std::fs::remove_file(&p);
    r
}

/// Puts back the data from before the last restore (the newest safety copy), then removes that copy.
#[tauri::command]
fn undo_restore(app: AppHandle) -> Result<Option<String>, String> {
    let copy = backup::safety_copies(&backup::safety_dir()).into_iter().next().ok_or("There is no restore to undo.")?;
    let r = restore_from(&app, &copy, false)?;
    let _ = std::fs::remove_file(&copy);
    Ok(r)
}

/// Replaces History, Dictionary, Snippets, notes and settings with those in `file`, after checking it. With
/// `safety`, the current data is backed up first; any failure after that puts the current data back.
fn restore_from(app: &AppHandle, file: &std::path::Path, safety: bool) -> Result<Option<String>, String> {
    refuse_while_busy(app)?;
    let info = backup::read(file)?;
    let s = app.state::<Shared>();
    let db = history::db_path();
    let current_json = serde_json::to_string(&*s.settings.lock().unwrap()).unwrap();
    {
        let mut guard = s.history.lock().unwrap();
        let rescue = if safety {
            let dir = backup::safety_dir();
            std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
            let copy = backup::safety_path(&dir);
            match guard.as_ref() {
                Some(h) => {
                    backup::make(h, &current_json, &copy).map_err(|e| format!("The safety copy could not be made, so nothing was restored: {e}"))?;
                    backup::prune_safety(&dir);
                    Some(copy)
                }
                None => None, // the database could not be opened: nothing usable to keep
            }
        } else {
            None
        };
        *guard = None; // closes the database
        #[cfg(feature = "e2e")]
        let forced = std::env::var("ESYTYPE_TEST_RESTORE_FAIL").is_ok(); // test builds: prove a failure puts data back
        #[cfg(not(feature = "e2e"))]
        let forced = false;
        let reopened = backup::replace(file, &db).and_then(|_| if forced { Err("test failure".to_string()) } else { history::History::open(&db) });
        match reopened {
            Ok(h) => {
                *guard = Some(h);
                *s.history_error.lock().unwrap() = None;
            }
            Err(e) => {
                let back = rescue.as_ref().map(|c| backup::replace(c, &db));
                *guard = history::History::open(&db).ok();
                return Err(match back {
                    Some(Ok(())) => format!("The restore failed, and your data was put back as it was: {e}"),
                    _ => format!("The restore failed: {e}"),
                });
            }
        }
    }
    reload_dictionary(app);
    reload_snippets(app);
    let incoming = serde_json::from_str::<serde_json::Value>(&info.settings_json).ok().and_then(|v| v.as_object().cloned()).unwrap_or_default();
    let current = s.settings.lock().unwrap().clone();
    let (new, _, _) = settings::import(&incoming, &current, installed_model);
    let note = apply_settings(app, new)?;
    let _ = app.emit("history", ());
    Ok(note)
}

/// Delete all EsyType data: History, Dictionary, Snippets, notes, settings (to defaults), kept damaged-settings
/// copies and restore safety copies; the speech models too when `models`. Only EsyType's own files are touched.
#[tauri::command]
fn delete_all_data(app: AppHandle, models: bool) -> Result<Option<String>, String> {
    refuse_while_busy(&app)?;
    let s = app.state::<Shared>();
    {
        let mut guard = s.history.lock().unwrap();
        match guard.as_ref() {
            Some(h) => h.clear_everything()?,
            None => {
                let db = history::db_path();
                for f in [db.clone(), db.with_extension("db-wal"), db.with_extension("db-shm")] {
                    let _ = std::fs::remove_file(f);
                }
                if let Ok(h) = history::History::open(&db) {
                    *guard = Some(h);
                    *s.history_error.lock().unwrap() = None;
                }
            }
        }
    }
    backup::remove_safety(&backup::safety_dir());
    let _ = std::fs::remove_file(pending_restore());
    for e in std::fs::read_dir(settings::data_dir()).into_iter().flatten().flatten() {
        if e.file_name().to_string_lossy().starts_with("settings.damaged-") {
            let _ = std::fs::remove_file(e.path());
        }
    }
    let mut new = Settings::default();
    if models {
        for m in &models::MODELS {
            let p = models::path(m);
            let _ = std::fs::remove_file(p.with_file_name(format!("{}.partial", m.file)));
            if p.exists() {
                std::fs::remove_file(&p).map_err(|e| format!("Could not delete {}: {e}", p.display()))?;
            }
        }
        *s.loaded.lock().unwrap() = None;
        s.settings.lock().unwrap().models_dir = None; // save_settings keeps the folder it finds
        models::set_dir(None);
        new.setup_done = Some(false); // the first-run wizard opens
    } else {
        new.setup_done = Some(true);
    }
    reload_dictionary(&app);
    reload_snippets(&app);
    *s.settings_problem.lock().unwrap() = None;
    let note = apply_settings(&app, new)?;
    let _ = app.emit("history", ());
    Ok(note)
}

/// Bytes used by EsyType's own files in its data folder (not the models), and by the downloaded models.
fn data_sizes() -> (u64, u64) {
    let size = |dir: &std::path::Path| std::fs::read_dir(dir).into_iter().flatten().flatten().filter_map(|e| e.metadata().ok()).filter(|m| m.is_file()).map(|m| m.len()).sum::<u64>();
    let data = size(&settings::data_dir()) + size(&backup::safety_dir());
    let models = models::MODELS.iter().filter(|m| models::installed(m)).map(|m| m.bytes).sum();
    (data, models)
}

#[tauri::command]
fn copy_text(text: String) -> Result<(), String> {
    insert::set_clipboard(&text, false)
}

#[tauri::command]
fn cancel_download(app: AppHandle) {
    app.state::<Shared>().cancel_download.store(true, Ordering::SeqCst);
}

#[tauri::command]
fn pill_cancel(app: AppHandle) {
    let s = app.state::<Shared>();
    if s.dictation.lock().unwrap().is_none() && !s.busy.load(Ordering::SeqCst) {
        pill(&app, "hidden", ""); // closes a warning
    } else {
        cancel(&app);
    }
}

/// The pill's Copy button after an unconfirmed insertion: puts the last dictation on the clipboard.
#[tauri::command]
fn pill_copy(app: AppHandle) -> Result<(), String> {
    let s = app.state::<Shared>();
    let text = s.last.lock().unwrap()["text"].as_str().unwrap_or_default().to_string();
    insert::set_clipboard(&text, false)?;
    pill(&app, "copied", "");
    hide_pill_after(&app, 2500);
    Ok(())
}

/// The pill's Original button after Clean mode changed a dictation: copies the engine's original text.
#[tauri::command]
fn pill_original(app: AppHandle) -> Result<(), String> {
    let s = app.state::<Shared>();
    let text = s.last.lock().unwrap()["original"].as_str().unwrap_or_default().to_string();
    if text.is_empty() {
        return Ok(());
    }
    insert::set_clipboard(&text, false)?;
    pill(&app, "copied", "");
    hide_pill_after(&app, 2500);
    Ok(())
}

#[tauri::command]
fn pill_stop(app: AppHandle) {
    stop(&app);
}

fn main() {
    let (mut settings, settings_problem) = settings::load();
    models::set_dir(settings.models_dir.as_ref().map(Into::into));
    // Decided in memory only (the file is written at the next save, as before): starting never rewrites settings.json.
    // A settings file that exists but cannot be read also means someone has used EsyType: they get the recovery banner,
    // not the wizard.
    settings::settle_setup(&mut settings, models::MODELS.iter().any(models::installed) || settings_problem.is_some());
    // A PC that is not set up opens the window even from the startup entry: a new user would otherwise see nothing.
    let start_hidden = std::env::args().any(|a| a == "--minimized") && settings.setup_done != Some(false);
    // A database that cannot be opened turns history off for this run; dictation is unaffected.
    let (history, history_error) = match history::History::open(&history::db_path()) {
        Ok(h) => {
            let _ = h.purge(settings.history_retention_days);
            (Some(h), None)
        }
        Err(e) => {
            eprintln!("history: {e}");
            (None, Some(e))
        }
    };
    let autostart = settings.start_with_windows;
    let parse = |s: &str, fallback: &str| s.parse::<Shortcut>().unwrap_or_else(|_| fallback.parse().unwrap());
    let keys = (parse(&settings.ptt, "Ctrl+Space"), parse(&settings.toggle, "Ctrl+Shift+Space"));
    let model = settings.model.clone();
    let (undo_key, paste_key) = (settings.undo_shortcut.clone(), settings.paste_last_shortcut.clone());
    let builtin_vocabulary = settings.builtin_vocabulary;
    #[allow(unused_mut)]
    let mut context = tauri::generate_context!();
    // Test builds get their own identity, so the single-instance check never hands off to an installed EsyType.
    #[cfg(feature = "e2e")]
    context.config_mut().identifier.push_str(".e2e");
    tauri::Builder::default()
        // Must be first: a second launch focuses the running EsyType instead of starting another one.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| show_main(app)))
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--minimized"])))
        .plugin(tauri_plugin_global_shortcut::Builder::new().with_handler(|app, sc, ev| on_shortcut(app, sc, ev.state)).build())
        .manage(Shared {
            settings: Mutex::new(settings),
            keys: Mutex::new(keys),
            engine: stt::Engine::spawn(vad_model()),
            loaded: Mutex::new(None),
            dictation: Mutex::new(None),
            busy: AtomicBool::new(false),
            downloading: Mutex::new(None),
            cancel_download: Arc::new(AtomicBool::new(false)),
            last: Mutex::new(serde_json::Value::Null),
            last_insert: Mutex::new(None),
            dict: Mutex::new(dictionary_matcher(history.as_ref().and_then(|h| h.dict_enabled().ok()).unwrap_or_default(), builtin_vocabulary)),
            snippets: Mutex::new(snippets::Matcher::new(&history.as_ref().and_then(|h| h.snip_enabled().ok()).unwrap_or_default())),
            history: Mutex::new(history),
            history_error: Mutex::new(history_error),
            tray_clean: Mutex::new(None),
            flush: Mutex::new(None),
            last_undo: Mutex::new(None),
            extra_keys: Mutex::new((None, None)),
            settings_problem: Mutex::new(settings_problem),
            pause_gen: AtomicU64::new(0),
            mic_testing: AtomicBool::new(false),
            tray_recording: AtomicBool::new(false),
            pill_gen: AtomicU64::new(0),
        })
        .setup(move |app| {
            let theme = app.state::<Shared>().settings.lock().unwrap().theme.clone();
            apply_theme(app.handle(), &theme);
            create_pill(app.handle())?;
            create_tray(app.handle())?;
            // Test builds only: page zoom, to check layouts at large text sizes without changing Windows' display setting.
            #[cfg(feature = "e2e")]
            if let (Some(w), Some(z)) = (app.get_webview_window("main"), std::env::var("ESYTYPE_TEST_ZOOM").ok().and_then(|z| z.parse::<f64>().ok())) {
                let _ = w.set_zoom(z);
            }
            if let Err(e) = apply_autostart(app.handle(), autostart) {
                eprintln!("{e}");
            }
            if !start_hidden {
                show_main(app.handle());
            }
            let gs = app.global_shortcut();
            for k in [keys.0, keys.1] {
                if let Err(e) = gs.register(k) {
                    eprintln!("shortcut {k:?} could not be registered: {e}");
                }
            }
            if let Err(e) = register_extra_keys(app.handle(), &undo_key, &paste_key) {
                eprintln!("{e}");
            }
            load_model(app.handle(), model.clone());
            Ok(())
        })
        .on_window_event(|w, e| {
            // Closing the window keeps EsyType running in the tray, so shortcuts keep working.
            if let tauri::WindowEvent::CloseRequested { api, .. } = e {
                if w.label() == "main" {
                    api.prevent_close();
                    let _ = w.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![get_status, save_settings, set_models_dir, download_model, cancel_download, history_list, history_edit, history_delete, history_clear, vocabulary_names, transparency_effects, microphone_allowed, open_mic_privacy, usage_summary, insights_data, ui_state, ui_remember, dict_meta, snip_meta,
            dict_list, dict_add, dict_update, dict_delete, dict_clear, dict_import, dict_export, snip_list, snip_add, snip_update, snip_delete, snip_clear, snip_import, snip_export, snip_preview, style_preview, recent_apps, notes_list, note_get, note_create, note_save, note_delete, notes_clear, note_export, flushed, show_in_folder, dismiss_settings_problem, open_folder, check_shortcut, pause_shortcuts, mic_test, hide_window, history_export, settings_export, settings_import_preview, settings_import_apply, backup_now, backup_check, backup_forget, restore_backup, undo_restore, delete_all_data, copy_text, pill_cancel, pill_copy, pill_original, pill_undo, pill_use_original, pill_stop])
        .run(context)
        .expect("EsyType failed to start");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tray_dot_while_dictating() {
        for s in ["listening", "recording", "processing", "inserting"] {
            assert!(tray_recording(s), "{s}");
        }
        for s in ["hidden", "done", "cleaned", "copied", "error", "unsure", "undone"] {
            assert!(!tray_recording(s), "{s}");
        }
    }

    #[test]
    fn shortcut_keys_for_the_hold_watch() {
        let vks = |s: &str| shortcut_vks(&s.parse::<Shortcut>().unwrap());
        assert_eq!(vks("Ctrl+Space"), vec![0x11, 0x20]);
        assert_eq!(vks("Ctrl+F8"), vec![0x11, 0x77]);
        assert_eq!(vks("Alt+Shift+Z"), vec![0x10, 0x12, 0x5A]);
        assert_eq!(vks("Ctrl+Alt+D"), vec![0x11, 0x12, 0x44]);
        assert_eq!(vks("Ctrl+Shift+5"), vec![0x11, 0x10, 0x35]);
        assert_eq!(vks("F9"), vec![0x78]);
    }
}
