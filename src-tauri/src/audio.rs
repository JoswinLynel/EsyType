//! Microphone capture on its own thread (cpal streams must stay on the thread that created them).
//! Produces 16 kHz mono f32 samples, the format whisper.cpp expects.
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SizedSample};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

pub fn device_name(d: &cpal::Device) -> String {
    d.description().map(|x| x.name().to_string()).unwrap_or_else(|_| "Unknown microphone".into())
}

pub fn list_inputs() -> Vec<String> {
    cpal::default_host().input_devices().map(|ds| ds.map(|d| device_name(&d)).collect()).unwrap_or_default()
}

pub struct Recording {
    stop: mpsc::Sender<()>,
    handle: JoinHandle<Result<Vec<f32>, String>>,
    /// The chosen microphone was not found, so the Windows default is being used.
    pub fell_back: bool,
}

impl Recording {
    /// Stops the stream and returns the recording as 16 kHz mono.
    pub fn finish(self) -> Result<Vec<f32>, String> {
        let _ = self.stop.send(());
        self.handle.join().map_err(|_| "The recording thread stopped unexpectedly.".to_string())?
    }
}

/// `on_level` gets 0..1 about every 40 ms; `on_live` fires once, when the first real samples arrive,
/// so the "recording" cue never shows while the microphone is still opening.
pub fn start(
    mic: Option<String>,
    on_level: impl Fn(f32) + Send + 'static,
    on_live: impl FnOnce() + Send + 'static,
) -> Result<Recording, String> {
    let (stop, stop_rx) = mpsc::channel::<()>();
    #[cfg(feature = "e2e")]
    if let Ok(file) = std::env::var("ESYTYPE_TEST_AUDIO") {
        let handle = std::thread::spawn(move || {
            let b = std::fs::read(file).map_err(|e| e.to_string())?;
            on_live();
            while stop_rx.recv_timeout(Duration::from_millis(40)) == Err(RecvTimeoutError::Timeout) {
                on_level(0.5);
            }
            Ok(b.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect())
        });
        return Ok(Recording { stop, handle, fell_back: false });
    }
    let (ready_tx, ready_rx) = mpsc::channel::<Result<bool, String>>();
    let handle = std::thread::spawn(move || {
        let host = cpal::default_host();
        let chosen = mic.as_ref().and_then(|name| host.input_devices().ok().and_then(|mut ds| ds.find(|d| &device_name(d) == name)));
        let fell_back = mic.is_some() && chosen.is_none();
        let device = chosen.or_else(|| host.default_input_device());
        let Some(device) = device else {
            let _ = ready_tx.send(Err("No microphone found. Connect one, or check Windows sound settings.".into()));
            return Ok(Vec::new());
        };
        let config = match device.default_input_config() {
            Ok(c) => c,
            Err(e) => {
                let _ = ready_tx.send(Err(format!("The microphone could not be opened: {e}")));
                return Ok(Vec::new());
            }
        };
        let rate = config.sample_rate() as f32;
        let channels = config.channels() as usize;
        let buf = Arc::new(Mutex::new(Vec::<f32>::with_capacity(rate as usize * 30)));
        let level = Arc::new(AtomicU32::new(0));
        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => build::<f32>(&device, &config.into(), channels, buf.clone(), level.clone()),
            cpal::SampleFormat::I16 => build::<i16>(&device, &config.into(), channels, buf.clone(), level.clone()),
            cpal::SampleFormat::I32 => build::<i32>(&device, &config.into(), channels, buf.clone(), level.clone()),
            cpal::SampleFormat::U16 => build::<u16>(&device, &config.into(), channels, buf.clone(), level.clone()),
            f => Err(format!("Unsupported microphone sample format: {f}")),
        };
        let stream = match stream.and_then(|s| s.play().map(|_| s).map_err(|e| e.to_string())) {
            Ok(s) => s,
            Err(e) => {
                let _ = ready_tx.send(Err(format!("The microphone could not be started: {e}")));
                return Ok(Vec::new());
            }
        };
        let _ = ready_tx.send(Ok(fell_back));
        let mut on_live = Some(on_live);
        loop {
            match stop_rx.recv_timeout(Duration::from_millis(40)) {
                Err(RecvTimeoutError::Timeout) => {
                    if on_live.is_some() && !buf.lock().unwrap().is_empty() {
                        (on_live.take().unwrap())();
                    }
                    on_level(f32::from_bits(level.load(Ordering::Relaxed)));
                }
                _ => break,
            }
        }
        drop(stream);
        let raw = std::mem::take(&mut *buf.lock().unwrap());
        Ok(resample_to_16k(&raw, rate))
    });
    match ready_rx.recv() {
        Ok(Ok(fell_back)) => Ok(Recording { stop, handle, fell_back }),
        Ok(Err(e)) => {
            let _ = handle.join();
            Err(e)
        }
        Err(_) => Err("The recording thread stopped unexpectedly.".into()),
    }
}

fn build<T: SizedSample + Send + 'static>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    channels: usize,
    buf: Arc<Mutex<Vec<f32>>>,
    level: Arc<AtomicU32>,
) -> Result<cpal::Stream, String>
where
    f32: FromSample<T>,
{
    device
        .build_input_stream(
            config.clone(),
            move |data: &[T], _| {
                let mut sum = 0.0f32;
                let mut b = buf.lock().unwrap();
                for frame in data.chunks(channels) {
                    let v = frame.iter().map(|s| s.to_sample::<f32>()).sum::<f32>() / channels as f32;
                    sum += v * v;
                    b.push(v);
                }
                let rms = (sum / (data.len() / channels).max(1) as f32).sqrt();
                level.store((rms * 8.0).min(1.0).to_bits(), Ordering::Relaxed); // x8: speech RMS is ~0.02-0.1
            },
            |e| eprintln!("microphone stream error: {e}"),
            None,
        )
        .map_err(|e| e.to_string())
}

/// Downsample to 16 kHz by averaging each output sample's span of input (a box filter, which also
/// removes most content above 8 kHz). Good enough for speech recognition.
pub fn resample_to_16k(input: &[f32], rate: f32) -> Vec<f32> {
    if (rate - 16000.0).abs() < 1.0 {
        return input.to_vec();
    }
    let ratio = rate / 16000.0;
    let n = (input.len() as f32 / ratio) as usize;
    (0..n)
        .map(|i| {
            let a = (i as f32 * ratio) as usize;
            let b = (((i + 1) as f32 * ratio) as usize).clamp(a + 1, input.len());
            input[a..b].iter().sum::<f32>() / (b - a) as f32
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn resample_lengths_and_dc() {
        let x = vec![0.5f32; 48000];
        let y = resample_to_16k(&x, 48000.0);
        assert_eq!(y.len(), 16000);
        assert!(y.iter().all(|v| (v - 0.5).abs() < 1e-6));
        assert_eq!(resample_to_16k(&vec![0.0; 44100], 44100.0).len(), 16000);
        assert_eq!(resample_to_16k(&[0.1, 0.2], 16000.0), vec![0.1, 0.2]);
    }
}

/// The microphone test's verdict from the loudest level heard (the 0..1 levels `start` reports): "heard", "quiet" or
/// "none". shortcut: thresholds from typical speech RMS (0.02-0.1, level 0.16-0.8), not yet checked on many
/// microphones; adjust once real-microphone results from other PCs exist.
pub fn verdict(loudest: f32) -> &'static str {
    if loudest >= 0.12 { "heard" } else if loudest >= 0.03 { "quiet" } else { "none" }
}

#[cfg(test)]
mod mic_tests {
    #[test]
    fn verdicts() {
        assert_eq!([0.0, 0.02, 0.05, 0.12, 0.5, 1.0].map(super::verdict), ["none", "none", "quiet", "heard", "heard", "heard"]);
    }

    /// Opens the default microphone for about one second (kept in memory, then discarded).
    /// Run on a machine with a microphone: `cargo test -- --ignored records_from_default_mic`.
    #[test]
    #[ignore]
    fn records_from_default_mic() {
        let live = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let l = live.clone();
        let rec = super::start(None, |_| {}, move || l.store(true, std::sync::atomic::Ordering::SeqCst)).expect("open microphone");
        std::thread::sleep(std::time::Duration::from_millis(1200));
        let pcm = rec.finish().unwrap();
        assert!(live.load(std::sync::atomic::Ordering::SeqCst), "samples arrived");
        assert!((14_000..=20_000).contains(&pcm.len()), "about 1.2 s at 16 kHz, got {}", pcm.len());
        println!("devices: {:?}", super::list_inputs());
        println!("samples: {}  peak: {:.4}", pcm.len(), pcm.iter().fold(0f32, |m, v| m.max(v.abs())));
    }
}
