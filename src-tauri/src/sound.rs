//! Start and stop sounds (Mac design: Settings, Recording, Sounds): two short soft tones made here, played on the
//! default output device. Off by default. Nothing is downloaded or stored.
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

/// The tone for a start (rising) or a stop (falling), as mono samples at `rate`, scaled by `volume` (0 to 1).
pub fn tone(start: bool, rate: u32, volume: f32) -> Vec<f32> {
    let (a, b) = if start { (660.0, 880.0) } else { (880.0, 660.0) };
    let note = (rate as f32 * 0.07) as usize; // 70 ms per note
    let mut out = Vec::with_capacity(note * 2);
    for (k, f) in [a, b].iter().enumerate() {
        for i in 0..note {
            let t = i as f32 / rate as f32;
            let x = (k * note + i) as f32 / (note * 2) as f32;
            let env = (x * std::f32::consts::PI).sin().powf(0.6); // soft in and out, no click
            out.push((2.0 * std::f32::consts::PI * f * t).sin() * env * 0.25 * volume.clamp(0.0, 1.0));
        }
    }
    out
}

/// Plays the tone without waiting; a missing or busy speaker is ignored (sounds are a nicety).
pub fn play(start: bool, volume: f32) {
    if volume <= 0.0 {
        return;
    }
    std::thread::spawn(move || {
        let Some(dev) = cpal::default_host().default_output_device() else { return };
        let Ok(cfg) = dev.default_output_config() else { return };
        if cfg.sample_format() != cpal::SampleFormat::F32 {
            return; // shortcut: Windows' shared mode is 32-bit float; other formats stay silent rather than convert
        }
        let (channels, rate) = (cfg.channels() as usize, cfg.sample_rate());
        let samples = tone(start, rate, volume);
        let len = samples.len();
        let mut at = 0;
        let Ok(stream) = dev.build_output_stream(
            cfg.into(),
            move |data: &mut [f32], _| {
                for frame in data.chunks_mut(channels) {
                    let v = samples.get(at).copied().unwrap_or(0.0);
                    at += 1;
                    frame.iter_mut().for_each(|s| *s = v);
                }
            },
            |_| {},
            None,
        ) else {
            return;
        };
        if stream.play().is_ok() {
            std::thread::sleep(std::time::Duration::from_millis(len as u64 * 1000 / rate.max(1) as u64 + 150));
        }
    });
}

#[cfg(test)]
mod tests {
    #[test]
    fn tones_are_short_soft_and_silent_at_zero() {
        let t = super::tone(true, 48_000, 1.0);
        assert_eq!(t.len(), 2 * 3360, "two notes of 70 ms");
        assert!(t.iter().all(|v| v.abs() <= 0.25), "soft");
        assert!(t[0].abs() < 0.01 && t[t.len() - 1].abs() < 0.01, "fades in and out");
        assert!(super::tone(false, 48_000, 0.0).iter().all(|v| *v == 0.0));
    }
}
