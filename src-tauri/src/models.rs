//! The three speech models, and downloading exactly one of them with resume and SHA-256 verification.
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Serialize, Clone, Copy, Debug)]
pub struct Model {
    pub id: &'static str,
    pub name: &'static str,
    pub tagline: &'static str,
    pub file: &'static str,
    pub bytes: u64,
    pub sha256: &'static str,
    pub languages: &'static str,
    /// Measured on the dev PC, 17 Nov 2026 (docs/testing/2026-11-17-stt-dev-pc.md).
    pub peak_ram_mb: u64,
    pub ref_seconds_10s: f32,
    pub ref_wer_pct: f32,
}

pub const MODELS: [Model; 3] = [
    Model { id: "tiny", name: "Tiny", tagline: "Low-resource computers", file: "ggml-tiny.en-q5_1.bin", bytes: 32_166_155,
        sha256: "c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b", languages: "English",
        peak_ram_mb: 245, ref_seconds_10s: 1.2, ref_wer_pct: 5.6 },
    Model { id: "base", name: "Base", tagline: "Balanced everyday dictation", file: "ggml-base.en-q5_1.bin", bytes: 59_721_011,
        sha256: "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f", languages: "English",
        peak_ram_mb: 345, ref_seconds_10s: 2.6, ref_wer_pct: 3.4 },
    Model { id: "small", name: "Small", tagline: "Computers with more resources", file: "ggml-small-q5_1.bin", bytes: 190_085_487,
        sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb", languages: "English and 98 others",
        peak_ram_mb: 601, ref_seconds_10s: 8.5, ref_wer_pct: 2.9 },
];
/// Provisional default (owner, 17 Nov 2026).
pub const DEFAULT: &str = "base";
const PINNED: &str = "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1";

pub fn find(id: &str) -> Option<&'static Model> {
    MODELS.iter().find(|m| m.id == id)
}

static DIR: std::sync::RwLock<Option<PathBuf>> = std::sync::RwLock::new(None);

pub fn default_dir() -> PathBuf {
    crate::settings::data_dir().join("models")
}

/// The folder models are read from and downloaded to: the user's choice, or the default.
pub fn dir() -> PathBuf {
    DIR.read().unwrap().clone().unwrap_or_else(default_dir)
}

pub fn set_dir(p: Option<PathBuf>) {
    *DIR.write().unwrap() = p;
}

/// Checks that `to` is an absolute folder EsyType can create and write to.
pub fn check_folder(to: &std::path::Path) -> Result<(), String> {
    if !to.is_absolute() {
        return Err("Choose a full folder path, for example D:\\EsyAI\\EsyType\\models.".into());
    }
    std::fs::create_dir_all(to).map_err(|e| format!("That folder could not be created: {e}"))?;
    let probe = to.join(".esytype-write-test");
    std::fs::write(&probe, b"ok").map_err(|e| format!("EsyType cannot write to that folder: {e}"))?;
    let _ = std::fs::remove_file(probe);
    Ok(())
}

/// Moves every installed model from the current folder to `to`. Each file is copied, checked against its
/// SHA-256, and only then deleted from the old folder, so a failure never loses a model.
/// Returns the ids moved. The caller switches `dir()` to `to` on success.
pub fn move_to(to: &std::path::Path) -> Result<Vec<&'static str>, String> {
    let from = dir();
    check_folder(to)?;
    if std::fs::canonicalize(&from).ok() == std::fs::canonicalize(to).ok() {
        return Ok(vec![]);
    }
    let mut moved = vec![];
    for m in MODELS.iter().filter(|m| installed(m)) {
        let (src, dst) = (from.join(m.file), to.join(m.file));
        let ok = |p: &std::path::Path| sha256_file(p).map(|h| h == m.sha256).unwrap_or(false);
        if !ok(&dst) {
            let part = to.join(format!("{}.partial", m.file));
            std::fs::copy(&src, &part).map_err(|e| format!("Could not copy {}: {e}", m.name))?;
            if !ok(&part) {
                let _ = std::fs::remove_file(&part);
                return Err(format!("The copy of {} failed its integrity check; nothing was deleted.", m.name));
            }
            std::fs::rename(&part, &dst).map_err(|e| e.to_string())?;
        }
        std::fs::remove_file(&src).map_err(|e| format!("{} was copied but the old file could not be deleted: {e}", m.name))?;
        moved.push(m.id);
    }
    for m in MODELS.iter() {
        let _ = std::fs::remove_file(from.join(format!("{}.partial", m.file))); // unfinished downloads: nothing to keep
    }
    Ok(moved)
}

pub fn path(m: &Model) -> PathBuf {
    dir().join(m.file)
}

/// Size check on every start; the full hash is checked when the file is downloaded.
pub fn installed(m: &Model) -> bool {
    std::fs::metadata(path(m)).map(|x| x.len() == m.bytes).unwrap_or(false)
}

/// Where models are downloaded from, as shown in Settings (the pinned address, not a test server).
pub fn source() -> &'static str {
    PINNED
}

fn url(m: &Model) -> String {
    // ESYTYPE_MODEL_BASE_URL exists only so tests can serve models from a local server instead of the internet.
    let base = std::env::var("ESYTYPE_MODEL_BASE_URL").unwrap_or_else(|_| PINNED.into());
    format!("{}/{}", base.trim_end_matches('/'), m.file)
}

pub fn sha256_file(p: &std::path::Path) -> std::io::Result<String> {
    let mut f = std::fs::File::open(p)?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Ok(h.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// Downloads one model to `<file>.partial`, resuming if a partial file exists, then verifies and renames it.
pub fn download(m: &Model, cancel: &AtomicBool, mut progress: impl FnMut(u64, u64)) -> Result<(), String> {
    std::fs::create_dir_all(dir()).map_err(|e| e.to_string())?;
    let part = dir().join(format!("{}.partial", m.file));
    let have = std::fs::metadata(&part).map(|x| x.len()).unwrap_or(0);
    let client = reqwest::blocking::Client::builder().user_agent("EsyType").timeout(None).build().map_err(|e| e.to_string())?;
    let mut req = client.get(url(m));
    if have > 0 {
        req = req.header(reqwest::header::RANGE, format!("bytes={have}-"));
    }
    let mut resp = req.send().map_err(|e| format!("Could not reach the download server: {e}"))?;
    let (mut done, append) = match resp.status().as_u16() {
        206 => (have, true),
        200 => (0, false),
        s => return Err(format!("Download failed (HTTP {s}).")),
    };
    let mut f = std::fs::OpenOptions::new().create(true).write(true).append(append).truncate(!append).open(&part).map_err(|e| e.to_string())?;
    let mut buf = vec![0u8; 1 << 16];
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err("Download cancelled.".into()); // partial file kept so the next attempt resumes
        }
        let n = resp.read(&mut buf).map_err(|e| format!("Download interrupted: {e}"))?;
        if n == 0 {
            break;
        }
        f.write_all(&buf[..n]).map_err(|e| format!("Could not write the model file: {e}"))?;
        done += n as u64;
        progress(done, m.bytes);
    }
    drop(f);
    if sha256_file(&part).map_err(|e| e.to_string())? != m.sha256 {
        let _ = std::fs::remove_file(&part);
        return Err("The downloaded file failed its integrity check and was deleted. Please try again.".into());
    }
    std::fs::rename(&part, path(m)).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn lineup_is_exactly_tiny_base_small() {
        assert_eq!(MODELS.iter().map(|m| m.id).collect::<Vec<_>>(), ["tiny", "base", "small"]);
        assert!(find(DEFAULT).is_some());
        assert!(MODELS.iter().all(|m| m.sha256.len() == 64));
    }
    #[test]
    fn sha256_known_value() {
        let p = std::env::temp_dir().join("esytype-sha-test.txt");
        std::fs::write(&p, b"abc").unwrap();
        assert_eq!(sha256_file(&p).unwrap(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        let _ = std::fs::remove_file(p);
    }
}

#[cfg(test)]
mod download_tests {
    use super::*;
    /// Run with a local server: `ESYTYPE_MODEL_BASE_URL=http://127.0.0.1:8765 cargo test -- --ignored`.
    /// LOCALAPPDATA must point at a scratch folder.
    #[test]
    #[ignore]
    fn downloads_and_verifies_tiny_from_local_server() {
        let m = find("tiny").unwrap();
        let _ = std::fs::remove_file(path(m));
        std::fs::create_dir_all(dir()).unwrap();
        std::fs::write(dir().join(format!("{}.partial", m.file)), b"stale partial data").unwrap(); // must not corrupt the result
        let mut calls = 0;
        download(m, &AtomicBool::new(false), |_, _| calls += 1).unwrap();
        assert!(installed(m) && calls > 0);
        assert_eq!(sha256_file(&path(m)).unwrap(), m.sha256);
        assert!(download(m, &AtomicBool::new(true), |_, _| {}).is_err(), "cancel is honoured");

        // Moving storage: verified copy to the new folder, nothing left behind in the old one.
        let to = crate::settings::data_dir().join("moved-models");
        let _ = std::fs::remove_dir_all(&to);
        assert_eq!(move_to(&to).unwrap(), ["tiny"]);
        assert!(!path(m).exists(), "old copy removed");
        set_dir(Some(to.clone()));
        assert!(installed(m) && path(m).starts_with(&to));
        assert!(move_to(std::path::Path::new("relative\\folder")).is_err());
        set_dir(None);
    }
}
