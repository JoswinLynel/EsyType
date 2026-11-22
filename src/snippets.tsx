import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { ask, Banner, Empty, exported, focusField, ListHead, listArrows, NoMatch, SearchBox, SkeletonRows, toast, toastError, useRefocus } from "./ui";

type Snippet = { id: number; trigger: string; body: string; mode: "whole" | "anywhere"; uses: number };
const MAX_BODY = 4000;

function Editor({ initial, onSave, onCancel, saveLabel, triggerId }: {
  initial: { trigger: string; body: string; mode: "whole" | "anywhere" };
  onSave: (s: { trigger: string; body: string; mode: "whole" | "anywhere" }) => Promise<boolean>;
  onCancel?: () => void; saveLabel: string; triggerId?: string;
}) {
  const [trigger, setTrigger] = useState(initial.trigger);
  const [body, setBody] = useState(initial.body);
  const [mode, setMode] = useState(initial.mode);
  const [preview, setPreview] = useState("");
  const box = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { invoke<string>("snip_preview", { body }).then(setPreview).catch(() => setPreview(body)); }, [body]);
  const insert = (p: string) => {
    const t = box.current; const at = t?.selectionStart ?? body.length;
    setBody(body.slice(0, at) + p + body.slice(t?.selectionEnd ?? at));
  };
  const save = async () => { if (trigger.trim() && body.trim() && await onSave({ trigger, body, mode })) { setTrigger(initial.trigger); setBody(initial.body); setMode(initial.mode); } };
  return (
    // Ctrl+Enter saves; Esc cancels an edit.
    <div className="snippet-editor" onKeyDown={(e) => {
      if (e.key === "Enter" && e.ctrlKey) { e.preventDefault(); save(); }
      if (e.key === "Escape" && onCancel) { e.preventDefault(); onCancel(); }
    }}>
      <label className="field">
        <span>When I say</span>
        <input id={triggerId} type="text" aria-label="Trigger" autoFocus={!!onCancel} value={trigger} maxLength={60} onChange={(e) => setTrigger(e.target.value)} placeholder="my email signature" />
      </label>
      <label className="field">
        <span>Insert ({body.length} of {MAX_BODY} characters)</span>
        <textarea ref={box} aria-label="Snippet text" value={body} maxLength={MAX_BODY} onChange={(e) => setBody(e.target.value)} placeholder={"Kind regards,\nJo Smith"} />
      </label>
      <div className="row">
        <span className="small">Add:</span>
        {["{date}", "{time}", "{day}"].map((p) => <button key={p} className="btn sm" onClick={() => insert(p)}>{p}</button>)}
      </div>
      {preview !== body && <p className="small">Preview: <span style={{ whiteSpace: "pre-wrap" }}>{preview}</span></p>}
      <div className="row" role="radiogroup" aria-label="When to use it">
        <label className="row"><input type="radio" checked={mode === "whole"} onChange={() => setMode("whole")} /><span><b>Whole dictation</b>: only when I say just the trigger</span></label>
        <label className="row"><input type="radio" checked={mode === "anywhere"} onChange={() => setMode("anywhere")} /><span><b>Anywhere</b>: wherever I say it in a sentence (two words or more)</span></label>
      </div>
      <div className="row">
        <button className="btn primary" disabled={!trigger.trim() || !body.trim()} onClick={save}>{saveLabel}</button>
        {onCancel && <button className="btn" onClick={onCancel}>Cancel</button>}
      </div>
    </div>
  );
}

function Row({ s, onChange, deleting }: { s: Snippet; onChange: () => void; deleting: () => void }) {
  const [editing, setEditing] = useState(false);
  const li = useRef<HTMLLIElement>(null);
  const backToRow = () => setTimeout(() => li.current?.querySelector<HTMLElement>("button")?.focus());
  const save = async (v: { trigger: string; body: string; mode: string }) => {
    try { await invoke("snip_update", { id: s.id, ...v }); setEditing(false); toast("Saved."); onChange(); backToRow(); return true; } catch (e) { toastError(e); return false; }
  };
  return (
    <li className="entry" ref={li}>
      {editing ? <Editor initial={s} onSave={save} onCancel={() => { setEditing(false); backToRow(); }} saveLabel="Save" /> : (
        <>
          <div className="row" style={{ justifyContent: "space-between" }}>
            <b>"{s.trigger}"</b>
            <span className="row small">
              {s.mode === "whole" ? "Whole dictation" : "Anywhere"} · used {s.uses} {s.uses === 1 ? "time" : "times"}
              <button className="btn sm" onClick={() => setEditing(true)}>Edit</button>
              <button className="btn sm" onClick={async () => {
                if (!await ask({ title: `Delete the snippet "${s.trigger}"?`, action: "Delete", danger: true })) return;
                deleting();
                try { await invoke("snip_delete", { id: s.id }); toast(`Deleted "${s.trigger}".`); onChange(); } catch (e) { toastError(e); }
              }}>Delete</button>
            </span>
          </div>
          <p className="entry-text small">{s.body.length > 160 ? s.body.slice(0, 160) + "…" : s.body}</p>
        </>
      )}
    </li>
  );
}

export function SnippetsPage({ available, dbError }: { available: boolean; dbError: string | null }) {
  const [items, setItems] = useState<Snippet[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [query, setQuery] = useState("");
  const file = useRef<HTMLInputElement>(null);
  const load = useCallback(async () => {
    if (!available) return;
    try { setItems(await invoke<Snippet[]>("snip_list")); setLoaded(true); } catch (e) { toastError(e); }
  }, [available]);
  useEffect(() => { load(); }, [load]);

  const add = async (v: { trigger: string; body: string; mode: string }) => {
    try { await invoke("snip_add", v); toast(`Added "${v.trigger}".`); load(); return true; } catch (e) { toastError(e); return false; }
  };
  const importFile = async (f: File) => {
    try {
      const r = await invoke<{ added: number; duplicates: number; problems: string[] }>("snip_import", { text: await f.text() });
      toast(`Imported ${r.added} ${r.added === 1 ? "snippet" : "snippets"}; ${r.duplicates} already there.${r.problems.length ? ` Not imported: ${r.problems.join("; ")}` : ""}`);
      load();
    } catch (e) { toastError(e); }
  };
  const exportAs = async (format: "csv" | "json") => {
    try { exported(await invoke<string>("snip_export", { format })); } catch (e) { toastError(e); }
  };
  const q = query.toLowerCase();
  const shown = items.filter((s) => !q || s.trigger.toLowerCase().includes(q) || s.body.toLowerCase().includes(q));
  const { list, deleting } = useRefocus(shown);

  if (!available) return <Banner tone="red">Snippets are unavailable{dbError ? `: ${dbError}` : "."} Dictation still works normally.</Banner>;
  return (
    <>
      <section className="panel">
        <h2>Add a snippet</h2>
        <Editor initial={{ trigger: "", body: "", mode: "whole" }} onSave={add} saveLabel="Add snippet" triggerId="snip-trigger" />
        <p className="small">Say the trigger and EsyType inserts the text exactly as written, line breaks included. Works in Clean and Verbatim. {"{date}"}, {"{time}"} and {"{day}"} are filled in when the snippet is used.</p>
      </section>
      <section className="panel">
        <ListHead title="Snippets" count={loaded ? items.length : undefined}
          danger={<button className="btn sm danger" disabled={!items.length} onClick={async () => {
            if (!await ask({ title: `Delete all ${items.length} snippets?`, body: "This cannot be undone. Export first if you may want them back.", action: "Delete all", danger: true })) return;
            try { await invoke("snip_clear"); toast("Snippets cleared."); load(); } catch (e) { toastError(e); }
          }}>Delete all</button>}>
          <button className="btn sm" onClick={() => file.current?.click()}>Import</button>
          <input ref={file} type="file" accept=".csv,.json,text/csv,application/json" hidden aria-label="Import file" onChange={(e) => { const f = e.target.files?.[0]; if (f) importFile(f); e.target.value = ""; }} />
          <button className="btn sm" disabled={!items.length} onClick={() => exportAs("csv")}>Export CSV</button>
          <button className="btn sm" disabled={!items.length} onClick={() => exportAs("json")}>Export JSON</button>
        </ListHead>
        <SearchBox label="Search snippets" placeholder="Search your snippets" value={query} onChange={setQuery} />
        {!loaded ? <SkeletonRows /> : shown.length === 0 ? (
          items.length ? <NoMatch query={query} clear={() => setQuery("")} />
            : <Empty icon="snippets" title="No snippets yet" text="Try your email signature, address or a meeting link."
                action={<button className="btn primary" onClick={() => focusField("snip-trigger")}>Add a snippet</button>} />
        ) : (
          <ul className="entries" ref={list} onKeyDown={listArrows}>{shown.map((s) => <Row key={s.id} s={s} onChange={load} deleting={deleting} />)}</ul>
        )}
        <p className="small">Import accepts CSV with a header row (trigger, text, and optionally mode) or JSON. Exports go to your Downloads folder.</p>
      </section>
    </>
  );
}
