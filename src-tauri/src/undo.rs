//! Undo last dictation, Restore original and the guards that keep them safe. EsyType cannot see the app's text,
//! so it acts only when it is sure what Ctrl+Z would undo: the most recent dictation, at most 60 s old, the same
//! window in front, and no key press or click by the user since.
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub const MAX_AGE: Duration = Duration::from_secs(60);
/// The request itself (the shortcut's key, or a click on the pill) is input; this much before it is allowed.
pub const GRACE: Duration = Duration::from_millis(600);

/// What Undo needs to know about the last dictation. In memory only.
#[derive(Clone, Debug)]
pub struct Last {
    pub target: isize,
    pub ended: Instant,
    /// Pasted (confirmed) or typed; anything else cannot be undone.
    pub undoable: bool,
    pub typed: bool,
    /// Executable name, for the per-program "never offer Undo" list.
    pub program: Option<String>,
    /// A console or terminal window, where Ctrl+Z does something else.
    pub console: bool,
    pub raw: String,
    pub text: String,
    /// The inserted text began with the space that separates consecutive dictations.
    pub leading_space: bool,
    pub history_id: Option<i64>,
}

/// Why Undo cannot run now, or Ok.
pub fn check(last: Option<&Last>, now: Instant, foreground: isize, user_input: Option<Instant>, never: &[String]) -> Result<(), String> {
    let l = last.ok_or("There is no recent dictation to undo.")?;
    if !l.undoable {
        return Err("The last dictation was not typed into an app, so there is nothing to undo.".into());
    }
    if l.console || l.program.as_deref().is_some_and(|p| never.iter().any(|n| n.eq_ignore_ascii_case(p))) {
        return Err("Undo is not offered in this program (Ctrl+Z means something else there).".into());
    }
    if now.duration_since(l.ended) > MAX_AGE {
        return Err("Undo works for 60 seconds after a dictation.".into());
    }
    if foreground != l.target {
        return Err("Go back to the window you dictated into first.".into());
    }
    if user_input.is_some_and(|t| t > l.ended && t + GRACE < now) {
        return Err("You typed or clicked after the dictation, so Ctrl+Z would undo that instead. Use Ctrl+Z yourself.".into());
    }
    Ok(())
}

// ---------- input watch ----------
// Low-level keyboard and mouse hooks run only for the minute after a dictation. They record the time of the first
// key press (not Shift, Ctrl, Alt or Windows) or mouse click, and nothing else: no key codes, no positions.
// EsyType's own simulated input carries insert::SIGNATURE and is ignored.

static LAST_INPUT: Mutex<Option<Instant>> = Mutex::new(None);
static DEADLINE_MS: AtomicU64 = AtomicU64::new(0);
static RUNNING: AtomicBool = AtomicBool::new(false);
/// False if the hooks could not be installed: then EsyType cannot know about typing since, and refuses Undo.
static HOOKED: AtomicBool = AtomicBool::new(false);

/// Whether the input watch is working (if not, Undo is refused rather than guessed).
pub fn watching() -> bool {
    HOOKED.load(Ordering::SeqCst)
}

fn epoch() -> Instant {
    static E: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();
    *E.get_or_init(Instant::now)
}

/// The first user key press or click since the watch began, if any. The first, not the last: the Undo request is
/// itself a key press or click, and must not hide typing that came before it.
pub fn first_user_input() -> Option<Instant> {
    *LAST_INPUT.lock().unwrap()
}

/// Starts (or extends) the watch for the next minute and forgets earlier input.
pub fn watch() {
    *LAST_INPUT.lock().unwrap() = None;
    DEADLINE_MS.store((epoch().elapsed() + MAX_AGE + Duration::from_secs(1)).as_millis() as u64, Ordering::SeqCst);
    if RUNNING.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(|| {
        use windows::Win32::UI::WindowsAndMessaging::{
            DispatchMessageW, PeekMessageW, SetWindowsHookExW, TranslateMessage, UnhookWindowsHookEx, MSG, PM_REMOVE, WH_KEYBOARD_LL, WH_MOUSE_LL,
        };
        // Global low-level hooks need this module's handle; without it Windows refuses them.
        let module = unsafe { windows::Win32::System::LibraryLoader::GetModuleHandleW(None) }.ok().map(|m| m.into());
        let kb = unsafe { SetWindowsHookExW(WH_KEYBOARD_LL, Some(keyboard), module, 0) };
        let ms = unsafe { SetWindowsHookExW(WH_MOUSE_LL, Some(mouse), module, 0) };
        if kb.is_err() || ms.is_err() {
            eprintln!("input watch could not start: {:?} {:?}", kb.as_ref().err(), ms.as_ref().err());
            HOOKED.store(false, Ordering::SeqCst);
        } else {
            HOOKED.store(true, Ordering::SeqCst);
        }
        while (epoch().elapsed().as_millis() as u64) < DEADLINE_MS.load(Ordering::SeqCst) {
            let mut msg = MSG::default();
            while unsafe { PeekMessageW(&mut msg, None, 0, 0, PM_REMOVE) }.as_bool() {
                unsafe {
                    let _ = TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                }
            }
            std::thread::sleep(Duration::from_millis(5)); // hooks are answered from this loop
        }
        if let Ok(h) = kb {
            let _ = unsafe { UnhookWindowsHookEx(h) };
        }
        if let Ok(h) = ms {
            let _ = unsafe { UnhookWindowsHookEx(h) };
        }
        RUNNING.store(false, Ordering::SeqCst);
    });
}

fn note() {
    LAST_INPUT.lock().unwrap().get_or_insert_with(Instant::now);
}

extern "system" fn keyboard(code: i32, wp: windows::Win32::Foundation::WPARAM, lp: windows::Win32::Foundation::LPARAM) -> windows::Win32::Foundation::LRESULT {
    use windows::Win32::UI::Input::KeyboardAndMouse::{VK_CONTROL, VK_LCONTROL, VK_LMENU, VK_LSHIFT, VK_LWIN, VK_MENU, VK_RCONTROL, VK_RMENU, VK_RSHIFT, VK_RWIN, VK_SHIFT};
    use windows::Win32::UI::WindowsAndMessaging::{CallNextHookEx, KBDLLHOOKSTRUCT, WM_KEYDOWN, WM_SYSKEYDOWN};
    if code >= 0 && (wp.0 as u32 == WM_KEYDOWN || wp.0 as u32 == WM_SYSKEYDOWN) {
        let k = unsafe { &*(lp.0 as *const KBDLLHOOKSTRUCT) };
        let modifier = [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN].iter().any(|v| v.0 as u32 == k.vkCode);
        if !modifier && k.dwExtraInfo != crate::insert::SIGNATURE {
            note();
        }
    }
    unsafe { CallNextHookEx(None, code, wp, lp) }
}

extern "system" fn mouse(code: i32, wp: windows::Win32::Foundation::WPARAM, lp: windows::Win32::Foundation::LPARAM) -> windows::Win32::Foundation::LRESULT {
    use windows::Win32::UI::WindowsAndMessaging::{CallNextHookEx, MSLLHOOKSTRUCT, WM_LBUTTONDOWN, WM_MBUTTONDOWN, WM_RBUTTONDOWN};
    if code >= 0 && matches!(wp.0 as u32, WM_LBUTTONDOWN | WM_RBUTTONDOWN | WM_MBUTTONDOWN) {
        let m = unsafe { &*(lp.0 as *const MSLLHOOKSTRUCT) };
        if m.dwExtraInfo != crate::insert::SIGNATURE {
            note();
        }
    }
    unsafe { CallNextHookEx(None, code, wp, lp) }
}

/// Number of Left presses that put the caret where `{cursor}` was, or None when it is absent or too far back.
/// A line break counts once, as Notepad, Word and browsers step over it in one press.
pub fn cursor_steps(text_after_marker: &str) -> Option<usize> {
    let n = text_after_marker.replace("\r\n", "\n").chars().count();
    (n <= 300).then_some(n)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn last(t0: Instant) -> Last {
        Last { target: 7, ended: t0, undoable: true, typed: false, program: Some("WINWORD.EXE".into()), console: false, raw: "a".into(), text: "A.".into(), leading_space: false, history_id: Some(1) }
    }

    #[test]
    fn guards() {
        let t0 = Instant::now();
        let s = |d: u64| t0 + Duration::from_millis(d);
        let never = vec!["WindowsTerminal.exe".to_string()];
        let l = last(t0);
        assert!(check(Some(&l), s(2000), 7, None, &never).is_ok(), "fresh, same window, no input");
        assert!(check(None, s(10), 7, None, &never).unwrap_err().contains("no recent"));
        assert!(check(Some(&Last { undoable: false, ..l.clone() }), s(10), 7, None, &never).unwrap_err().contains("not typed"));
        assert!(check(Some(&l), s(61_000), 7, None, &never).unwrap_err().contains("60 seconds"));
        assert!(check(Some(&l), s(59_000), 7, None, &never).is_ok());
        assert!(check(Some(&l), s(2000), 8, None, &never).unwrap_err().contains("window"));
        assert!(check(Some(&l), s(5000), 7, Some(s(1000)), &never).unwrap_err().contains("typed or clicked"), "input well before the request");
        assert!(check(Some(&l), s(5000), 7, Some(s(4700)), &never).is_ok(), "the request's own key or click");
        assert!(check(Some(&l), s(5000), 7, Some(t0 - Duration::from_millis(5)), &never).is_ok(), "input before the dictation ended");
        assert!(check(Some(&Last { console: true, ..l.clone() }), s(10), 7, None, &never).unwrap_err().contains("not offered"));
        assert!(check(Some(&Last { program: Some("windowsterminal.EXE".into()), ..l.clone() }), s(10), 7, None, &never).unwrap_err().contains("not offered"));
    }

    #[test]
    fn cursor() {
        assert_eq!(cursor_steps(""), Some(0));
        assert_eq!(cursor_steps("\r\nJo"), Some(3));
        assert_eq!(cursor_steps("ab\ncd"), Some(5));
        assert_eq!(cursor_steps(&"x".repeat(301)), None);
    }
}
