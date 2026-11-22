import { createRoot } from "react-dom/client";
import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { HistoryPage } from "./history";
import { DictionaryPage } from "./dictionary";
import { SnippetsPage } from "./snippets";
import { StylePage } from "./style";
import { ScratchpadPage, padOpen } from "./scratchpad";
import { SettingsPage, SettingsProblem, type Progress, type Settings, type Status } from "./settings";
import { Setup } from "./setup";
import { Banner, DialogHost, Empty, focusField, Icon, ToastHost, toastError, useDialogOpen, type IconName } from "./ui";
import "./styles.css";

type Page = "dictation" | "history" | "dictionary" | "snippets" | "style" | "scratchpad" | "settings";
const PAGES: { id: Page; name: string; icon: IconName; lead: string }[] = [
  { id: "dictation", name: "Dictation", icon: "dictation", lead: "" },
  { id: "history", name: "History", icon: "history", lead: "Your dictations, kept on this PC only, for as long as you choose." },
  { id: "dictionary", name: "Dictionary", icon: "dictionary", lead: "Names and terms spelled your way, every time they are heard." },
  { id: "snippets", name: "Snippets", icon: "snippets", lead: "Say a trigger and EsyType inserts the saved text." },
  { id: "style", name: "Style", icon: "style", lead: "How dictated text is finished in each app." },
  { id: "scratchpad", name: "Scratchpad", icon: "scratchpad", lead: "Notes that save themselves as you write or dictate." },
  { id: "settings", name: "Settings", icon: "settings", lead: "Speech model, microphone, shortcuts and how EsyType runs." },
];

function Sidebar({ page, setPage, status, engine }: { page: Page; setPage: (p: Page) => void; status: Status; engine: string }) {
  const nav = useRef<HTMLElement>(null);
  // Up and Down move between the items, as in a list.
  const arrows = (e: React.KeyboardEvent) => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    const items = Array.from(nav.current?.querySelectorAll<HTMLButtonElement>("button") ?? []);
    const at = items.indexOf(document.activeElement as HTMLButtonElement);
    if (at < 0) return;
    e.preventDefault();
    items[(at + (e.key === "ArrowDown" ? 1 : items.length - 1)) % items.length].focus();
  };
  const item = (p: (typeof PAGES)[number]) => (
    <button key={p.id} className={page === p.id ? "on" : ""} aria-current={page === p.id ? "page" : undefined} onClick={() => setPage(p.id)}>
      <Icon name={p.icon} /><span className="side-label">{p.name}</span>
    </button>
  );
  const ready = status.loaded !== null;
  const model = status.models.find((m) => m.model.id === status.loaded)?.model.name ?? status.loaded;
  return (
    <aside className="side">
      <span className="wordmark side-label">EsyType.</span>
      <nav ref={nav} className="side-nav" aria-label="Sections" onKeyDown={arrows}>
        {PAGES.filter((p) => p.id !== "settings").map(item)}
        <span className="side-gap" />
        {item(PAGES[PAGES.length - 1])}
      </nav>
      <button className="side-status" onClick={() => setPage("settings")} title="Speech engine">
        <span className={"chip " + (ready ? "green" : engine === "error" ? "red" : "amber")}>
          <span className="side-label">{ready ? `Local · ${model} · ${status.threads_effective} threads` : engine === "error" ? "Model failed to load" : "Loading model…"}</span>
        </span>
      </button>
    </aside>
  );
}

const OUTCOME_NOTE: Record<string, string> = {
  Copied: " · not typed because the window changed (copied instead)",
  Typed: " · typed (your clipboard held non-text content)",
  Failed: " · not confirmed: the app didn't take the text. It is in History.",
};

function Home({ status, save, engine, openSettings }: { status: Status; save: (p: Partial<Settings>) => Promise<boolean>; engine: string; openSettings: () => void }) {
  const s = status.settings;
  const clean = s.text_mode !== "verbatim";
  return (
    <>
      <h1 className="display">Hold <kbd>{s.ptt}</kbd>, speak, release.</h1>
      <p className="lead">Or press <kbd>{s.toggle}</kbd> to start and again to stop. <kbd>Esc</kbd> cancels. Text goes where your cursor was. English only for now.</p>
      {!status.shortcuts_ok && <Banner tone="red" action={<button className="btn sm" onClick={openSettings}>Change shortcuts</button>}>A shortcut could not be registered; another app may be using it.</Banner>}
      {engine === "error" && <Banner tone="red" action={<button className="btn sm" onClick={openSettings}>Speech model settings</button>}>The speech model could not be loaded, so dictation is not available.</Banner>}

      <section className="panel">
        <h2>Try it</h2>
        <textarea id="practice" placeholder="Click here, then hold the shortcut and speak." aria-label="Practice area" />
      </section>

      <section className="panel">
        <h2>Last dictation</h2>
        {status.last ? (
          <p className="small">Last: {status.last.audio_seconds.toFixed(1)} s of speech transcribed in {status.last.seconds.toFixed(1)} s{OUTCOME_NOTE[status.last.outcome] ?? ""}</p>
        ) : (
          <Empty icon="dictation" title="Nothing dictated yet" text="Your first dictation will appear here: how long you spoke and how quickly it was typed." />
        )}
      </section>

      <section className="panel">
        <h2>Text</h2>
        <div className="choice" role="radiogroup" aria-label="Text mode">
          <label className={"card" + (clean ? " selected" : "")}>
            <input type="radio" name="mode" checked={clean} onChange={() => save({ text_mode: "clean" })} />
            <span className="name">Clean</span>
            <span className="small">Removes fillers like "um", follows "scratch that" and "new line", formats numbers, money, dates and times, fixes capitals. Same words otherwise.</span>
          </label>
          <label className={"card" + (!clean ? " selected" : "")}>
            <input type="radio" name="mode" checked={!clean} onChange={() => save({ text_mode: "verbatim" })} />
            <span className="name">Verbatim</span>
            <span className="small">Exactly what the speech engine heard.</span>
          </label>
        </div>
        <p className="small">Also in the tray menu. Clean's options are in <a href="#" onClick={(e) => { e.preventDefault(); openSettings(); }}>Settings</a>.</p>
      </section>
    </>
  );
}

/** What screen readers hear for each dictation state (the pill also announces, for when this window is closed). */
const SPOKEN: Record<string, (m: string) => string> = {
  listening: () => "Listening", processing: () => "Transcribing", done: () => "Typed", cleaned: () => "Typed",
  copied: () => "Copied. Press Ctrl+V to paste.", error: (m) => m, unsure: (m) => `Not typed: ${m}`, undone: (m) => m,
};

/** A polite live region announcing dictation (design system section 10). */
function Announcer() {
  const [text, setText] = useState("");
  useEffect(() => {
    const u = listen<{ state: string; message: string }>("pill", (e) => { const f = SPOKEN[e.payload.state]; if (f) setText(f(e.payload.message)); });
    return () => { u.then((f) => f()); };
  }, []);
  return <div id="dictation-status" className="sr-only" role="status" aria-live="polite">{text}</div>;
}

function Loading() {
  return (
    <div className="app" aria-busy="true">
      <aside className="side"><span className="wordmark side-label">EsyType.</span></aside>
      <main className="main"><div className="page">
        <div className="skel" style={{ height: 40, width: "60%" }} />
        <div className="skel" style={{ height: 16, width: "45%", marginBottom: 24 }} />
        <div className="skel" style={{ height: 140 }} /><div className="skel" style={{ height: 96 }} />
        <span className="sr-only">Loading…</span>
      </div></main>
    </div>
  );
}

function App() {
  const [status, setStatus] = useState<Status | null>(null);
  const [progress, setProgress] = useState<Progress | null>(null);
  const [engine, setEngine] = useState("");
  const [page, setPage] = useState<Page>("dictation");
  const [setupOpen, setSetupOpen] = useState(false);
  const dialogOpen = useDialogOpen();
  const main = useRef<HTMLElement>(null);

  const refresh = useCallback(async () => {
    const s = await invoke<Status>("get_status");
    setStatus(s);
    return s;
  }, []);

  useEffect(() => {
    refresh();
    const subs = [
      listen<Progress>("download", (e) => {
        setProgress(e.payload);
        if (e.payload.error) toastError(e.payload.error);
        if (e.payload.finished || e.payload.error) refresh();
      }),
      listen<{ engine: string }>("status", (e) => { setEngine(e.payload.engine); refresh(); }),
      listen("transcript", () => refresh()),
      listen("settings", () => refresh()),
      listen<string>("open-tab", (e) => setPage(e.payload as Page)),
      listen("flush", () => { if (!padOpen) invoke("flushed"); }),
    ];
    return () => subs.forEach((p) => p.then((f) => f()));
  }, [refresh]);
  useEffect(() => { main.current?.scrollTo(0, 0); }, [page]);

  if (!status) return <Loading />;

  const save = async (patch: Partial<Settings>) => {
    try {
      await invoke("save_settings", { new: { ...status.settings, ...patch } });
      await refresh();
      return true;
    } catch (e) {
      toastError(e);
      return false;
    }
  };
  const problem = status.settings_problem && (
    <SettingsProblem p={status.settings_problem} onDismiss={() => invoke("dismiss_settings_problem").then(refresh)} />
  );
  const hosts = <><DialogHost /><ToastHost /><Announcer /></>;

  // Not set up yet (a new user), or "Run setup again" from Settings.
  if (status.settings.setup_done === false || setupOpen) {
    return (
      <>
        <div className="setup-wrap" inert={dialogOpen}>
          <Setup status={status} save={save} progress={progress} setProgress={setProgress} onDone={() => { setSetupOpen(false); setPage("dictation"); }} />
        </div>
        {hosts}
      </>
    );
  }

  const info = PAGES.find((p) => p.id === page)!;
  const db = { available: status.history_available, dbError: status.history_error };
  return (
    <>
      <div className="app" inert={dialogOpen}>
        <Sidebar page={page} setPage={setPage} status={status} engine={engine} />
        <main className="main" ref={main}>
          <div className="page">
            {problem}
            {page !== "dictation" && (
              <header className="page-head">
                <h1 className="display">{info.name}</h1>
                <p className="lead">{info.lead}</p>
              </header>
            )}
            {page === "dictation" ? <Home status={status} save={save} engine={engine} openSettings={() => setPage("settings")} />
              : page === "history" ? <HistoryPage settings={status.settings} {...db} openPrivacy={() => { setPage("settings"); setTimeout(() => document.getElementById("set-privacy")?.scrollIntoView({ block: "start" }), 100); }}
                tryIt={() => { setPage("dictation"); focusField("practice"); }} />
              : page === "dictionary" ? <DictionaryPage {...db} hint={status.settings.dictionary_hint} hintWords={status.dictionary_hint_words} setHint={async (on) => { await save({ dictionary_hint: on }); }}
                builtin={status.settings.builtin_vocabulary} setBuiltin={async (on) => { await save({ builtin_vocabulary: on }); }} />
              : page === "snippets" ? <SnippetsPage {...db} />
              : page === "style" ? <StylePage settings={status.settings} save={async (p) => { await save(p); }} cleanOn={status.settings.text_mode !== "verbatim"} />
              : page === "scratchpad" ? <ScratchpadPage {...db} />
              : <SettingsPage status={status} save={save} refresh={refresh} progress={progress} setProgress={setProgress} openSetup={() => setSetupOpen(true)} />}
          </div>
        </main>
      </div>
      {hosts}
    </>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
