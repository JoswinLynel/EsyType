import { useCallback, useEffect, useRef, useState } from "react";
import { PageTop } from "./hero";
import { invoke } from "@tauri-apps/api/core";
import { ask, Banner, Empty, exported, focusField, Icon, ListHead, listArrows, NoMatch, SearchBox, SkeletonRows, Switch, toast, toastError, useRefocus } from "./ui";

type Entry = { id: number; kind: "word" | "correction"; term: string; replacement: string | null; uses: number; category: string | null; description: string | null; enabled: boolean };
const CATEGORIES = ["Brand", "Technical", "Abbreviation", "Name", "Other"];

/** Words and phrases that differ between two versions of a text, for "Add to Dictionary?" after an edit. */
export function suggestCorrection(before: string, after: string): { heard: string; write: string } | null {
  const a = before.trim().split(/\s+/), b = after.trim().split(/\s+/);
  let s = 0;
  while (s < a.length && s < b.length && a[s] === b[s]) s++;
  let e = 0;
  while (e < a.length - s && e < b.length - s && a[a.length - 1 - e] === b[b.length - 1 - e]) e++;
  const strip = (w: string[]) => w.join(" ").replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
  const heard = strip(a.slice(s, a.length - e)), write = strip(b.slice(s, b.length - e));
  const words = (x: string) => x.split(" ").length;
  // only small, word-level changes look like a recognition mistake worth remembering
  if (!heard || !write || heard === write || words(heard) > 4 || words(write) > 4 || heard.length > 60 || write.length > 60) return null;
  return { heard, write };
}

/** A Dictionary entry's sheet (Mac design: Dictionary, Edit): type, words, category, note, on/off. Enter saves, Esc cancels. */
function EditSheet({ e, close, saved }: { e: Entry; close: () => void; saved: () => void }) {
  const [kind, setKind] = useState(e.kind);
  const [term, setTerm] = useState(e.term);
  const [write, setWrite] = useState(e.replacement ?? "");
  const [category, setCategory] = useState(e.category ?? "");
  const [description, setDescription] = useState(e.description ?? "");
  const [enabled, setEnabled] = useState(e.enabled);
  const save = async () => {
    try {
      await invoke("dict_update", { id: e.id, kind, term, replacement: kind === "correction" ? write : null });
      await invoke("dict_meta", { id: e.id, category, description, enabled });
      toast("Saved."); saved();
    } catch (err) { toastError(err); }
  };
  return (
    <div className="scrim sheet-scrim" onMouseDown={(x) => x.target === x.currentTarget && close()}>
      <div className="dialog sheet" role="dialog" aria-modal="true" aria-label={`Edit ${e.term}`}
        onKeyDown={(x) => {
          if (x.key === "Escape") { x.preventDefault(); x.stopPropagation(); close(); }
          if (x.key === "Enter" && (x.target as HTMLElement).tagName === "INPUT") { x.preventDefault(); save(); }
          if (x.key === "Tab") {
            x.preventDefault();
            const items = Array.from(x.currentTarget.querySelectorAll<HTMLElement>("input, button"));
            const at = items.indexOf(document.activeElement as HTMLElement);
            items[(at + (x.shiftKey ? items.length - 1 : 1)) % items.length]?.focus();
          }
        }}>
        <h2>Edit</h2>
        <div className="seg" role="radiogroup" aria-label="Type">
          {(["word", "correction"] as const).map((k) => <button key={k} role="radio" aria-checked={kind === k} className={kind === k ? "on" : ""} onClick={() => setKind(k)}>{k === "word" ? "Word" : "Correction"}</button>)}
        </div>
        <div className="row">
          <label className="field" style={{ flex: 1 }}><span>{kind === "correction" ? "When I say" : "Word or name"}</span>
            <input type="text" aria-label={kind === "correction" ? "When I say" : "Word"} value={term} maxLength={60} onChange={(x) => setTerm(x.target.value)} autoFocus /></label>
          {kind === "correction" && <label className="field" style={{ flex: 1 }}><span>Write</span>
            <input type="text" aria-label="Write" value={write} maxLength={60} onChange={(x) => setWrite(x.target.value)} /></label>}
        </div>
        <label className="field"><span>Category</span>
          <input type="text" aria-label="Category" list="dict-categories" placeholder="Brand, Technical, Name…" value={category} maxLength={40} onChange={(x) => setCategory(x.target.value)} /></label>
        <datalist id="dict-categories">{CATEGORIES.map((c) => <option key={c} value={c} />)}</datalist>
        <label className="field"><span>Note</span>
          <input type="text" aria-label="Note" placeholder="Optional" value={description} maxLength={200} onChange={(x) => setDescription(x.target.value)} /></label>
        <div className="switch-row"><span>Use this entry when I dictate</span><Switch on={enabled} set={setEnabled} label="Use this entry" /></div>
        <div className="row dialog-actions">
          <button className="btn" onClick={close}>Cancel</button>
          <button className="btn primary" onClick={save}>Save</button>
        </div>
      </div>
    </div>
  );
}

function Row({ e, wins, onChange, deleting }: { e: Entry; wins: string | null; onChange: () => void; deleting: () => void }) {
  const [editing, setEditing] = useState(false);
  const li = useRef<HTMLLIElement>(null);
  const backToRow = () => setTimeout(() => li.current?.querySelector<HTMLElement>("button")?.focus());
  const details = [e.kind === "correction" ? "Correction" : "Word", e.category, e.description, `used ${e.uses} ${e.uses === 1 ? "time" : "times"}`].filter(Boolean).join(" · ");
  return (
    <li className={"lrow" + (e.enabled ? "" : " off")} ref={li}>
      <span className="ltile" aria-hidden="true"><Icon name={e.kind === "correction" ? "swap" : "word"} size={15} /></span>
      <div className="lmain">
        <span className="lwords">{e.kind === "correction" ? <><span className="heard">{e.term}</span> <span className="arrow">→</span> <b>{e.replacement}</b></> : <b>{e.term}</b>}</span>
        <span className="ldetails">{details}{!e.enabled && " · off"}</span>
      </div>
      {wins && <span className="warn" role="img" aria-label={`“${wins}” wins over this entry`} title={`“${wins}” was added first and wins over this entry`}><Icon name="alert" size={15} /></span>}
      <span className="lactions">
        <button className="icon-btn" aria-label="Edit" title="Edit" onClick={() => setEditing(true)}><Icon name="edit" size={14} /></button>
        <button className="icon-btn danger" aria-label="Delete" title="Delete" onClick={async () => {
          if (await ask({ title: `Delete "${e.term}" from the dictionary?`, action: "Delete", danger: true })) {
            deleting();
            try { await invoke("dict_delete", { id: e.id }); toast(`Deleted "${e.term}".`); onChange(); } catch (err) { toastError(err); }
          }
        }}><Icon name="trash" size={14} /></button>
      </span>
      <Switch small on={e.enabled} label={`Use "${e.term}"`} set={async (on) => {
        try { await invoke("dict_meta", { id: e.id, category: e.category ?? "", description: e.description ?? "", enabled: on }); onChange(); } catch (err) { toastError(err); }
      }} />
      {editing && <EditSheet e={e} close={() => { setEditing(false); backToRow(); }} saved={() => { setEditing(false); onChange(); backToRow(); }} />}
    </li>
  );
}

/** What an import would do, then (if you agree) does it (Mac design: import preview). */
export async function importWithPreview(cmd: string, text: string, noun: [string, string]) {
  type R = { added: number; duplicates: number; problems: string[] };
  const dry = await invoke<R>(cmd, { text, dry: true });
  const n = (x: number) => `${x} ${x === 1 ? noun[0] : noun[1]}`;
  const list = [`${n(dry.added)} to add`, `${n(dry.duplicates)} already there, kept as they are`, ...dry.problems.map((p) => `Not imported: ${p}`)];
  if (!dry.added) { await ask({ title: "Nothing new to import", list, action: "OK" }); return false; }
  if (!await ask({ title: `Import ${n(dry.added)}?`, body: "Nothing has changed yet.", list, action: "Import" })) return false;
  const r = await invoke<R>(cmd, { text });
  toast(`Imported ${n(r.added)}.`);
  return true;
}

export function DictionaryPage({ available, dbError, hint, hintWords, setHint, builtin, setBuiltin }: {
  available: boolean; dbError: string | null; hint: boolean; hintWords: number; setHint: (on: boolean) => Promise<void>;
  builtin: boolean; setBuiltin: (on: boolean) => Promise<void>;
}) {
  const [items, setItems] = useState<Entry[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [kind, setKind] = useState<"word" | "correction">("word");
  const [term, setTerm] = useState("");
  const [write, setWrite] = useState("");
  const [status, setStatus] = useState("");
  const [query, setQuery] = useState("");
  const file = useRef<HTMLInputElement>(null);
  const [names, setNames] = useState<[string, string[]][]>([]);
  useEffect(() => { invoke<[string, string[]][]>("vocabulary_names").then(setNames).catch(() => setNames([])); }, []);

  const load = useCallback(async () => {
    if (!available) return;
    try { setItems(await invoke<Entry[]>("dict_list")); setLoaded(true); } catch (e) { toastError(e); }
  }, [available]);
  useEffect(() => { load(); }, [load]);

  const add = async () => {
    const what = kind === "correction" ? `${term.trim()} → ${write.trim()}` : term.trim();
    try {
      await invoke("dict_add", { kind, term, replacement: kind === "correction" ? write : null });
      toast(`Added "${what}".`); setStatus(`Added “${what}”.`); setTerm(""); setWrite(""); load();
    } catch (e) { toastError(e); setStatus(String(e)); }
  };
  const exportAs = async (format: "csv" | "json") => {
    try { exported(await invoke<string>("dict_export", { format })); } catch (e) { toastError(e); }
  };
  const q = query.toLowerCase();
  const shown = items.filter((e) => !q || e.term.toLowerCase().includes(q) || (e.replacement ?? "").toLowerCase().includes(q) || (e.category ?? "").toLowerCase().includes(q));
  const { list, deleting } = useRefocus(shown);
  // An entry whose spoken words another, earlier entry already uses: the earlier one wins.
  const first = new Map<string, Entry>();
  [...items].sort((a, b) => a.id - b.id).forEach((e) => { const k = e.term.toLowerCase(); if (!first.has(k)) first.set(k, e); });
  const wins = (e: Entry) => { const f = first.get(e.term.toLowerCase()); return f && f.id !== e.id ? (f.replacement ?? f.term) : null; };
  const latest = [...items].sort((a, b) => b.id - a.id).slice(0, 4);

  if (!available) return <Banner tone="red">The dictionary is unavailable{dbError ? `: ${dbError}` : "."} Dictation still works normally.</Banner>;
  return (
    <div className="stack">
      <PageTop id="dictionary" title="Dictionary" hero={{ headline: ["EsyType spells the way ", "you", " do."], glow: "var(--et-glow-dictionary)",
        message: "Add names, company jargon and uncommon words once, and they’re spelled right every time you dictate.",
        actions: <>
          <button className="hero-btn" onClick={() => { setKind("word"); focusField("dict-term"); }}>Add new word</button>
          {(latest.length ? latest.map((e) => e.replacement ?? e.term) : ["EsyType", "Priya", "Kubernetes"]).map((w) => (
            <button key={w} className="hero-chip act" title={latest.length ? `Search for ${w}` : `Add ${w}`} onClick={() => { if (latest.length) setQuery(w); else { setKind("word"); setTerm(w); focusField("dict-term"); } }}>{w}</button>
          ))}
        </> }} />
      <section className="panel">
        <h2>Add to your dictionary</h2>
        <div className="seg" role="group" aria-label="Kind">
          <button className={kind === "word" ? "on" : ""} aria-pressed={kind === "word"} onClick={() => setKind("word")}>Word</button>
          <button className={kind === "correction" ? "on" : ""} aria-pressed={kind === "correction"} onClick={() => setKind("correction")}>Correction</button>
        </div>
        <div className="row add-row">
          <label className="field" style={{ flex: 1 }}>
            <span>{kind === "word" ? "Word or name, spelled as you want it" : "When I say"}</span>
            <input id="dict-term" key={kind} aria-label={kind === "word" ? "Word or name, spelled as you want it" : "When I say"} type="text" value={term} maxLength={60} onChange={(e) => setTerm(e.target.value)} placeholder={kind === "word" ? "EsyType" : "esy type"} onKeyDown={(e) => e.key === "Enter" && add()} />
          </label>
          {kind === "correction" && <span className="arrow add-arrow" aria-hidden="true">→</span>}
          {kind === "correction" && (
            <label className="field" style={{ flex: 1 }}>
              <span>Write</span>
              <input aria-label="Write" type="text" value={write} maxLength={60} onChange={(e) => setWrite(e.target.value)} placeholder="EsyType" onKeyDown={(e) => e.key === "Enter" && add()} />
            </label>
          )}
          <button className="btn primary" disabled={!term.trim() || (kind === "correction" && !write.trim())} onClick={add}>Add</button>
        </div>
        <p className="small">Words are spelled exactly as you enter them whenever they’re heard, even when the speech engine splits them (“esy type” → EsyType). Corrections replace what the speech engine writes with what you want. Neither is ever changed by Clean or Style.</p>
        <div className="switch-row">
          <span><span className="switch-title">Also give these words to the speech engine as a hint{hint && hintWords ? ` (${hintWords} in use)` : ""}</span>
            <span className="small">Off by default. In testing it spelled names right more often (24 of 45 instead of 7) but made dictation about 40% slower, slightly less accurate on ordinary speech, and sometimes put a dictionary word where it didn’t belong.</span></span>
          <Switch on={hint} set={(on) => setHint(on)} label="Also give these words to the speech engine as a hint" />
        </div>
        {status && <p className="small status-line" role="status">{status}</p>}
      </section>

      <section className="panel">
        <ListHead title="Your dictionary" count={loaded ? items.length : undefined}
          danger={<button className="btn sm danger" disabled={!items.length} onClick={async () => {
            if (!await ask({ title: "Delete all dictionary entries?", body: "This can’t be undone. Export first if you may want them back.", action: `Delete all ${items.length}`, danger: true })) return;
            try { await invoke("dict_clear"); toast("Dictionary cleared."); load(); } catch (e) { toastError(e); }
          }}>Delete all</button>}>
          <button className="btn sm" onClick={() => file.current?.click()}>Import</button>
          <input ref={file} type="file" accept=".csv,.json,text/csv,application/json" hidden aria-label="Import file" onChange={async (e) => {
            const f = e.target.files?.[0]; e.target.value = "";
            if (f) { try { if (await importWithPreview("dict_import", await f.text(), ["entry", "entries"])) load(); } catch (err) { toastError(err); } }
          }} />
          <button className="btn sm" disabled={!items.length} onClick={() => exportAs("csv")}>Export CSV</button>
          <button className="btn sm" disabled={!items.length} onClick={() => exportAs("json")}>Export JSON</button>
        </ListHead>
        <SearchBox label="Search dictionary" placeholder="Search your dictionary" value={query} onChange={setQuery} />
        {!loaded ? <SkeletonRows /> : shown.length === 0 ? (
          items.length ? <NoMatch query={query} clear={() => setQuery("")} />
            : <Empty icon="dictionary" title="Your dictionary is empty" text="Add names and terms the speech engine gets wrong."
                action={<button className="btn dark" onClick={() => { setKind("word"); focusField("dict-term"); }}>Add a word</button>} />
        ) : (
          <ul className="entries lrows" ref={list} onKeyDown={listArrows}>{shown.map((e) => <Row key={e.id} e={e} wins={wins(e)} onChange={load} deleting={deleting} />)}</ul>
        )}
        <p className="small">Import reads CSV (kind, term, replacement; or term, replacement) or JSON, and shows what it will do before anything changes. New entries are added; existing ones are left as they are. Exports go to your Downloads folder.</p>
      </section>

      <section className="panel">
        <h2>Built-in product names</h2>
        <div className="switch-row">
          <span className="switch-title">Correct common product names: “chat gpt” becomes ChatGPT, “superbase” becomes Supabase, “microsoft co-pilot” becomes Microsoft Copilot</span>
          <Switch on={builtin} set={(on) => setBuiltin(on)} label="Correct common product names" />
        </div>
        <p className="small">A fixed list, kept apart from your dictionary: it can’t be edited or deleted and is never exported. Your own entries always win. Names that are also everyday words, such as Claude, Notion, Python or Excel, are never changed by it; add them above if you want them.</p>
        {names.length > 0 && (
          <details className="small">
            <summary>Show the list ({names.length} names)</summary>
            <ul className="vocab">{names.map(([w, heard]) => <li key={w}><b>{w}</b> from {heard.join(", ")}</li>)}</ul>
          </details>
        )}
      </section>
    </div>
  );
}
