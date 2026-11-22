import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { suggestCorrection } from "./dictionary";
import { ask, Banner, Empty, exported, ListHead, listArrows, NoMatch, SearchBox, SkeletonRows, toast, toastError, useRefocus } from "./ui";

export type HistorySettings = {
  history_enabled: boolean; history_retention_days: number; history_record_app: boolean; history_keep_raw: boolean;
};
type Entry = {
  id: number; created_at: number; raw_text: string | null; final_text: string; edited_text: string | null;
  model: string; mode: string; style: string | null; undone: boolean; audio_ms: number; outcome: string; app: string | null; word_count: number;
};

const OUTCOME: Record<string, string> = { copied: "Copied, not typed", typed: "Typed", failed: "Not inserted" };

function Item({ e, onChange, deleting }: { e: Entry; onChange: () => void; deleting: () => void }) {
  const text = e.edited_text ?? e.final_text;
  const [editing, setEditing] = useState<string | null>(null);
  const [offer, setOffer] = useState<{ heard: string; write: string } | null>(null);
  const li = useRef<HTMLLIElement>(null);
  const backToRow = () => setTimeout(() => li.current?.querySelector<HTMLElement>("button")?.focus());
  const saveEdit = async () => { await run("history_edit", { id: e.id, text: editing }, "Saved."); setOffer(suggestCorrection(text, editing ?? "")); setEditing(null); backToRow(); };
  const run = async (cmd: string, args: Record<string, unknown>, done?: string) => {
    try { await invoke(cmd, args); if (done) toast(done); onChange(); } catch (err) { toastError(err); }
  };
  return (
    <li className="entry" ref={li}>
      <div className="row small" style={{ justifyContent: "space-between" }}>
        <span>
          {new Date(e.created_at).toLocaleString()}{e.app ? ` · ${e.app}` : ""} · {e.word_count} {e.word_count === 1 ? "word" : "words"}
          {e.mode === "clean" ? (e.style && e.style !== "standard" ? ` · Clean, ${e.style[0].toUpperCase() + e.style.slice(1)}` : " · Clean") : " · Verbatim"}
          {e.edited_text !== null && " · edited"}
          {e.undone && " · undone"}
        </span>
        {OUTCOME[e.outcome] && <span className={"chip " + (e.outcome === "typed" ? "green" : "amber")}>{OUTCOME[e.outcome]}</span>}
      </div>
      {editing === null ? <p className="entry-text">{text}</p> : (
        <textarea value={editing} onChange={(ev) => setEditing(ev.target.value)} aria-label="Edit dictation" autoFocus
          onKeyDown={(ev) => {
            if (ev.key === "Escape") { ev.preventDefault(); setEditing(null); backToRow(); }
            if (ev.key === "Enter" && ev.ctrlKey) { ev.preventDefault(); saveEdit(); }
          }} />
      )}
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
      <div className="row">
        {editing === null ? (
          <>
            <button className="btn sm" onClick={() => run("copy_text", { text }, "Copied.")}>Copy</button>
            <button className="btn sm" onClick={() => setEditing(text)}>Edit</button>
            <button className="btn sm" onClick={async () => { if (await ask({ title: "Delete this dictation from history?", body: "This cannot be undone.", action: "Delete", danger: true })) { deleting(); run("history_delete", { id: e.id }, "Dictation deleted."); } }}>Delete</button>
          </>
        ) : (
          <>
            <button className="btn sm primary" onClick={saveEdit}>Save</button>
            <button className="btn sm" onClick={() => { setEditing(null); backToRow(); }}>Cancel</button>
            {e.edited_text !== null && <button className="btn sm" onClick={async () => { await run("history_edit", { id: e.id, text: "" }); setEditing(null); }}>Undo my edits</button>}
          </>
        )}
      </div>
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

export function HistoryPage({ settings, available, dbError, openPrivacy, tryIt }: {
  settings: HistorySettings; available: boolean; dbError: string | null; openPrivacy: () => void; tryIt: () => void;
}) {
  const [query, setQuery] = useState("");
  const [items, setItems] = useState<Entry[]>([]);
  const [total, setTotal] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const { list, deleting } = useRefocus(items);
  const load = useCallback(async (more = false) => {
    if (!available) return;
    try {
      const r = await invoke<{ items: Entry[]; total: number }>("history_list", { query, offset: more ? items.length : 0 });
      setItems((old) => (more ? [...old, ...r.items] : r.items));
      setTotal(r.total);
      setLoaded(true);
    } catch (e) { toastError(e); }
  }, [available, query, items.length]);

  // Reload when the search changes (debounced) and whenever a dictation is saved.
  useEffect(() => { const t = setTimeout(() => load(), 200); return () => clearTimeout(t); }, [query, available]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { const u = listen("history", () => load()); return () => { u.then((f) => f()); }; }, [load]);

  const clearAll = async () => {
    if (!await ask({ title: `Delete all ${total} dictations from history?`, body: "This cannot be undone. The database is compacted afterwards so the text cannot be recovered from the file.", action: "Delete all", danger: true })) return;
    try { await invoke("history_clear"); toast("All history deleted."); load(); } catch (e) { toastError(e); }
  };

  return (
    <>
      <p className="small">History is stored only on this PC; audio is never saved. {settings.history_enabled ? "" : "History is off: new dictations are not saved. "}
        What is kept and for how long: <a href="#" onClick={(e) => { e.preventDefault(); openPrivacy(); }}>Privacy settings</a>.</p>

      <section className="panel">
        <ListHead title="History" count={available && loaded ? total : undefined}
          danger={<button className="btn sm danger" disabled={!available || total === 0} onClick={clearAll}>Delete all history</button>}>
          {(["csv", "json"] as const).map((f) => (
            <button key={f} className="btn sm" disabled={!available || total === 0} onClick={async () => {
              try { const r = await invoke<{ path: string; count: number }>("history_export", { query, format: f }); exported(r.path); } catch (e) { toastError(e); }
            }}>Export {f.toUpperCase()}</button>
          ))}
        </ListHead>
        {!available ? (
          <Banner tone="red">History is unavailable{dbError ? `: ${dbError}` : "."} Dictation still works normally.</Banner>
        ) : (
          <>
            <SearchBox label="Search history" placeholder="Search your dictations" value={query} onChange={setQuery} />
            {!loaded ? <SkeletonRows /> : items.length === 0 ? (
              query ? <NoMatch query={query} clear={() => setQuery("")} />
                : settings.history_enabled
                  ? <Empty icon="history" title="Nothing here yet" text="Your dictations appear here as you speak." action={<button className="btn primary" onClick={tryIt}>Try it</button>} />
                  : <Empty icon="history" title="History is off" text="New dictations are not saved." action={<button className="btn primary" onClick={openPrivacy}>Privacy settings</button>} />
            ) : (
              <ul className="entries" ref={list} onKeyDown={listArrows}>{items.map((e) => <Item key={e.id} e={e} onChange={() => load()} deleting={deleting} />)}</ul>
            )}
            {items.length < total && <button className="btn" onClick={() => load(true)}>Show more ({total - items.length} left)</button>}
            {total > 0 && <p className="small">Export saves {query ? `the ${total} ${total === 1 ? "dictation" : "dictations"} matching your search` : `all ${total} ${total === 1 ? "dictation" : "dictations"}`} to your Downloads folder.</p>}
          </>
        )}
      </section>
    </>
  );
}
