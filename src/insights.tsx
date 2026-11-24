// Insights (Mac design system: Insights): your own numbers, worked out on this PC from the daily usage totals, which
// stay even when History is off or trimmed. Charts are drawn here; nothing is downloaded.
import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { Settings } from "./settings";
import { wpm } from "./home";
import { SkeletonRows } from "./ui";

type Day = { day: string; dictations: number; words: number; audio_ms: number; processing_ms: number };
type Usage = { words: number; audio_ms: number; processing_ms: number; dictations: number; since: string | null; streak: number };
type Data = { days: Day[]; apps_week: { kind: string; words: number }[]; today: string; week_start: string; usage: Usage };

const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
const parse = (d: string) => { const [y, m, dd] = d.split("-").map(Number); return new Date(y, m - 1, dd); };
const key = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const add = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const num = (n: number) => Math.round(n).toLocaleString();
const dayMonth = (d: Date) => d.toLocaleDateString(undefined, { day: "numeric", month: "short" });
const weekday = (d: Date) => d.toLocaleDateString(undefined, { weekday: "short" });

/** Minutes as "3 h 20 min" or "12 min". */
export const duration = (ms: number) => { const m = Math.round(Math.max(0, ms) / 60000); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`; };
/** Typing the words at your typing speed, minus speaking and processing time; never below zero. */
export const timeSaved = (words: number, typingWpm: number, audioMs: number, processingMs: number) => {
  const typing = (words / Math.max(1, typingWpm)) * 60000;
  return { typing, saved: Math.max(0, typing - audioMs - processingMs) };
};

/** Counts up from 0 over about 1.1 s when shown (not with reduced motion). */
function useCountUp(target: number) {
  const [v, setV] = useState(reduced() ? target : 0);
  useEffect(() => {
    if (reduced()) { setV(target); return; }
    let raf = 0; const t0 = performance.now();
    const step = (t: number) => { const p = Math.min(1, (t - t0) / 1100); setV(target * (1 - Math.pow(1 - p, 3))); if (p < 1) raf = requestAnimationFrame(step); };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [target]);
  return v;
}

function Tile({ value, label, note, children }: { value: string; label: string; note: string; children?: React.ReactNode }) {
  return (
    <div className="tile">
      <span className="tile-number">{value}</span>
      <span className="tile-label">{label}</span>
      <span className="tile-note">{note}{children}</span>
    </div>
  );
}

export function InsightsPage({ settings, save }: { settings: Settings; save: (p: Partial<Settings>) => Promise<boolean> }) {
  const [data, setData] = useState<Data | null | undefined>(undefined);   // undefined: loading
  const [range, setRange] = useState<7 | 30 | 90>(30);
  const [how, setHow] = useState(false);
  useEffect(() => {
    const load = () => invoke<Data>("insights_data").then(setData).catch(() => setData(null));
    load();
    const subs = ["transcript", "history", "usage"].map((ev) => listen(ev, load));
    return () => subs.forEach((p) => p.then((f) => f()));
  }, []);
  const typing = Math.min(150, Math.max(10, settings.typing_wpm || 40));
  const u = data?.usage;
  const speed = u ? wpm(u.words, u.audio_ms) : null;
  const saved = u ? timeSaved(u.words, typing, u.audio_ms, u.processing_ms) : null;
  const words = useCountUp(u?.words ?? 0);
  const rate = useCountUp(speed ?? 0);
  const savedMs = useCountUp(saved?.saved ?? 0);

  if (data === undefined) return <SkeletonRows />;
  if (data === null) return <section className="panel"><p className="small">Your numbers could not be read.</p></section>;
  const today = parse(data.today);
  const byDay = new Map(data.days.map((d) => [d.day, d]));
  const wordsOn = (d: Date) => byDay.get(key(d))?.words ?? 0;

  // words per day
  const span = Array.from({ length: range }, (_, i) => add(today, i - range + 1));
  const spanWords = span.map(wordsOn);
  const spanTotal = spanWords.reduce((a, b) => a + b, 0);
  const avg = spanTotal / range;
  const top = Math.max(1, ...spanWords);
  const every = range === 7 ? 1 : range === 30 ? 5 : 15;

  // activity: 18 weeks, Monday first, the current week last
  const weekStart = parse(data.week_start);
  const first = add(weekStart, -17 * 7);
  const cells = Array.from({ length: 18 * 7 }, (_, i) => add(first, Math.floor(i / 7) * 7 + (i % 7)));
  const past = cells.filter((d) => d <= today);
  const heatTop = Math.max(0, ...past.map(wordsOn));
  const active = past.filter((d) => wordsOn(d) > 0);
  const busiest = active.reduce<Date | null>((b, d) => (!b || wordsOn(d) > wordsOn(b) ? d : b), null);
  const activeWords = active.reduce((a, d) => a + wordsOn(d), 0);
  const level = (d: Date) => { const w = wordsOn(d); return w <= 0 || heatTop <= 0 ? 0 : Math.min(4, Math.max(1, Math.ceil((w / heatTop) * 4))); };

  // this week
  const week = Array.from({ length: 7 }, (_, i) => add(weekStart, i));
  const weekWords = week.map(wordsOn);
  const weekTotal = weekWords.reduce((a, b) => a + b, 0);
  const weekTop = Math.max(1, ...weekWords);
  const appsTotal = data.apps_week.reduce((a, b) => a + b.words, 0);

  return (
    <div className="insights">
      <div className="tiles">
        <Tile value={num(words)} label="Words dictated" note={u?.since ? `since ${dayMonth(parse(u.since))}` : "nothing yet"} />
        <Tile value={speed === null ? "—" : num(rate)} label="Words per minute" note="speaking, not typing" />
        <Tile value={saved ? duration(savedMs) : "—"} label="Time saved" note={`at ${typing} wpm typing `}>
          <button className="link-btn" aria-expanded={how} onClick={() => setHow(!how)}>How?</button>
        </Tile>
        <Tile value="—" label="Meetings transcribed" note="comes with EsyMeet" />
      </div>
      {how && u && saved && (
        <p className="small how" role="note">
          Typing {num(u.words)} words at {typing} wpm: {duration(saved.typing)} − speaking {duration(u.audio_ms)} − processing {duration(u.processing_ms)} = {duration(saved.saved)} saved.
        </p>
      )}

      <section className="panel chart-card">
        <div className="chart-head">
          <div><h2>Words per day</h2><p className="small">{num(spanTotal)} words in {range} days</p></div>
          <div className="seg" role="radiogroup" aria-label="Range">
            {([7, 30, 90] as const).map((r) => <button key={r} role="radio" aria-checked={range === r} className={range === r ? "on" : ""} onClick={() => setRange(r)}>{r} days</button>)}
          </div>
        </div>
        <div className="bars" role="img" aria-label={`Words per day for the last ${range} days: ${num(spanTotal)} in all, about ${num(avg)} a day.`}>
          <div className="bars-plot" key={range}>
            {spanWords.map((w, i) => <span key={i} className="bar" style={{ height: `${(w / top) * 100}%` }} title={`${dayMonth(span[i])}: ${num(w)} words`} />)}
            {avg > 0 && <span className="avg" style={{ bottom: `${(avg / top) * 100}%` }}><span className="avg-label">avg {num(avg)}</span></span>}
          </div>
          <div className="bars-axis" style={{ gridTemplateColumns: `repeat(${range}, minmax(0, 1fr))` }} aria-hidden="true">
            {span.map((d, i) => <span key={i}>{range === 7 ? weekday(d) : i % every === 0 ? dayMonth(d) : ""}</span>)}
          </div>
        </div>
      </section>

      <div className="insights-row">
        <section className="panel">
          <h2>Activity</h2>
          <p className="small">{active.length} active {active.length === 1 ? "day" : "days"} in 18 weeks</p>
          <div className="heat" role="img" aria-label={`${active.length} days with dictation in the last 18 weeks${busiest ? `; busiest day ${num(wordsOn(busiest))} words` : ""}.`}>
            <div className="heat-days" aria-hidden="true"><span>Mon</span><span /><span>Wed</span><span /><span>Fri</span><span /><span /></div>
            <div className="heat-grid">
              {cells.map((d, i) => (
                <span key={i} className={"cell" + (d > today ? " future" : "")} data-level={d > today ? undefined : level(d)} style={{ animationDelay: `${Math.floor(i / 7) * 25}ms` }}
                  title={d > today ? undefined : `${weekday(d)} ${dayMonth(d)}: ${num(wordsOn(d))} words`} />
              ))}
            </div>
          </div>
          <div className="heat-legend" aria-hidden="true">Less {[0, 1, 2, 3, 4].map((l) => <span key={l} className="cell" data-level={l} />)} More</div>
          <div className="mini-stats">
            <div><b>{u?.streak ?? 0}</b><span>day streak</span></div>
            <div><b>{busiest ? `${weekday(busiest)} ${dayMonth(busiest)}` : "—"}</b><span>busiest day</span></div>
            <div><b>{active.length ? num(activeWords / active.length) : "—"}</b><span>words a day when active</span></div>
          </div>
        </section>
        <section className="panel week">
          <h2>This week</h2>
          <p className="small">{num(weekTotal)} words</p>
          <div className="week-bars" role="img" aria-label={`This week: ${week.map((d, i) => `${weekday(d)} ${num(weekWords[i])}`).join(", ")}.`}>
            {week.map((d, i) => (
              <div key={i} className={"week-day" + (key(d) === data.today ? " today" : "")}>
                <span className="week-bar"><i style={{ height: `${(weekWords[i] / weekTop) * 100}%` }} /></span>
                <span aria-hidden="true">{weekday(d).slice(0, 1)}</span>
              </div>
            ))}
          </div>
          <h3 className="kinds-title">By kind of app</h3>
          {data.apps_week.length === 0 ? <p className="small">Nothing yet this week.</p> : (
            <ul className="kinds">
              {data.apps_week.map((a) => {
                const pct = Math.round((a.words / Math.max(1, appsTotal)) * 100);
                return <li key={a.kind}><span className="kind-name">{a.kind}</span><span className="kind-bar"><i style={{ width: `${pct}%` }} /></span><span className="kind-pct">{pct}%</span></li>;
              })}
            </ul>
          )}
        </section>
      </div>

      <div className="insights-foot">
        <p className="small">App kinds come from the program’s name only. EsyType never reads window titles or what you write for Insights. These numbers stay on this PC, also when History is off.</p>
        <div className="stepper" role="group" aria-label="Typing speed">
          <span className="small">Typing speed</span>
          <button className="icon-btn" aria-label="Slower typing speed" disabled={typing <= 10} onClick={() => save({ typing_wpm: typing - 5 })}>−</button>
          <span className="stepper-value">{typing} wpm</span>
          <button className="icon-btn" aria-label="Faster typing speed" disabled={typing >= 150} onClick={() => save({ typing_wpm: typing + 5 })}>+</button>
        </div>
      </div>
    </div>
  );
}
