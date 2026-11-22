//! Puts the transcript into the window that had focus when recording started, and nowhere else.
use std::time::{Duration, Instant};
use windows::core::PCWSTR;
use windows::Win32::Foundation::{GlobalFree, HANDLE, HGLOBAL};
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, EnumClipboardFormats, GetClipboardData, GetClipboardFormatNameW, OpenClipboard, RegisterClipboardFormatW, SetClipboardData,
};
use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalSize, GlobalUnlock, GMEM_MOVEABLE};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP, KEYEVENTF_UNICODE, VIRTUAL_KEY,
    VK_CONTROL, VK_INSERT, VK_LEFT, VK_LWIN, VK_MENU, VK_RETURN, VK_RWIN, VK_SHIFT,
};
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

#[derive(Debug, PartialEq, Clone, Copy, serde::Serialize)]
pub enum Outcome {
    /// Pasted: the target program took the text from the clipboard (confirmed). The user's clipboard is put back.
    Pasted,
    /// Typed key by key, because the clipboard held something that cannot be copied exactly. Windows accepted the
    /// keystrokes; whether the program showed them cannot be confirmed.
    Typed,
    /// Focus moved to another window: nothing was typed, the text is on the clipboard instead.
    Copied,
    /// The paste key was sent but the target program never asked for the text, so it was not inserted.
    /// The user's clipboard is put back; the text is in History and can be copied from the pill.
    Failed,
}

pub fn foreground() -> isize {
    unsafe { GetForegroundWindow().0 as isize }
}

/// Executable file name of the program that owns a window, e.g. "WINWORD.EXE". Only the file name:
/// never the window title, which can hold document names, URLs or email subjects.
pub fn process_name(window: isize) -> Option<String> {
    use windows::core::PWSTR;
    use windows::Win32::Foundation::{CloseHandle, HWND};
    use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
    let mut pid = 0u32;
    unsafe { GetWindowThreadProcessId(HWND(window as _), Some(&mut pid)) };
    if pid == 0 {
        return None;
    }
    let h = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) }.ok()?;
    let mut buf = [0u16; 1024];
    let mut len = buf.len() as u32;
    let ok = unsafe { QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len) }.is_ok();
    let _ = unsafe { CloseHandle(h) };
    if !ok {
        return None;
    }
    let path = String::from_utf16_lossy(&buf[..len as usize]);
    std::path::Path::new(&path).file_name().map(|n| n.to_string_lossy().into_owned())
}

pub fn insert(text: &str, target: isize) -> Result<Outcome, String> {
    wait_for_modifiers_released(Duration::from_millis(1500));
    // The previous paste's text may still be on the clipboard; the user's clipboard must be back before it is read.
    wait_until_restored(Duration::from_secs(4));
    // The leading space that separates consecutive dictations belongs to the target window, not the clipboard.
    let copyable = text.trim_start();
    if foreground() != target {
        set_clipboard(copyable, false)?;
        return Ok(Outcome::Copied);
    }
    if let Some(saved) = snapshot() {
        paste(text, saved, target)
    } else {
        type_text(text).inspect_err(|_| {
            let _ = set_clipboard(copyable, false); // so the user can still paste it themselves
        })?;
        Ok(Outcome::Typed)
    }
}

/// The shortcut's Ctrl/Shift/Alt/Win may still be held; pasting then would send e.g. Ctrl+Shift+V.
pub fn wait_for_modifiers_released(max: Duration) {
    let t = Instant::now();
    let held = || [VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN].iter().any(|k| unsafe { GetAsyncKeyState(k.0 as i32) } as u16 & 0x8000 != 0);
    while held() && t.elapsed() < max {
        std::thread::sleep(Duration::from_millis(15));
    }
}

/// Every clipboard format that lives in ordinary global memory, copied byte for byte.
struct Snapshot(Vec<(u32, Vec<u8>)>);

const MAX_SNAPSHOT_BYTES: usize = 64 << 20;
const HISTORY_MARKERS: [&str; 3] = ["ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard"];

fn format_name(f: u32) -> String {
    let mut name = [0u16; 128];
    let n = unsafe { GetClipboardFormatNameW(f, &mut name) };
    String::from_utf16_lossy(&name[..n.max(0) as usize])
}

fn open_clipboard() -> bool {
    for _ in 0..25 {
        if unsafe { OpenClipboard(None) }.is_ok() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20)); // another app has the clipboard open
    }
    false
}

/// Copies the user's clipboard so it can be put back exactly after pasting. Returns None when it holds
/// something that cannot be copied exactly (drawing handles, owner-drawn or private formats) or is very
/// large; EsyType then types the text instead, leaving the clipboard untouched.
fn snapshot() -> Option<Snapshot> {
    if !open_clipboard() {
        return None;
    }
    let result = (|| {
        let mut formats = vec![];
        let mut f = 0;
        loop {
            f = unsafe { EnumClipboardFormats(f) };
            if f == 0 {
                break;
            }
            formats.push(f);
        }
        let has = |x: u32| formats.contains(&x);
        let (mut out, mut total) = (vec![], 0usize);
        for &f in &formats {
            match f {
                2 if has(8) || has(17) => continue, // CF_BITMAP: Windows recreates it from the DIB
                1 | 7 if has(13) => continue,       // ANSI/OEM text: recreated from CF_UNICODETEXT
                2 | 3 | 9 | 14 | 0x80..=0x8F | 0x200..=0x3FF => return None, // handles, not memory
                _ => {}
            }
            let name = format_name(f);
            if name == "DataObject" || name == "Ole Private Data" {
                continue; // OLE bookkeeping that points into the source app; the data itself is kept
            }
            let h = unsafe { GetClipboardData(f) }.ok()?;
            let g = HGLOBAL(h.0);
            let size = unsafe { GlobalSize(g) };
            total += size;
            if total > MAX_SNAPSHOT_BYTES {
                return None;
            }
            let p = unsafe { GlobalLock(g) } as *const u8;
            if p.is_null() {
                return None;
            }
            let bytes = unsafe { std::slice::from_raw_parts(p, size) }.to_vec();
            let _ = unsafe { GlobalUnlock(g) };
            out.push((f, bytes));
        }
        Some(Snapshot(out))
    })();
    let _ = unsafe { CloseClipboard() };
    result
}

/// Puts a snapshot back, marked so Windows does not add it to clipboard history a second time. On failure the
/// snapshot is handed back, to try again.
fn restore(saved: Snapshot) -> Result<(), (String, Snapshot)> {
    if !open_clipboard() {
        return Err(("Could not restore the clipboard: another app is holding it.".into(), saved));
    }
    let _ = unsafe { EmptyClipboard() };
    let names: Vec<String> = saved.0.iter().map(|(f, _)| format_name(*f)).collect();
    for (f, bytes) in &saved.0 {
        put(*f, bytes);
    }
    put_history_markers_except(&names);
    let _ = unsafe { CloseClipboard() };
    Ok(())
}

/// Adds a copy of `bytes` to the open clipboard.
fn put(f: u32, bytes: &[u8]) {
    unsafe {
        let Ok(g) = GlobalAlloc(GMEM_MOVEABLE, bytes.len().max(1)) else { return };
        let p = GlobalLock(g) as *mut u8;
        if p.is_null() {
            let _ = GlobalFree(Some(g));
            return;
        }
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), p, bytes.len());
        let _ = GlobalUnlock(g);
        if SetClipboardData(f, Some(HANDLE(g.0))).is_err() {
            let _ = GlobalFree(Some(g)); // ownership passes to Windows only on success
        }
    }
}

/// Marks the open clipboard's content to stay out of clipboard history, cloud sync and clipboard monitors.
fn put_history_markers_except(present: &[String]) {
    for m in HISTORY_MARKERS.iter().filter(|m| !present.iter().any(|n| n == *m)) {
        let wide: Vec<u16> = m.encode_utf16().chain([0]).collect();
        let f = unsafe { RegisterClipboardFormatW(PCWSTR(wide.as_ptr())) };
        put(f, &0u32.to_ne_bytes());
    }
}

pub fn set_clipboard(text: &str, hide_from_history: bool) -> Result<(), String> {
    use arboard::SetExtWindows;
    wait_until_restored(Duration::from_secs(4)); // or the restore would overwrite this copy
    let mut cb = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    let r = if hide_from_history { cb.set().exclude_from_history().exclude_from_cloud().text(text) } else { cb.set().text(text) };
    r.map_err(|e| format!("Could not use the clipboard: {e}"))
}

/// How long the target program has to ask for the text after the paste key. Measured on the development PC:
/// Notepad, Word, Chrome, ChatGPT and a WinForms window asked within 5-100 ms; a busy program can take longer.
const CONFIRM_WITHIN: Duration = Duration::from_millis(3000);

/// How long the text stays on the clipboard after the target first asks for it. Word reads it several times per
/// paste, the last read up to ~220 ms after the first on an idle PC (measured) and later on a busy one: with a fixed
/// 250 ms it once pasted the user's clipboard. At least a second, longer when the target was slow to ask.
fn hold_after(first_read: Duration) -> Duration {
    (first_read * 25).clamp(Duration::from_millis(1000), Duration::from_millis(3000))
}

/// True while a paste's text is still on the clipboard; the user's clipboard is put back when it turns false.
static HOLDING: std::sync::Mutex<bool> = std::sync::Mutex::new(false);
static RESTORED: std::sync::Condvar = std::sync::Condvar::new();

/// Waits (at most `max`) until the user's clipboard is back after the last paste.
pub fn wait_until_restored(max: Duration) {
    let held = HOLDING.lock().unwrap_or_else(|e| e.into_inner());
    let _ = RESTORED.wait_timeout_while(held, max, |h| *h);
}

/// Marks the end of a paste's hold, also if the paste thread fails.
struct Released;
impl Drop for Released {
    fn drop(&mut self) {
        *HOLDING.lock().unwrap_or_else(|e| e.into_inner()) = false;
        RESTORED.notify_all();
    }
}

/// Pastes through a clipboard "promise" (delayed rendering): the text is handed over only when a program asks for
/// it, so EsyType knows whether the target actually took it, and the user's clipboard is put back only after that.
/// The outcome is known as soon as the target asks; the text then stays on the clipboard a little longer on the
/// paste's own thread (see `hold_after`), so the pill, History and the next dictation do not wait for it.
fn paste(text: &str, saved: Snapshot, target: isize) -> Result<Outcome, String> {
    let (tx, rx) = std::sync::mpsc::channel();
    let text = text.to_string();
    *HOLDING.lock().unwrap_or_else(|e| e.into_inner()) = true;
    std::thread::spawn(move || {
        let _released = Released;
        let owner = match owner::Owner::new(&text, target) {
            Ok(o) => o,
            Err(e) => {
                let _ = restore(saved);
                let _ = tx.send(Err(e));
                return;
            }
        };
        if let Err(e) = owner.offer() {
            let _ = restore(saved);
            let _ = tx.send(Err(e));
            return;
        }
        // Programs that read every new clipboard do so within ~20 ms (measured). Their requests are refused until
        // the paste key has been sent, so the first request after it is the target's, and they never get the text.
        owner.pump(Duration::from_millis(150));
        owner.arm();
        let sent = send(&paste_keys());
        if !(sent.is_ok() && owner.wait_until_taken(CONFIRM_WITHIN)) {
            let restored = restore(saved).map_err(|(e, _)| e);
            drop(owner);
            // blocked keystrokes: the user's clipboard is back; the caller offers the text instead
            let _ = tx.send(sent.and(restored).map(|_| Outcome::Failed));
            return;
        }
        let _ = tx.send(Ok(Outcome::Pasted));
        owner.pump(hold_after(owner.first_read_after()));
        if !owner.taken_anonymously() {
            owner::learn(target);
        }
        if !owner.still_owns() {
            // Something else was copied meanwhile (by the user or a program): that is newer, so it stays.
            trace!("clipboard changed during the paste; not put back");
            drop(owner);
            return;
        }
        // Nobody is waiting now, so keep trying if another program is holding the clipboard.
        let mut saved = Some(saved);
        for _ in 0..20 {
            match restore(saved.take().unwrap()) {
                Ok(()) => break,
                Err((_e, back)) => {
                    trace!("{_e} Trying again.");
                    saved = Some(back);
                    std::thread::sleep(Duration::from_millis(100));
                }
            }
        }
        drop(owner);
    });
    rx.recv().unwrap_or_else(|_| Err("The paste stopped unexpectedly.".into()))
}

/// A hidden window that owns the clipboard while a paste is in flight and renders the text on request.
mod owner {
    use std::cell::RefCell;
    use std::time::{Duration, Instant};
    use windows::core::w;
    use windows::Win32::Foundation::{GlobalFree, HANDLE, HWND, LPARAM, LRESULT, WPARAM};
    use windows::Win32::System::DataExchange::{
        CloseClipboard, EmptyClipboard, GetClipboardOwner, GetOpenClipboardWindow, IsClipboardFormatAvailable, OpenClipboard, SetClipboardData,
    };
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetWindowThreadProcessId, PeekMessageW, RegisterClassW, TranslateMessage, HWND_MESSAGE, MSG,
        PM_REMOVE, WINDOW_EX_STYLE, WINDOW_STYLE, WM_RENDERALLFORMATS, WM_RENDERFORMAT, WNDCLASSW,
    };

    const CF_UNICODETEXT: u32 = 13;

    struct Pending {
        text: Vec<u16>, // with the terminating NUL
        target_pid: u32,
        since: Instant,
        /// False until the paste key is about to be sent: requests before that cannot be the paste and are refused.
        armed: bool,
        taken: bool,
        /// The target is known to identify itself when it reads, so a read that does not is someone else's.
        refuse_anonymous: bool,
        /// Taken by a read that did not identify the program.
        anonymous: bool,
        /// How long after the paste key the text was first asked for.
        first_read: Duration,
    }

    /// Programs that open the clipboard with a window of their own when they paste (measured: Word, Notepad; Office
    /// and most programs read through OLE, which does). Chrome and Electron apps do not. Lower case.
    const IDENTIFY_THEMSELVES: [&str; 6] = ["winword.exe", "excel.exe", "powerpnt.exe", "outlook.exe", "onenote.exe", "notepad.exe"];
    /// Programs seen identifying themselves since EsyType started.
    static LEARNED: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

    fn identifies_itself(program: Option<&str>) -> bool {
        program.map(str::to_lowercase).is_some_and(|p| IDENTIFY_THEMSELVES.contains(&p.as_str()) || LEARNED.lock().unwrap().contains(&p))
    }

    /// Remembers that the target program identified itself, so later reads without a window are refused for it.
    pub fn learn(target: isize) {
        if let Some(p) = super::process_name(target).map(|p| p.to_lowercase()) {
            let mut l = LEARNED.lock().unwrap();
            if !l.contains(&p) && !IDENTIFY_THEMSELVES.contains(&p.as_str()) {
                l.push(p);
            }
        }
    }

    #[derive(Debug, PartialEq)]
    pub(super) enum Verdict {
        Refuse(&'static str),
        Target,
        Anonymous,
    }

    /// Who may have the text: only a request after the paste key, from the target program, or (for programs that do
    /// not identify themselves, like Chrome) from a reader without a window.
    pub(super) fn judge(armed: bool, reader_pid: Option<u32>, target_pid: u32, refuse_anonymous: bool) -> Verdict {
        match reader_pid {
            _ if !armed => Verdict::Refuse("request before the paste"),
            Some(pid) if pid == target_pid => Verdict::Target,
            Some(_) => Verdict::Refuse("request from another program"),
            None if refuse_anonymous => Verdict::Refuse("request without a window (this program identifies itself)"),
            None => Verdict::Anonymous,
        }
    }

    thread_local! {
        static PENDING: RefCell<Option<Pending>> = const { RefCell::new(None) };
    }

    fn pid_of(w: HWND) -> u32 {
        let mut pid = 0;
        unsafe { GetWindowThreadProcessId(w, Some(&mut pid)) };
        pid
    }

    /// Answers a request for the text. Only the target program gets it: requests before the paste key is sent, and
    /// requests from any other program, are refused (nothing is rendered), so the promise stays open for the
    /// target.
    fn render(force: bool) {
        let reader = unsafe { GetOpenClipboardWindow() }.ok().filter(|w| !w.is_invalid());
        PENDING.with_borrow_mut(|p| {
            let Some(p) = p else { return };
            if !force {
                // Refused requests get nothing, so the promise stays open for the target. A background program that
                // read without a window was once counted as the paste while a slow Word asked later and got the
                // user's clipboard; for programs that identify themselves such reads are refused.
                match judge(p.armed, reader.map(pid_of), p.target_pid, p.refuse_anonymous) {
                    Verdict::Refuse(_why) => {
                        trace!("{_why} refused ({} ms)", p.since.elapsed().as_millis());
                        return;
                    }
                    Verdict::Target => p.anonymous = false,
                    Verdict::Anonymous => p.anonymous = true,
                }
                if !p.taken {
                    p.first_read = p.since.elapsed();
                }
                p.taken = true;
                trace!(
                    "text taken by the target {} ms after the paste key (opened by {})",
                    p.since.elapsed().as_millis(),
                    reader.map_or("no window".to_string(), |w| format!("pid {}", pid_of(w)))
                );
            }
            let bytes = p.text.len() * 2;
            unsafe {
                let Ok(g) = GlobalAlloc(GMEM_MOVEABLE, bytes) else { return };
                let dst = GlobalLock(g) as *mut u16;
                if dst.is_null() {
                    let _ = GlobalFree(Some(g));
                    return;
                }
                std::ptr::copy_nonoverlapping(p.text.as_ptr(), dst, p.text.len());
                let _ = GlobalUnlock(g);
                if SetClipboardData(CF_UNICODETEXT, Some(HANDLE(g.0))).is_err() {
                    let _ = GlobalFree(Some(g));
                }
            }
        });
    }

    extern "system" fn proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
        match msg {
            WM_RENDERFORMAT if wp.0 as u32 == CF_UNICODETEXT => render(false),
            // Destroyed while still owning the promise (the clipboard could not be restored): keep the text available.
            WM_RENDERALLFORMATS => unsafe {
                if OpenClipboard(Some(hwnd)).is_ok() {
                    if GetClipboardOwner().ok() == Some(hwnd) {
                        render(true);
                    }
                    let _ = CloseClipboard();
                }
            },
            _ => return unsafe { DefWindowProcW(hwnd, msg, wp, lp) },
        }
        LRESULT(0)
    }

    pub struct Owner(HWND);

    impl Owner {
        pub fn new(text: &str, target: isize) -> Result<Owner, String> {
            let instance = unsafe { GetModuleHandleW(None) }.map_err(|e| e.to_string())?;
            let class = WNDCLASSW { lpfnWndProc: Some(proc), hInstance: instance.into(), lpszClassName: w!("EsyTypeClipboardOwner"), ..Default::default() };
            unsafe { RegisterClassW(&class) }; // fails harmlessly when already registered
            let hwnd = unsafe {
                CreateWindowExW(WINDOW_EX_STYLE(0), w!("EsyTypeClipboardOwner"), w!(""), WINDOW_STYLE(0), 0, 0, 0, 0, Some(HWND_MESSAGE), None, Some(instance.into()), None)
            }
            .map_err(|e| format!("Could not prepare the paste: {e}"))?;
            let mut target_pid = 0;
            unsafe { GetWindowThreadProcessId(HWND(target as _), Some(&mut target_pid)) };
            // Line breaks as CRLF, the Windows clipboard convention.
            let text = text.replace("\r\n", "\n").replace('\n', "\r\n").encode_utf16().chain([0]).collect();
            let refuse_anonymous = identifies_itself(super::process_name(target).as_deref());
            PENDING.with_borrow_mut(|p| *p = Some(Pending { text, target_pid, since: Instant::now(), armed: false, taken: false, refuse_anonymous, anonymous: false, first_read: Duration::ZERO }));
            Ok(Owner(hwnd))
        }

        /// Replaces the clipboard with a promise of the text, marked to stay out of clipboard history.
        pub fn offer(&self) -> Result<(), String> {
            for _ in 0..25 {
                if unsafe { OpenClipboard(Some(self.0)) }.is_ok() {
                    let _ = unsafe { EmptyClipboard() };
                    // A promise returns a null handle even on success, which the wrapper reports as an error.
                    let _ = unsafe { SetClipboardData(CF_UNICODETEXT, None) };
                    let ok = unsafe { IsClipboardFormatAvailable(CF_UNICODETEXT) }.is_ok();
                    super::put_history_markers_except(&[]);
                    let _ = unsafe { CloseClipboard() };
                    PENDING.with_borrow_mut(|p| p.as_mut().map(|p| p.since = Instant::now()));
                    return if ok { Ok(()) } else { Err("Could not use the clipboard.".into()) };
                }
                std::thread::sleep(Duration::from_millis(20));
            }
            Err("Could not use the clipboard: another app is holding it.".into())
        }

        /// From now on a request for the text is taken to be the paste.
        pub fn arm(&self) {
            PENDING.with_borrow_mut(|p| {
                if let Some(p) = p {
                    p.armed = true;
                    p.since = Instant::now();
                }
            });
        }

        /// Handles clipboard requests until the target program has asked for the text, or `max` has passed.
        pub fn wait_until_taken(&self, max: Duration) -> bool {
            let t = Instant::now();
            while t.elapsed() < max {
                self.pump(Duration::from_millis(5));
                if PENDING.with_borrow(|p| p.as_ref().is_some_and(|p| p.taken)) {
                    return true;
                }
            }
            false
        }

        /// The clipboard still holds the text EsyType offered (nobody copied anything since).
        pub fn still_owns(&self) -> bool {
            unsafe { GetClipboardOwner() }.ok() == Some(self.0)
        }

        pub fn first_read_after(&self) -> Duration {
            PENDING.with_borrow(|p| p.as_ref().map_or(Duration::ZERO, |p| p.first_read))
        }

        pub fn taken_anonymously(&self) -> bool {
            PENDING.with_borrow(|p| p.as_ref().is_some_and(|p| p.anonymous))
        }

        pub fn pump(&self, d: Duration) {
            let t = Instant::now();
            loop {
                let mut msg = MSG::default();
                while unsafe { PeekMessageW(&mut msg, Some(self.0), 0, 0, PM_REMOVE) }.as_bool() {
                    unsafe {
                        let _ = TranslateMessage(&msg);
                        DispatchMessageW(&msg);
                    }
                }
                if t.elapsed() >= d {
                    break;
                }
                std::thread::sleep(Duration::from_millis(2));
            }
        }
    }

    impl Drop for Owner {
        fn drop(&mut self) {
            let _ = unsafe { DestroyWindow(self.0) };
            PENDING.with_borrow_mut(|p| *p = None);
        }
    }
}

fn type_text(text: &str) -> Result<(), String> {
    let mut inputs = Vec::new();
    for unit in text.replace("\r\n", "\n").encode_utf16() {
        if unit == '\n' as u16 {
            // Shift+Enter: a new line in chat boxes instead of sending a half-finished message.
            inputs.extend([key(VK_SHIFT, false), key(VK_RETURN, false), key(VK_RETURN, true), key(VK_SHIFT, true)]);
        } else {
            inputs.push(unicode(unit, false));
            inputs.push(unicode(unit, true));
        }
    }
    send(&inputs)
}

fn send(inputs: &[INPUT]) -> Result<(), String> {
    let n = unsafe { SendInput(inputs, std::mem::size_of::<INPUT>() as i32) };
    if n as usize == inputs.len() {
        Ok(())
    } else {
        Err("Windows blocked the text from being typed (the target may be running as administrator). The text is on the clipboard.".into())
    }
}

/// Shift+Insert, the standard alternative paste key: on the development PC a background program read the
/// clipboard every time Ctrl+V was pressed, which made a paste the target ignored look successful.
fn paste_keys() -> Vec<INPUT> {
    #[cfg(feature = "e2e")]
    if std::env::var("ESYTYPE_PASTE_KEY").as_deref() == Ok("ctrlv") {
        let v = VIRTUAL_KEY(0x56); // V
        return vec![key(VK_CONTROL, false), key(v, false), key(v, true), key(VK_CONTROL, true)];
    }
    // Insert is on the extended key block; without the flag it can arrive as numeric keypad 0.
    let ins = |up: bool| input(VK_INSERT, 0, if up { KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP } else { KEYEVENTF_EXTENDEDKEY });
    vec![key(VK_SHIFT, false), ins(false), ins(true), key(VK_SHIFT, true)]
}

fn key(vk: VIRTUAL_KEY, up: bool) -> INPUT {
    input(vk, 0, if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) })
}

fn unicode(unit: u16, up: bool) -> INPUT {
    input(VIRTUAL_KEY(0), unit, if up { KEYEVENTF_UNICODE | KEYEVENTF_KEYUP } else { KEYEVENTF_UNICODE })
}

/// Marks EsyType's own simulated keys, so the Undo guard never mistakes them for the user's typing.
pub const SIGNATURE: usize = 0x4553_5954; // "ESYT"

fn input(vk: VIRTUAL_KEY, scan: u16, flags: KEYBD_EVENT_FLAGS) -> INPUT {
    INPUT { r#type: INPUT_KEYBOARD, Anonymous: INPUT_0 { ki: KEYBDINPUT { wVk: vk, wScan: scan, dwFlags: flags, time: 0, dwExtraInfo: SIGNATURE } } }
}

/// The app's own Undo, once (after the user's shortcut keys are released).
pub fn send_undo() -> Result<(), String> {
    wait_for_modifiers_released(Duration::from_millis(1500));
    let z = VIRTUAL_KEY(0x5A);
    send(&[key(VK_CONTROL, false), key(z, false), key(z, true), key(VK_CONTROL, true)])
}

/// One Alt press and release, marked as EsyType's own.
pub fn tap_alt() {
    let _ = send(&[key(VK_MENU, false), key(VK_MENU, true)]);
}

/// Moves the caret left `n` characters (for a snippet's {cursor}).
pub fn press_left(n: usize) -> Result<(), String> {
    let left = |up: bool| input(VK_LEFT, 0, if up { KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP } else { KEYEVENTF_EXTENDEDKEY });
    let keys: Vec<INPUT> = (0..n).flat_map(|_| [left(false), left(true)]).collect();
    if keys.is_empty() { Ok(()) } else { send(&keys) }
}

/// A console or terminal window (identified by its window class, never its title), where Ctrl+Z means something else.
pub fn is_console(window: isize) -> bool {
    use windows::Win32::UI::WindowsAndMessaging::GetClassNameW;
    let mut buf = [0u16; 128];
    let n = unsafe { GetClassNameW(windows::Win32::Foundation::HWND(window as _), &mut buf) };
    let class = String::from_utf16_lossy(&buf[..n.max(0) as usize]);
    matches!(class.as_str(), "ConsoleWindowClass" | "CASCADIA_HOSTING_WINDOW_CLASS" | "PseudoConsoleWindow" | "mintty")
}

#[cfg(test)]
mod tests {
    #[test]
    fn hold_after_the_first_read() {
        use std::time::Duration as D;
        assert_eq!(super::hold_after(D::from_millis(20)), D::from_millis(1000), "at least a second (Word reads again up to ~220 ms later)");
        assert_eq!(super::hold_after(D::from_millis(80)), D::from_millis(2000), "a slow program gets longer");
        assert_eq!(super::hold_after(D::from_secs(2)), D::from_millis(3000), "never more than three seconds");
    }

    #[test]
    fn who_gets_the_text() {
        use super::owner::{judge, Verdict::*};
        assert!(matches!(judge(false, Some(7), 7, false), Refuse(_)), "nothing before the paste key");
        assert_eq!(judge(true, Some(7), 7, true), Target);
        assert!(matches!(judge(true, Some(8), 7, false), Refuse(_)), "another identified program");
        assert_eq!(judge(true, None, 7, false), Anonymous, "Chrome reads without a window");
        assert!(matches!(judge(true, None, 7, true), Refuse(_)), "Word identifies itself: a read without a window is someone else");
    }

    #[test]
    fn process_name_is_the_executable_file_name_only() {
        use windows::core::w;
        use windows::Win32::UI::WindowsAndMessaging::FindWindowW;
        let taskbar = unsafe { FindWindowW(w!("Shell_TrayWnd"), None) }.expect("the Windows taskbar exists");
        let name = super::process_name(taskbar.0 as isize).expect("taskbar owner");
        assert!(name.eq_ignore_ascii_case("explorer.exe"), "{name}"); // no folder, no window title
        assert_eq!(super::process_name(0), None);
    }
}
