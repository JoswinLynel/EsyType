# Open-source evaluation

**Date of all figures:** 15 November 2026, read from the GitHub, crates.io and Hugging Face public APIs
**Purpose:** choose the engines, libraries and models EsyType is built on, with licensing checked for a commercial closed-source product

> **Nothing here has been benchmarked yet.** Sizes, versions, licences and activity are facts from the registries. Speed and accuracy statements are expectations to be tested in the engine phase, and are marked as such. The brief's target (10 to 15 seconds of speech transcribed in 2 to 3 seconds) remains unverified.

---

## 1. Summary of decisions

| Area | Choice | Runner-up kept as an option |
|---|---|---|
| Desktop framework | **Tauri 2** (stable 2.12.5) | none; Tauri 3 is alpha and is not used |
| UI | **React + TypeScript + Vite + Tailwind CSS** | none |
| Speech engine, first | **whisper.cpp** 1.9.5 through a Rust binding | |
| Speech engine, second | **Parakeet TDT 0.6B v3** through ONNX Runtime, to be benchmarked against Whisper | Moonshine for very low-end machines |
| Voice activity detection | **Silero VAD v6** (the 0.9 MB GGML build that whisper.cpp loads directly) | `earshot` (pure Rust) |
| Clean-up engine | **llama.cpp** 1.0.0, run in a **separate helper process** | |
| Clean-up models | **Qwen2.5-0.5B-Instruct** and **Qwen2.5-1.5B-Instruct**, GGUF Q4_K_M | Gemma 3 1B after legal sign-off; Qwen3 0.6B / 1.7B to be compared |
| Audio capture | **cpal** 0.18 (WASAPI) with **rubato** resampling | direct WASAPI through `windows` |
| Global shortcuts | **Own low-level keyboard hook** (`windows` crate), `global-hotkey` as fallback | |
| Text insertion | **Own module on `windows` SendInput** plus clipboard save and restore | `enigo` |
| Local database | **SQLite** through `rusqlite` (bundled), FTS5 for search | |
| Hardware detection | `sysinfo` plus DXGI through `windows` | `nvml-wrapper` for NVIDIA detail |
| Model downloads | `reqwest` streaming with resume and SHA-256 verification against a manifest shipped in the app | `hf-hub` |
| Installer | Tauri bundler, **NSIS**, per-user | WiX MSI for enterprise later |
| Updates | `tauri-plugin-updater` (signed updates) | |

---

## 2. A project the brief did not list: Handy

**`cjpais/Handy`** is an MIT-licensed, open-source, fully offline dictation app built on Tauri 2 and React. It has 38,885 stars and released v0.10.1 on 14 November 2026. Its README describes the same core loop as EsyType's first milestone: press a shortcut, speak, release, and the text is pasted into the focused app, with Silero VAD and a choice of Whisper models or Parakeet V3 ("CPU-optimized model with excellent performance").

Why this matters:

1. **It is a competitor.** A free, popular, local-first dictation app already exists. EsyType has to win on what Handy explicitly declines to do ("One tool, one job"): the productivity layer (dictionary corrections, snippets, styles, transforms, insights), the hardware-aware install wizard, optional AI clean-up with review, wrong-window protection, and ESYAI design quality.
2. **It proves the stack.** Tauri 2 plus a native speech engine plus Silero VAD works on Windows in production. Its dependency list (read from its public `Cargo.toml`) is a useful map of what a shipping app needed: `rusqlite`, `enigo`, `rubato`, `reqwest`, `sha2`, `hf-hub`, `tauri-plugin-global-shortcut`, `tauri-plugin-single-instance`, `tauri-plugin-autostart`, `tauri-plugin-updater`, plus its own crates for recording, key handling and inference.
3. **It signals where the hard parts are.** Handy's team wrote their own crates for microphone capture (`handy-recorder`), global keys (`handy-keys`) and inference (`transcribe-cpp`). That is evidence the off-the-shelf options for those three areas were not good enough, which matches the choices in section 1.

**Position.** MIT would legally allow reuse with attribution. The brief requires EsyType to have its own source code and architecture, so EsyType will learn from Handy's public design decisions and write its own implementation. If any MIT code is ever adopted, it will be recorded in a third-party notices file.

---

## 3. Speech recognition engines

### 3.1 Comparison

| Project | Licence | Stars | Latest release | Language | Verdict |
|---|---|---|---|---|---|
| `openai/whisper` | MIT | 112,799 | v20250625 (26 Jun 2025) | Python, PyTorch | **Reference only.** Needs Python and PyTorch (gigabytes). Not embeddable in a small desktop app. |
| `SYSTRAN/faster-whisper` | MIT | 26,775 | v1.2.1 (31 Oct 2025) | Python on CTranslate2 | **Not chosen.** Fast on CPU, but a Python runtime would have to be bundled and managed. |
| `ggml-org/whisper.cpp` | MIT | 55,217 | v1.9.5 (6 Oct 2026) | C/C++ | **Chosen first engine.** Single native library, quantised GGML models, runs on plain CPUs, optional Vulkan, CUDA and OpenVINO back ends, built-in Silero VAD support. |
| `k2-fsa/sherpa-onnx` | Apache-2.0 | 15,970 | active, weekly | C++ on ONNX Runtime | **Strong second option.** Runs Parakeet, Whisper, Moonshine and others; includes VAD and speaker diarisation, which makes it the likely base for Notetaker later. Official Rust crate `sherpa-onnx` 2.0.1. |
| `OpenNMT/CTranslate2` | MIT | 4,751 | v4.9.0 (10 Nov 2026) | C++ | Engine under faster-whisper. No reason to adopt directly while whisper.cpp fits. |
| `moonshine-ai/moonshine` | MIT for code and English models | 11,519 | v0.1.6 (6 Nov 2026) | C++ / ONNX | **Candidate for very weak hardware.** English-only under MIT; several older non-English models are non-commercial and must not be shipped. |

### 3.2 Why whisper.cpp first

- **It covers the brief's model list exactly:** Tiny, Base, Small and Medium, each in multilingual and English-only form, each with quantised variants (section 3.4).
- **No runtime to install.** It compiles into the application.
- **Works without a GPU,** which the brief requires. GPU back ends are optional extras.
- **Supports an initial prompt,** the mechanism for feeding personal-dictionary terms to the recogniser.
- **MIT** for code and models.

### 3.3 Why Parakeet must be benchmarked as a second engine

- Handy's README singles out Parakeet V3 as its CPU-optimised option. NVIDIA's `parakeet-tdt-0.6b-v3` is licensed **CC-BY-4.0**, which allows commercial use with attribution.
- The int8 ONNX export is about 670 MB in three files (encoder 652.3 MB, decoder 11.8 MB, joiner 6.4 MB).
- **Expectation, not a result:** on CPU-only machines it may beat Whisper Small on both speed and English accuracy, and could be what makes the 2 to 3 second target reachable on an average laptop. This is the first thing to measure.
- Trade-offs to verify: v3 covers European languages rather than Whisper's wider set; dictionary biasing works differently from Whisper's prompt; one model size, so no small option for 4 GB machines.

The architecture therefore defines a `SpeechEngine` interface with whisper.cpp as the first implementation, so a second engine is an addition, not a rewrite.

### 3.4 Whisper model files (GGML, from `ggerganov/whisper.cpp` on Hugging Face, MIT)

Sizes are the actual file sizes. "RAM" is deliberately not listed: it will be measured on this project's hardware rather than quoted from elsewhere.

| Model | Full precision | Q8_0 | Q5 | English-only variant |
|---|---|---|---|---|
| Tiny | 77.7 MB | 43.5 MB | 32.2 MB (Q5_1) | yes, same sizes |
| Base | 148.0 MB | 81.8 MB | 59.7 MB (Q5_1) | yes |
| Small | 487.6 MB | 264.5 MB | 190.1 MB (Q5_1) | yes |
| Medium | 1,533.8 MB | 823.4 MB | 539.2 MB (Q5_0) | yes |
| Large-v3-turbo | 1,624.6 MB | 874.2 MB | 574.0 MB (Q5_0) | multilingual only |

Also available under MIT: `distil-whisper/distil-small.en` in GGML form (336.2 MB), a distilled English model worth including in the benchmark.

**Product lineup (decided 17 Nov 2026):** Tiny, Base and Small only, one file each. Measured results and the chosen files are in `docs/testing/2026-11-17-stt-dev-pc.md`; the recommendation logic is in the architecture, section 10.3. No hardware-to-model table is published until more machines are measured.

### 3.5 Rust bindings for whisper.cpp

| Crate | Version | Licence | Notes |
|---|---|---|---|
| `whisper-rs` | 0.16.0 (12 Mar 2026) | Unlicense | Most used (1.13 M downloads in 90 days). **Its GitHub repository was archived in July 2025; development moved to Codeberg.** Thin wrapper over whisper.cpp. |
| `transcribe-rs` | 0.3.12 (2 Oct 2026) | MIT | Multi-engine: whisper.cpp plus ONNX engines (Parakeet, Moonshine and others) with DirectML, CUDA and Vulkan features. By Handy's author. |
| `transcribe-cpp` | 0.4.2 (12 Nov 2026) | MIT | New ggml-based multi-model library from the Handy organisation. Young. |

**Decision.** Start with `whisper-rs` for the first milestone because it is the thinnest and most widely used, and keep it behind EsyType's own `SpeechEngine` interface. Evaluate `transcribe-rs` (or the official `sherpa-onnx` crate) when adding Parakeet. The archive of the GitHub mirror is a maintenance risk to watch, which is the main reason for the interface.

### 3.6 Acceleration on Windows

| Back end | Applies to | Status for EsyType |
|---|---|---|
| CPU (AVX2) | Everything | **Default and mandatory.** |
| Vulkan | Most GPUs including Intel Iris Xe and AMD integrated | To benchmark on the dev PC's Iris Xe. Integrated GPUs do not always beat the CPU. |
| OpenVINO | Intel CPUs and GPUs | To evaluate; adds a large runtime dependency. |
| CUDA | NVIDIA | Optional later; cannot be tested on the dev PC, which has no NVIDIA GPU. |
| DirectML (ONNX engines) | Any DirectX 12 GPU | Relevant if Parakeet is adopted. |

---

## 4. Voice activity detection

| Option | Licence | Size | Notes |
|---|---|---|---|
| **Silero VAD v6** (`snakers4/silero-vad`, v6.2.3, 23 Sep 2026) | MIT | 0.9 MB as GGML (`ggml-org/whisper-vad`), 0.6 to 2.2 MB as ONNX | **Chosen.** whisper.cpp can load the GGML file directly, so no extra runtime is needed. |
| `earshot` 1.2.2 | MIT or Apache-2.0 | none (pure Rust) | Fallback; used by Handy. |
| `voice_activity_detector` 0.2.1 | non-standard licence string | wraps Silero through ONNX Runtime | Not chosen: licence field needs review and it pulls in ONNX Runtime. |

Role in EsyType: trim leading and trailing silence, skip recordings that contain no speech (which prevents Whisper inventing text from silence), and segment long recordings. It is small enough to ship inside the installer rather than as a download.

---

## 5. Optional AI clean-up

### 5.1 Inference engine

| Project | Licence | Stars | Latest | Verdict |
|---|---|---|---|---|
| `ggml-org/llama.cpp` | MIT | 135,202 | v1.0.0 (13 Nov 2026) | **Chosen.** Runs GGUF models on CPU, with optional GPU back ends. |
| `utilityai/llama-cpp-rs` (`llama-cpp-2` 0.1.161, 3 Nov 2026) | MIT or Apache-2.0 | 674 | tracks llama.cpp closely | Rust binding, used inside the helper process. |
| ONNX Runtime GenAI | MIT | | | Not chosen: fewer small models in ready form. |

**Run it as a separate helper process.** Reasons:

1. whisper.cpp and llama.cpp each embed their own copy of the ggml library. Linking both into one program risks symbol clashes between two ggml versions. A separate executable removes the problem.
2. The brief requires speech recognition to work independently of AI clean-up. A separate process makes that true by construction: if the helper is missing, crashes or runs out of memory, dictation is unaffected.
3. Stopping the helper returns all of the model's memory to Windows at once, which matters on 8 GB machines.
4. It talks to the main app over standard input and output pipes, so **no network port is opened**, not even on localhost.

### 5.2 Models

All sizes are actual GGUF file sizes on Hugging Face.

| Model | Licence | Gated | Q4_K_M | Q5_K_M | Q8_0 | Commercial redistribution |
|---|---|---|---|---|---|---|
| **Qwen2.5-0.5B-Instruct** | Apache-2.0 | no | 491.4 MB | 522.2 MB | 675.7 MB | Yes, with licence notice |
| **Qwen2.5-1.5B-Instruct** | Apache-2.0 | no | 1,117.3 MB | 1,285.5 MB | 1,894.5 MB | Yes, with licence notice |
| Gemma 3 1B it | **Gemma Terms of Use** | Google's repos are gated; the `ggml-org` GGUF mirror is not | 806.1 MB | | 1,069.3 MB | Conditional, see below |
| Qwen3-0.6B | Apache-2.0 | no | | | 639.4 MB | Yes |
| Qwen3-1.7B | Apache-2.0 | no | | | 1,834.4 MB | Yes |
| SmolLM2-1.7B-Instruct | Apache-2.0 | no | 1,055.6 MB | | | Yes |
| SmolLM2-360M-Instruct | Apache-2.0 | no | | | 386.4 MB | Yes |
| Gemma 3 270M it | Gemma Terms of Use | gated | | | 291.5 MB | Conditional |

**Gemma licensing (terms last modified 1 April 2026).** Distribution is permitted only if the distributor includes Google's use restrictions "as an enforceable provision" in its own licence agreement and gives users notice of them. Google also "reserves the right to restrict (remotely or otherwise) usage". That means EsyType's end-user licence would have to carry Google's Prohibited Use Policy. It is workable, but it is a legal decision for ESYAI, not an engineering one.

**Decision.**

- Ship the wizard with **Qwen2.5-0.5B** as the lightweight option and **Qwen2.5-1.5B** as the more capable option. Both are Apache-2.0 and ungated, so EsyType can download them from Hugging Face or mirror them on ESYAI's own storage.
- **Hold Gemma 3 1B** until ESYAI decides whether to accept its terms.
- Compare **Qwen3 0.6B and 1.7B** during the AI phase. They are newer and Apache-2.0, but they are "thinking" models whose reasoning output must be reliably switched off for a clean-up task; that needs testing.

**Expectation to test, not a promise.** A 0.5B model is adequate for punctuation and light grammar and unreliable for rewriting; it will sometimes change meaning. That is why the design keeps rule-based Clean mode separate from the model, requires review before insertion for AI Enhanced, and adds automatic guards (reject output whose length or content drifts too far from the input).

---

## 6. Desktop framework

| Framework | Licence | Version | Installer size class | Glass materials on Windows | Verdict |
|---|---|---|---|---|---|
| **Tauri 2** | MIT or Apache-2.0 | 2.12.5 stable; 3.0.0-alpha.6 exists | Small: uses the system WebView2 | Mica, Acrylic and related effects through the window effects API and `window-vibrancy` 0.8.1 | **Chosen** |
| Electron | MIT | 45.3.3 | Large: bundles Chromium | Supported | Rejected: this is the footprint EsyType is trying to beat (Wispr Flow measured 920 MB installed, 12 processes) |
| WinUI 3 / .NET | MIT | | Medium | Best native support | Rejected: Windows-only C# stack, no reuse of ESYAI's React and Tailwind design language, different inference bindings |
| Wails 3 | MIT | 3.1.0 | Small | Supported | Rejected: Go back end; the Rust ecosystem for audio and inference is stronger |
| Flutter | BSD-3 | | Medium | Through plugins | Rejected: custom renderer, less natural fit for the glass styling already written as CSS |

Why Tauri 2 fits specifically:

- **WebView2 is already on this PC** (157.0.4341.46) and ships with Windows 11; Windows 10 machines get it through the installer's bootstrapper.
- **ESYAI's site is React, Tailwind and CSS variables.** The brand's glass classes transfer almost unchanged.
- **Rust core** gives direct, safe access to the Win32 APIs that dictation needs (keyboard hooks, SendInput, clipboard, WASAPI, DXGI) through Microsoft's own `windows` crate (0.62.2).
- **Official plugins cover the plumbing:** single instance 2.5.5, autostart 2.7.0, updater 2.14.1, global shortcut 2.4.1.

Known Tauri caveats to design around:

- Acrylic can stutter while a window is dragged or resized on some Windows builds (documented by `window-vibrancy`). Mica does not have this problem but is Windows 11 only. The design system specifies the fallback order.
- Tauri 3 is in alpha. EsyType stays on 2.x until 3.0 is stable.

---

## 7. Supporting libraries

| Need | Library | Version | Licence | Notes |
|---|---|---|---|---|
| Audio capture | `cpal` | 0.18.2 | Apache-2.0 | WASAPI on Windows; device enumeration and default-device changes |
| Resampling to 16 kHz mono | `rubato` | 5.1.0 | MIT or Apache-2.0 | |
| Win32 access | `windows` | 0.62.2 | MIT or Apache-2.0 | Keyboard hook, SendInput, clipboard formats, foreground window, DXGI, DPAPI |
| Global shortcuts (fallback) | `global-hotkey` | 0.10.0 | MIT or Apache-2.0 | Built on RegisterHotKey; cannot express modifier-only chords such as Ctrl + Win, and takes the key combination away from every other app, hence the custom hook |
| Key simulation (fallback) | `enigo` | 0.6.1 | MIT | Not the primary route; the custom module needs finer control |
| Clipboard | `arboard` | 3.7.0 | MIT or Apache-2.0 | Text and images; full multi-format save and restore needs Win32 directly |
| Database | `rusqlite` | 0.43.0 | MIT | Bundled SQLite with FTS5 |
| Hardware facts | `sysinfo` | 0.40.3 | MIT | CPU, cores, memory, disks, OS |
| GPU facts | DXGI through `windows`; `nvml-wrapper` 0.13.0 | | MIT or Apache-2.0 | Adapter name and dedicated VRAM for every vendor |
| HTTP downloads | `reqwest` | 0.13.5 | MIT or Apache-2.0 | Streaming, range requests for resume |
| Hash verification | `sha2` | | MIT or Apache-2.0 | |
| Hugging Face client | `hf-hub` | 1.0.0 | Apache-2.0 | Optional; direct HTTPS against a pinned manifest is simpler and more controllable |
| Update signature | `minisign-verify` (inside the updater) | 0.3.0 | MIT | |
| ONNX Runtime binding | `ort` | 2.0.0-rc.15 (no stable 2.0 yet) | MIT or Apache-2.0 | Only if Parakeet or Moonshine is adopted |

Avoided: `rdev` on crates.io (0.5.3, last published June 2023; Handy uses a fork from another organisation, which signals the upstream is stale) and `tauri-plugin-sql` (exposes SQL to the web layer; EsyType keeps all database access in Rust).

---

## 8. Licence compliance summary

| Component | Licence | Obligation for a closed-source commercial app |
|---|---|---|
| Tauri, cpal, rubato, windows, rusqlite, sysinfo, reqwest, arboard, llama-cpp-2 | MIT and/or Apache-2.0 | Include licence texts and notices |
| whisper.cpp, llama.cpp, Silero VAD | MIT | Include licence texts |
| `whisper-rs` | Unlicense (public-domain dedication) | None; list it anyway |
| SQLite | Public domain | None |
| Whisper models (OpenAI) | MIT | Include notice |
| Qwen2.5 models | Apache-2.0 | Include licence and notice |
| Parakeet TDT 0.6B (if adopted) | CC-BY-4.0 | **Visible attribution to NVIDIA** in the app's About or licences page |
| Gemma (if adopted) | Gemma Terms of Use | **Pass Google's use restrictions through EsyType's own licence agreement**; ESYAI legal decision |
| Moonshine non-English legacy models | Non-commercial | **Do not ship** |
| Fonts: Instrument Serif, Barlow | SIL Open Font License | May be bundled; include the licence; do not sell the fonts alone |
| Lucide icons | ISC | Include notice |

No GPL or LGPL component is in the chosen set, so there is no copyleft obligation on EsyType's own code. (FFmpeg, which is LGPL or GPL depending on build, is on the dev PC but is not part of the design.)

Deliverable for the release phase: a generated third-party notices file and an in-app licences page.

**Model hosting.** First release downloads models from Hugging Face over HTTPS and verifies SHA-256 against a manifest shipped inside the app. Every licence above permits ESYAI to mirror the files on its own storage later, which is recommended before a commercial launch so installs do not depend on a third party's availability.

---

## 9. Risks found during evaluation

| Risk | Impact | Mitigation |
|---|---|---|
| `whisper-rs` GitHub repo archived; development on Codeberg | Binding could stall | Engine interface; alternatives identified (`transcribe-rs`, `transcribe-cpp`, own FFI) |
| The `cmake` crate drops `/O2` from MSVC release flags (found 17 Nov 2026) | whisper.cpp compiles **unoptimised** and runs about 7 times slower (tiny.en on a 10 s clip: 8.1 s instead of 1.15 s) with no warning | Every crate that builds whisper.cpp or llama.cpp sets `CMAKE_C_FLAGS_RELEASE` and `CMAKE_CXX_FLAGS_RELEASE` to `/MD /O2 /Ob2 /DNDEBUG` in `.cargo/config.toml` (see `bench/stt-bench/.cargo/config.toml`). Check the generated `CMakeCache.txt` after any toolchain change. |
| `whisper-rs-sys` 0.15.0 ships bindings generated on Linux (found 16 Nov 2026) | On Windows the bundled bindings fail to compile, and the generator aborts instead of falling back when `libclang` is missing. LLVM's `libclang` is therefore a build requirement on Windows. | Install the Build Tools Clang component and set `LIBCLANG_PATH`; affects developers only, not end users |
| Two ggml copies in one program | Build or runtime failures | Clean-up runs in a separate helper process |
| `ort` has no stable 2.0 | API churn if Parakeet is adopted | Pin an exact version; isolate behind the engine interface |
| Performance target unproven on CPU-only hardware | Core promise of the product | Benchmark Whisper and Parakeet on the dev PC before building UI around either |
| Small clean-up models change meaning | Trust | Review before insertion, drift guards, rule-based Clean mode that needs no model |
| Hugging Face availability or rate limits | Install failures | Resume, retry, checksum, and a planned ESYAI mirror |
| Handy is free and already popular | Market | Differentiate on the productivity layer, design, wizard and safety features |
| Code-signing certificate not yet obtained | Windows SmartScreen warnings on install | ESYAI to procure a certificate before public release |
| Dev PC has 7.9 GB free on C: | Rust and MSVC toolchains may not fit | Install toolchains and build output on D:; see the roadmap |

---

## 10. What is installed so far

Only what the research phase needed:

| Item | Version | Where |
|---|---|---|
| Node.js | 24.22.3 (was 24.13.1) | `C:\Program Files\nodejs` |
| REA | 6.9.0 | npm global |
| ponytail plugin | 5.3.3 | Claude Code user plugins |

Added on 16 November 2026 for the foundation phase (measured sizes):

| Item | Version | Where | Size |
|---|---|---|---|
| Rust (minimal profile, clippy, rustfmt) | 1.100.0 | `D:\AI Projects\Tools\rust` | 646 MB |
| Microsoft C++ Build Tools 2022 | 17.14.37906, MSVC 14.44.35207 | `D:\AI Projects\Tools\vs` | 3,425 MB |
| Clang / `libclang` | 19.1.5 (Build Tools component) | inside the Build Tools folder | 5,580 MB (it installs x64, x86 and ARM64 builds) |
| Windows SDK | 10.0.26100.0 | `C:\Program Files (x86)\Windows Kits\10` (location fixed by Microsoft) | 1,725 MB |
| CMake and Ninja | 3.31.6 (bundled with Build Tools) | inside the Build Tools folder; added to the user PATH | included above |

User environment variables set: `RUSTUP_HOME`, `CARGO_HOME`, `LIBCLANG_PATH`, and two additions to the user `Path` (Cargo's `bin` and the bundled CMake).

**Build check passed (16 Nov 2026):** a throwaway crate using `whisper-rs` 0.16 compiles in 69 seconds, links whisper.cpp statically into a 2.8 MB executable, and runs. whisper.cpp reports CPU features AVX, AVX2, FMA, F16C and AVX-512 on the development PC. No audio has been transcribed yet.
