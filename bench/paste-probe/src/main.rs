//! Usage: paste-probe <variant> <text>   (variant: app | gap | paced | plain | raw)
//! Sets the clipboard and sends Ctrl+V to the foreground window the way EsyType does, with one change per variant.
use std::{thread::sleep, time::Duration};
use windows::Win32::UI::Input::KeyboardAndMouse::*;

fn input(vk: VIRTUAL_KEY, up: bool) -> INPUT {
    let flags = if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) };
    INPUT { r#type: INPUT_KEYBOARD, Anonymous: INPUT_0 { ki: KEYBDINPUT { wVk: vk, wScan: 0, dwFlags: flags, time: 0, dwExtraInfo: 0 } } }
}

fn main() {
    use arboard::SetExtWindows;
    let a: Vec<String> = std::env::args().collect();
    let (variant, text) = (a[1].as_str(), a[2].as_str());
    if variant == "raw" {
        raw_set(text);
    } else {
        let mut cb = arboard::Clipboard::new().unwrap();
        if variant == "plain" { cb.set_text(text).unwrap() } else { cb.set().exclude_from_history().exclude_from_cloud().text(text).unwrap() }
    }
    if variant == "gap" { sleep(Duration::from_millis(150)); }
    let keys = [input(VK_CONTROL, false), input(VK_V, false), input(VK_V, true), input(VK_CONTROL, true)];
    if variant == "paced" {
        for k in keys { unsafe { SendInput(&[k], std::mem::size_of::<INPUT>() as i32) }; sleep(Duration::from_millis(30)); }
    } else {
        unsafe { SendInput(&keys, std::mem::size_of::<INPUT>() as i32) };
    }
    sleep(Duration::from_millis(500));
    raw_set("RESTORED");
}

/// Direct Win32: open, empty, put CF_UNICODETEXT, close.
fn raw_set(text: &str) {
    use windows::Win32::Foundation::HANDLE;
    use windows::Win32::System::DataExchange::*;
    use windows::Win32::System::Memory::*;
    let wide: Vec<u16> = text.encode_utf16().chain([0]).collect();
    unsafe {
        while OpenClipboard(None).is_err() { sleep(Duration::from_millis(20)); }
        let _ = EmptyClipboard();
        let g = GlobalAlloc(GMEM_MOVEABLE, wide.len() * 2).unwrap();
        let p = GlobalLock(g) as *mut u16;
        std::ptr::copy_nonoverlapping(wide.as_ptr(), p, wide.len());
        let _ = GlobalUnlock(g);
        let _ = SetClipboardData(13, Some(HANDLE(g.0)));
        let _ = CloseClipboard();
    }
}
