//! EsyMeet 8.2: notices when a meeting app starts using the microphone, so EsyType can offer to transcribe
//! (plan: docs/plans/esymeet-8.2-meeting-detection-plan.md). It never records anything itself.
//!
//! It asks Windows which programs have an active microphone stream right now: the audio sessions on each microphone
//! (WASAPI's session manager, a documented interface). The plan first named Windows' privacy record in the registry
//! (`CapabilityAccessManager\ConsentStore\microphone`), but on the development PC (Windows 11 build 26300) that record
//! had not been updated since September 2026, so it cannot tell what is in use now (measured 25 Nov).
//! Only apps on the meeting allow-list count, never "any app using the microphone", and never EsyType itself. Only
//! program file names are read: no window titles, meeting names or people.
use std::collections::HashMap;
use std::time::{Duration, Instant};

/// How long an app must hold the microphone before the prompt (a sound check or a voice search is shorter).
pub const MIN_USE: Duration = Duration::from_secs(5);

/// Meeting apps: (key for settings, name shown, program file names, Store package name prefixes; the last are kept for
/// reference, as audio sessions give program paths).
pub const APPS: &[(&str, &str, &[&str], &[&str])] = &[
    ("teams", "Microsoft Teams", &["ms-teams.exe", "teams.exe"], &["msteams_", "microsoftteams_"]),
    ("zoom", "Zoom", &["zoom.exe"], &[]),
    ("webex", "Webex", &["webex.exe", "ciscocollabhost.exe", "atmgr.exe"], &["cisco.webex"]),
    ("slack", "Slack", &["slack.exe"], &["91750d7e.slack_"]),
    ("skype", "Skype", &["skype.exe"], &["microsoft.skypeapp_"]),
    ("goto", "GoTo Meeting", &["g2mcomm.exe", "g2mstart.exe", "goto.exe"], &[]),
    ("ringcentral", "RingCentral", &["ringcentral.exe"], &[]),
    ("discord", "Discord", &["discord.exe"], &[]),
    ("chrome", "Chrome", &["chrome.exe"], &[]),
    ("edge", "Edge", &["msedge.exe"], &[]),
    ("firefox", "Firefox", &["firefox.exe"], &[]),
    ("brave", "Brave", &["brave.exe"], &[]),
    ("opera", "Opera", &["opera.exe"], &[]),
    ("vivaldi", "Vivaldi", &["vivaldi.exe"], &[]),
];

/// Apps switched off by default (Discord is often gaming voice chat; owner decision, 25 Nov).
pub fn default_off() -> Vec<String> {
    vec!["discord".into()]
}

/// The meeting app a program belongs to: (key, name), or None. `program` is its path or file name.
pub fn identify(program: &str, test_exe: Option<&str>) -> Option<(&'static str, &'static str)> {
    let lower = program.to_lowercase();
    let file = lower.rsplit(['#', '\\', '/']).next().unwrap_or(&lower);
    if file == "esytype.exe" {
        return None;
    }
    if test_exe.is_some_and(|t| t.eq_ignore_ascii_case(file)) {
        return Some(("test", "Test meeting")); // test builds only: the meeting suite's own program
    }
    APPS.iter().find(|a| a.2.contains(&file)).map(|a| (a.0, a.1))
}

/// A meeting app using the microphone now: key, name, and its process id (a new call in a new process is a new use).
#[derive(Clone, Debug, PartialEq)]
pub struct Active {
    pub key: &'static str,
    pub name: &'static str,
    pub since: u64,
}

/// The meeting apps with an active microphone stream right now.
pub fn read_active(test_exe: Option<&str>) -> Vec<Active> {
    let own = std::process::id();
    let mut out: Vec<Active> = Vec::new();
    for pid in sessions::capturing() {
        if pid == own {
            continue;
        }
        let Some(program) = sessions::program(pid) else { continue };
        if let Some((key, name)) = identify(&program, test_exe) {
            if !out.iter().any(|a| a.key == key) {
                out.push(Active { key, name, since: pid as u64 });
            }
        }
    }
    out
}

/// What the detector asks the app to do.
#[derive(Debug, PartialEq)]
pub enum Event {
    /// Show "Meeting detected · <name>".
    Prompt { key: &'static str, name: &'static str },
    /// The app the prompt is about stopped using the microphone (or was switched off): hide the prompt.
    Ended { key: &'static str },
}

struct Stretch {
    since: u64,
    seen: Instant,
    prompted: bool,
    /// Not now, or Start: no more prompts for this stretch of microphone use.
    answered: bool,
}

/// The rules (plan section 3), with no Windows calls, so they can be tested.
#[derive(Default)]
pub struct Detector {
    stretches: HashMap<&'static str, Stretch>,
    prompting: Option<&'static str>,
}

impl Detector {
    /// One look at the record. `enabled`: Settings, "Detect meetings"; `off`: apps switched off.
    pub fn step(&mut self, active: &[Active], now: Instant, enabled: bool, off: &[String]) -> Vec<Event> {
        let mut events = Vec::new();
        let allowed = |k: &str| enabled && !off.iter().any(|o| o == k);
        for a in active {
            let fresh = self.stretches.get(a.key).is_none_or(|s| s.since != a.since);
            if fresh {
                self.stretches.insert(a.key, Stretch { since: a.since, seen: now, prompted: false, answered: false });
            }
        }
        // Calls that ended (the app let go of the microphone), or apps switched off while prompting.
        self.stretches.retain(|k, _| active.iter().any(|a| a.key == *k));
        if let Some(p) = self.prompting {
            if !self.stretches.contains_key(p) || !allowed(p) {
                events.push(Event::Ended { key: p });
                self.prompting = None;
            }
        }
        if self.prompting.is_none() {
            let next = active
                .iter()
                .filter(|a| allowed(a.key))
                .filter_map(|a| self.stretches.get(a.key).map(|s| (a, s)))
                .filter(|(_, s)| !s.prompted && !s.answered && now.duration_since(s.seen) >= MIN_USE)
                .min_by_key(|(_, s)| s.seen)
                .map(|(a, _)| (a.key, a.name));
            if let Some((key, name)) = next {
                self.stretches.get_mut(key).unwrap().prompted = true;
                self.prompting = Some(key);
                events.push(Event::Prompt { key, name });
            }
        }
        events
    }

    /// Not now or Start: the prompt goes, and this call is not prompted again.
    pub fn answer(&mut self) {
        if let Some(p) = self.prompting.take() {
            if let Some(s) = self.stretches.get_mut(p) {
                s.answered = true;
            }
        }
    }

    /// The prompt faded unanswered: it goes, this call is not prompted again (the tray still offers Start).
    pub fn faded(&mut self) {
        self.answer();
    }

    /// A meeting app is using the microphone now and is allowed: the tray offers "Start meeting transcription".
    pub fn in_meeting(&self, enabled: bool, off: &[String]) -> Option<&'static str> {
        self.stretches.keys().find(|k| enabled && !off.iter().any(|o| o == *k)).copied()
    }
}

/// The Windows calls: which processes are capturing, and which program a process is.
mod sessions {
    use windows::core::Interface;
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::Media::Audio::{eCapture, AudioSessionStateActive, IAudioSessionControl2, IAudioSessionManager2, IMMDeviceEnumerator, MMDeviceEnumerator, DEVICE_STATE_ACTIVE};
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED};
    use windows::Win32::System::Diagnostics::ToolHelp::{CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS};
    use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};

    /// Process ids with an active audio session on any microphone.
    pub fn capturing() -> Vec<u32> {
        let mut pids = Vec::new();
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED); // once per thread; a repeat call is harmless
            let Ok(en) = CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL) else { return pids };
            let Ok(devices) = en.EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE) else { return pids };
            for i in 0..devices.GetCount().unwrap_or(0) {
                let Ok(dev) = devices.Item(i) else { continue };
                let Ok(mgr) = dev.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else { continue };
                let Ok(list) = mgr.GetSessionEnumerator() else { continue };
                for j in 0..list.GetCount().unwrap_or(0) {
                    let Ok(s) = list.GetSession(j) else { continue };
                    if s.GetState().ok() != Some(AudioSessionStateActive) {
                        continue;
                    }
                    if let Ok(pid) = s.cast::<IAudioSessionControl2>().and_then(|c| c.GetProcessId()) {
                        if pid != 0 && !pids.contains(&pid) {
                            pids.push(pid);
                        }
                    }
                }
            }
        }
        pids
    }

    /// The program a process runs. Apps built on WebView2 (the new Teams) capture through a `msedgewebview2.exe`
    /// helper: that is followed up to the app that started it.
    pub fn program(pid: u32) -> Option<String> {
        let mut pid = pid;
        for _ in 0..4 {
            let path = path_of(pid)?;
            if !path.to_lowercase().ends_with("msedgewebview2.exe") {
                return Some(path);
            }
            pid = parent_of(pid)?;
        }
        None
    }

    fn path_of(pid: u32) -> Option<String> {
        unsafe {
            let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
            let mut buf = [0u16; 1024];
            let mut n = buf.len() as u32;
            let r = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, windows::core::PWSTR(buf.as_mut_ptr()), &mut n);
            let _ = CloseHandle(h);
            r.ok().map(|_| String::from_utf16_lossy(&buf[..n as usize]))
        }
    }

    fn parent_of(pid: u32) -> Option<u32> {
        unsafe {
            let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0).ok()?;
            let mut e = PROCESSENTRY32W { dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32, ..Default::default() };
            let mut found = None;
            if Process32FirstW(snap, &mut e).is_ok() {
                loop {
                    if e.th32ProcessID == pid {
                        found = Some(e.th32ParentProcessID);
                        break;
                    }
                    if Process32NextW(snap, &mut e).is_err() {
                        break;
                    }
                }
            }
            let _ = CloseHandle(snap);
            found
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allow_list() {
        assert_eq!(identify(r"C:#Program Files#Zoom#bin#Zoom.exe", None), Some(("zoom", "Zoom")));
        assert_eq!(identify(r"C:#Program Files#Google#Chrome#Application#chrome.exe", None), Some(("chrome", "Chrome")));
        assert_eq!(identify(r"C:#Program Files (x86)#Microsoft#Edge#Application#msedge.exe", None), Some(("edge", "Edge")));
        assert_eq!(identify(r"C:\Program Files\WindowsApps\MSTeams_25.1_x64__8wekyb3d8bbwe\ms-teams.exe", None), Some(("teams", "Microsoft Teams")));
        assert_eq!(identify(r"C:#Users#x#AppData#Local#Microsoft#Teams#current#Teams.exe", None), Some(("teams", "Microsoft Teams")));
        // never EsyType, never other microphone users seen on the owner's PC
        for other in ["EsyType.exe", "Wispr Flow.exe", "obs64.exe", "VoiceAccess.exe", "VALORANT-Win64-Shipping.exe", "sox.exe", "msedgewebview2.exe"] {
            assert_eq!(identify(&format!(r"C:#Apps#{other}"), None), None, "{other}");
        }
        assert_eq!(identify(r"C:\Program Files\WindowsApps\Claude_1.0_x64__pzs8sxrjxfjjc\claude.exe", None), None);
        assert_eq!(identify(r"D:#AI Projects#Tools#meet-capture.exe", Some("meet-capture.exe")), Some(("test", "Test meeting")));
        assert_eq!(identify(r"D:#AI Projects#Tools#meet-capture.exe", None), None);
    }

    /// Manual check on a real PC: `cargo test --release live_sessions -- --ignored --nocapture` while a meeting app (or
    /// meet-capture.exe) uses the microphone.
    #[test]
    #[ignore]
    fn live_sessions() {
        println!("capturing pids: {:?}", sessions::capturing());
        for pid in sessions::capturing() {
            println!("  {pid}: {:?}", sessions::program(pid));
        }
        println!("meeting apps: {:?}", read_active(Some("meet-capture.exe")));
    }

    fn zoom(since: u64) -> Active {
        Active { key: "zoom", name: "Zoom", since }
    }

    #[test]
    fn rules() {
        let t0 = Instant::now();
        let at = |s: u64| t0 + Duration::from_secs(s);
        let mut d = Detector::default();
        let none: Vec<String> = vec![];
        // 5 s minimum
        assert!(d.step(&[zoom(1)], at(0), true, &none).is_empty());
        assert!(d.step(&[zoom(1)], at(4), true, &none).is_empty());
        assert_eq!(d.step(&[zoom(1)], at(5), true, &none), vec![Event::Prompt { key: "zoom", name: "Zoom" }]);
        assert!(d.step(&[zoom(1)], at(6), true, &none).is_empty(), "prompted once per call");
        // Not now: quiet for the rest of this call
        d.answer();
        assert!(d.step(&[zoom(1)], at(20), true, &none).is_empty());
        // the call ends, a new one starts: prompts again after 5 s
        assert!(d.step(&[], at(21), true, &none).is_empty());
        assert!(d.step(&[zoom(2)], at(22), true, &none).is_empty());
        assert_eq!(d.step(&[zoom(2)], at(27), true, &none).len(), 1);
        // the call ends while prompting: the prompt goes
        assert_eq!(d.step(&[], at(28), true, &none), vec![Event::Ended { key: "zoom" }]);
        // a short use (voice search) never prompts
        d.step(&[zoom(3)], at(30), true, &none);
        assert!(d.step(&[], at(33), true, &none).is_empty());
        // detection off, or the app switched off: nothing
        let mut d = Detector::default();
        d.step(&[zoom(4)], at(0), false, &none);
        assert!(d.step(&[zoom(4)], at(10), false, &none).is_empty());
        assert!(d.step(&[zoom(4)], at(10), true, &["zoom".into()]).is_empty());
        // two apps: one prompt, naming the first; the second waits until the first is answered
        let mut d = Detector::default();
        let chrome = Active { key: "chrome", name: "Chrome", since: 9 };
        d.step(&[zoom(5)], at(0), true, &none);
        d.step(&[zoom(5), chrome.clone()], at(1), true, &none);
        assert_eq!(d.step(&[zoom(5), chrome.clone()], at(6), true, &none), vec![Event::Prompt { key: "zoom", name: "Zoom" }]);
        d.answer();
        assert_eq!(d.step(&[zoom(5), chrome.clone()], at(7), true, &none), vec![Event::Prompt { key: "chrome", name: "Chrome" }]);
        // switched off while prompting: the prompt goes
        assert_eq!(d.step(&[zoom(5), chrome], at(8), true, &["chrome".into()]), vec![Event::Ended { key: "chrome" }]);
        // the tray's "Start meeting transcription": while an allowed meeting app holds the microphone
        assert!(d.in_meeting(true, &none).is_some());
        assert_eq!(d.in_meeting(true, &["zoom".into(), "chrome".into()]), None);
        assert_eq!(d.in_meeting(false, &none), None);
    }
}
