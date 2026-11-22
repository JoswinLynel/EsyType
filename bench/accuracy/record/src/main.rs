//! Recording kit for the real-voice accuracy benchmark (`docs/plans/recognition-accuracy-plan.md`, Proposal C).
//! Test tool only: recordings stay on this PC.
//!
//!   esytype-record list                                      the microphones Windows offers
//!   esytype-record record <script.json> <folder> [--mic NAME] [--only ID,ID]
//!   esytype-record convert <folder>                          <folder>\app16k\owner-<id>.f32 via the app's own 16 kHz code
//!
//! `record` shows one sentence at a time and saves <id>.wav: mono (channels averaged, as the app does), 16-bit, at the
//! microphone's own rate, so the 16 kHz conversion can be tested later. takes.json in the folder lists every take;
//! sentences already recorded are skipped, so a session can be stopped and carried on.
#[allow(dead_code)]
#[path = "../../../../src-tauri/src/audio.rs"]
mod audio;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SizedSample};
use serde_json::{json, Map, Value};
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let r = match a.get(1).map(|s| s.as_str()) {
        Some("list") => Ok(for m in audio::list_inputs() { println!("{m}") }),
        Some("record") if a.len() >= 4 => record(Path::new(&a[2]), Path::new(&a[3]), flag(&a, "--mic"), flag(&a, "--only")),
        Some("convert") if a.len() >= 3 => convert(Path::new(&a[2])),
        _ => Err("usage: esytype-record list | record <script.json> <folder> [--mic NAME] [--only ID,ID] | convert <folder>".into()),
    };
    if let Err(e) = r {
        eprintln!("{e}");
        std::process::exit(1);
    }
}

fn flag(a: &[String], name: &str) -> Option<String> {
    a.iter().position(|x| x == name).and_then(|i| a.get(i + 1).cloned())
}

fn line() -> String {
    let mut s = String::new();
    std::io::stdin().lock().read_line(&mut s).ok();
    s.trim().to_lowercase()
}

// ---------- capture at the microphone's own rate ----------

struct Mic {
    device: cpal::Device,
    name: String,
    rate: u32,
    channels: u16,
}

fn open(mic: Option<&str>) -> Result<Mic, String> {
    let host = cpal::default_host();
    let device = match mic {
        Some(n) => host.input_devices().map_err(|e| e.to_string())?.find(|d| audio::device_name(d) == n)
            .ok_or(format!("No microphone called \"{n}\". `esytype-record list` shows the names."))?,
        None => host.default_input_device().ok_or("No microphone found. Connect one, or check Windows sound settings.")?,
    };
    let c = device.default_input_config().map_err(|e| format!("The microphone could not be opened: {e}"))?;
    Ok(Mic { name: audio::device_name(&device), rate: c.sample_rate(), channels: c.channels(), device })
}

/// Records until `stop` is set, then keeps going for `tail` so the last word is never cut. Returns mono samples.
fn capture(m: &Mic, stop: &AtomicBool, level: Arc<AtomicU32>, tail: Duration) -> Result<Vec<f32>, String> {
    let c = m.device.default_input_config().map_err(|e| e.to_string())?;
    let buf = Arc::new(Mutex::new(Vec::<f32>::new()));
    let ch = m.channels as usize;
    let stream = match c.sample_format() {
        cpal::SampleFormat::F32 => build::<f32>(&m.device, &c.into(), ch, buf.clone(), level),
        cpal::SampleFormat::I16 => build::<i16>(&m.device, &c.into(), ch, buf.clone(), level),
        cpal::SampleFormat::I32 => build::<i32>(&m.device, &c.into(), ch, buf.clone(), level),
        cpal::SampleFormat::U16 => build::<u16>(&m.device, &c.into(), ch, buf.clone(), level),
        f => Err(format!("Unsupported microphone sample format: {f}")),
    }?;
    stream.play().map_err(|e| e.to_string())?;
    while !stop.load(Ordering::SeqCst) {
        std::thread::sleep(Duration::from_millis(20));
    }
    std::thread::sleep(tail);
    drop(stream);
    let out = std::mem::take(&mut *buf.lock().unwrap());
    Ok(out)
}

fn build<T: SizedSample + Send + 'static>(d: &cpal::Device, c: &cpal::StreamConfig, ch: usize, buf: Arc<Mutex<Vec<f32>>>, level: Arc<AtomicU32>) -> Result<cpal::Stream, String>
where
    f32: FromSample<T>,
{
    d.build_input_stream(
        c.clone(),
        move |data: &[T], _| {
            let mut b = buf.lock().unwrap();
            let mut peak = 0f32;
            for frame in data.chunks(ch) {
                let v = frame.iter().map(|s| s.to_sample::<f32>()).sum::<f32>() / ch as f32; // as the app downmixes
                peak = peak.max(v.abs());
                b.push(v);
            }
            level.store(peak.to_bits(), Ordering::Relaxed);
        },
        |_| { GLITCHES.fetch_add(1, Ordering::Relaxed); }, // counted, not printed: it would break the display
        None,
    )
    .map_err(|e| e.to_string())
}

/// Stream errors (buffer overruns) the microphone reported during the current take.
static GLITCHES: AtomicU32 = AtomicU32::new(0);

fn db(x: f32) -> f32 {
    20.0 * x.max(1e-6).log10()
}

/// Peak and speech level (RMS of the loudest tenth of 50 ms frames), in dB below full scale.
fn levels(x: &[f32], rate: u32) -> (f32, f32) {
    let peak = x.iter().fold(0f32, |m, v| m.max(v.abs()));
    let n = (rate as usize / 20).max(1);
    let mut frames: Vec<f32> = x.chunks(n).map(|f| (f.iter().map(|v| v * v).sum::<f32>() / f.len() as f32).sqrt()).collect();
    frames.sort_by(|a, b| b.partial_cmp(a).unwrap());
    let top = &frames[..(frames.len() / 10).max(1).min(frames.len())];
    (db(peak), db(top.iter().sum::<f32>() / top.len().max(1) as f32))
}

/// One line of advice from the take's levels; None when it is fine.
fn advice(kind: &str, peak: f32, speech: f32) -> Option<&'static str> {
    match kind {
        "room" | "noise" => None,
        _ if peak > -0.5 => Some("Too loud: it clipped. Move back a little or lower the microphone level, then record it again."),
        "quiet" if speech < -50.0 => Some("Almost nothing was heard. Speak a little louder than that, then record it again."),
        "quiet" => None,
        _ if speech < -40.0 => Some("Very quiet. Check the microphone is the right one and close enough, then record it again."),
        _ => None,
    }
}

// ---------- WAV ----------

fn write_wav(path: &Path, x: &[f32], rate: u32) -> std::io::Result<()> {
    let data: Vec<u8> = x.iter().flat_map(|v| ((v.clamp(-1.0, 1.0) * 32767.0).round() as i16).to_le_bytes()).collect();
    let mut f = Vec::with_capacity(44 + data.len());
    f.extend(b"RIFF"); f.extend((36 + data.len() as u32).to_le_bytes()); f.extend(b"WAVEfmt ");
    f.extend(16u32.to_le_bytes()); f.extend(1u16.to_le_bytes()); f.extend(1u16.to_le_bytes());
    f.extend(rate.to_le_bytes()); f.extend((rate * 2).to_le_bytes()); f.extend(2u16.to_le_bytes()); f.extend(16u16.to_le_bytes());
    f.extend(b"data"); f.extend((data.len() as u32).to_le_bytes()); f.extend(data);
    std::fs::write(path, f)
}

/// Mono 16-bit PCM WAV, as `write_wav` makes it: (samples, rate).
fn read_wav(path: &Path) -> Result<(Vec<f32>, u32), String> {
    let b = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let u16_at = |i: usize| u16::from_le_bytes([b[i], b[i + 1]]);
    let u32_at = |i: usize| u32::from_le_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]);
    if b.len() < 12 || &b[..4] != b"RIFF" || &b[8..12] != b"WAVE" {
        return Err(format!("{}: not a WAV file", path.display()));
    }
    let (mut i, mut rate, mut fmt_ok) = (12, 0, false);
    while i + 8 <= b.len() {
        let (id, len) = (&b[i..i + 4], u32_at(i + 4) as usize);
        let body = i + 8;
        if id == b"fmt " {
            fmt_ok = u16_at(body) == 1 && u16_at(body + 2) == 1 && u16_at(body + 14) == 16;
            rate = u32_at(body + 4);
        } else if id == b"data" {
            if !fmt_ok {
                return Err(format!("{}: expected mono 16-bit PCM", path.display()));
            }
            let end = (body + len).min(b.len());
            return Ok((b[body..end].chunks_exact(2).map(|c| i16::from_le_bytes([c[0], c[1]]) as f32 / 32768.0).collect(), rate));
        }
        i = body + len + (len & 1);
    }
    Err(format!("{}: no audio data", path.display()))
}

// ---------- record ----------

fn load_takes(p: &Path) -> Map<String, Value> {
    std::fs::read_to_string(p).ok().and_then(|s| serde_json::from_str::<Value>(s.trim_start_matches('\u{feff}')).ok()).and_then(|v| v.as_object().cloned()).unwrap_or_default()
}

fn record(script: &Path, folder: &Path, mic: Option<String>, only: Option<String>) -> Result<(), String> {
    let items: Vec<Value> = serde_json::from_str(&std::fs::read_to_string(script).map_err(|e| format!("{}: {e}", script.display()))?)
        .map_err(|e| format!("{}: {e}", script.display()))?;
    std::fs::create_dir_all(folder).map_err(|e| e.to_string())?;
    let takes_path = folder.join("takes.json");
    let mut takes = load_takes(&takes_path);
    let only: Option<Vec<String>> = only.map(|s| s.split(',').map(|x| x.trim().to_string()).collect());
    let todo: Vec<&Value> = items.iter().filter(|it| {
        let id = it["id"].as_str().unwrap_or("");
        match &only { Some(o) => o.iter().any(|x| x == id), None => !takes.contains_key(id) }
    }).collect();
    let m = open(mic.as_deref())?;
    println!("\nEsyType recording kit: {} to record, {} already done. Recordings stay on this PC, in {}.", todo.len(), takes.len(), folder.display());
    println!("Microphone: {} ({} Hz, {} channel{}). Another one: --mic \"name\" (esytype-record list).", m.name, m.rate, m.channels, if m.channels == 1 { "" } else { "s" });
    println!("Sit as you do when you dictate. For each sentence: press Enter, read it, press Enter. Stop any time with q.\n");
    let mut last_how = String::new();
    let total = items.len();
    for it in todo {
        let id = it["id"].as_str().unwrap_or("?");
        let kind = it["kind"].as_str().unwrap_or("");
        let pos = items.iter().position(|x| x["id"] == it["id"]).unwrap_or(0) + 1;
        // a section's instructions come with its first sentence; show them again when resuming mid-section
        let how = items[..pos].iter().rev().find_map(|x| x["how"].as_str()).unwrap_or("").to_string();
        if how != last_how {
            println!("\n=== {how}\n");
            last_how = how;
        }
        let say = it["say"].as_str().or(it["ref"].as_str()).unwrap_or("");
        let auto = it["auto_s"].as_f64();
        loop {
            println!("[{pos}/{total}] {id}\n    {say}\n");
            print!("    Enter = start recording, s = skip, q = stop for now: ");
            std::io::stdout().flush().ok();
            match line().as_str() {
                "q" => return finish(&takes),
                "s" => break,
                _ => {}
            }
            GLITCHES.store(0, Ordering::Relaxed);
            let stop = Arc::new(AtomicBool::new(false));
            let level = Arc::new(AtomicU32::new(0));
            let (st, lv) = (stop.clone(), level.clone());
            let meter = std::thread::spawn(move || {
                let t = Instant::now();
                while !st.load(Ordering::SeqCst) {
                    let d = db(f32::from_bits(lv.load(Ordering::Relaxed)));
                    let bars = (((d + 60.0) / 60.0).clamp(0.0, 1.0) * 30.0) as usize;
                    print!("\r    ● recording {:>5.1} s  [{}{}]   ", t.elapsed().as_secs_f32(), "█".repeat(bars), " ".repeat(30 - bars));
                    std::io::stdout().flush().ok();
                    std::thread::sleep(Duration::from_millis(100));
                }
            });
            let (mm, sp) = (&m, stop.clone());
            let x = std::thread::scope(|s| {
                let h = s.spawn(move || capture(mm, &sp, level, Duration::from_millis(if auto.is_some() { 0 } else { 400 })));
                match auto {
                    Some(secs) => std::thread::sleep(Duration::from_secs_f64(secs)),
                    None => { let _ = line(); }
                }
                stop.store(true, Ordering::SeqCst);
                h.join().unwrap_or_else(|_| Err("The recording thread stopped unexpectedly.".into()))
            })?;
            meter.join().ok();
            let (peak, speech) = levels(&x, m.rate);
            let secs = x.len() as f32 / m.rate as f32;
            println!("\r    {secs:.1} s recorded. Loudest {peak:.0} dB, speech level {speech:.0} dB.{:30}", "");
            if GLITCHES.load(Ordering::Relaxed) > 1 {
                println!("    ! The microphone reported {} glitches. If you heard a click or a gap, record it again.", GLITCHES.load(Ordering::Relaxed));
            }
            if let Some(a) = advice(kind, peak, speech) {
                println!("    ! {a}");
            }
            print!("    Enter = keep it and go on, r = record it again, q = keep it and stop for now: ");
            std::io::stdout().flush().ok();
            let ans = line();
            if ans == "r" {
                continue;
            }
            let file = format!("{id}.wav");
            write_wav(&folder.join(&file), &x, m.rate).map_err(|e| e.to_string())?;
            takes.insert(id.into(), json!({"file": file, "kind": kind, "seconds": (secs as f64 * 100.0).round() / 100.0, "rate": m.rate,
                "mic": m.name, "mic_channels": m.channels, "peak_db": peak.round(), "speech_db": speech.round(),
                "recorded_unix": std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)}));
            std::fs::write(&takes_path, serde_json::to_string_pretty(&takes).unwrap()).map_err(|e| e.to_string())?;
            if ans == "q" {
                return finish(&takes);
            }
            break;
        }
    }
    finish(&takes)
}

fn finish(takes: &Map<String, Value>) -> Result<(), String> {
    let secs: f64 = takes.values().filter_map(|t| t["seconds"].as_f64()).sum();
    println!("\n{} recordings saved ({:.1} minutes of audio). Run the same command again to carry on; finished ones are skipped.", takes.len(), secs / 60.0);
    Ok(())
}

// ---------- convert ----------

/// <folder>\app16k\owner-<id>.f32: 16 kHz mono f32 through the app's own `resample_to_16k`, so the benchmark hears
/// exactly what EsyType would. Room-tone and noise-only takes are converted too (for noise mixing), but have no text.
fn convert(folder: &Path) -> Result<(), String> {
    let out: PathBuf = folder.join("app16k");
    std::fs::create_dir_all(&out).map_err(|e| e.to_string())?;
    let takes = load_takes(&folder.join("takes.json"));
    if takes.is_empty() {
        return Err(format!("No recordings listed in {}", folder.join("takes.json").display()));
    }
    let mut n = 0;
    for (id, t) in &takes {
        let (x, rate) = read_wav(&folder.join(t["file"].as_str().unwrap_or("")))?;
        let y = audio::resample_to_16k(&x, rate as f32);
        std::fs::write(out.join(format!("owner-{id}.f32")), y.iter().flat_map(|v| v.to_le_bytes()).collect::<Vec<u8>>()).map_err(|e| e.to_string())?;
        n += 1;
    }
    println!("converted {n} recordings to {}", out.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wav_round_trip_and_levels() {
        let dir = std::env::temp_dir().join("esytype-record-test");
        std::fs::create_dir_all(&dir).unwrap();
        let x: Vec<f32> = (0..48000).map(|i| 0.5 * (i as f32 * 0.05).sin()).collect();
        let p = dir.join("t.wav");
        write_wav(&p, &x, 48000).unwrap();
        let (y, rate) = read_wav(&p).unwrap();
        assert_eq!((rate, y.len()), (48000, 48000));
        assert!(x.iter().zip(&y).all(|(a, b)| (a - b).abs() < 1e-4));
        let (peak, speech) = levels(&y, rate);
        assert!((peak + 6.0).abs() < 0.2 && (speech + 9.0).abs() < 0.5, "{peak} {speech}"); // 0.5 sine: -6 dB peak, -9 dB RMS
        assert_eq!(advice("everyday", -0.1, -3.0).is_some(), true);
        assert_eq!(advice("everyday", -12.0, -20.0), None);
        assert_eq!(advice("everyday", -30.0, -45.0).is_some(), true);
        assert_eq!(advice("quiet", -30.0, -45.0), None);
        assert_eq!(advice("room", -70.0, -80.0), None);
        std::fs::remove_dir_all(dir).ok();
    }
}
