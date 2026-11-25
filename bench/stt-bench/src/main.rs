//! Usage: stt-bench <model.bin> <threads> <runs> <short_ctx:0|1> <clip.f32>...
//! One model per process, so peak memory belongs to that model alone.
//! Prints one JSON line per clip run plus a final summary line.
//! ESYTYPE_BENCH_PROMPT: initial prompt (the Dictionary hint) for every clip. ESYTYPE_BENCH_APP=1: also the app's
//! non-speech suppression, so results match EsyType's settings.
//! Short-window study (EsyMeet plan, 8.0): ESYTYPE_BENCH_SHORT=<margin frames> shrinks the encoder window to the clip
//! plus that margin (1500 frames = 30 s; also turns short_ctx on); ESYTYPE_BENCH_SINGLE=1 one segment;
//! ESYTYPE_BENCH_NOTS=1 no timestamps; ESYTYPE_BENCH_TOKPS=<f> at most f tokens per second of audio (+8);
//! ESYTYPE_BENCH_DEDUP=1 drops a sentence that repeats an earlier one.
use std::time::Instant;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

#[repr(C)]
#[derive(Default)]
struct MemCounters { cb: u32, page_faults: u32, peak_ws: usize, ws: usize, a: usize, b: usize, c: usize, d: usize, pagefile: usize, peak_pagefile: usize }
#[repr(C)]
#[derive(Default, Clone, Copy)]
struct FileTime { lo: u32, hi: u32 }
extern "system" {
    fn GetCurrentProcess() -> isize;
    fn K32GetProcessMemoryInfo(p: isize, m: *mut MemCounters, cb: u32) -> i32;
    fn GetProcessTimes(p: isize, c: *mut FileTime, e: *mut FileTime, k: *mut FileTime, u: *mut FileTime) -> i32;
}
fn peak_mb() -> f64 {
    let mut m = MemCounters { cb: std::mem::size_of::<MemCounters>() as u32, ..Default::default() };
    unsafe { K32GetProcessMemoryInfo(GetCurrentProcess(), &mut m, m.cb) };
    m.peak_ws as f64 / 1048576.0
}
/// Total CPU seconds (user + kernel) used by this process so far.
fn cpu_s() -> f64 {
    let (mut c, mut e, mut k, mut u) = (FileTime::default(), FileTime::default(), FileTime::default(), FileTime::default());
    unsafe { GetProcessTimes(GetCurrentProcess(), &mut c, &mut e, &mut k, &mut u) };
    let t = |f: FileTime| ((f.hi as u64) << 32 | f.lo as u64) as f64 / 1e7;
    t(k) + t(u)
}
/// Drops each sentence whose words (lower case, letters and digits only) equal an earlier sentence's.
fn dedup(text: &str) -> String {
    let key = |s: &str| s.chars().filter(|c| c.is_alphanumeric() || c.is_whitespace()).collect::<String>().to_lowercase().split_whitespace().collect::<Vec<_>>().join(" ");
    let (mut seen, mut out, mut cur) = (Vec::<String>::new(), String::new(), String::new());
    for c in text.chars().chain(std::iter::once('\n')) {
        cur.push(c);
        if matches!(c, '.' | '!' | '?' | '\n') {
            let k = key(&cur);
            if !k.is_empty() && !seen.contains(&k) { seen.push(k); out.push_str(&cur); }
            cur.clear();
        }
    }
    out.trim_end_matches('\n').to_string()
}

#[test]
fn dedup_drops_repeated_sentences() {
    assert_eq!(dedup(" I want tea. I want tea. Thanks!"), " I want tea. Thanks!");
    assert_eq!(dedup(" One. Two."), " One. Two.");
}

fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', " ") }

fn main() {
    let a: Vec<String> = std::env::args().collect();
    assert!(a.len() >= 6, "usage: stt-bench <model> <threads> <runs> <short_ctx> <clip.f32>...");
    let (model, threads, runs, short_ctx) = (&a[1], a[2].parse::<i32>().unwrap(), a[3].parse::<usize>().unwrap(), a[4] == "1");

    let t0 = Instant::now();
    let ctx = WhisperContext::new_with_params(model, WhisperContextParameters::default()).expect("load model");
    let mut state = ctx.create_state().expect("create state");
    let load_s = t0.elapsed().as_secs_f64();
    let english_only = model.contains(".en");
    let prompt = std::env::var("ESYTYPE_BENCH_PROMPT").unwrap_or_default();
    let app_params = std::env::var("ESYTYPE_BENCH_APP").is_ok();

    for clip in &a[5..] {
        let bytes = std::fs::read(clip).expect("read clip");
        let pcm: Vec<f32> = bytes.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
        let audio_s = pcm.len() as f64 / 16000.0;
        for run in 0..runs {
            // ESYTYPE_BENCH_BEAM=<n>: beam search with n beams instead of greedy decoding (the app's setting)
            let beam: i32 = std::env::var("ESYTYPE_BENCH_BEAM").ok().and_then(|v| v.parse().ok()).unwrap_or(0);
            let mut p = FullParams::new(if beam > 1 { SamplingStrategy::BeamSearch { beam_size: beam, patience: -1.0 } } else { SamplingStrategy::Greedy { best_of: 1 } });
            p.set_n_threads(threads);
            p.set_language(Some("en"));
            p.set_no_context(true);
            p.set_suppress_blank(true);
            p.set_suppress_nst(app_params);
            if !prompt.is_empty() { p.set_initial_prompt(&prompt); }
            p.set_print_progress(false); p.set_print_realtime(false); p.set_print_special(false); p.set_print_timestamps(false);
            // Encoder normally processes a fixed 30 s window; shrink it for short clips (1500 frames = 30 s).
            let margin: Option<i32> = std::env::var("ESYTYPE_BENCH_SHORT").ok().and_then(|v| v.parse().ok());
            if (short_ctx || margin.is_some()) && audio_s < 30.0 { p.set_audio_ctx(((audio_s / 30.0 * 1500.0).ceil() as i32 + margin.unwrap_or(64)).min(1500)); }
            let on = |k: &str| std::env::var(k).is_ok_and(|v| v == "1");
            if on("ESYTYPE_BENCH_SINGLE") { p.set_single_segment(true); }
            if on("ESYTYPE_BENCH_NOTS") { p.set_no_timestamps(true); }
            if let Some(tps) = std::env::var("ESYTYPE_BENCH_TOKPS").ok().and_then(|v| v.parse::<f64>().ok()) { p.set_max_tokens((audio_s * tps).ceil() as i32 + 8); }
            let (c0, t) = (cpu_s(), Instant::now());
            state.full(p, &pcm).expect("transcribe");
            let (secs, cpu) = (t.elapsed().as_secs_f64(), cpu_s() - c0);
            let text: String = state.as_iter().map(|s| s.to_str_lossy().map(|c| c.into_owned()).unwrap_or_default()).collect();
            let text = if on("ESYTYPE_BENCH_DEDUP") { dedup(&text) } else { text };
            println!("{{\"model\":\"{}\",\"threads\":{},\"short_ctx\":{},\"clip\":\"{}\",\"audio_s\":{:.2},\"run\":{},\"transcribe_s\":{:.3},\"rtf\":{:.4},\"cpu_s\":{:.2},\"cpu_cores_avg\":{:.2},\"text\":\"{}\"}}",
                esc(model), threads, short_ctx, esc(clip), audio_s, run, secs, secs / audio_s, cpu, cpu / secs, esc(text.trim()));
        }
    }
    println!("{{\"summary\":true,\"model\":\"{}\",\"threads\":{},\"short_ctx\":{},\"english_only\":{},\"whisper_cpp\":\"{}\",\"load_s\":{:.3},\"peak_ws_mb\":{:.1}}}", esc(model), threads, short_ctx, english_only, whisper_rs::get_whisper_version(), load_s, peak_mb());
}
