// First-run setup (Phase 5, Milestone 2; docs/plans/first-run-plan.md): one step per screen, reusing the model
// cards, download, microphone and shortcut code from Settings.
import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { confirmModel, CTRL_SPACE_NOTE, initialModel, KeyCapture, mb, ModelCards, type Progress, type Save, type Status } from "./settings";
import { Banner, Icon, toastError } from "./ui";
import { Wave } from "./hero";

const STEPS = ["Welcome", "Privacy", "Your name", "Light or dark", "Speech model", "Download", "Microphone", "Shortcut", "Try it", "Ready"];

const seconds = (s: number) => (s < 90 ? `${Math.max(1, Math.round(s))} s` : `${Math.round(s / 60)} min`);

export function Setup({ status, save, progress, setProgress, onDone }: {
  status: Status; save: Save; progress: Progress | null; setProgress: (p: Progress | null) => void; onDone: () => void;
}) {
  const [step, setStep] = useState(0);
  const [model, setModel] = useState(() => initialModel(status));
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus(); }, [step]);

  const s = status.settings;
  const entry = status.models.find((x) => x.model.id === model)!;
  const next = () => setStep((n) => Math.min(n + 1, STEPS.length - 1));
  const back = () => setStep((n) => Math.max(n - 1, 0));
  const chooseModel = async () => { if (await confirmModel(status, model)) next(); };
  const finish = async () => {
    if (!await save({ setup_done: true })) return;
    await invoke("hide_window");
    onDone();
  };

  const body = [
    <Welcome key="w" />,
    <Privacy key="p" on={s.history_enabled} days={s.history_retention_days} set={(v) => save({ history_enabled: v })} />,
    <Name key="n" value={s.user_name} save={save} />,
    <Theme key="th" value={s.theme} save={save} />,
    <ModelStep key="m" status={status} model={model} setModel={setModel} />,
    <Download key="d" status={status} model={model} progress={progress} setProgress={setProgress} save={save} />,
    <Microphone key="mic" status={status} save={save} />,
    <Shortcut key="k" status={status} save={save} />,
    <TryIt key="t" status={status} model={model} />,
    <Ready key="r" status={status} save={save} />,
  ][step];
  const at = (name: string) => step === STEPS.indexOf(name);
  const primary = at("Welcome") ? <button className="btn primary" onClick={next}>Get started</button>
    : at("Speech model") ? <button className="btn primary" onClick={chooseModel}>{entry.installed ? `Use ${entry.model.name}` : `Download ${entry.model.name}`}</button>
    : at("Your name") || at("Try it") ? <><button className="btn" onClick={next}>Skip</button><button className="btn primary" onClick={next}>Continue</button></>
    : at("Ready") ? <button className="btn primary" onClick={finish}>Finish</button>
    : <button className="btn primary" onClick={next}>Continue</button>;

  return (
    <main className="setup">
      <div className="setup-top">
        <span className="wordmark">EsyType.</span>
        <span className="small" aria-live="polite">Step {step + 1} of {STEPS.length}: {STEPS[step]}</span>
      </div>
      <div className="steps" aria-hidden="true">{STEPS.map((n, i) => <span key={n} className={i <= step ? "on" : ""} />)}</div>
      {at("Welcome") && <div className="setup-wave"><Wave fade hint={30} /></div>}
      <section className="setup-body" aria-labelledby="setup-title">
        <h1 className="display" id="setup-title" tabIndex={-1} ref={heading}>{TITLES[step]}</h1>
        {body}
      </section>
      <div className="setup-nav">
        {step > 0 ? <button className="btn" onClick={back}>Back</button> : <span />}
        <span className="row">{primary}</span>
      </div>
    </main>
  );
}

const TITLES = ["Speak. It types.", "Private by design", "What should EsyType call you?", "Light or dark?", "Choose a speech model", "Getting the model", "First, your microphone", "Your shortcut", "Try it", "You're ready"];

function Name({ value, save }: { value: string; save: Save }) {
  return (
    <>
      <p className="lead">EsyType greets you by your first name. It stays in EsyType's settings on this PC.</p>
      <label className="field" style={{ maxWidth: 360 }}>
        <span>Your name</span>
        <input type="text" placeholder="Optional" maxLength={60} defaultValue={value} key={value} autoFocus
          onBlur={(e) => { const v = e.target.value.trim(); if (v !== value) save({ user_name: v }); }}
          onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
      </label>
    </>
  );
}

function Theme({ value, save }: { value: string; save: Save }) {
  return (
    <>
      <p className="lead">Follow Windows switches with your Windows light or dark mode. You can change it any time in Settings ▸ General.</p>
      <div className="seg" role="radiogroup" aria-label="Theme">
        {([["system", "Follow Windows"], ["dark", "Dark"], ["light", "Light"]] as const).map(([v, name]) => (
          <button key={v} role="radio" aria-checked={value === v} className={value === v ? "on" : ""} onClick={() => save({ theme: v })}>{name}</button>
        ))}
      </div>
    </>
  );
}

function Welcome() {
  return (
    <>
      <span className="eyebrow"><Icon name="lock" size={14} /> Private · On this PC · No account</span>
      <p className="lead" style={{ marginTop: 16 }}>EsyType turns your voice into text in any app: hold a shortcut, speak, let go, and the words appear where your cursor is. Everything runs on this computer.</p>
      <p className="small">Setup takes about two minutes: a speech model, your microphone and your shortcut.</p>
    </>
  );
}

const kept = (days: number) => (days ? `kept ${days} days` : "kept until you delete it");

function Privacy({ on, days, set }: { on: boolean; days: number; set: (v: boolean) => void }) {
  return (
    <>
      <ul className="ticks">
        <li><Icon name="check" size={16} /> <span><b>Stays on this PC:</b> your voice, the text, History, Dictionary, Snippets and notes. Your voice is never saved to disk.</span></li>
        <li><Icon name="check" size={16} /> <span><b>The only internet use:</b> downloading the speech model you choose, from one fixed address. Each file is checked against its SHA-256 fingerprint before it is used.</span></li>
        <li><Icon name="check" size={16} /> <span><b>No account, no analytics,</b> nothing you say or write is sent anywhere.</span></li>
      </ul>
      <section className="panel">
        <label className="row">
          <input type="checkbox" checked={on} onChange={(e) => set(e.target.checked)} />
          <span>Keep a History of dictations on this PC</span>
        </label>
        <p className="small">{kept(days)[0].toUpperCase() + kept(days).slice(1)}, with the program's name (never window titles), so you can find and copy past dictations. Change this any time in History.</p>
      </section>
    </>
  );
}

function ModelStep({ status, model, setModel }: { status: Status; model: string; setModel: (id: string) => void }) {
  const hw = status.hardware;
  const rec = status.models.find((x) => x.model.id === status.recommended)?.model.name;
  const ok = <span className="chip green">OK</span>;
  return (
    <>
      <p className="lead">{rec ? `${rec} is recommended for this PC.` : "None of the models fits this PC's free memory or storage right now; closing other programs or freeing space may help."} You can change the model later in Settings.</p>
      <dl className="pc">
        <div><dt>Processor</dt><dd>{hw.cpu || "Unknown"}{hw.physical ? ` · ${hw.physical} cores` : ""} · {hw.logical} threads</dd></div>
        <div><dt>Memory</dt><dd>{Math.round(hw.total_ram_mb / 1024)} GB, {hw.available_ram_mb} MB free</dd></div>
        <div><dt>Free storage</dt><dd>{Math.round(hw.free_disk_mb / 1024)} GB where models are kept {hw.free_disk_mb > 500 ? ok : <span className="chip amber">Low</span>}</dd></div>
        <div><dt>AVX2</dt><dd>{hw.avx2 ? <>Yes {ok}</> : <>No <span className="chip amber">Speech may be slow; untested</span></>}</dd></div>
      </dl>
      <ModelCards status={status} selected={model} onSelect={setModel} />
    </>
  );
}

function Download({ status, model, progress, setProgress, save }: {
  status: Status; model: string; progress: Progress | null; setProgress: (p: Progress | null) => void; save: Save;
}) {
  const entry = status.models.find((x) => x.model.id === model)!;
  const m = entry.model;
  const mine = progress?.id === model ? progress : null;
  const active = status.downloading === model || (!!mine && !mine.finished && !mine.error);
  const first = useRef<{ t: number; done: number } | null>(null);
  const begun = useRef(false);

  const start = async () => {
    first.current = null;
    setProgress({ id: model, done: 0, total: m.bytes });
    try { await invoke("download_model", { id: model }); } catch (e) { setProgress({ id: model, error: String(e) }); }
  };
  useEffect(() => {
    if (begun.current) return;
    begun.current = true;
    if (entry.installed) { if (status.settings.model !== model) save({ model }); }
    else if (!active) start();
  }, []);
  if (mine?.done && !first.current) first.current = { t: Date.now(), done: mine.done };

  const done = mine?.done ?? 0;
  const total = mine?.total ?? m.bytes;
  const pct = Math.round((done / Math.max(total, 1)) * 100);
  const f = first.current;
  const rate = f && Date.now() - f.t > 1500 ? (done - f.done) / ((Date.now() - f.t) / 1000) : 0;
  const ready = status.loaded === model;

  if (entry.installed) {
    return (
      <div className="panel" role="status">
        <p className="row"><Icon name="check" /> <b>Verified.</b> {m.name} is on this PC and checked (SHA-256).</p>
        <p className="small">{ready ? `${m.name} is loaded and ready.` : "Loading the model…"}</p>
      </div>
    );
  }
  if (mine?.error) {
    const offline = /reach the download server/.test(mine.error);
    return (
      <Banner tone="red" action={<button className="btn sm" onClick={start}>Retry</button>}>
        {mine.error === "Download cancelled." ? "The download was cancelled. Retry carries on from where it stopped." : mine.error}
        {offline && " Check that this PC is connected to the internet, then retry."}
      </Banner>
    );
  }
  const checking = active && done >= total;
  return (
    <div className="panel">
      <p><b>{m.name}</b> · {mb(m.bytes)}</p>
      <div className="progress" aria-label="Download progress"><div style={{ width: `${pct}%` }} /></div>
      <p className="small" role="status">
        {checking ? "Checking the file (SHA-256)…"
          : `${pct}% · ${mb(done)} of ${mb(total)}` + (rate > 0 ? ` · ${(rate / 1_000_000).toFixed(1)} MB/s · about ${seconds((total - done) / rate)} left` : "")}
      </p>
      {!checking && <button className="btn sm" onClick={() => invoke("cancel_download")}>Cancel download</button>}
      <p className="small">You can continue while it downloads: the next two steps do not need it.</p>
    </div>
  );
}

const VERDICT: Record<string, [string, string]> = {
  heard: ["green", "We heard you."],
  quiet: ["amber", "Very quiet. Move closer, or raise the input level in Windows' sound settings."],
  none: ["red", "Nothing heard. Check the microphone is connected and not muted, or choose another."],
};

/** Records 3 seconds from the microphone (nothing kept) and says whether it heard you. Setup and Settings. */
export function MicTest({ mic }: { mic: string | null }) {
  const [testing, setTesting] = useState(false);
  const [level, setLevel] = useState(0);
  const [result, setResult] = useState<{ verdict: string; fell_back: boolean } | null>(null);
  useEffect(() => {
    const sub = listen<number>("mic-level", (e) => setLevel(e.payload));
    return () => { sub.then((f) => f()); };
  }, []);
  const test = async () => {
    setTesting(true);
    setResult(null);
    try { setResult(await invoke("mic_test", { mic })); } catch (e) { toastError(e); }
    setTesting(false);
    setLevel(0);
  };
  const v = result && VERDICT[result.verdict];
  return (
    <div className="mic-test">
      <button className="btn" disabled={testing} onClick={test}>{testing ? "Listening for 3 seconds…" : "Test microphone"}</button>
      <div className="meter" role="meter" aria-label="Microphone level" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(level * 100)}>
        <div style={{ width: `${Math.round(level * 100)}%` }} />
      </div>
      {v && <p className="row" role="status"><span className={"chip " + v[0]}>{v[1]}</span></p>}
      {result?.fell_back && <p className="small">The chosen microphone was not found, so the test used the Windows default.</p>}
    </div>
  );
}

function Microphone({ status, save }: { status: Status; save: Save }) {
  const s = status.settings;
  return (
    <>
      <p className="lead">Choose the microphone EsyType listens to, then say a few words to test it.</p>
      <div className="row">
        <label className="field" style={{ minWidth: 280 }}>
          <span>Microphone</span>
          <select value={s.mic ?? ""} onChange={(e) => save({ mic: e.target.value || null })}>
            <option value="">Windows default</option>
            {status.mics.map((m) => <option key={m} value={m}>{m}</option>)}
          </select>
        </label>
      </div>
      <MicTest key={s.mic ?? ""} mic={s.mic} />
      <p className="small">The test records for 3 seconds and keeps nothing. Windows shows its microphone icon while it listens.</p>
    </>
  );
}

function Shortcut({ status, save }: { status: Status; save: Save }) {
  const s = status.settings;
  return (
    <>
      <p className="lead">Hold the shortcut, speak, and let go. Or press the start/stop shortcut once to start and again to stop.</p>
      {!status.shortcuts_ok && <Banner tone="red">A shortcut could not be registered; another app may be using it. Choose a different one.</Banner>}
      <div className="keys panel">
        <KeyCapture label="Hold to talk" value={s.ptt} save={(v) => save({ ptt: v })} />
        <KeyCapture label="Start / stop" value={s.toggle} save={(v) => save({ toggle: v })} />
      </div>
      <p className="small">{CTRL_SPACE_NOTE} <kbd>Esc</kbd> cancels a dictation. Undo and Paste last shortcuts are in Settings.</p>
    </>
  );
}

function TryIt({ status, model }: { status: Status; model: string }) {
  const ready = status.loaded !== null;
  const name = status.models.find((x) => x.model.id === model)?.model.name;
  const [seen] = useState(() => JSON.stringify(status.last)); // status is fetched anew on every change: compare by value
  const fresh = status.last && JSON.stringify(status.last) !== seen ? status.last : null;
  return (
    <>
      <p className="lead">Click in the box, hold <kbd>{status.settings.ptt}</kbd>, say a sentence, and let go.</p>
      {!ready && <p className="small" role="status">{status.downloading ? `Finishing the ${name} download…` : "Loading the speech model…"}</p>}
      <textarea placeholder="Click here, then hold the shortcut and speak." aria-label="Practice area" />
      {fresh && <p className="small" role="status">{fresh.audio_seconds.toFixed(1)} s of speech, typed in {fresh.seconds.toFixed(1)} s.</p>}
    </>
  );
}

function Ready({ status, save }: { status: Status; save: Save }) {
  const s = status.settings;
  const model = status.models.find((x) => x.model.id === s.model);
  return (
    <>
      <dl className="pc">
        <div><dt>Speech model</dt><dd>{model?.model.name}{model?.installed ? "" : " (still downloading)"}</dd></div>
        <div><dt>Microphone</dt><dd>{s.mic ?? "Windows default"}</dd></div>
        <div><dt>Hold to talk</dt><dd><kbd>{s.ptt}</kbd></dd></div>
        <div><dt>Start / stop</dt><dd><kbd>{s.toggle}</kbd></dd></div>
        <div><dt>History</dt><dd>{s.history_enabled ? `On, ${kept(s.history_retention_days)}` : "Off"}</dd></div>
      </dl>
      <label className="row">
        <input type="checkbox" checked={s.start_with_windows} onChange={(e) => save({ start_with_windows: e.target.checked })} />
        <span>Start EsyType when Windows starts (it waits in the system tray)</span>
      </label>
      <p className="small">Finish closes this window. EsyType keeps running in the system tray: click its icon to open it again. Everything here can be changed in Settings.</p>
    </>
  );
}
