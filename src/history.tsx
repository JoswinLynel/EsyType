import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { suggestCorrection } from "./dictionary";
import { ask, Banner, Empty, exported, Icon, listArrows, NoMatch, SearchBox, SkeletonRows, toast, toastError, useRefocus } from "./ui";
import { PageTop, Wave } from "./hero";

export type HistorySettings = {
  history_enabled: boolean; history_retention_days: number; history_record_app: boolean; history_keep_raw: boolean;
};
export type Entry = {
  id: number; created_at: number; raw_text: string | null; final_text: string; edited_text: string | null;
  model: string; mode: string; style: string | null; undone: boolean; audio_ms: number; outcome: string; app: string | null; word_count: number;
};

const OUTCOME: Record<string, string> = { copied: "Copied, not typed", typed: "Typed" };

/** The search's matches in the text, in bold accent ink. */
function Marked({ text, query }: { text: string; query: string }) {
  const q = query.trim();
  if (!q) return <>{text}</>;
  const low = text.toLowerCase(), ql = q.toLowerCase();
  const out: ReactNode[] = [];
  for (let at = 0, k = 0; at < text.length; k++) {
    const hit = low.indexOf(ql, at);
    if (hit < 0) { out.push(text.slice(at)); break; }
    out.push(text.slice(at, hit), <mark key={k} className="hit">{text.slice(hit, hit + q.length)}</mark>);
    at = hit + q.length;
  }
  return <>{out}</>;
}

/** Edit a dictation in a sheet over the window (Mac design: History, Edit). */
function EditSheet({ e, text, close, saved }: { e: Entry; text: string; close: () => void; saved: (to: string) => void }) {
  const [value, setValue] = useState(text);
  const save = async () => { try { await invoke("history_edit", { id: e.id, text: value }); toast("Saved."); saved(value); } catch (err) { toastError(err); } };
  const undoEdits = async () => { try { await invoke("history_edit", { id: e.id, text: "" }); saved(e.final_text); } catch (err) { toastError(err); } };
  return (
    <div className="scrim sheet-scrim" onMouseDown={(ev) => ev.target === ev.currentTarget && close()}>
      <div className="dialog sheet" role="dialog" aria-modal="true" aria-label="Edit this dictation"
        onKeyDown={(ev) => {
          if (ev.key === "Escape") { ev.preventDefault(); ev.stopPropagation(); close(); }
          if (ev.key === "Enter" && ev.ctrlKey) { ev.preventDefault(); save(); }
          if (ev.key === "Tab") { // keep focus inside the sheet
            ev.preventDefault();
            const items = Array.from(ev.currentTarget.querySelectorAll<HTMLElement>("textarea, button"));
            const at = items.indexOf(document.activeElement as HTMLElement);
            items[(at + (ev.shiftKey ? items.length - 1 : 1)) % items.length]?.focus();
          }
        }}>
        <h2>Edit dictation</h2>
        <textarea value={value} onChange={(ev) => setValue(ev.target.value)} aria-label="Edit dictation" autoFocus />
        <div className="row dialog-actions">
          {e.edited_text !== null && <button className="btn" onClick={undoEdits}>Undo my edits</button>}
          <button className="btn" onClick={close}>Cancel</button>
          <button className="btn primary" onClick={save}>Save</button>
        </div>
      </div>
    </div>
  );
}

const appInitial = (app: string) => app.replace(/\.exe$/i, "").slice(0, 1).toUpperCase();

function Item({ e, query, edge, group, onChange, deleting }: { e: Entry; query: string; edge: string; group: number; onChange: () => void; deleting: () => void }) {
  const text = e.edited_text ?? e.final_text;
  const [editing, setEditing] = useState(false);
  const [copied, setCopied] = useState(false);
  const [offer, setOffer] = useState<{ heard: string; write: string } | null>(null);
  const li = useRef<HTMLLIElement>(null);
  const backToRow = () => setTimeout(() => li.current?.querySelector<HTMLElement>("button")?.focus());
  const run = async (cmd: string, args: Record<string, unknown>, done?: string) => {
    try { await invoke(cmd, args); if (done) toast(done); onChange(); } catch (err) { toastError(err); }
  };
  const style = e.mode === "clean" ? (e.style && e.style !== "standard" ? `Clean, ${e.style[0].toUpperCase() + e.style.slice(1)}` : "Clean") : "Verbatim";
  const details = [e.app, `${e.word_count} ${e.word_count === 1 ? "word" : "words"}`, `${Math.max(1, Math.round(e.audio_ms / 1000))} s spoken`, style,
    e.edited_text !== null ? "edited" : null, e.undone ? "undone" : null].filter(Boolean).join(" · ");
  return (
    <li className={"hrow" + edge} ref={li} style={{ animationDelay: `${group * 70}ms` }}>
      <div className="hrow-when">
        <span className="hrow-time">{new Date(e.created_at).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })}</span>
        {e.app && <span className="app-tile" aria-hidden="true" title={e.app}>{appInitial(e.app)}</span>}
      </div>
      <div className="hrow-body">
        <p className="hrow-text"><Marked text={text} query={query} /></p>
        <p className="hrow-details">
          <span>{details}</span>
          {e.outcome === "failed" && <span className="badge-warn" title="EsyType couldn’t type this one, so it was copied for you to paste.">Not inserted</span>}
          {OUTCOME[e.outcome] && <span className="sr-only"> · {OUTCOME[e.outcome]}</span>}
        </p>
        {offer && (
          <div className="row small" role="status">
            <span>Add <b>{offer.heard} → {offer.write}</b> to your dictionary, so it is written this way next time?</span>
            <button className="btn sm primary" onClick={async () => { await run("dict_add", { kind: "correction", term: offer.heard, replacement: offer.write }, `Added ${offer.heard} → ${offer.write} to the dictionary.`); setOffer(null); }}>Add</button>
            <button className="btn sm" onClick={() => setOffer(null)}>No thanks</button>
          </div>
        )}
        {e.raw_text !== null && e.raw_text !== text && (
          <details className="small">
            <summary>Original transcription</summary>
            <p>{e.raw_text}</p>
            <div className="row">
              <button className="btn sm" onClick={() => run("copy_text", { text: e.raw_text }, "Original copied.")}>Copy original</button>
              <button className="btn sm" onClick={() => run("history_edit", { id: e.id, text: e.raw_text }, "Using the original. Undo my edits brings the Clean text back.")}>Use original instead</button>
            </div>
          </details>
        )}
      </div>
      <div className="hrow-actions">
        <button className="icon-btn" aria-label="Copy" title="Copy" onClick={async () => { await run("copy_text", { text }, "Copied."); setCopied(true); setTimeout(() => setCopied(false), 1500); }}>
          <Icon name={copied ? "check" : "copy"} size={14} />
        </button>
        <button className="icon-btn" aria-label="Edit" title="Edit" onClick={() => setEditing(true)}><Icon name="edit" size={14} /></button>
        <button className="icon-btn danger" aria-label="Delete" title="Delete" onClick={async () => { if (await ask({ title: "Delete this dictation from history?", body: "This can’t be undone.", action: "Delete", danger: true })) { deleting(); run("history_delete", { id: e.id }, "Dictation deleted."); } }}>
          <Icon name="trash" size={14} />
        </button>
      </div>
      {editing && <EditSheet e={e} text={text} close={() => { setEditing(false); backToRow(); }}
        saved={(to) => { setEditing(false); setOffer(suggestCorrection(text, to)); onChange(); backToRow(); }} />}
    </li>
  );
}

/** What History keeps and for how long; shown in Settings, Data and privacy. */
export function HistoryPrivacy({ settings, save }: { settings: HistorySettings; save: (p: Partial<HistorySettings>) => Promise<unknown> }) {
  return (
    <>
        <h3>History</h3>
        <label className="row">
          <input type="checkbox" checked={settings.history_enabled} onChange={(e) => save({ history_enabled: e.target.checked })} />
          <span>Save my dictations in History</span>
        </label>
        {!settings.history_enabled && <p className="small">History is off: new dictations are not saved anywhere. Entries already saved stay until they expire or you delete them.</p>}
        <div className="row" style={{ marginTop: 12 }}>
          <label className="field">
            <span>Keep history</span>
            <select value={settings.history_retention_days} onChange={async (e) => {
              const days = Number(e.target.value);
              if (days && !await ask({ title: `Keep history for ${days} days?`, body: `Dictations older than ${days} days will be deleted now and from then on.`, action: "Continue", danger: true })) return;
              save({ history_retention_days: days });
            }}>
              <option value={30}>30 days</option>
              <option value={90}>90 days</option>
              <option value={0}>Until I delete it</option>
            </select>
          </label>
        </div>
        <label className="row" style={{ marginTop: 12 }}>
          <input type="checkbox" checked={settings.history_record_app} onChange={(e) => save({ history_record_app: e.target.checked })} />
          <span>Note which program I dictated into (its file name only, such as WINWORD.EXE; never window titles, documents or web addresses)</span>
        </label>
        <label className="row" style={{ marginTop: 12 }}>
          <input type="checkbox" checked={settings.history_keep_raw} onChange={async (e) => {
            const on = e.target.checked;
            if (!on && !await ask({ title: "Stop keeping the original transcription?", body: "Originals already saved will be removed too; the text that was inserted, and your edits, stay.", action: "Stop keeping originals", danger: true })) return;
            save({ history_keep_raw: on });
          }} />
          <span>Keep the original transcription next to the inserted text</span>
        </label>
        <p className="small">History is stored only on this PC. Audio recordings are never saved.</p>
    </>
  );
}

type Stats = { dictations: number; words: number; not_inserted: number; apps: string[] };
type Show = "" | "today" | "week" | "failed" | `app:${string}`;
const dayLabel = (ms: number) => {
  const d = new Date(ms), t = new Date();
  const y = new Date(t.getFullYear(), t.getMonth(), t.getDate() - 1);
  if (d.toDateString() === t.toDateString()) return "Today";
  if (d.toDateString() === y.toDateString()) return "Yesterday";
  return d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long", year: "numeric" });
};

export function HistoryPage({ settings, available, dbError, openPrivacy, tryIt }: {
  settings: HistorySettings; available: boolean; dbError: string | null; openPrivacy: () => void; tryIt: () => void;
}) {
  const [query, setQuery] = useState("");
  const [show, setShow] = useState<Show>("");
  const [items, setItems] = useState<Entry[]>([]);
  const [total, setTotal] = useState(0);
  const [stats, setStats] = useState<Stats | null>(null);
  const [loaded, setLoaded] = useState(false);
  const { list, deleting } = useRefocus(items);
  const load = useCallback(async (more = false) => {
    if (!available) return;
    try {
      const r = await invoke<{ items: Entry[]; total: number; stats: Stats }>("history_list", { query, offset: more ? items.length : 0, show });
      setItems((old) => (more ? [...old, ...r.items] : r.items));
      setTotal(r.total);
      setStats(r.stats);
      setLoaded(true);
    } catch (e) { toastError(e); }
  }, [available, query, show, items.length]);

  // Reload when the search or filter changes (debounced) and whenever a dictation is saved.
  useEffect(() => { const t = setTimeout(() => load(), 200); return () => clearTimeout(t); }, [query, show, available]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { const u = listen("history", () => load()); return () => { u.then((f) => f()); }; }, [load]);
  useEffect(() => { if (show === "failed" && stats && stats.not_inserted === 0) setShow(""); }, [show, stats]);

  const clearAll = async () => {
    if (!await ask({ title: "Delete all dictation history?", body: `All ${stats?.dictations ?? total} dictations. This can’t be undone. The database is compacted afterwards so the text cannot be recovered from the file.`, action: `Delete all ${stats?.dictations ?? total}`, danger: true })) return;
    try { await invoke("history_clear"); toast("All history deleted."); load(); } catch (e) { toastError(e); }
  };
  const n = (x: number, one: string, many: string) => `${x.toLocaleString()} ${x === 1 ? one : many}`;
  const chips = stats && stats.dictations > 0 ? <>
    <span className="hero-chip">{n(stats.dictations, "dictation", "dictations")}</span>
    <span className="hero-chip">{n(stats.words, "word", "words")}</span>
    {stats.not_inserted > 0 && <button className="hero-chip act" onClick={() => setShow("failed")}>{stats.not_inserted} not inserted</button>}
  </> : undefined;
  const filters: [Show, string][] = [["", "All"], ["today", "Today"], ["week", "This week"],
    ...(stats && stats.not_inserted > 0 ? [["failed", "Not inserted"] as [Show, string]] : []),
    ...(stats?.apps ?? []).map((a) => [`app:${a}`, a.replace(/\.exe$/i, "")] as [Show, string])];
  // One flat list (the keyboard and the refocus after a delete work along it); each day starts with a heading row
  // and its dictations are drawn as one card.
  const day = (e: Entry) => new Date(e.created_at).toDateString();
  const perDay = new Map<string, number>();
  items.forEach((e) => perDay.set(day(e), (perDay.get(day(e)) ?? 0) + 1));
  let group = -1;
  const rows = items.flatMap((e, i) => {
    const first = i === 0 || day(items[i - 1]) !== day(e), last = i === items.length - 1 || day(items[i + 1]) !== day(e);
    if (first) group++;
    const row = <Item key={e.id} e={e} query={query} group={group} edge={(first ? " first" : "") + (last ? " last" : "")} onChange={() => load()} deleting={deleting} />;
    return first ? [<li key={"day-" + e.id} className="day-head" role="presentation"><span className="day-eyebrow">{dayLabel(e.created_at)}</span><span className="count-badge">{perDay.get(day(e))}</span></li>, row] : [row];
  });

  return (
    <div className="history">
      <PageTop id="history" title="History" hero={{ headline: ["Everything you’ve ", "said", ", kept on this PC."], glow: "var(--et-glow-history)",
        message: "Your dictations, stored only on this PC for as long as you choose. Audio is never saved.", actions: chips }} />
      {!available ? (
        <Banner tone="red">History is unavailable{dbError ? `: ${dbError}` : "."} Dictation still works normally.</Banner>
      ) : <>
        <div className="summary-row">
          <span className="small">{stats ? `${n(stats.dictations, "dictation", "dictations")} · ${n(stats.words, "word", "words")}` : ""}
            {settings.history_enabled ? "" : " · History is off: new dictations are not saved."} <a href="#" onClick={(e) => { e.preventDefault(); openPrivacy(); }}>Privacy settings</a></span>
          <span className="row">
            {(["csv", "json"] as const).map((f) => (
              <button key={f} className="btn sm tool" aria-label={`Export ${f.toUpperCase()}`} disabled={total === 0} onClick={async () => {
                try { const r = await invoke<{ path: string; count: number }>("history_export", { query, format: f }); exported(r.path); } catch (e) { toastError(e); }
              }}><Icon name="export" size={14} />{f.toUpperCase()}</button>
            ))}
            <button className="btn sm danger" aria-label="Delete all history" disabled={!stats || stats.dictations === 0} onClick={clearAll}>Delete all</button>
          </span>
        </div>
        <SearchBox label="Search history" placeholder="Search your dictations" value={query} onChange={setQuery} />
        {stats && stats.dictations > 0 && (
          <div className="chips" role="group" aria-label="Show">
            {filters.map(([v, label]) => <button key={v} className={"fchip" + (show === v ? " on" : "")} aria-pressed={show === v} onClick={() => setShow(v)}>{label}</button>)}
          </div>
        )}
        {!loaded ? <SkeletonRows /> : items.length === 0 ? (
          query ? <NoMatch query={query} clear={() => setQuery("")} />
            : show ? <p className="small">Nothing here yet.</p>
            : settings.history_enabled
              ? <section className="panel"><div className="empty"><span className="empty-wave"><Wave bar={4} gap={4} hint={18} /></span><p className="empty-title">Nothing here yet</p>
                  <p className="small">Your dictations appear here as you speak, stored only on this PC. Settings ▸ History & Privacy sets how long they’re kept.</p>
                  <button className="btn dark" onClick={tryIt}>Open Scratchpad</button></div></section>
              : <Empty icon="history" title="History is off" text="New dictations are not saved." action={<button className="btn primary" onClick={openPrivacy}>Privacy settings</button>} />
        ) : (
          <ul className="days" ref={list} onKeyDown={listArrows}>{rows}</ul>
        )}
        {items.length < total && <button className="btn" onClick={() => load(true)}>Show more ({total - items.length} left)</button>}
        {total > 0 && <p className="small">Export saves {query ? `the ${total} ${total === 1 ? "dictation" : "dictations"} matching your search` : `all ${stats?.dictations ?? total} ${(stats?.dictations ?? total) === 1 ? "dictation" : "dictations"}`} to your Downloads folder.</p>}
      </>}
    </div>
  );
}
