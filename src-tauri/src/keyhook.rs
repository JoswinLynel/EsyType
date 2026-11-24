//! Push to talk on a single key (Mac design: Settings, Shortcuts): Right Ctrl, Right Alt or Right Shift, which a
//! global shortcut cannot register on its own. A low-level keyboard hook notes only that key's presses and releases
//! and passes them on; the key is swallowed while it is the push-to-talk key, so it does nothing else (a held Right
//! Alt would otherwise open app menus). The hook does no work itself, so typing is never slowed.
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Mutex, OnceLock};
use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, GetMessageW, SetWindowsHookExW, KBDLLHOOKSTRUCT, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP,
};

static KEY: AtomicU32 = AtomicU32::new(0); // virtual-key code; 0: no single-key push to talk
static DOWN: AtomicBool = AtomicBool::new(false);
static EVENTS: OnceLock<Mutex<Sender<bool>>> = OnceLock::new();

/// "RightCtrl", "RightAlt", "RightShift"; anything else: off.
pub fn vk(name: &str) -> u32 {
    match name {
        "RightCtrl" => 0xA3,
        "RightAlt" => 0xA5,
        "RightShift" => 0xA1,
        _ => 0,
    }
}

/// Chooses the key (0: off). The hook is installed the first time a key is chosen and then stays.
pub fn set_key(code: u32, events: impl FnOnce() -> Sender<bool>) {
    KEY.store(code, Ordering::SeqCst);
    DOWN.store(false, Ordering::SeqCst);
    if code != 0 && EVENTS.get().is_none() {
        let _ = EVENTS.set(Mutex::new(events()));
        std::thread::spawn(|| unsafe {
            let module = windows::Win32::System::LibraryLoader::GetModuleHandleW(None).ok();
            if SetWindowsHookExW(WH_KEYBOARD_LL, Some(hook), module.map(|m| m.into()), 0).is_err() {
                eprintln!("keyhook: could not install the keyboard hook");
                return;
            }
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {} // the hook runs on this thread's message loop
        });
    }
}

unsafe extern "system" fn hook(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    let key = KEY.load(Ordering::Relaxed);
    if code >= 0 && key != 0 {
        let kb = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
        if kb.vkCode == key {
            let msg = wparam.0 as u32;
            let pressed = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
            let released = msg == WM_KEYUP || msg == WM_SYSKEYUP;
            // Key repeat sends more key-downs while held: only the first counts.
            let changed = (pressed && !DOWN.swap(true, Ordering::SeqCst)) || (released && DOWN.swap(false, Ordering::SeqCst));
            if changed {
                if let Some(tx) = EVENTS.get() {
                    let _ = tx.lock().map(|t| t.send(pressed));
                }
            }
            if pressed || released {
                return LRESULT(1); // swallowed: the key does nothing else while it is the push-to-talk key
            }
        }
    }
    CallNextHookEx(None, code, wparam, lparam)
}

/// What a press or release means, given the dictation in progress and the previous tap.
#[derive(Debug, PartialEq)]
pub enum Act {
    StartHold,
    StartHandsFree,
    Stop,
    Cancel,
    Nothing,
}

/// `running`: None, or Some(true) for a hands-free dictation, Some(false) for a held one; `held_ms`: how long the key
/// has been down (on release); `since_tap_ms`: time since the last short tap ended, if any.
pub fn decide(pressed: bool, running: Option<bool>, held_ms: u64, since_tap_ms: Option<u64>, double_tap: bool, min_hold_ms: u64) -> Act {
    match (pressed, running) {
        (true, Some(true)) => Act::Stop,                                  // a tap ends hands-free
        (true, Some(false)) => Act::Nothing,
        (true, None) if double_tap && since_tap_ms.is_some_and(|t| t <= 400) => Act::StartHandsFree,
        (true, None) => Act::StartHold,
        (false, Some(false)) if held_ms < min_hold_ms => Act::Cancel,     // a tap, not a dictation
        (false, Some(false)) => Act::Stop,
        (false, _) => Act::Nothing,
    }
}

#[cfg(test)]
mod tests {
    use super::{decide, Act};
    #[test]
    fn hold_tap_and_double_tap() {
        assert_eq!(decide(true, None, 0, None, true, 400), Act::StartHold);
        assert_eq!(decide(false, Some(false), 2000, None, true, 400), Act::Stop, "held: stop and type");
        assert_eq!(decide(false, Some(false), 150, None, true, 400), Act::Cancel, "a short tap records nothing");
        assert_eq!(decide(true, None, 0, Some(250), true, 400), Act::StartHandsFree, "second tap soon after: hands-free");
        assert_eq!(decide(true, None, 0, Some(250), false, 400), Act::StartHold, "double-tap switched off");
        assert_eq!(decide(true, None, 0, Some(900), true, 400), Act::StartHold, "too slow for a double tap");
        assert_eq!(decide(false, Some(true), 100, None, true, 400), Act::Nothing, "releasing the second tap keeps hands-free");
        assert_eq!(decide(true, Some(true), 0, None, true, 400), Act::Stop, "a tap ends hands-free");
        assert_eq!(super::vk("RightCtrl"), 0xA3);
        assert_eq!(super::vk("Off"), 0);
    }
}
