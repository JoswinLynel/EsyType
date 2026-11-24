import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { HistoryPrivacy, type HistorySettings } from "./history";
import type { StyleSettings } from "./style";
import { ask, Banner, exported, Icon, toast, toastError } from "./ui";

export type Model = {
  id: string; name: string; tagline: string; bytes: number; languages: string;
  peak_ram_mb: number; ref_seconds_10s: number; ref_wer_pct: number;
};
export type Settings = { model: string; mic: string | null; threads: number; ptt: string; toggle: string; models_dir: string | null; start_with_windows: boolean;
  text_mode: "clean" | "verbatim"; clean_fillers_extended: boolean; clean_small_numbers_as_words: boolean; dictionary_hint: boolean; builtin_vocabulary: boolean;
  undo_shortcut: string; paste_last_shortcut: string; undo_on_pill: boolean; undo_never: string[]; setup_done: boolean | null; theme: "system" | "dark" | "light"; user_name: string; typing_wpm: number } & HistorySettings & StyleSettings;
export type Status = {
  settings: Settings;
  models: { model: Model; installed: boolean; fit: "ok" | "ram" | "disk" }[];
  /** Base, or Tiny when Base does not fit; null when neither fits. */
  recommended: string | null;
  hardware: { cpu: string; logical: number; physical: number | null; avx2: boolean; total_ram_mb: number; available_ram_mb: number; free_disk_mb: number };
  mics: string[];
  loaded: string | null;
  threads_auto: number;
  threads_effective: number;
  downloading: string | null;
  shortcuts_ok: boolean;
  last: { text: string; outcome: string; seconds: number; audio_seconds: number } | null;
  models_dir: string;
  models_dir_default: string;
  history_available: boolean;
  history_error: string | null;
  dictionary_hint_words: number;
  settings_problem: { reset: string[]; kept: string | null } | null;
  data_bytes: number;
  models_bytes: number;
  /** When the newest restore safety copy was made (Undo restore), Unix ms. */
  undo_restore: number | null;
  download_source: string;
  data_dir: string;
  version: string;
};
export type Progress = { id: string; done?: number; total?: number; finished?: boolean; error?: string };
/** Saves a change; false (with the error shown) if it was refused. */
export type Save = (patch: Partial<Settings>) => Promise<boolean>;

export const mb = (b: number) => `${Math.round(b / 1_000_000)} MB`;
const SLOW_SECONDS = 3; // the brief's target: 10 s of speech in 2-3 s

/** Names for settings.json keys, for the "these settings were reset" banner. */
const LABELS: Record<string, string> = {
  model: "Speech model", mic: "Microphone", threads: "Processor threads", ptt: "Hold-to-talk shortcut", toggle: "Start/stop shortcut",
  models_dir: "Model folder", start_with_windows: "Start with Windows", history_enabled: "Save dictations in History",
  history_retention_days: "Keep history", history_record_app: "Note the program", history_keep_raw: "Keep the original transcription",
  text_mode: "Clean or Verbatim", clean_fillers_extended: "Extra fillers", clean_small_numbers_as_words: "Zero to nine as words",
  dictionary_hint: "Dictionary hint", builtin_vocabulary: "Correct common product names", style_default: "Style for other apps", style_rules: "Style rules for apps", style_custom: "Custom style",
  undo_shortcut: "Undo shortcut", paste_last_shortcut: "Paste last shortcut", undo_on_pill: "Undo on the pill", undo_never: "Programs without Undo", theme: "Theme", user_name: "Your name", typing_wpm: "Typing speed",
};

export function SettingsProblem({ p, onDismiss }: { p: NonNullable<Status["settings_problem"]>; onDismiss: () => void }) {
  const what = p.reset.length
    ? <>Some settings could not be read and were reset to their defaults: {p.reset.map((k) => LABELS[k] ?? k).join(", ")}. Your other settings are kept.</>
    : <>Your settings file could not be read, so EsyType is using default settings.</>;
  return (
    <Banner tone="amber" action={<span className="row">
      {p.kept && <button className="btn sm" onClick={() => invoke("show_in_folder", { path: p.kept }).catch(toastError)}>Show in folder</button>}
      <button className="btn sm" onClick={onDismiss}>Dismiss</button>
    </span>}>
      {what} {p.kept ? "The original file was kept as " + p.kept.split(/[\\/]/).pop() + "." : "The file could not be copied."}
    </Banner>
  );
}

function ModelCard({ entry, recommended, selected, onSelect, active }: {
  entry: Status["models"][number]; recommended: boolean; selected: boolean; onSelect: () => void; active: boolean;
}) {
  const { model: m, installed, fit } = entry;
  const slow = m.ref_seconds_10s > SLOW_SECONDS;
  const chip = fit === "ram" ? ["red", "Not enough free memory"] : fit === "disk" ? ["red", "Not enough free storage"]
    : slow ? ["amber", "May feel slow on many PCs"] : ["green", "Fits this PC"];
  return (
    <button className={"card" + (selected ? " selected" : "")} onClick={onSelect} aria-pressed={selected}>
      <div className="row" style={{ justifyContent: "space-between" }}>
        <span className="name">{m.name}</span>
        {active ? <span className="badge">Active</span> : recommended && <span className="badge">Recommended</span>}
      </div>
      <div className="small">{m.tagline}</div>
      <dl>
        <dt>Download</dt><dd>{installed ? "Downloaded" : mb(m.bytes)}</dd>
        <dt>Memory</dt><dd>about {m.peak_ram_mb} MB</dd>
        <dt>Speed</dt><dd>{m.ref_seconds_10s.toFixed(1)} s per 10 s of speech*</dd>
        <dt>Languages</dt><dd>{m.languages}</dd>
      </dl>
      <div style={{ marginTop: 12 }}><span className={"chip " + chip[0]}>{chip[1]}</span></div>
    </button>
  );
}

/** The model a page starts with selected: the active one once any is installed, else the recommendation. */
export const initialModel = (status: Status) =>
  status.models.some((x) => x.installed) ? status.settings.model : status.recommended ?? "tiny";

/** Asks first when the model may not fit or may feel slow; true to go ahead. */
export async function confirmModel(status: Status, id: string) {
  const entry = status.models.find((x) => x.model.id === id)!;
  const m = entry.model;
  const hw = status.hardware;
  const go = entry.installed ? `Use ${m.name}` : `Download ${m.name}`;
  if (entry.fit !== "ok" && !await ask({ title: `${m.name} may not run well on this PC`, body: `This PC has ${hw.available_ram_mb} MB of free memory and ${hw.free_disk_mb} MB of free storage.`, action: go })) return false;
  if (entry.fit === "ok" && m.ref_seconds_10s > SLOW_SECONDS && !await ask({ title: `${m.name} may feel slow here`, body: `It took about ${m.ref_seconds_10s.toFixed(1)} s to transcribe 10 s of speech on a 4-core test laptop.`, action: go })) return false;
  return true;
}

export function ModelCards({ status, selected, onSelect }: { status: Status; selected: string; onSelect: (id: string) => void }) {
  const anyInstalled = status.models.some((x) => x.installed);
  return (
    <>
      <div className="cards">
        {status.models.map((e) => (
          <ModelCard key={e.model.id} entry={e} recommended={e.model.id === status.recommended} selected={e.model.id === selected}
            active={anyInstalled && e.model.id === status.loaded} onSelect={() => onSelect(e.model.id)} />
        ))}
      </div>
      <p className="small">*Measured on a 4-core Intel laptop without a graphics card. Your PC may be faster or slower. Only the model you choose is downloaded; you can add another later. Every download is checked (SHA-256) before it is used.</p>
    </>
  );
}

/** The three model cards with download, used by Settings. */
export function ModelChooser({ status, progress, setProgress, save }: {
  status: Status; progress: Progress | null; setProgress: (p: Progress | null) => void; save: Save;
}) {
  const [choice, setChoice] = useState<string | null>(null);
  const selected = choice ?? initialModel(status);
  const sel = status.models.find((x) => x.model.id === selected)!;
  const downloading = status.downloading ?? (progress && !progress.finished && !progress.error ? progress.id : null);
  const pct = progress?.total ? Math.round(((progress.done ?? 0) / progress.total) * 100) : 0;
  const hw = status.hardware;

  const pick = async (id: string) => {
    const entry = status.models.find((x) => x.model.id === id)!;
    const m = entry.model;
    if (!await confirmModel(status, id)) return;
    if (entry.installed) return save({ model: id });
    try {
      setProgress({ id, done: 0, total: m.bytes });
      await invoke("download_model", { id });
    } catch (e) {
      toastError(e);
    }
  };

  return (
    <>
      <ModelCards status={status} selected={selected} onSelect={setChoice} />
      <div className="row">
        {sel.installed ? (
          <button className="btn primary" disabled={status.loaded === selected} onClick={() => pick(selected)}>
            {status.loaded === selected ? `${sel.model.name} is active` : `Use ${sel.model.name}`}
          </button>
        ) : (
          <button className="btn primary" disabled={!!downloading} onClick={() => pick(selected)}>
            Download {sel.model.name} · {mb(sel.model.bytes)}
          </button>
        )}
        {downloading && <button className="btn" onClick={() => invoke("cancel_download")}>Cancel download</button>}
      </div>
      {downloading && (
        <>
          <div className="progress" aria-label="Download progress"><div style={{ width: `${pct}%` }} /></div>
          <p className="small" role="status">Downloading {downloading}: {pct}%{progress?.done ? ` (${mb(progress.done)} of ${mb(progress.total ?? 0)})` : ""}</p>
        </>
      )}
      <p className="small">This PC: {hw.cpu || "CPU"} · {hw.physical ? `${hw.physical} cores, ` : ""}{hw.logical} threads · {Math.round(hw.total_ram_mb / 1024)} GB RAM ({hw.available_ram_mb} MB free) · {Math.round(hw.free_disk_mb / 1024)} GB free storage{hw.avx2 ? "" : " · no AVX2 (untested)"}</p>
    </>
  );
}

export const CTRL_SPACE_NOTE = "Ctrl+Space is also used by Windows to switch Chinese input methods, by Excel to select a column, by code editors for suggestions and by Word to clear formatting. If you use those, choose another shortcut.";

const MODIFIER_CODES = /^(Control|Shift|Alt|Meta|OS)(Left|Right)?$/;
/** A key press as EsyType writes shortcuts ("Ctrl+Shift+Space", "Ctrl+F8", "Alt+D"). */
function combo(e: React.KeyboardEvent) {
  const mods = [e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", e.metaKey && "Win"].filter(Boolean) as string[];
  // Input without a hardware scan code (remote desktops, on-screen keyboards) has no code: fall back to the key name.
  const k = e.key;
  const code = e.code && e.code !== "Unidentified" ? e.code
    : k === " " ? "Space" : /^[a-z]$/i.test(k) ? "Key" + k.toUpperCase() : /^\d$/.test(k) ? "Digit" + k : k;
  if (MODIFIER_CODES.test(code)) return { text: mods.join("+") + "+…", done: false };
  const key = code.replace(/^Key([A-Z])$/, "$1").replace(/^Digit(\d)$/, "$1");
  return { text: [...mods, key].join("+"), done: true };
}

/**
 * A shortcut shown as keys, changed by pressing the new keys. EsyType's own shortcuts are paused while capturing
 * (Windows would otherwise hand them to EsyType), and resumed on Use, Cancel, Esc, leaving the window, or after
 * 20 seconds (by EsyType itself).
 */
export function KeyCapture({ label, value, save, optional }: { label: string; value: string; save: (v: string) => Promise<boolean>; optional?: boolean }) {
  const [capturing, setCapturing] = useState(false);
  const [keys, setKeys] = useState<{ text: string; done: boolean } | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const box = useRef<HTMLDivElement>(null);
  const stop = () => {
    setCapturing(false);
    setKeys(null);
    setProblem(null);
    invoke("pause_shortcuts", { on: false });
  };
  useEffect(() => {
    if (!capturing) return;
    box.current?.focus();
    // Only when the window really lost focus: a click inside it can blur it for a moment.
    const blur = () => setTimeout(() => { if (!document.hasFocus()) stop(); }, 150);
    window.addEventListener("blur", blur);
    const timedOut = listen("shortcuts-resumed", () => {
      setCapturing(false);
      setKeys(null);
      toast("Shortcut change timed out. Your shortcuts are unchanged.");
    });
    return () => {
      window.removeEventListener("blur", blur);
      timedOut.then((f) => f());
      invoke("pause_shortcuts", { on: false }); // also when the page changes mid-capture; resuming twice is harmless
    };
  }, [capturing]);

  const start = async () => {
    await invoke("pause_shortcuts", { on: true });
    setCapturing(true);
  };
  const onKey = async (e: React.KeyboardEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.repeat) return;
    if (e.key === "Tab" && !e.ctrlKey && !e.altKey && !e.shiftKey) { // Tab leaves the box, to reach Use this
      e.currentTarget.parentElement?.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus();
      return;
    }
    if (e.key === "Escape" && !e.ctrlKey && !e.altKey && !e.shiftKey) return stop();
    const c = combo(e);
    setKeys(c);
    setProblem(c.done ? await invoke<string | null>("check_shortcut", { text: c.text }) : null);
  };
  const use = async () => {
    if (!keys?.done || problem) return;
    const v = keys.text;
    stop(); // resumes the current shortcuts first; saving then swaps them for the new one
    if (v !== value && await save(v)) toast(`${label}: ${v}`);
  };

  return (
    <div className="keyrow">
      <span className="keyname">{label}</span>
      {capturing ? (
        <div className="capture" ref={box} tabIndex={0} role="textbox" aria-label={`Press the new ${label} shortcut`} onKeyDown={onKey} onKeyUp={(e) => e.preventDefault()}>
          {keys ? <kbd>{keys.text}</kbd> : <span className="muted">Press the keys you want…</span>}
        </div>
      ) : value ? <kbd>{value}</kbd> : <span className="muted">none</span>}
      {capturing ? (
        <span className="row" key="capturing">
          <button className="btn sm primary" disabled={!keys?.done || !!problem} onClick={use}>Use this</button>
          <button className="btn sm" onClick={stop}>Cancel</button>
        </span>
      ) : (
        <span className="row" key="idle">
          <button className="btn sm" aria-label={`Change ${label} shortcut`} onClick={start}>Change</button>
          {optional && value && <button className="btn sm" aria-label={`Remove ${label} shortcut`} onClick={async () => { if (await save("")) toast(`${label}: no shortcut`); }}>Remove</button>}
        </span>
      )}
      {capturing && problem && <span className="keyproblem" role="alert">{problem}</span>}
    </div>
  );
}

/** "28 KB", "60 MB", "1.2 GB". */
const size = (b: number) => b < 1_000_000 ? `${Math.max(1, Math.round(b / 1000))} KB` : b < 1_000_000_000 ? `${Math.round(b / 1_000_000)} MB` : `${(b / 1_000_000_000).toFixed(1)} GB`;

/** A setting's value in words, for the import list. */
const shown = (v: unknown): string =>
  typeof v === "boolean" ? (v ? "on" : "off") : v === null || v === "" ? "none" : Array.isArray(v) ? `${v.length} ${v.length === 1 ? "item" : "items"}` : typeof v === "object" ? "changed" : String(v);

type BackupInfo = { app_version: string; schema: number; made_at: number; model: string; counts: { transcripts: number; dictionary: number; snippets: number; notes: number } };
type Preview = { changes: { key: string; from: unknown; to: unknown }[]; skipped: { key: string; why: string }[] };

/** Backups, the settings file, internet use and Delete all EsyType data (Settings, Data and privacy). */
function DataTools({ status, refresh }: { status: Status; refresh: () => Promise<unknown> }) {
  const backupFile = useRef<HTMLInputElement>(null);
  const settingsFile = useRef<HTMLInputElement>(null);
  const [working, setWorking] = useState(false);
  const run = async (f: () => Promise<void>) => {
    setWorking(true);
    try { await f(); } catch (e) { toastError(e); }
    setWorking(false);
    await refresh();
  };
  const done = (note: string | null, ok: string) => note ? toast(note) : toast(ok);

  const backupNow = () => run(async () => {
    const r = await invoke<{ path: string }>("backup_now");
    exported(r.path);
  });
  const restore = (f: File) => run(async () => {
    const info = await invoke<BackupInfo>("backup_check", new Uint8Array(await f.arrayBuffer()));
    const c = info.counts;
    const model = status.models.find((m) => m.model.id === info.model);
    const list = [
      `${c.transcripts} ${c.transcripts === 1 ? "dictation" : "dictations"}, ${c.dictionary} dictionary ${c.dictionary === 1 ? "entry" : "entries"}, ${c.snippets} ${c.snippets === 1 ? "snippet" : "snippets"}, ${c.notes} ${c.notes === 1 ? "note" : "notes"}, and settings`,
      "Your microphone and model folder on this PC are kept",
      ...(model && !model.installed ? [`The backup used the ${model.model.name} speech model, which is not downloaded here: your current model is kept`] : []),
    ];
    if (!await ask({
      title: `Restore the backup from ${new Date(info.made_at).toLocaleString()}?`,
      body: "It replaces your current History, Dictionary, Snippets, notes and settings. A safety copy of your current data is made first, so you can undo this.",
      list, action: "Restore", danger: true,
    })) { await invoke("backup_forget"); return; }
    done(await invoke<string | null>("restore_backup"), "Backup restored. Undo restore puts your previous data back.");
  });
  const undoRestore = () => run(async () => {
    if (!await ask({ title: "Undo the restore?", body: "Your data goes back to how it was before the last restore.", action: "Undo restore" })) return;
    done(await invoke<string | null>("undo_restore"), "Restore undone.");
  });
  const exportSettings = () => run(async () => { exported(await invoke<string>("settings_export")); });
  const importSettings = (f: File) => run(async () => {
    const text = await f.text();
    const p = await invoke<Preview>("settings_import_preview", { text });
    const skipped = p.skipped.map((x) => `Not changed: ${LABELS[x.key] ?? x.key} (${x.why})`);
    if (!p.changes.length) { toast(skipped.length ? `Nothing to change. ${skipped.join(". ")}.` : "Nothing to change: these settings are the same as yours."); return; }
    const list = [...p.changes.map((c) => `${LABELS[c.key] ?? c.key}: ${shown(c.from)} → ${shown(c.to)}`), ...skipped];
    if (!await ask({ title: `Change ${p.changes.length} ${p.changes.length === 1 ? "setting" : "settings"}?`, list, action: "Apply" })) return;
    done(await invoke<string | null>("settings_import_apply", { text }), "Settings imported.");
  });
  const deleteAll = () => run(async () => {
    const check = { label: `Also delete the downloaded speech models (${size(status.models_bytes)}). EsyType then sets up again from the start.`, value: false };
    if (!await ask({
      title: "Delete all EsyType data?",
      body: "This cannot be undone. Make a backup first if you may want any of it back.",
      list: [
        "Deleted: History, Dictionary, Snippets and notes, so they cannot be recovered from the file",
        "Settings go back to their defaults; safety copies and kept damaged-settings files are deleted",
        "Kept: backups and exports in your Downloads folder, and the program itself",
      ],
      check, action: "Delete everything", danger: true,
    })) return;
    done(await invoke<string | null>("delete_all_data", { models: check.value }), "All EsyType data deleted.");
  });

  const src = status.download_source.replace(/^https:\/\//, "").replace(/\/resolve\/(\w{7})\w*$/, " (version $1)");
  return (
    <>
      <h3>Backups</h3>
      <p className="small">A backup is one file holding your History, Dictionary, Snippets, notes and settings (not the speech models), saved to your Downloads folder. <b>It is not encrypted:</b> keep it somewhere private.</p>
      <div className="row">
        <button className="btn" disabled={working} onClick={backupNow}>Back up now</button>
        <button className="btn" disabled={working} onClick={() => backupFile.current?.click()}>Restore from a backup…</button>
        {status.undo_restore && <button className="btn" disabled={working} onClick={undoRestore}>Undo restore</button>}
        <input ref={backupFile} type="file" accept=".esytype-backup" hidden aria-label="Backup file" onChange={(e) => { const f = e.target.files?.[0]; if (f) restore(f); e.target.value = ""; }} />
      </div>
      {status.undo_restore && <p className="small">Undo restore puts back your data from before the restore on {new Date(status.undo_restore).toLocaleString()}. Delete all history removes these safety copies.</p>}

      <h3>Settings file</h3>
      <p className="small">Shortcuts, text, styles, Undo and History options, to move to another PC or keep. Your microphone and model folder are never taken from a file: they belong to this PC.</p>
      <div className="row">
        <button className="btn" disabled={working} onClick={exportSettings}>Export settings</button>
        <button className="btn" disabled={working} onClick={() => settingsFile.current?.click()}>Import settings…</button>
        <input ref={settingsFile} type="file" accept=".json,application/json" hidden aria-label="Settings file" onChange={(e) => { const f = e.target.files?.[0]; if (f) importSettings(f); e.target.value = ""; }} />
      </div>

      <h3>Internet use</h3>
      <p className="small">EsyType connects to the internet only when you download a speech model: one file from {src}, checked by its SHA-256 fingerprint before it is used. Nothing you say or write is sent anywhere. No account, no analytics, no update checks.</p>

      <h3>Delete all EsyType data</h3>
      <p className="small">History, Dictionary, Snippets, notes and settings, from this PC. The speech models only if you choose.</p>
      <button className="btn danger" disabled={working} onClick={deleteAll}>Delete all EsyType data</button>
    </>
  );
}

/** The Settings panel's sections (Mac design system, Settings), in sidebar order. */
export const SECTIONS = [
  ["general", "General"], ["shortcuts", "Shortcuts"], ["recording", "Recording"], ["speech", "Speech"], ["models", "Models"],
  ["privacy", "History & Privacy"], ["permissions", "Permissions"], ["about", "About"],
] as const;
export type Section = (typeof SECTIONS)[number][0];

/** Settings as a panel over the main window: its own sidebar, one section at a time. Esc or a click outside closes it. */
export function SettingsPanel({ section, setSection, close, ...rest }: Parameters<typeof SettingsPage>[0] & { setSection: (s: Section) => void; close: () => void }) {
  const panel = useRef<HTMLDivElement>(null);
  const before = useRef<HTMLElement | null>(null);
  useEffect(() => {
    before.current = document.activeElement as HTMLElement | null;
    panel.current?.querySelector<HTMLElement>(".side-nav button.on")?.focus();
    // A confirmation dialog on top handles its own Esc.
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape" && !document.querySelector(".dialog") && !e.defaultPrevented) { e.preventDefault(); close(); } };
    window.addEventListener("keydown", esc);
    return () => { window.removeEventListener("keydown", esc); before.current?.focus?.(); };
  }, [close]);
  const label = SECTIONS.find(([id]) => id === section)![1];
  const row = ([id, name]: (typeof SECTIONS)[number]) => (
    <button key={id} className={section === id ? "on" : ""} aria-current={section === id ? "page" : undefined} onClick={() => setSection(id)}>
      <span className="side-label">{name}</span>
    </button>
  );
  const arrows = (e: React.KeyboardEvent<HTMLElement>) => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    const at = SECTIONS.findIndex(([id]) => id === section);
    e.preventDefault();
    const next = SECTIONS[(at + (e.key === "ArrowDown" ? 1 : SECTIONS.length - 1)) % SECTIONS.length][0];
    setSection(next);
    setTimeout(() => panel.current?.querySelector<HTMLElement>(".side-nav button.on")?.focus(), 0);
  };
  return (
    <div className="scrim settings-scrim" onMouseDown={(e) => e.target === e.currentTarget && close()}>
      <div ref={panel} className="settings-panel" role="dialog" aria-modal="true" aria-label="Settings">
        <aside className="settings-side">
          <nav className="side-nav" aria-label="Settings sections" onKeyDown={arrows}>
            <span className="side-eyebrow">Settings</span>
            {SECTIONS.slice(0, -1).map(row)}
            <span className="side-rule" />
            <span className="side-eyebrow">EsyType</span>
            {row(SECTIONS[SECTIONS.length - 1])}
          </nav>
          <p className="settings-foot"><span>EsyType {rest.status.version}</span><span title="Everything runs on this PC"><Icon name="lock" size={14} /> On this PC</span></p>
        </aside>
        <div className="settings-content">
          <h1 className="settings-title">{label}</h1>
          <SettingsPage section={section} {...rest} />
        </div>
      </div>
    </div>
  );
}

export function SettingsPage({ section, status, save, refresh, progress, setProgress, openSetup }: {
  section: Section; status: Status; save: Save; refresh: () => Promise<unknown>; progress: Progress | null; setProgress: (p: Progress | null) => void; openSetup: () => void;
}) {
  const s = status.settings;
  const hw = status.hardware;
  const [never, setNever] = useState<string | null>(null);
  const [folder, setFolder] = useState(status.models_dir);
  const [moving, setMoving] = useState(false);
  const [mic, setMic] = useState<boolean | null>(null);
  useEffect(() => { if (section === "permissions") invoke<boolean>("microphone_allowed").then(setMic).catch(() => setMic(null)); }, [section]);
  const is = (...ids: Section[]) => ids.includes(section);

  return (
    <>
      {is("models") && <section className="panel" id="set-model">
        <h2>Speech model</h2>
        <ModelChooser status={status} progress={progress} setProgress={setProgress} save={save} />
      </section>}

      {is("recording") && <section className="panel" id="set-microphone">
        <h2>Microphone</h2>
        <label className="field" style={{ maxWidth: 420 }}>
          <span>Microphone</span>
          <select value={s.mic ?? ""} onChange={(e) => save({ mic: e.target.value || null })}>
            <option value="">Windows default</option>
            {status.mics.map((m) => <option key={m} value={m}>{m}</option>)}
          </select>
        </label>
        {s.mic && !status.mics.includes(s.mic) && (
          <div style={{ marginTop: 12 }}><Banner tone="amber">"{s.mic}" is not connected. EsyType will use the Windows default microphone until it is.</Banner></div>
        )}
      </section>}

      {is("shortcuts") && <section className="panel" id="set-shortcuts">
        <h2>Shortcuts</h2>
        {!status.shortcuts_ok && <Banner tone="red">A shortcut could not be registered; another app may be using it. Choose a different one.</Banner>}
        <div className="keys">
          <KeyCapture label="Hold to talk" value={s.ptt} save={(v) => save({ ptt: v })} />
          <KeyCapture label="Start / stop" value={s.toggle} save={(v) => save({ toggle: v })} />
          <KeyCapture label="Undo last dictation" value={s.undo_shortcut} save={(v) => save({ undo_shortcut: v })} optional />
          <KeyCapture label="Paste last again" value={s.paste_last_shortcut} save={(v) => save({ paste_last_shortcut: v })} optional />
        </div>
        <p className="small">{CTRL_SPACE_NOTE} <kbd>Esc</kbd> always cancels a dictation.</p>
      </section>}

      {is("speech") && <section className="panel" id="set-text">
        <h2>Text</h2>
        <p className="small">Clean or Verbatim, Clean’s options and per-app style are on the Style page.</p>
      </section>}

      {is("shortcuts") && <section className="panel" id="set-undo">
        <h2>Undo</h2>
        <label className="row">
          <input type="checkbox" checked={s.undo_on_pill} onChange={(e) => save({ undo_on_pill: e.target.checked })} />
          <span>Show Undo on the pill after a dictation</span>
        </label>
        <p className="small">Undo sends the app's own Ctrl+Z once, and only for the last dictation, within 60 seconds, in the same window, and if you have not typed or clicked since; otherwise EsyType tells you why it did nothing. It is never offered in consoles and terminals.</p>
        <div className="row">
          <label className="field" style={{ flex: 1 }}>
            <span>Never offer Undo in these programs too</span>
            <input type="text" value={never ?? s.undo_never.join(", ")} onChange={(e) => setNever(e.target.value)} />
          </label>
          <button className="btn" style={{ alignSelf: "end" }} disabled={never === null} onClick={async () => {
            if (await save({ undo_never: (never ?? "").split(",").map((x) => x.trim()).filter(Boolean) })) { setNever(null); toast("List saved."); }
          }}>Save list</button>
        </div>
      </section>}

      {is("general") && <section className="panel" id="set-appearance">
        <h2>Appearance</h2>
        <div className="seg" role="radiogroup" aria-label="Theme">
          {([["system", "Follow Windows"], ["dark", "Dark"], ["light", "Light"]] as const).map(([v, name]) => (
            <button key={v} role="radio" aria-checked={s.theme === v} className={s.theme === v ? "on" : ""} onClick={() => save({ theme: v })}>{name}</button>
          ))}
        </div>
        <p className="small">Follow Windows switches with your Windows light or dark mode. Frosted glass appears while Windows' Transparency effects are on (Settings, Personalisation, Colours).</p>
      </section>}

      {is("general") && <section className="panel" id="set-about-you">
        <span className="side-eyebrow card-eyebrow">About you</span>
        <label className="field" style={{ maxWidth: 360 }}>
          <span>Your name</span>
          <input type="text" placeholder="Optional" maxLength={60} defaultValue={s.user_name} key={s.user_name}
            onBlur={(e) => { const v = e.target.value.trim(); if (v !== s.user_name) save({ user_name: v }); }}
            onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
        </label>
        <p className="small">Its first word greets you on the Dictation page. Kept only in EsyType's settings file on this PC.</p>
      </section>}

      {is("general") && <section className="panel" id="set-startup">
        <h2>Startup</h2>
        <label className="row">
          <input type="checkbox" checked={s.start_with_windows} onChange={(e) => save({ start_with_windows: e.target.checked })} />
          <span>Start EsyType when Windows starts (it waits in the system tray)</span>
        </label>
      </section>}

      {is("speech") && <section className="panel" id="set-performance">
        <h2>Performance</h2>
        <label className="field" style={{ marginTop: 12, maxWidth: 240 }}>
          <span>Processor threads</span>
          <select value={s.threads} onChange={(e) => save({ threads: Number(e.target.value) })}>
            <option value={0}>Automatic ({status.threads_auto})</option>
            {Array.from({ length: hw.logical }, (_, i) => i + 1).map((n) => <option key={n} value={n}>{n}</option>)}
          </select>
        </label>
        <p className="small">Automatic uses one thread per processor core{hw.physical ? ` (${hw.physical} here)` : ""}, leaving room for other programs: more threads are slightly faster on an idle PC but can be much slower while other programs are busy. Fewer threads: slower transcription, less load.</p>
      </section>}

      {is("permissions") && <section className="panel" id="set-permissions">
        <h2>Microphone</h2>
        <div className="row">
          <span className={"chip " + (mic === false ? "red" : mic ? "green" : "amber")}>{mic === false ? "Blocked in Windows" : mic ? "Allowed" : "Checking…"}</span>
          {mic === false && <button className="btn sm" onClick={() => invoke("open_mic_privacy").catch(toastError)}>Open Windows settings</button>}
        </div>
        <p className="small">EsyType needs the microphone to hear you. Windows asks for nothing else: typing into your apps needs no permission.</p>
      </section>}

      {is("models") && <section className="panel" id="set-storage">
        <h2>Storage</h2>
        <div className="row">
          <label className="field" style={{ flex: 1 }}>
            <span>Folder for speech models</span>
            <input type="text" value={folder} onChange={(e) => setFolder(e.target.value)} style={{ width: "100%" }} />
          </label>
          <button className="btn" style={{ alignSelf: "end" }} disabled={moving || !folder || folder === status.models_dir}
            onClick={async () => {
              setMoving(true);
              try { toast(await invoke<string>("set_models_dir", { path: folder })); await refresh(); }
              catch (e) { toastError(e); }
              setMoving(false);
            }}>{moving ? "Moving…" : "Move models here"}</button>
        </div>
        <p className="small">Now: {status.models_dir}. Downloaded models are moved and checked before the old copies are deleted; future downloads go here. {Math.round(hw.free_disk_mb / 1024)} GB free on this drive.</p>
      </section>}

      {is("privacy") && <section className="panel" id="set-privacy">
        <h2>Data and privacy</h2>
        <p className="small"><Icon name="lock" size={14} /> Dictation runs on this PC. Your voice is never recorded to disk, and nothing you say or write is sent anywhere.</p>
        <dl className="facts">
          <div><dt>Settings, History, Dictionary, Snippets, notes · {size(status.data_bytes)}</dt><dd>{status.data_dir}</dd><dd><button className="btn sm" onClick={() => invoke("open_folder", { which: "data" }).catch(toastError)}>Open folder</button></dd></div>
          <div><dt>Speech models · {size(status.models_bytes)}</dt><dd>{status.models_dir}</dd><dd><button className="btn sm" onClick={() => invoke("open_folder", { which: "models" }).catch(toastError)}>Open folder</button></dd></div>
        </dl>
        <HistoryPrivacy settings={s} save={save} />
        <DataTools status={status} refresh={refresh} />
      </section>}

      {is("about") && <section className="panel" id="set-about">
        <h2>About</h2>
        <p><span className="wordmark">EsyType.</span> <span className="muted">by EsyAI · version {status.version}</span></p>
        <p className="small">Runs on this PC. The only internet use is downloading the speech model you choose, from a fixed address, checked before use. No account.</p>
        <button className="btn" onClick={openSetup}>Run setup again</button>
        <p className="small">Walks through the first-run steps with your current choices. Nothing is deleted or reset.</p>
      </section>}
    </>
  );
}
