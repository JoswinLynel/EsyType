//! Hardware facts for the model cards: RAM, CPU and free storage, and whether a model fits.
use crate::models::Model;
use serde::Serialize;

#[derive(Serialize, Clone, Debug)]
pub struct Hardware {
    pub cpu: String,
    pub logical: usize,
    pub physical: Option<usize>,
    pub avx2: bool,
    pub total_ram_mb: u64,
    pub available_ram_mb: u64,
    pub free_disk_mb: u64,
}

/// Any probe that fails reports 0 / empty rather than stopping the app.
pub fn detect() -> Hardware {
    let s = sysinfo::System::new().ok().map(|mut s| {
        s.refresh_memory();
        s.refresh_cpu_all();
        s
    });
    let data = crate::models::dir(); // free space where models are stored
    let free = sysinfo::Disks::new_with_refreshed_list()
        .ok()
        .and_then(|disks| {
            disks.iter().filter(|d| data.starts_with(d.mount_point())).max_by_key(|d| d.mount_point().as_os_str().len()).map(|d| d.available_space())
        })
        .unwrap_or(0);
    Hardware {
        cpu: s.as_ref().and_then(|s| s.cpus().first().map(|c| c.brand().trim().to_string())).unwrap_or_default(),
        logical: std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1),
        physical: sysinfo::System::physical_core_count().ok(),
        avx2: std::arch::is_x86_feature_detected!("avx2"),
        total_ram_mb: s.as_ref().map(|s| s.total_memory()).unwrap_or(0) / 1_048_576,
        available_ram_mb: s.as_ref().map(|s| s.available_memory()).unwrap_or(0) / 1_048_576,
        free_disk_mb: free / 1_048_576,
    }
}

// shortcut: EsyType's own memory use is not measured yet; 300 MB is a placeholder until the app is profiled.
const APP_HEADROOM_MB: u64 = 300;

/// "ok", "ram" (not enough free memory) or "disk" (not enough free storage).
pub fn fit(m: &Model, hw: &Hardware, installed: bool) -> &'static str {
    if hw.available_ram_mb < m.peak_ram_mb + APP_HEADROOM_MB {
        "ram"
    } else if !installed && hw.free_disk_mb < m.bytes * 3 / 2 / 1_048_576 {
        "disk"
    } else {
        "ok"
    }
}

/// The model to recommend on this PC: Base, or Tiny when Base does not fit; None when neither fits. Small is never
/// recommended automatically, and there is no hardware-to-model table until more PCs are measured (owner, 17 Nov).
pub fn recommend(hw: &Hardware) -> Option<&'static str> {
    [crate::models::DEFAULT, "tiny"].into_iter().find(|id| {
        let m = crate::models::find(id).expect("known model");
        fit(m, hw, crate::models::installed(m)) == "ok"
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn hw(ram: u64, disk: u64) -> Hardware {
        Hardware { cpu: String::new(), logical: 8, physical: Some(4), avx2: true, total_ram_mb: ram, available_ram_mb: ram, free_disk_mb: disk }
    }
    #[test]
    fn fit_checks() {
        let small = crate::models::find("small").unwrap();
        assert_eq!(fit(small, &hw(4000, 10_000), false), "ok");
        assert_eq!(fit(small, &hw(800, 10_000), false), "ram");
        assert_eq!(fit(small, &hw(4000, 100), false), "disk");
        assert_eq!(fit(small, &hw(4000, 100), true), "ok"); // already downloaded: no disk needed
    }
    #[test]
    fn recommendation() {
        let base = crate::models::find("base").unwrap();
        assert_eq!(recommend(&hw(8000, 10_000)), Some("base"));
        assert_eq!(recommend(&hw(base.peak_ram_mb + 299, 10_000)), Some("tiny")); // Base just too big, Tiny fits
        assert_eq!(recommend(&hw(100, 10_000)), None);
    }
}
