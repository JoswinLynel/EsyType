//! Speech recognition on a dedicated worker thread, so the UI never waits on whisper.cpp.
use std::path::PathBuf;
use std::sync::mpsc;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters, WhisperState, WhisperVadContext, WhisperVadContextParams, WhisperVadParams};

enum Job {
    Load { path: PathBuf, threads: i32, done: mpsc::Sender<Result<(), String>> },
    Threads(i32),
    Transcribe { pcm: Vec<f32>, prompt: String, lang: String, translate: bool, done: mpsc::Sender<Result<(String, String), String>> },
}

#[derive(Clone)]
pub struct Engine {
    tx: mpsc::Sender<Job>,
}

impl Engine {
    /// `vad_model`: the bundled Silero model. Without it, recordings are passed to Whisper untrimmed.
    pub fn spawn(vad_model: Option<PathBuf>) -> Engine {
        let (tx, rx) = mpsc::channel::<Job>();
        std::thread::Builder::new()
            .name("speech".into())
            .spawn(move || {
                lower_priority();
                let mut loaded: Option<(WhisperContext, WhisperState, i32)> = None;
                let mut vad = vad_model.and_then(|p| {
                    let mut c = WhisperVadContextParams::new();
                    c.set_n_threads(1);
                    WhisperVadContext::new(p.to_str()?, c).inspect_err(|e| eprintln!("voice activity model not loaded: {e}")).ok()
                });
                for job in rx {
                    match job {
                        Job::Load { path, threads, done } => {
                            loaded = None; // free the old model before loading the new one
                            let r = load(&path).map(|(ctx, mut state)| {
                                let _ = run(&mut state, &vec![0.0; 16000], threads, "", "en", false); // warm-up pass
                                loaded = Some((ctx, state, threads));
                            });
                            let _ = done.send(r);
                        }
                        Job::Threads(t) => {
                            if let Some(l) = loaded.as_mut() {
                                l.2 = t;
                            }
                        }
                        Job::Transcribe { pcm, prompt, lang, translate, done } => {
                            let r = match loaded.as_mut() {
                                Some((_, state, threads)) => match speech_only(vad.as_mut(), &pcm) {
                                    Some(speech) => run(state, speech, *threads, &prompt, &lang, translate).map(|(t, l)| (clean(&t), l)),
                                    None => Ok((String::new(), lang.clone())), // no speech: nothing to transcribe or type
                                },
                                None => Err("No speech model is loaded yet.".into()),
                            };
                            let _ = done.send(r);
                        }
                    }
                }
            })
            .expect("spawn speech thread");
        Engine { tx }
    }

    /// Blocks until the model is loaded and warmed up; call from a background thread.
    pub fn load(&self, path: PathBuf, threads: i32) -> Result<(), String> {
        let (done, rx) = mpsc::channel();
        self.tx.send(Job::Load { path, threads, done }).map_err(|e| e.to_string())?;
        rx.recv().map_err(|e| e.to_string())?
    }

    pub fn set_threads(&self, threads: i32) {
        let _ = self.tx.send(Job::Threads(threads));
    }

    /// Blocks until done; call from a background thread. `prompt`: the Dictionary hint ("" for none). `lang`: "en",
    /// "auto" or a language code; `translate`: write it in English. Returns the text and the language heard.
    pub fn transcribe(&self, pcm: Vec<f32>, prompt: &str, lang: &str, translate: bool) -> Result<(String, String), String> {
        let (done, rx) = mpsc::channel();
        self.tx.send(Job::Transcribe { pcm, prompt: prompt.to_string(), lang: lang.to_string(), translate, done }).map_err(|e| e.to_string())?;
        rx.recv().map_err(|e| e.to_string())?
    }
}

/// Voice activity detection as a gate: None when the recording holds no speech (Whisper invents text from
/// silence), otherwise the whole recording. Trimming to the detected speech cost accuracy in testing
/// (4.4% vs 3.4% word errors on the benchmark clips), so the audio is passed through untouched.
fn speech_only<'a>(vad: Option<&mut WhisperVadContext>, pcm: &'a [f32]) -> Option<&'a [f32]> {
    let Some(vad) = vad else { return Some(pcm) };
    match vad.segments_from_samples(WhisperVadParams::new(), pcm) {
        Ok(mut s) => s.next().map(|_| pcm),
        Err(_) => Some(pcm), // detector failed: better to transcribe than to drop the user's words
    }
}

/// Drops output that is only a non-speech annotation ("[BLANK_AUDIO]", "(music)") or punctuation.
pub fn clean(text: &str) -> String {
    let t = text.trim();
    let without_tags: String = {
        let mut out = String::new();
        let mut depth = 0;
        for ch in t.chars() {
            match ch {
                '[' | '(' => depth += 1,
                ']' | ')' if depth > 0 => depth -= 1,
                _ if depth == 0 => out.push(ch),
                _ => {}
            }
        }
        out
    };
    if without_tags.chars().any(|c| c.is_alphanumeric()) { t.to_string() } else { String::new() }
}

fn load(path: &PathBuf) -> Result<(WhisperContext, WhisperState), String> {
    let p = path.to_str().ok_or("Model path is not valid text.")?;
    let ctx = WhisperContext::new_with_params(p, WhisperContextParameters::default()).map_err(|e| format!("The speech model could not be loaded: {e}"))?;
    let state = ctx.create_state().map_err(|e| e.to_string())?;
    Ok((ctx, state))
}

fn run(state: &mut WhisperState, pcm: &[f32], threads: i32, prompt: &str, lang: &str, translate: bool) -> Result<(String, String), String> {
    let mut p = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    p.set_n_threads(threads);
    p.set_language(Some(lang)); // "auto" detects; "detect_language" would stop after detecting
    p.set_translate(translate);
    p.set_no_context(true);
    p.set_suppress_blank(true);
    p.set_suppress_nst(true); // no "[music]"-style non-speech tokens
    if !prompt.is_empty() {
        p.set_initial_prompt(prompt); // Dictionary words, as context that nudges spellings
    }
    p.set_print_progress(false);
    p.set_print_realtime(false);
    p.set_print_special(false);
    p.set_print_timestamps(false);
    state.full(p, pcm).map_err(|e| format!("Transcription failed: {e}"))?;
    let text: String = state.as_iter().map(|s| s.to_str_lossy().map(|c| c.into_owned()).unwrap_or_default()).collect();
    let heard = whisper_rs::get_lang_str(state.full_lang_id_from_state()).unwrap_or(lang).to_string();
    Ok((text.trim().to_string(), heard))
}

/// Speech runs below normal priority so the app being dictated into stays responsive.
fn lower_priority() {
    use windows::Win32::System::Threading::{GetCurrentThread, SetThreadPriority, THREAD_PRIORITY_BELOW_NORMAL};
    unsafe {
        let _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
    }
}

#[cfg(test)]
mod tests {
    use super::clean;
    #[test]
    fn drops_non_speech_output() {
        assert_eq!(clean(" [BLANK_AUDIO] "), "");
        assert_eq!(clean("(speaking in foreign language)"), "");
        assert_eq!(clean("..........."), "");
        assert_eq!(clean("Hello (laughs) there."), "Hello (laughs) there.");
        assert_eq!(clean("Meet at 3."), "Meet at 3.");
    }
}
