import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { ask, Banner, Empty, exported, focusField, ListHead, listArrows, NoMatch, SearchBox, SkeletonRows, toast, toastError, useRefocus } from "./ui";

type Entry = { id: number; kind: "word" | "correction"; term: string; replacement: string | null; uses: number };

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

function Row({ e, onChange, deleting }: { e: Entry; onChange: () => void; deleting: () => void }) {
  const [edit, setEdit] = useState<{ term: string; replacement: string } | null>(null);
  const li = useRef<HTMLLIElement>(null);
  const backToRow = () => setTimeout(() => li.current?.querySelector<HTMLElement>("button")?.focus());
  const run = async (cmd: string, args: Record<string, unknown>, done: string) => {
    try { await invoke(cmd, args); setEdit(null); toast(done); onChange(); return true; } catch (err) { toastError(err); return false; }
  };
  const saveEdit = async () => {
    if (edit && await run("dict_update", { id: e.id, kind: e.kind, term: edit.term, replacement: e.kind === "correction" ? edit.replacement : null }, "Saved.")) backToRow();
  };
  // In the edit boxes: Enter or Ctrl+Enter saves, Esc cancels.
  const keys = (x: React.KeyboardEvent) => {
    if (x.key === "Enter") { x.preventDefault(); saveEdit(); }
    if (x.key === "Escape") { x.preventDefault(); setEdit(null); backToRow(); }
  };
  return (
    <li className="entry" ref={li}>
      {edit === null ? (
        <div className="row" style={{ justifyContent: "space-between" }}>
          <span className="entry-text">
            {e.kind === "correction" ? <>{e.term} <span className="muted">→</span> <b>{e.replacement}</b></> : <b>{e.term}</b>}
          </span>
          <span className="row small">
            {e.kind === "correction" ? "Correction" : "Word"} · used {e.uses} {e.uses === 1 ? "time" : "times"}
            <button className="btn sm" onClick={() => setEdit({ term: e.term, replacement: e.replacement ?? "" })}>Edit</button>
            <button className="btn sm" onClick={async () => { if (await ask({ title: `Delete "${e.term}" from the dictionary?`, action: "Delete", danger: true })) { deleting(); run("dict_delete", { id: e.id }, `Deleted "${e.term}".`); } }}>Delete</button>
          </span>
        </div>
      ) : (
        <div className="row" onKeyDown={keys}>
          <input type="text" aria-label={e.kind === "correction" ? "When I say" : "Word"} value={edit.term} maxLength={60} onChange={(x) => setEdit({ ...edit, term: x.target.value })} autoFocus />
          {e.kind === "correction" && <input type="text" aria-label="Write" value={edit.replacement} maxLength={60} onChange={(x) => setEdit({ ...edit, replacement: x.target.value })} />}
          <button className="btn sm primary" onClick={saveEdit}>Save</button>
          <button className="btn sm" onClick={() => { setEdit(null); backToRow(); }}>Cancel</button>
        </div>
      )}
    </li>
  );
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
    try {
      await invoke("dict_add", { kind, term, replacement: kind === "correction" ? write : null });
      toast(`Added "${kind === "correction" ? `${term} → ${write}` : term}".`); setTerm(""); setWrite(""); load();
    } catch (e) { toastError(e); }
  };
  const importFile = async (f: File) => {
    try {
      const r = await invoke<{ added: number; duplicates: number; problems: string[] }>("dict_import", { text: await f.text() });
      toast(`Imported ${r.added} ${r.added === 1 ? "entry" : "entries"}; ${r.duplicates} already there.${r.problems.length ? ` Not imported: ${r.problems.join("; ")}` : ""}`);
      load();
    } catch (e) { toastError(e); }
  };
  const exportAs = async (format: "csv" | "json") => {
    try { exported(await invoke<string>("dict_export", { format })); } catch (e) { toastError(e); }
  };
  const q = query.toLowerCase();
  const shown = items.filter((e) => !q || e.term.toLowerCase().includes(q) || (e.replacement ?? "").toLowerCase().includes(q));
  const { list, deleting } = useRefocus(shown);

  if (!available) return <Banner tone="red">The dictionary is unavailable{dbError ? `: ${dbError}` : "."} Dictation still works normally.</Banner>;
  return (
    <>
      <section className="panel">
        <h2>Add to your dictionary</h2>
        <div className="row">
          <div className="tabs" role="radiogroup" aria-label="Kind">
            <button className={kind === "word" ? "on" : ""} aria-pressed={kind === "word"} onClick={() => setKind("word")}>Word</button>
            <button className={kind === "correction" ? "on" : ""} aria-pressed={kind === "correction"} onClick={() => setKind("correction")}>Correction</button>
          </div>
        </div>
        <div className="row" style={{ marginTop: 12 }}>
          <label className="field" style={{ flex: 1 }}>
            <span>{kind === "word" ? "Word or name, spelled as you want it" : "When I say"}</span>
            <input id="dict-term" key={kind} aria-label={kind === "word" ? "Word or name, spelled as you want it" : "When I say"} type="text" value={term} maxLength={60} onChange={(e) => setTerm(e.target.value)} placeholder={kind === "word" ? "EsyType" : "easy type"} onKeyDown={(e) => e.key === "Enter" && add()} />
          </label>
          {kind === "correction" && (
            <label className="field" style={{ flex: 1 }}>
              <span>Write</span>
              <input aria-label="Write" type="text" value={write} maxLength={60} onChange={(e) => setWrite(e.target.value)} placeholder="EsyType" onKeyDown={(e) => e.key === "Enter" && add()} />
            </label>
          )}
          <button className="btn primary" style={{ alignSelf: "end" }} disabled={!term.trim() || (kind === "correction" && !write.trim())} onClick={add}>Add</button>
        </div>
        <p className="small">Words are spelled exactly as you enter them whenever they are heard. Corrections replace what the speech engine hears with what you want written. Both work in Clean and Verbatim, and are never changed by Clean's rules.</p>
        <label className="row" style={{ marginTop: 8 }}>
          <input type="checkbox" checked={hint} onChange={(e) => setHint(e.target.checked)} />
          <span>Also give these words to the speech engine as a hint{hint && hintWords ? ` (${hintWords} in use)` : ""}. Off by default: in testing it spelled names right more often (24 of 45 instead of 7) but made dictation about 40% slower, slightly less accurate on ordinary speech, and sometimes put a dictionary word where it did not belong.</span>
        </label>
      </section>

      <section className="panel">
        <ListHead title="Dictionary" count={loaded ? items.length : undefined}
          danger={<button className="btn sm danger" disabled={!items.length} onClick={async () => {
            if (!await ask({ title: `Delete all ${items.length} dictionary entries?`, body: "This cannot be undone. Export first if you may want them back.", action: "Delete all", danger: true })) return;
            try { await invoke("dict_clear"); toast("Dictionary cleared."); load(); } catch (e) { toastError(e); }
          }}>Delete all</button>}>
          <button className="btn sm" onClick={() => file.current?.click()}>Import</button>
          <input ref={file} type="file" accept=".csv,.json,text/csv,application/json" hidden aria-label="Import file" onChange={(e) => { const f = e.target.files?.[0]; if (f) importFile(f); e.target.value = ""; }} />
          <button className="btn sm" disabled={!items.length} onClick={() => exportAs("csv")}>Export CSV</button>
          <button className="btn sm" disabled={!items.length} onClick={() => exportAs("json")}>Export JSON</button>
        </ListHead>
        <SearchBox label="Search dictionary" placeholder="Search your dictionary" value={query} onChange={setQuery} />
        {!loaded ? <SkeletonRows /> : shown.length === 0 ? (
          items.length ? <NoMatch query={query} clear={() => setQuery("")} />
            : <Empty icon="dictionary" title="Your dictionary is empty" text="Add names and terms the speech engine gets wrong."
                action={<button className="btn primary" onClick={() => { setKind("word"); focusField("dict-term"); }}>Add a word</button>} />
        ) : (
          <ul className="entries" ref={list} onKeyDown={listArrows}>{shown.map((e) => <Row key={e.id} e={e} onChange={load} deleting={deleting} />)}</ul>
        )}
        <p className="small">Import accepts CSV with a header row (kind, term, replacement; or term, replacement) or JSON. New entries are added; existing ones are left as they are. Exports go to your Downloads folder.</p>
      </section>

      <section className="panel">
        <h2>Built-in product names</h2>
        <label className="row">
          <input type="checkbox" checked={builtin} onChange={(e) => setBuiltin(e.target.checked)} />
          <span>Correct common product names: "chat GPT" becomes ChatGPT, "Superbase" becomes Supabase, "Microsoft co-pilot" becomes Microsoft Copilot</span>
        </label>
        <p className="small">A fixed list, kept apart from your dictionary: it cannot be edited or deleted and is not exported. Your own entries always win. Names that are also everyday words, such as Claude, Notion, Python or Excel, are never changed by it; add them above if you want them.</p>
        {names.length > 0 && (
          <details className="small">
            <summary>Show the list ({names.length} names)</summary>
            <ul className="vocab">{names.map(([w, heard]) => <li key={w}><b>{w}</b> from {heard.join(", ")}</li>)}</ul>
          </details>
        )}
      </section>
    </>
  );
}
