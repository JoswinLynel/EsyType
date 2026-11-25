//! Usage: meet-capture <seconds> <dir>
//! Captures your microphone and the PC's sound with EsyType's capture module (not yet in the app) into <dir>/mic.f32
//! and <dir>/system.f32 (16 kHz mono f32, one timeline). Prints a JSON status line every 5 s and a summary at the end,
//! with the start time (Unix ms) so a test can line up what it played.
#[path = "../../../src-tauri/src/audio.rs"]
#[allow(dead_code)]
mod audio;
#[path = "../../../src-tauri/src/capture.rs"]
mod capture;

use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct FileTime { lo: u32, hi: u32 }
extern "system" {
    fn GetCurrentProcess() -> isize;
    fn GetProcessTimes(p: isize, c: *mut FileTime, e: *mut FileTime, k: *mut FileTime, u: *mut FileTime) -> i32;
}
/// CPU seconds (user + kernel) used by this process so far.
fn cpu_s() -> f64 {
    let (mut c, mut e, mut k, mut u) = (FileTime::default(), FileTime::default(), FileTime::default(), FileTime::default());
    unsafe { GetProcessTimes(GetCurrentProcess(), &mut c, &mut e, &mut k, &mut u) };
    let t = |f: FileTime| ((f.hi as u64) << 32 | f.lo as u64) as f64 / 1e7;
    t(k) + t(u)
}
fn unix_ms() -> f64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs_f64() * 1000.0 }
fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('"', "\\\"") }

fn json(s: &capture::Stats) -> String {
    format!("{{\"device\":\"{}\",\"format\":\"{}\",\"seconds\":{:.3},\"padded_s\":{:.3},\"gaps\":{},\"reopens\":{},\"xruns\":{},\"late\":{},\"live\":{},\"level\":{:.4},\"events\":[{}]}}",
        esc(&s.device), esc(&s.format), s.samples as f64 / capture::RATE, s.padded as f64 / capture::RATE, s.gaps, s.reopens, s.xruns, s.late, s.live, s.level,
        s.events.iter().map(|e| format!("\"{}\"", esc(e))).collect::<Vec<_>>().join(","))
}

/// `--tones=<s>`: plays a 1 kHz, 200 ms tone through the default output every <s> seconds, from this process, and
/// prints when each tone's first sample was handed to Windows (`handed_s`, seconds on the capture's clock) and cpal's
/// own estimate of when it would be heard (`playback_est_s`). The test then finds each tone in both tracks.
fn tones(start: std::time::Instant, every: f64, until: f64) -> cpal::Stream {
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    let dev = cpal::default_host().default_output_device().expect("no output device");
    let cfg = dev.default_output_config().expect("output config");
    assert_eq!(cfg.sample_format(), cpal::SampleFormat::F32, "tones: f32 output only");
    let (rate, ch) = (cfg.sample_rate() as f64, cfg.channels() as usize);
    let (mut k, mut left) = (1u32, 0usize); // next tone; samples of the current tone still to play
    let len = (rate * 0.2) as usize;
    let s = dev.build_output_stream(cfg.into(), move |out: &mut [f32], info: &cpal::OutputCallbackInfo| {
        let now = start.elapsed().as_secs_f64();
        if left == 0 && now >= k as f64 * every && now < until {
            let ts = info.timestamp();
            let est = ts.playback.duration_since(ts.callback).as_secs_f64();
            println!("{{\"tone\":{k},\"handed_s\":{now:.4},\"playback_est_s\":{:.4}}}", now + est);
            left = len;
            k += 1;
        }
        for frame in out.chunks_mut(ch) {
            let v = if left > 0 {
                let i = len - left;
                left -= 1;
                let ramp = (i.min(len - i) as f64 / (rate * 0.002)).min(1.0); // 2 ms edges: a sharp but click-free start
                (0.3 * ramp * (2.0 * std::f64::consts::PI * 1000.0 * i as f64 / rate).sin()) as f32
            } else {
                0.0
            };
            frame.iter_mut().for_each(|s| *s = v);
        }
    }, |e| eprintln!("tone stream: {e}"), None).expect("tone stream");
    s.play().expect("play tones");
    s
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    assert!(a.len() >= 3, "usage: meet-capture <seconds> <dir> [--tones=<every s>]");
    let seconds: f64 = a[1].parse().expect("seconds");
    let before = unix_ms();
    let cap = capture::start(std::path::Path::new(&a[2]), None).expect("start");
    let start_ms = (before + unix_ms()) / 2.0;
    println!("{{\"started\":true,\"start_unix_ms\":{start_ms:.1}}}");
    let every: Option<f64> = a.iter().find_map(|x| x.strip_prefix("--tones=")).and_then(|v| v.parse().ok());
    let _tones = every.map(|e| tones(cap.start, e, seconds - 1.0));
    let mut last = 0.0;
    while cap.start.elapsed().as_secs_f64() < seconds {
        std::thread::sleep(Duration::from_millis(200));
        let t = cap.start.elapsed().as_secs_f64();
        if t - last >= 5.0 {
            last = t;
            let s = cap.stats();
            println!("{{\"t\":{t:.1},\"cpu_s\":{:.2},\"mic\":{},\"system\":{}}}", cpu_s(), json(&s[0]), json(&s[1]));
        }
    }
    let wall = cap.start.elapsed().as_secs_f64();
    let s = cap.stop();
    let cpu = cpu_s();
    println!("{{\"summary\":true,\"start_unix_ms\":{start_ms:.1},\"wall_s\":{wall:.3},\"cpu_s\":{cpu:.2},\"cpu_pct_of_one_core\":{:.2},\"mic\":{},\"system\":{}}}",
        cpu / wall * 100.0, json(&s[0]), json(&s[1]));
}
