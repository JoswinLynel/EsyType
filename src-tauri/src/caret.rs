//! The character just before the cursor in the window EsyType is about to type into, read through Windows'
//! accessibility interface (UI Automation), to decide whether dictated text needs a separating space.
//! Only that one character is read; it is never stored or logged. Password fields are never read.
use std::sync::mpsc;
use std::time::Duration;

/// How long EsyType waits for the app to answer. An app that is slow or does not expose its text gets the fallback.
const ANSWER_WITHIN: Duration = Duration::from_millis(300);

/// What is before the cursor: `None` if it cannot be read safely; `Some(None)` at the start of the text.
pub type Before = Option<Option<char>>;

pub fn before_cursor(target: isize) -> Before {
    let (tx, rx) = mpsc::channel();
    // Own thread: UI Automation calls into the other app; if it hangs, dictation does not.
    std::thread::spawn(move || {
        // Plain Windows text boxes (WinForms, older programs) do not offer their text to UI Automation.
        let _ = tx.send(read(target).or_else(|why| read_edit(target).map_err(|_| why)));
    });
    match rx.recv_timeout(ANSWER_WITHIN) {
        Ok(Ok(c)) => Some(c),
        Ok(Err(_why)) => {
            trace!("cannot read before the cursor: {_why}");
            None
        }
        Err(_) => {
            trace!("cannot read before the cursor: no answer in time");
            None
        }
    }
}

/// The character before the cursor (`None` at the start), or which step could not be done.
fn read(target: isize) -> Result<Option<char>, &'static str> {
    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED};
    use windows::Win32::UI::Accessibility::{
        CUIAutomation8, IUIAutomation2, IUIAutomationTextPattern, TextPatternRangeEndpoint_End, TextPatternRangeEndpoint_Start, TextUnit_Character, UIA_TextPatternId,
    };
    use windows::Win32::UI::WindowsAndMessaging::{GetAncestor, GA_ROOT};
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let uia: IUIAutomation2 = CoCreateInstance(&CUIAutomation8, None, CLSCTX_INPROC_SERVER).map_err(|_| "UI Automation unavailable")?;
        let _ = uia.SetConnectionTimeout(ANSWER_WITHIN.as_millis() as u32);
        let _ = uia.SetTransactionTimeout(ANSWER_WITHIN.as_millis() as u32);
        let el = uia.GetFocusedElement().map_err(|_| "no focused element")?;
        if el.CurrentIsPassword().map_err(|_| "no answer")?.as_bool() {
            return Err("password field");
        }
        // The focused element must be inside the window being typed into. Web content (Chrome, EsyType's own
        // window) has no window handle of its own, so look up to the nearest element that has one; it can belong to
        // a helper process (WebView2), so compare windows, not programs.
        let walker = uia.ControlViewWalker().map_err(|_| "no tree")?;
        let mut cur = el.clone();
        let mut hwnd = HWND::default();
        for _ in 0..40 {
            hwnd = cur.CurrentNativeWindowHandle().unwrap_or_default();
            if !hwnd.is_invalid() {
                break;
            }
            cur = walker.GetParentElement(&cur).map_err(|_| "no window above the focus")?;
        }
        if hwnd.is_invalid() || GetAncestor(hwnd, GA_ROOT) != HWND(target as _) {
            return Err("focus is in another window");
        }
        let text: IUIAutomationTextPattern = el.GetCurrentPatternAs(UIA_TextPatternId).map_err(|_| "no text pattern")?;
        let sel = text.GetSelection().map_err(|_| "no selection")?;
        if sel.Length().map_err(|_| "no selection")? < 1 {
            return Err("no cursor");
        }
        // From the start of the selection (the cursor), one character back.
        let r = sel.GetElement(0).and_then(|r| r.Clone()).map_err(|_| "no cursor range")?;
        r.MoveEndpointByRange(TextPatternRangeEndpoint_End, &r, TextPatternRangeEndpoint_Start).map_err(|_| "cannot move")?;
        if r.MoveEndpointByUnit(TextPatternRangeEndpoint_Start, TextUnit_Character, -1).map_err(|_| "cannot move")? == 0 {
            return Ok(None);
        }
        Ok(r.GetText(4).map_err(|_| "no text")?.to_string().chars().next_back())
    }
}

/// The same for a plain Windows text box ("Edit" class) with the keyboard focus in the target window, through the
/// standard text-box messages. Never a password box.
fn read_edit(target: isize) -> Result<Option<char>, &'static str> {
    use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
    use windows::Win32::UI::WindowsAndMessaging::{
        GetAncestor, GetClassNameW, GetGUIThreadInfo, GetWindowLongW, GetWindowThreadProcessId, SendMessageTimeoutW, GA_ROOT, GUITHREADINFO, GWL_STYLE,
        SMTO_ABORTIFHUNG, WM_GETTEXT,
    };
    const EM_GETSEL: u32 = 0x00B0;
    const ES_PASSWORD: i32 = 0x0020;
    unsafe {
        let tid = GetWindowThreadProcessId(HWND(target as _), None);
        let mut gui = GUITHREADINFO { cbSize: std::mem::size_of::<GUITHREADINFO>() as u32, ..Default::default() };
        GetGUIThreadInfo(tid, &mut gui).map_err(|_| "no focus")?;
        let h = gui.hwndFocus;
        if h.is_invalid() || GetAncestor(h, GA_ROOT) != HWND(target as _) {
            return Err("focus is in another window");
        }
        let mut class = [0u16; 64];
        let n = GetClassNameW(h, &mut class) as usize;
        let class = String::from_utf16_lossy(&class[..n]).to_ascii_lowercase();
        if !(class == "edit" || class.contains(".edit.")) {
            return Err("not a text box");
        }
        if GetWindowLongW(h, GWL_STYLE) & ES_PASSWORD != 0 {
            return Err("password field");
        }
        let ms = ANSWER_WITHIN.as_millis() as u32;
        let mut sel = 0usize;
        if SendMessageTimeoutW(h, EM_GETSEL, WPARAM(0), LPARAM(0), SMTO_ABORTIFHUNG, ms, Some(&mut sel)).0 == 0 {
            return Err("no answer");
        }
        let start = sel & 0xFFFF; // the cursor, or the start of the selection
        if start == 0 {
            return Ok(None);
        }
        // Only the text up to the cursor is read, and only its last character is kept.
        let mut buf = vec![0u16; start + 1];
        let mut got = 0usize;
        if SendMessageTimeoutW(h, WM_GETTEXT, WPARAM(buf.len()), LPARAM(buf.as_mut_ptr() as isize), SMTO_ABORTIFHUNG, ms, Some(&mut got)).0 == 0 || got < start {
            return Err("no text");
        }
        Ok(char::decode_utf16([buf[start - 1]]).next().and_then(|c| c.ok()))
    }
}

/// Whether dictated `text` needs a space in front: after a word or end punctuation, yes; after a space, a line
/// break, an opening bracket or quote, or at the start, no; text that begins with punctuation, a space or a line
/// break never gets one. If the app's text cannot be read, only after EsyType's own previous dictation there
/// (`follows_own`), as before.
pub fn needs_space(before: Before, follows_own: bool, text: &str) -> bool {
    let Some(first) = text.chars().next() else { return false };
    if first.is_whitespace() || ",.;:!?)]}%…'’\"”".contains(first) {
        return false;
    }
    match before {
        None => follows_own,
        Some(None) => false,
        Some(Some(c)) => !(c.is_whitespace() || "([{“‘«¿¡/'\"\u{a0}".contains(c)),
    }
}

#[cfg(test)]
mod tests {
    use super::needs_space;

    #[test]
    fn spacing() {
        let t = "We need milk.";
        assert!(needs_space(Some(Some('t')), false, t), "after a word typed by hand");
        assert!(needs_space(Some(Some('.')), false, t), "after a full stop");
        assert!(needs_space(Some(Some(',')), false, t), "after a comma");
        assert!(needs_space(Some(Some('5')), false, t));
        assert!(needs_space(Some(Some(')')), false, t));
        assert!(!needs_space(Some(Some(' ')), true, t), "already a space: never two");
        assert!(!needs_space(Some(Some('\n')), true, t), "start of a line");
        assert!(!needs_space(Some(Some('\t')), false, t));
        assert!(!needs_space(Some(Some('(')), false, t), "after an opening bracket");
        assert!(!needs_space(Some(Some('“')), false, t));
        assert!(!needs_space(Some(None), true, t), "start of the text");
        assert!(needs_space(None, true, t), "cannot read: after EsyType's own dictation, as before");
        assert!(!needs_space(None, false, t), "cannot read, typed by hand: no space (cannot know)");
        assert!(!needs_space(Some(Some('t')), true, ", and eggs"), "text that starts with punctuation");
        assert!(!needs_space(Some(Some('t')), true, "\nNext line"), "a snippet that starts with a line break");
        assert!(!needs_space(Some(Some('t')), true, ""));
    }
}
