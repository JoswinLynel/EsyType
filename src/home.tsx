// The Dictation page (Mac design system: Dictation (home)): greeting, microphone permission, the hero with your
// numbers, and recent dictations by day. Also the Clean or Verbatim choice, which now sits on the Style page.
import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { Settings, Status } from "./settings";
import type { Entry } from "./history";
import { PageTop } from "./hero";
import { Banner, Icon, Switch } from "./ui";

type Usage = { words: number; audio_ms: number; dictations: number; since: string | null; streak: number; dictionary: number; snippets: number };
type Go = "insights" | "history" | "dictionary" | "style";

/** 12,400 -> "12.4K"; 950 -> "950". */
export const short = (n: number) => n < 1000 ? String(n) : n < 1_000_000 ? `${+(n / 1000).toFixed(1)}K` : `${+(n / 1_000_000).toFixed(1)}M`;
/** Speaking speed, from words and seconds of speech; null until there is speech to measure. */
export const wpm = (words: number, audio_ms: number) => audio_ms >= 1000 ? Math.round(words / (audio_ms / 60000)) : null;

const dayKey = (ms: number) => new Date(ms).toDateString();
function dayLabel(ms: number) {
  const d = new Date(ms), today = new Date();
  const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
  if (d.toDateString() === today.toDateString()) return "Today";
  if (d.toDateString() === yesterday.toDateString()) return "Yesterday";
  return d.toLocaleDateString(undefined, { day: "numeric", month: "long", year: "numeric" });
}

export function Home({ status, engine, openSettings, go }: { status: Status; engine: string; openSettings: (at?: "privacy" | "shortcuts" | "models" | "permissions") => void; go: (p: Go) => void }) {
  const s = status.settings;
  const first = s.user_name.trim().split(/\s+/)[0];
  const [usage, setUsage] = useState<Usage | null>(null);
  const [recent, setRecent] = useState<Entry[] | null>(null);
  const [mic, setMic] = useState<boolean | null>(null);

  const load = useCallback(() => {
    invoke<Usage>("usage_summary").then(setUsage).catch(() => setUsage(null));
    if (s.history_enabled) invoke<{ items: Entry[] }>("history_list", { query: "", offset: 0 }).then((r) => setRecent(r.items.slice(0, 40))).catch(() => setRecent([]));
    else setRecent([]);
  }, [s.history_enabled]);
  useEffect(() => {
    load();
    const subs = ["transcript", "history", "usage"].map((ev) => listen(ev, load));
    return () => subs.forEach((p) => p.then((f) => f()));
  }, [load]);
  // The microphone permission: checked on open and when the window comes back to the front; every 2 s while blocked.
  useEffect(() => {
    const check = () => invoke<boolean>("microphone_allowed").then(setMic).catch(() => setMic(null));
    check();
    window.addEventListener("focus", check);
    const t = window.setInterval(() => { if (mic === false) check(); }, 2000);
    return () => { window.removeEventListener("focus", check); window.clearInterval(t); };
  }, [mic]);

  const speed = usage ? wpm(usage.words, usage.audio_ms) : null;
  const groups: { key: string; label: string; items: Entry[] }[] = [];
  for (const e of recent ?? []) {
    const k = dayKey(e.created_at);
    if (groups.at(-1)?.key !== k) groups.push({ key: k, label: dayLabel(e.created_at), items: [] });
    groups.at(-1)!.items.push(e);
  }

  return (
    <div className="home">
      <h1 className="welcome">{first ? `Welcome back, ${first}` : "Welcome back"}</h1>
      {!status.shortcuts_ok && <Banner tone="red" action={<button className="btn sm" onClick={() => openSettings("shortcuts")}>Change shortcuts</button>}>A shortcut could not be registered; another app may be using it.</Banner>}
      {engine === "error" && <Banner tone="red" action={<button className="btn sm" onClick={() => openSettings("models")}>Speech model settings</button>}>The speech model could not be loaded, so dictation is not available.</Banner>}
      {mic === false && (
        <section className="panel permission">
          <h2>EsyType needs your permission</h2>
          <p className="small">Windows decides which apps may use the microphone. Allow desktop apps, and EsyType notices by itself.</p>
          <div className="perm-row">
            <span className="perm-dot" aria-hidden="true" />
            <div><p className="perm-title">Microphone</p><p className="small">Needed to hear you</p></div>
            <button className="btn sm" onClick={() => invoke("open_mic_privacy")}>Allow…</button>
          </div>
        </section>
      )}

      <div className="home-top">
        <PageTop id="dictation" foldable={false} hero={{ headline: ["Your voice, typed ", "anywhere", "."], glow: "var(--et-mark-amber)",
          message: <>Hold <kbd>{s.ptt}</kbd> in any app and speak. Or press <kbd>{s.toggle}</kbd> to start and stop. <kbd>Esc</kbd> cancels. It all stays on this PC.</>,
          actions: <button className="hero-btn" onClick={() => go("style")}>Set your style</button> }} />
        <section className="numbers" aria-label="Your numbers">
          <button className="numbers-stats" onClick={() => go("insights")} title="Open Insights">
            <span className="stat"><b>{usage ? short(usage.words) : "—"}</b> total words</span>
            <span className="stat"><b>{speed ?? "—"}</b> wpm</span>
            <span className="stat"><b>{usage ? usage.streak : "—"}</b> day streak</span>
          </button>
          <button className="numbers-words" onClick={() => go("dictionary")} title="Open Dictionary">
            <span className="numbers-title">Your words</span>
            <span className="small">{usage ? `${usage.dictionary} in your dictionary · ${usage.snippets} ${usage.snippets === 1 ? "snippet" : "snippets"}` : "Dictionary and snippets"}</span>
          </button>
        </section>
      </div>

      <section className="recent" aria-label="Recent dictations">
        {recent === null ? null : groups.length === 0 ? (
          <>
            <div className="day-head"><span className="day-eyebrow">Today</span></div>
            <p className="small recent-empty">{s.history_enabled
              ? <>Your dictations appear here. Hold <kbd>{s.ptt}</kbd> in any app and speak.</>
              : <>History is off, so dictations aren’t listed here. Your totals still count. <a href="#" onClick={(e) => { e.preventDefault(); openSettings("privacy"); }}>History settings</a></>}</p>
          </>
        ) : groups.map((g, i) => (
          <div key={g.key} className="day">
            <div className="day-head">
              <span className="day-eyebrow">{g.label}</span>
              {i === 0 && <button className="icon-btn" aria-label="Search your dictations in History" title="Search in History" onClick={() => go("history")}><Icon name="search" size={15} /></button>}
            </div>
            <ul className="day-card">
              {g.items.map((e) => (
                <li key={e.id}>
                  <span className="day-time">{new Date(e.created_at).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })}</span>
                  <p className="day-text">{e.edited_text ?? e.final_text}</p>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </section>
    </div>
  );
}

/** Clean or Verbatim (also in the tray menu). */
export function TextMode({ settings, save }: { settings: Settings; save: (p: Partial<Settings>) => Promise<boolean> }) {
  const clean = settings.text_mode !== "verbatim";
  return (
    <section className="panel">
      <h2>Clean or Verbatim</h2>
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
      <p className="small">Also in the tray menu. Styles below apply in Clean mode.</p>
    </section>
  );
}

/** Clean, before any style (Mac design: Style). EsyType's Clean always removes fillers, follows "scratch that" and "new
 * line", fixes spacing and capitals, and formats numbers; these are its two choices. */
export function CleanCard({ settings, save }: { settings: Settings; save: (p: Partial<Settings>) => Promise<boolean> }) {
  return (
    <section className="panel">
      <h2>Clean, before any style</h2>
      <p className="small">Clean runs first in every app: it removes fillers (“um, uh, erm”), follows “scratch that” and “new line”, fixes spacing, punctuation and capitals, and writes numbers, money, dates and times as you would type them. Links, emails and code are never changed.</p>
      <div className="switch-row">
        <span><span className="switch-title">Also remove “you know”, “I mean”, “like”, “sort of” and “kind of”</span><span className="small">only when set off by commas</span></span>
        <Switch on={settings.clean_fillers_extended} set={(on) => save({ clean_fillers_extended: on })} label="Also remove you know, I mean, like, sort of and kind of" />
      </div>
      <div className="switch-row">
        <span><span className="switch-title">Write zero to nine as words</span><span className="small">“3 apples” → “three apples”; larger numbers, money and times stay as digits</span></span>
        <Switch on={settings.clean_small_numbers_as_words} set={(on) => save({ clean_small_numbers_as_words: on })} label="Write zero to nine as words" />
      </div>
      <p className="small">The original is kept in History (unless you turned that off). Rules only: nothing leaves this PC.</p>
    </section>
  );
}
