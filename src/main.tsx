import { createRoot } from "react-dom/client";
import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { HistoryPage } from "./history";
import { DictionaryPage } from "./dictionary";
import { SnippetsPage } from "./snippets";
import { StylePage } from "./style";
import { ScratchpadPage, padOpen } from "./scratchpad";
import { SECTIONS, SettingsPanel, SettingsProblem, type Progress, type Section, type Settings, type Status } from "./settings";
import { Setup } from "./setup";
import { PageTop, type HeroSpec } from "./hero";
import { Home, TextMode } from "./home";
import { InsightsPage } from "./insights";
import { loadMemory, remember, remembered, Banner, DialogHost, Empty, focusField, Icon, ToastHost, toastError, useDialogOpen, type IconName } from "./ui";
import "./styles.css";

type Page = "dictation" | "meet" | "insights" | "history" | "dictionary" | "snippets" | "style" | "scratchpad";
const PAGES: { id: Page; name: string; icon: IconName; lead: string; words?: true; soon?: true }[] = [
  { id: "dictation", name: "Dictation", icon: "dictation", lead: "" },
  { id: "meet", name: "EsyMeet", icon: "meet", lead: "Live transcription of your meetings, on this PC.", soon: true },
  { id: "insights", name: "Insights", icon: "insights", lead: "Your own numbers, worked out on this PC. They stay even when History is off or trimmed." },
  { id: "history", name: "History", icon: "history", lead: "Your dictations, kept on this PC only, for as long as you choose.", words: true },
  { id: "dictionary", name: "Dictionary", icon: "dictionary", lead: "Names and terms spelled your way, every time they are heard.", words: true },
  { id: "snippets", name: "Snippets", icon: "snippets", lead: "Say a trigger and EsyType inserts the saved text.", words: true },
  { id: "style", name: "Style", icon: "style", lead: "How dictated text is finished in each app.", words: true },
  { id: "scratchpad", name: "Scratchpad", icon: "scratchpad", lead: "Notes that save themselves as you write or dictate.", words: true },
];
/** Clicks or focuses something on the page, once the page is showing. */
const reach = (sel: string) => setTimeout(() => { const el = document.querySelector<HTMLElement>(sel); if (!el) return; if (el.tagName === "BUTTON") el.click(); else { el.focus(); el.scrollIntoView({ block: "center" }); } }, 50);
const heroBtn = (label: string, run: () => void) => <button className="hero-btn" onClick={run}>{label}</button>;
/** Hero banners (Mac design system: PageHero), one sentence with one italic word. */
const HEROES: Partial<Record<Page, HeroSpec>> = {
  history: { headline: ["Everything you’ve ", "said", ", kept on this PC."], glow: "var(--et-glow-history)",
    message: "Your dictations, stored only on this PC for as long as you choose. Audio is never saved." },
  dictionary: { headline: ["EsyType spells the way ", "you", " do."], glow: "var(--et-glow-dictionary)",
    message: "Add names, company jargon and uncommon words once, and they’re spelled right every time you dictate.",
    actions: heroBtn("Add new word", () => reach("#dict-term")) },
  snippets: { headline: ["Say a few words, ", "type", " the rest."], glow: "var(--et-mark-blue)",
    message: "Your signature, address, meeting link or standard reply, typed in full when you say its trigger.",
    actions: heroBtn("New snippet", () => reach('input[aria-label="Trigger"]')) },
  style: { headline: ["Write like ", "you", ", in every app."], glow: "var(--et-mark-amber)",
    message: "EsyType finishes your words in the style you set for each app: written-out forms for email, chat-style for messages. It never changes your tone or rewrites sentences." },
  scratchpad: { headline: ["Think out ", "loud", "."], glow: "var(--et-glow-scratchpad)",
    message: "Notes that save themselves as you write or dictate. Click in a note, hold your shortcut and speak: the text goes in at the cursor.",
    actions: heroBtn("New note", () => reach(".pad-list > .btn.primary")) },
};

const isPage = (p: string | null): p is Page => PAGES.some((x) => x.id === p);

function Sidebar({ page, setPage, status, engine, openSettings }: { page: Page; setPage: (p: Page) => void; status: Status; engine: string; openSettings: (s?: Section) => void }) {
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
      <Icon name={p.icon} size={16} /><span className="side-label">{p.name}</span>{p.soon && <span className="soon side-label" aria-label=", coming soon">Soon</span>}
    </button>
  );
  const ready = status.loaded !== null;
  const model = status.models.find((m) => m.model.id === status.loaded)?.model.name ?? status.loaded;
  return (
    <aside className="side">
      <span className="wordmark side-label">EsyType.</span>
      <nav ref={nav} className="side-nav" aria-label="Sections" onKeyDown={arrows}>
        {PAGES.filter((p) => !p.words).map(item)}
        <span className="side-eyebrow side-label">Your words</span>
        {PAGES.filter((p) => p.words).map(item)}
        <span className="side-gap" />
        <button onClick={() => openSettings()}><Icon name="settings" size={16} /><span className="side-label">Settings</span></button>
      </nav>
      <button className="side-status" onClick={() => openSettings("models")} title="Speech engine">
        <span className={"chip " + (ready ? "green" : engine === "error" ? "red" : "amber")}>
          <span className="side-label">{ready ? `Local · ${model} · ${status.threads_effective} threads` : engine === "error" ? "Model failed to load" : "Loading model…"}</span>
        </span>
      </button>
    </aside>
  );
}

/** EsyMeet is not built yet (plan Phases 8-10). */
function Meet() {
  return (
    <section className="panel">
      <Empty icon="meet" title="EsyMeet is coming" text="Live transcription of your meetings, worked out on this PC like your dictation. It isn’t built yet." />
    </section>
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
  const [page, setPageNow] = useState<Page>(() => { const p = remembered("et-page"); return isPage(p) ? p : "dictation"; });
  const setPage = useCallback((p: Page) => { setPageNow(p); remember("et-page", p); }, []);
  const [settingsAt, setSettingsAt] = useState<Section | null>(null);
  const openSettings = useCallback((at?: Section) => {
    const last = remembered("et-settings");
    setSettingsAt(at ?? (SECTIONS.some(([id]) => id === last) ? last as Section : "general"));
  }, []);
  const closeSettings = useCallback(() => setSettingsAt(null), []);
  const setSection = (s: Section) => { setSettingsAt(s); remember("et-settings", s); };
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
      listen<string>("open-tab", (e) => { if (e.payload === "settings") openSettings(); else if (isPage(e.payload)) setPage(e.payload); }),
      listen("flush", () => { if (!padOpen) invoke("flushed"); }),
    ];
    return () => subs.forEach((p) => p.then((f) => f()));
  }, [refresh, openSettings, setPage]);
  // Ctrl+, opens Settings, as in other Windows apps.
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if (e.ctrlKey && e.key === "," && !e.altKey && !e.shiftKey) { e.preventDefault(); openSettings(); } };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [openSettings]);
  useEffect(() => { main.current?.scrollTo(0, 0); }, [page]);
  // Frosted glass follows Windows' Transparency effects switch; checked again whenever the window comes back to the front.
  useEffect(() => {
    const glass = () => invoke<boolean>("transparency_effects").then((on) => { document.documentElement.dataset.glass = on ? "on" : "off"; }).catch(() => {});
    glass();
    window.addEventListener("focus", glass);
    return () => window.removeEventListener("focus", glass);
  }, []);

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
      <div className="app" inert={dialogOpen || settingsAt !== null}>
        <Sidebar page={page} setPage={setPage} status={status} engine={engine} openSettings={openSettings} />
        <main className="main" ref={main}>
          <div className="page">
            {problem}
            {page !== "dictation" && (HEROES[page] ? <PageTop id={page} title={info.name} hero={HEROES[page]!} /> : (
              <header className="page-head">
                <h1 className="display">{info.name}</h1>
                <p className="lead">{info.lead}</p>
              </header>
            ))}
            {page === "dictation" ? <Home status={status} engine={engine} openSettings={(at) => openSettings(at)} go={setPage} />
              : page === "meet" ? <Meet />
              : page === "insights" ? <InsightsPage settings={status.settings} save={save} />
              : page === "history" ? <HistoryPage settings={status.settings} {...db} openPrivacy={() => openSettings("privacy")}
                tryIt={() => { setPage("scratchpad"); focusField("note-text"); }} />
              : page === "dictionary" ? <DictionaryPage {...db} hint={status.settings.dictionary_hint} hintWords={status.dictionary_hint_words} setHint={async (on) => { await save({ dictionary_hint: on }); }}
                builtin={status.settings.builtin_vocabulary} setBuiltin={async (on) => { await save({ builtin_vocabulary: on }); }} />
              : page === "snippets" ? <SnippetsPage {...db} />
              : page === "style" ? <><TextMode settings={status.settings} save={save} /><StylePage settings={status.settings} save={async (p) => { await save(p); }} cleanOn={status.settings.text_mode !== "verbatim"} /></>
              : <ScratchpadPage {...db} />}
          </div>
        </main>
      </div>
      {settingsAt && (
        <div inert={dialogOpen}>
          <SettingsPanel section={settingsAt} setSection={setSection} close={closeSettings} status={status} save={save} refresh={refresh}
            progress={progress} setProgress={setProgress} openSetup={() => { setSettingsAt(null); setSetupOpen(true); }} />
        </div>
      )}
      {hosts}
    </>
  );
}

loadMemory().finally(() => createRoot(document.getElementById("root")!).render(<App />));
