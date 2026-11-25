//! EsyMeet capture (plan 8.1): your microphone and the PC's sound (WASAPI loopback of the default output) at the same
//! time, each written as 16 kHz mono f32 to its own temporary file on one shared timeline.
//!
//! - **One clock.** Each chunk is placed by the moment Windows says its first sample was captured (WASAPI's
//!   performance-counter position, which cpal passes as the capture timestamp), not by when it reached EsyType, so
//!   Windows' buffering does not shift it. Windows sends no loopback data while nothing plays, so when a source falls
//!   more than `PAD_AFTER` behind, silence is written up to its next chunk. Sample N of either file is therefore
//!   N / 16000 s after `start`, for both sources.
//! - **Devices.** Every `CHECK` the capture thread compares the Windows default devices with the open ones; a change
//!   (headphones plugged in) or a stream error reopens that source. A source that cannot open (microphone unplugged)
//!   is "lost" and retried; the other keeps going, and the lost one is filled with silence when it comes back.
//! - **Temporary files.** Each source is flushed to disk about once a second, so a crash loses at most that much.
//! - **Silence keeps up.** While a source sends nothing, its writer fills in silence up to `KEEP_UP` behind the clock,
//!   so a live reader of the file always sees both sources advance.
//! - The cpal callbacks only copy samples into a channel; resampling and writing happen on one writer thread per source.
//!
//! Not yet part of the app: used by `bench/meet-capture` until it is integrated (plan 8.3).
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SizedSample};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub const RATE: f64 = 16000.0;
/// A source this far behind the clock gets silence up to it (loopback is silent while nothing plays).
const PAD_AFTER: f64 = 0.1;
const CHECK: Duration = Duration::from_secs(2);
/// While a source sends nothing, its file is kept this close behind the clock with silence. Chunks arrive 10-30 ms
/// after their audio, so they still land where they belong.
const KEEP_UP: Duration = Duration::from_millis(500);

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Source {
    Mic,
    System,
}

impl Source {
    pub fn name(self) -> &'static str {
        match self {
            Source::Mic => "mic",
            Source::System => "system",
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct Stats {
    pub device: String,
    /// The device's own rate and channels.
    pub format: String,
    /// 16 kHz samples in the file, including padding.
    pub samples: u64,
    /// Of those, silence written from the clock.
    pub padded: u64,
    /// Pads while the source was open and live: for the microphone these are real gaps (it always delivers).
    pub gaps: u32,
    pub reopens: u32,
    /// Discontinuities Windows flagged in the data (some samples may be missing); the stream carries on.
    pub xruns: u32,
    /// Chunks whose place on the timeline was already filled (the file was more than `PAD_AFTER` past it, which
    /// needs a chunk to arrive more than `KEEP_UP` late): appended, so they sit later than they were heard. Expected 0.
    pub late: u32,
    /// Open and delivering.
    pub live: bool,
    /// RMS of the latest chunk, 0..1.
    pub level: f32,
    /// What happened to the device, with seconds since start.
    pub events: Vec<String>,
}

pub struct Capture {
    stop: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
    stats: Arc<Mutex<[Stats; 2]>>,
    pub start: Instant,
    pub dir: PathBuf,
}

impl Capture {
    pub fn stats(&self) -> [Stats; 2] {
        self.stats.lock().unwrap().clone()
    }
    /// Stops both sources and pads each file to the same end, so both cover start..stop.
    pub fn stop(mut self) -> [Stats; 2] {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
        self.stats()
    }
}

/// Starts capturing into `dir` (`mic.f32`, `system.f32`). `mic`: a device name, or None for the Windows default.
/// Fails only if neither source can be opened.
pub fn start(dir: &Path, mic: Option<String>) -> Result<Capture, String> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let start = Instant::now();
    let stop = Arc::new(AtomicBool::new(false));
    let stats = Arc::new(Mutex::new([Stats::default(), Stats::default()]));
    let (ready_tx, ready_rx) = mpsc::channel::<bool>();
    let (s2, st2, d2) = (stop.clone(), stats.clone(), dir.to_path_buf());
    let thread = std::thread::spawn(move || run(&d2, mic, start, s2, st2, ready_tx));
    match ready_rx.recv() {
        Ok(true) => Ok(Capture { stop, thread: Some(thread), stats, start, dir: dir.to_path_buf() }),
        _ => {
            let _ = thread.join();
            Err("Neither the microphone nor the PC's sound could be opened.".into())
        }
    }
}

/// A chunk from a callback: mono samples, the device rate (0: none, a padding or end marker), and when its first
/// sample was captured.
type Chunk = (Vec<f32>, u32, Instant);

struct Open {
    /// Held only to keep the stream running; dropping it closes the device.
    _stream: cpal::Stream,
    device: String,
    /// The stream's error, if cpal reported one that stops it.
    failed: Arc<Mutex<Option<String>>>,
}

/// The capture thread: owns the cpal streams (they must stay on the thread that made them) and watches the devices.
fn run(dir: &Path, mic: Option<String>, start: Instant, stop: Arc<AtomicBool>, stats: Arc<Mutex<[Stats; 2]>>, ready: Sender<bool>) {
    let mut writers = Vec::new();
    let mut opens: [Option<Open>; 2] = [None, None];
    let mut senders = Vec::new();
    let xruns = [Arc::new(AtomicU32::new(0)), Arc::new(AtomicU32::new(0))]; // per source, across reopens
    for src in [Source::Mic, Source::System] {
        let (tx, rx) = mpsc::channel::<Chunk>();
        senders.push(tx);
        let (path, st) = (dir.join(format!("{}.f32", src.name())), stats.clone());
        writers.push(std::thread::spawn(move || write(src, rx, &path, start, st)));
    }
    let note = |i: usize, what: String| {
        let mut s = stats.lock().unwrap();
        s[i].events.push(format!("{:.1} s: {what}", start.elapsed().as_secs_f64()));
    };
    for (i, src) in [Source::Mic, Source::System].into_iter().enumerate() {
        opens[i] = open(src, mic.as_deref(), &senders[i], &xruns[i], &stats, i);
        note(i, opens[i].as_ref().map_or("could not open".into(), |o| format!("opened {}", o.device)));
    }
    let _ = ready.send(opens.iter().any(|o| o.is_some()));
    let mut last_check = Instant::now();
    while !stop.load(Ordering::SeqCst) {
        std::thread::sleep(Duration::from_millis(100));
        if last_check.elapsed() < CHECK {
            continue;
        }
        last_check = Instant::now();
        {
            let mut s = stats.lock().unwrap();
            for (i, o) in opens.iter().enumerate() {
                if o.is_some() {
                    s[i].xruns = xruns[i].load(Ordering::Relaxed);
                }
            }
        }
        for (i, src) in [Source::Mic, Source::System].into_iter().enumerate() {
            let wanted = default_name(src, mic.as_deref());
            let why = match &opens[i] {
                None => wanted.as_ref().map(|_| "device available again".to_string()),
                Some(o) if o.failed.lock().unwrap().is_some() => Some(format!("stream error ({})", o.failed.lock().unwrap().clone().unwrap_or_default())),
                Some(o) if wanted.as_deref() != Some(o.device.as_str()) => Some(format!("default device is now {}", wanted.clone().unwrap_or_else(|| "none".into()))),
                _ => None,
            };
            if let Some(why) = why {
                opens[i] = None; // drop the old stream before opening the new one
                opens[i] = open(src, mic.as_deref(), &senders[i], &xruns[i], &stats, i);
                let ok = opens[i].is_some();
                {
                    let mut s = stats.lock().unwrap();
                    s[i].live = ok;
                    if ok {
                        s[i].reopens += 1;
                    }
                }
                note(i, format!("{why}; {}", opens[i].as_ref().map_or("lost, retrying".into(), |o| format!("reopened {}", o.device))));
            }
        }
    }
    drop(opens);
    {
        let mut s = stats.lock().unwrap();
        for i in 0..2 {
            s[i].xruns = xruns[i].load(Ordering::Relaxed);
        }
    }
    let end = Instant::now();
    for tx in &senders {
        let _ = tx.send((Vec::new(), 0, end)); // an empty chunk at the end time: pads the file to the end
    }
    drop(senders);
    for w in writers {
        let _ = w.join();
    }
}

fn default_name(src: Source, mic: Option<&str>) -> Option<String> {
    let host = cpal::default_host();
    match src {
        Source::Mic => {
            if let Some(name) = mic {
                if let Ok(mut ds) = host.input_devices() {
                    if ds.any(|d| crate::audio::device_name(&d) == name) {
                        return Some(name.to_string());
                    }
                }
            }
            host.default_input_device().map(|d| crate::audio::device_name(&d))
        }
        Source::System => host.default_output_device().map(|d| crate::audio::device_name(&d)),
    }
}

fn open(src: Source, mic: Option<&str>, tx: &Sender<Chunk>, xruns: &Arc<AtomicU32>, stats: &Arc<Mutex<[Stats; 2]>>, i: usize) -> Option<Open> {
    let host = cpal::default_host();
    let device = match src {
        Source::Mic => mic
            .and_then(|name| host.input_devices().ok()?.find(|d| crate::audio::device_name(d) == name))
            .or_else(|| host.default_input_device())?,
        Source::System => host.default_output_device()?,
    };
    // Loopback: an input stream on the output device, in the output's own format.
    let config = match src {
        Source::Mic => device.default_input_config().ok()?,
        Source::System => device.default_output_config().ok()?,
    };
    let (rate, channels) = (config.sample_rate(), config.channels() as usize);
    let failed = Arc::new(Mutex::new(None));
    let cfg: cpal::StreamConfig = config.clone().into();
    let stream = match config.sample_format() {
        cpal::SampleFormat::F32 => build::<f32>(&device, cfg, channels, rate, tx.clone(), failed.clone(), xruns.clone()),
        cpal::SampleFormat::I16 => build::<i16>(&device, cfg, channels, rate, tx.clone(), failed.clone(), xruns.clone()),
        cpal::SampleFormat::I32 => build::<i32>(&device, cfg, channels, rate, tx.clone(), failed.clone(), xruns.clone()),
        cpal::SampleFormat::U16 => build::<u16>(&device, cfg, channels, rate, tx.clone(), failed.clone(), xruns.clone()),
        _ => None,
    }?;
    stream.play().ok()?;
    let name = crate::audio::device_name(&device);
    let mut s = stats.lock().unwrap();
    s[i].device = name.clone();
    s[i].format = format!("{rate} Hz, {channels} ch, {:?}", config.sample_format());
    s[i].live = true;
    Some(Open { _stream: stream, device: name, failed })
}

fn build<T: SizedSample + Send + 'static>(device: &cpal::Device, cfg: cpal::StreamConfig, channels: usize, rate: u32, tx: Sender<Chunk>, failed: Arc<Mutex<Option<String>>>, xruns: Arc<AtomicU32>) -> Option<cpal::Stream>
where
    f32: FromSample<T>,
{
    device
        .build_input_stream(
            cfg,
            move |data: &[T], info: &cpal::InputCallbackInfo| {
                let mono: Vec<f32> = data.chunks(channels).map(|f| f.iter().map(|s| s.to_sample::<f32>()).sum::<f32>() / channels as f32).collect();
                // Windows' capture time of the first sample, as an age back from now (both on the performance counter).
                let ts = info.timestamp();
                let captured = Instant::now().checked_sub(ts.callback.duration_since(ts.capture)).unwrap_or_else(Instant::now);
                let _ = tx.send((mono, rate, captured));
            },
            // An overrun, or Windows moving the stream to another device by itself, does not stop the stream.
            move |e: cpal::Error| match e.kind() {
                cpal::ErrorKind::Xrun | cpal::ErrorKind::DeviceChanged | cpal::ErrorKind::RealtimeDenied => {
                    xruns.fetch_add(1, Ordering::Relaxed);
                }
                _ => *failed.lock().unwrap() = Some(e.to_string()),
            },
            None,
        )
        .ok()
}

/// One source's writer: resamples to 16 kHz, pads from the clock, appends to the file.
fn write(src: Source, rx: Receiver<Chunk>, path: &Path, start: Instant, stats: Arc<Mutex<[Stats; 2]>>) {
    let i = src as usize;
    let Ok(file) = std::fs::File::create(path) else { return };
    let mut out = std::io::BufWriter::with_capacity(64 * 1024, file);
    let mut rs: Option<(u32, Resampler)> = None;
    let (mut written, mut last_flush, mut reopens) = (0u64, Instant::now(), 0u32);
    loop {
        let (chunk, rate, at) = match rx.recv_timeout(Duration::from_millis(250)) {
            Ok(c) => c,
            // Nothing arrived (loopback is silent while nothing plays): fill in silence up to KEEP_UP behind the clock.
            Err(RecvTimeoutError::Timeout) => (Vec::new(), 0, Instant::now().checked_sub(KEEP_UP).unwrap_or(start)),
            Err(RecvTimeoutError::Disconnected) => break,
        };
        if rate != 0 && rs.as_ref().map_or(true, |(r, _)| *r != rate) {
            rs = Some((rate, Resampler::new(rate as f64))); // a reopened device may have another rate
        }
        let samples = rs.as_mut().map(|(_, r)| r.push(&chunk)).unwrap_or_default();
        // Where this chunk starts on the clock; pad if the file is behind it.
        let due = (at.duration_since(start).as_secs_f64() * RATE) as i64;
        let behind = due - written as i64;
        let mut s = stats.lock().unwrap();
        if !chunk.is_empty() && (behind as f64) < -PAD_AFTER * RATE {
            s[i].late += 1;
        }
        if behind as f64 > PAD_AFTER * RATE {
            // Padding on an open microphone is a real gap: it always delivers. (Not at the start or across a reopen.)
            if src == Source::Mic && s[i].live && written > 0 && s[i].reopens == reopens {
                s[i].gaps += 1;
            }
            write_f32(&mut out, &vec![0.0; behind as usize]);
            written += behind as u64;
            s[i].padded += behind as u64;
        }
        write_f32(&mut out, &samples);
        written += samples.len() as u64;
        s[i].samples = written;
        reopens = s[i].reopens;
        if !samples.is_empty() {
            s[i].level = (samples.iter().map(|v| v * v).sum::<f32>() / samples.len() as f32).sqrt();
        }
        drop(s);
        if last_flush.elapsed() > Duration::from_secs(1) {
            let _ = out.flush();
            last_flush = Instant::now();
        }
    }
    let _ = out.flush();
}

fn write_f32(out: &mut impl Write, v: &[f32]) {
    let bytes: Vec<u8> = v.iter().flat_map(|x| x.to_le_bytes()).collect();
    let _ = out.write_all(&bytes);
}

/// Box-filter downsampling to 16 kHz that carries its position across chunks, so chunk edges add no drift.
struct Resampler {
    ratio: f64,
    pending: Vec<f32>,
    /// Position of the next output sample in `pending`, in input samples.
    pos: f64,
}

impl Resampler {
    fn new(rate: f64) -> Self {
        Resampler { ratio: rate / RATE, pending: Vec::new(), pos: 0.0 }
    }
    fn push(&mut self, input: &[f32]) -> Vec<f32> {
        if (self.ratio - 1.0).abs() < 1e-9 {
            return input.to_vec();
        }
        self.pending.extend_from_slice(input);
        let mut out = Vec::with_capacity((input.len() as f64 / self.ratio) as usize + 1);
        while self.pos + self.ratio <= self.pending.len() as f64 {
            let (a, b) = (self.pos as usize, ((self.pos + self.ratio) as usize).max(self.pos as usize + 1));
            out.push(self.pending[a..b].iter().sum::<f32>() / (b - a) as f32);
            self.pos += self.ratio;
        }
        let used = self.pos as usize;
        self.pending.drain(..used);
        self.pos -= used as f64;
        out
    }
}

#[cfg(test)]
mod tests {
    use super::Resampler;
    #[test]
    fn resampler_keeps_length_across_chunks() {
        // 44.1 kHz in uneven chunks: one second in gives one second out (within a sample), and DC stays DC
        let mut r = Resampler::new(44100.0);
        let mut n = 0;
        for len in [441, 1000, 37, 2000, 40622] {
            let y = r.push(&vec![0.5; len]);
            assert!(y.iter().all(|v| (v - 0.5).abs() < 1e-6));
            n += y.len();
        }
        assert!((n as i64 - 16000).abs() <= 1, "{n}");
        let mut r = Resampler::new(48000.0);
        assert_eq!(r.push(&vec![0.0; 480]).len(), 160);
    }
}
