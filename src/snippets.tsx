import { useCallback, useEffect, useRef, useState } from "react";
import { PageTop } from "./hero";
import { importWithPreview } from "./dictionary";
import { invoke } from "@tauri-apps/api/core";
import { ask, Banner, Empty, exported, focusField, Icon, ListHead, listArrows, NoMatch, SearchBox, SkeletonRows, Switch, toast, toastError, useRefocus } from "./ui";

type Snippet = { id: number; trigger: string; body: string; mode: "whole" | "anywhere"; uses: number; category: string | null; enabled: boolean };
/** A change asked for from outside the editor (the hero's example chips): `n` makes each request new. */
type Seed = { n: number; trigger?: string; append?: string; mode?: "whole" | "anywhere" };
const MAX_BODY = 4000;

function Editor({ initial, onSave, onCancel, saveLabel, triggerId, seed, extra }: {
  initial: { trigger: string; body: string; mode: "whole" | "anywhere" };
  onSave: (s: { trigger: string; body: string; mode: "whole" | "anywhere" }) => Promise<boolean>;
  onCancel?: () => void; saveLabel: string; triggerId?: string; seed?: Seed; extra?: React.ReactNode;
}) {
  const [trigger, setTrigger] = useState(initial.trigger);
  const [body, setBody] = useState(initial.body);
  const [mode, setMode] = useState(initial.mode);
  const [preview, setPreview] = useState("");
  const box = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { invoke<string>("snip_preview", { body }).then(setPreview).catch(() => setPreview(body)); }, [body]);
  useEffect(() => {
    if (!seed?.n) return;
    if (seed.trigger !== undefined) setTrigger(seed.trigger);
    if (seed.mode) setMode(seed.mode);
    if (seed.append) setBody((b) => b + seed.append);
  }, [seed]);
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
        <textarea ref={box} aria-label="Snippet text" className={body.length >= MAX_BODY ? "over" : ""} value={body} maxLength={MAX_BODY} onChange={(e) => setBody(e.target.value)} placeholder={"Kind regards,\nJo Smith"} />
      </label>
      <div className="row">
        <span className="small">Add:</span>
        {["{date}", "{time}", "{day}"].map((p) => <button key={p} className="btn sm" onClick={() => insert(p)}>{p}</button>)}
      </div>
      {preview !== body && <p className="small">Preview: <span style={{ whiteSpace: "pre-wrap" }}>{preview}</span></p>}
      <div className="radios" role="radiogroup" aria-label="When to use it">
        <label className="row"><input type="radio" checked={mode === "whole"} onChange={() => setMode("whole")} /><span><b>Whole dictation</b>: only when I say just the trigger</span></label>
        <label className="row"><input type="radio" checked={mode === "anywhere"} onChange={() => setMode("anywhere")} /><span><b>Anywhere</b>: wherever I say it in a sentence (two words or more)</span></label>
      </div>
      {extra}
      <div className="row">
        <button className="btn primary" disabled={!trigger.trim() || !body.trim()} onClick={save}>{saveLabel}</button>
        {onCancel && <button className="btn" onClick={onCancel}>Cancel</button>}
      </div>
    </div>
  );
}

function Row({ s, clash, onChange, deleting }: { s: Snippet; clash: string | null; onChange: () => void; deleting: () => void }) {
  const [editing, setEditing] = useState(false);
  const [category, setCategory] = useState(s.category ?? "");
  const [enabled, setEnabled] = useState(s.enabled);
  const li = useRef<HTMLLIElement>(null);
  const backToRow = () => setTimeout(() => li.current?.querySelector<HTMLElement>("button")?.focus());
  const close = () => { setEditing(false); backToRow(); };
  const save = async (v: { trigger: string; body: string; mode: string }) => {
    try {
      await invoke("snip_update", { id: s.id, ...v });
      await invoke("snip_meta", { id: s.id, category, enabled });
      setEditing(false); toast("Saved."); onChange(); backToRow(); return true;
    } catch (e) { toastError(e); return false; }
  };
  const first = s.body.split("\n")[0];
  return (
    <li className={"lrow" + (s.enabled ? "" : " off")} ref={li}>
      <span className="ltile" aria-hidden="true"><Icon name="quote" size={15} /></span>
      <div className="lmain">
        <span className="lwords"><b>“{s.trigger}”</b> <span className="mode-badge">{s.mode === "whole" ? "Whole" : "Anywhere"}</span></span>
        <span className="ldetails">{[first.length > 90 ? first.slice(0, 90) + "…" : first, s.category, `used ${s.uses} ${s.uses === 1 ? "time" : "times"}`].filter(Boolean).join(" · ")}{!s.enabled && " · off"}</span>
      </div>
      {clash && <span className="warn" role="img" aria-label={`Clashes with “${clash}”`} title={`Clashes with “${clash}”: both can match the same words`}><Icon name="alert" size={15} /></span>}
      <span className="lactions">
        <button className="icon-btn" aria-label="Edit" title="Edit" onClick={() => { setCategory(s.category ?? ""); setEnabled(s.enabled); setEditing(true); }}><Icon name="edit" size={14} /></button>
        <button className="icon-btn danger" aria-label="Delete" title="Delete" onClick={async () => {
          if (!await ask({ title: `Delete the snippet "${s.trigger}"?`, action: "Delete", danger: true })) return;
          deleting();
          try { await invoke("snip_delete", { id: s.id }); toast(`Deleted "${s.trigger}".`); onChange(); } catch (e) { toastError(e); }
        }}><Icon name="trash" size={14} /></button>
      </span>
      <Switch small on={s.enabled} label={`Use "${s.trigger}"`} set={async (on) => {
        try { await invoke("snip_meta", { id: s.id, category: s.category ?? "", enabled: on }); onChange(); } catch (e) { toastError(e); }
      }} />
      {editing && (
        <div className="scrim sheet-scrim" onMouseDown={(e) => e.target === e.currentTarget && close()}>
          <div className="dialog sheet wide" role="dialog" aria-modal="true" aria-label={`Edit ${s.trigger}`} onKeyDown={(e) => { if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); } }}>
            <h2>Edit snippet</h2>
            <Editor initial={s} onSave={save} onCancel={close} saveLabel="Save" extra={<>
              <label className="field"><span>Category</span><input type="text" aria-label="Category" placeholder="Optional" value={category} maxLength={40} onChange={(e) => setCategory(e.target.value)} /></label>
              <div className="switch-row"><span>Use this snippet when I dictate</span><Switch on={enabled} set={setEnabled} label="Use this snippet" /></div>
            </>} />
          </div>
        </div>
      )}
    </li>
  );
}

export function SnippetsPage({ available, dbError }: { available: boolean; dbError: string | null }) {
  const [items, setItems] = useState<Snippet[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [query, setQuery] = useState("");
  const [seed, setSeed] = useState<Seed>({ n: 0 });
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
    try { if (await importWithPreview("snip_import", await f.text(), ["snippet", "snippets"])) load(); } catch (e) { toastError(e); }
  };
  const exportAs = async (format: "csv" | "json") => {
    try { exported(await invoke<string>("snip_export", { format })); } catch (e) { toastError(e); }
  };
  const q = query.toLowerCase();
  const shown = items.filter((s) => !q || s.trigger.toLowerCase().includes(q) || s.body.toLowerCase().includes(q) || (s.category ?? "").toLowerCase().includes(q));
  const { list, deleting } = useRefocus(shown);
  // Two triggers clash when one is part of the other and the shorter one may match anywhere in a sentence.
  const words = (t: string) => ` ${t.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim()} `;
  const clash = (s: Snippet) => items.find((o) => o.id !== s.id && o.enabled && s.enabled &&
    ((o.mode === "anywhere" && words(s.trigger).includes(words(o.trigger))) || (s.mode === "anywhere" && words(o.trigger).includes(words(s.trigger)))))?.trigger ?? null;

  if (!available) return <Banner tone="red">Snippets are unavailable{dbError ? `: ${dbError}` : "."} Dictation still works normally.</Banner>;
  return (
    <div className="stack">
      <PageTop id="snippets" title="Snippets" hero={{ headline: ["Say a few words, ", "type", " the rest."], glow: "var(--et-mark-blue)",
        message: "Your signature, address, meeting link or standard reply, typed in full when you say its trigger.",
        actions: <>
          <button className="hero-btn" onClick={() => focusField("snip-trigger")}>New snippet</button>
          <button className="hero-chip act" onClick={() => { setSeed({ n: seed.n + 1, trigger: "my email signature", mode: "anywhere" }); focusField("snip-trigger"); }}>my email signature</button>
          <button className="hero-chip act" onClick={() => setSeed({ n: seed.n + 1, append: "{date}" })}>{"{date}"}</button>
        </> }} />
      <section className="panel">
        <h2>Add a snippet</h2>
        <Editor initial={{ trigger: "", body: "", mode: "whole" }} onSave={add} saveLabel="Add snippet" triggerId="snip-trigger" seed={seed} />
        <p className="small">Say the trigger and EsyType inserts the text exactly as written, line breaks included. Works in Clean and Verbatim. {"{date}"}, {"{time}"} and {"{day}"} are filled in when the snippet is used.</p>
      </section>
      <section className="panel">
        <ListHead title="Your snippets" count={loaded ? items.length : undefined}
          danger={<button className="btn sm danger" disabled={!items.length} onClick={async () => {
            if (!await ask({ title: "Delete all snippets?", body: "This can’t be undone. Export first if you may want them back.", action: `Delete all ${items.length}`, danger: true })) return;
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
                action={<button className="btn dark" onClick={() => focusField("snip-trigger")}>Add a snippet</button>} />
        ) : (
          <ul className="entries lrows" ref={list} onKeyDown={listArrows}>{shown.map((s) => <Row key={s.id} s={s} clash={clash(s)} onChange={load} deleting={deleting} />)}</ul>
        )}
        <p className="small">Import reads CSV (trigger, text and optionally mode) or JSON, and shows what it will do before anything changes. Exports go to your Downloads folder.</p>
      </section>
    </div>
  );
}
