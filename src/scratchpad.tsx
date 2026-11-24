import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { PageTop } from "./hero";
import { ask, Banner, Empty, exported, Icon, ListHead, listArrows, NoMatch, SearchBox, SkeletonRows, toast, toastError } from "./ui";

/** "just now", "2 minutes ago", "3 hours ago", else the date. */
const ago = (ms: number) => { const m = Math.round((Date.now() - ms) / 60000); return m < 1 ? "just now" : m < 60 ? `${m} ${m === 1 ? "minute" : "minutes"} ago` : m < 1440 ? `${Math.round(m / 60)} ${Math.round(m / 60) === 1 ? "hour" : "hours"} ago` : new Date(ms).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }); };

type Summary = { id: number; title: string; words: number; updated_at: number };

/** True while the page is open; otherwise the main window answers "flush" itself (nothing unsaved). */
export let padOpen = false;

/** Notes save themselves: half a second after typing or dictating stops, and at once on switching note or tab,
 * hiding the window or quitting. */
export function ScratchpadPage({ available, dbError }: { available: boolean; dbError: string | null }) {
  const [list, setList] = useState<Summary[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [query, setQuery] = useState("");
  const [id, setId] = useState<number | null>(null);
  const [text, setText] = useState("");
  const [status, setStatus] = useState("");
  // the latest values, for saving from timers and event handlers
  const live = useRef({ id: null as number | null, text: "", dirty: false });
  const timer = useRef<number | undefined>(undefined);

  const refresh = useCallback(async () => {
    if (!available) return;
    try { setList(await invoke<Summary[]>("notes_list", { query })); setLoaded(true); } catch (e) { toastError(e); }
  }, [available, query]);

  const save = useCallback(async () => {
    window.clearTimeout(timer.current);
    const l = live.current;
    if (!l.dirty || !available) return;
    l.dirty = false;
    setStatus("Saving…");
    try {
      if (l.id === null) {
        if (!l.text.trim()) { setStatus(""); return; }
        l.id = await invoke<number>("note_create", { body: l.text });
        setId(l.id);
      } else {
        await invoke("note_save", { id: l.id, body: l.text });
      }
      setStatus("Saved");
      refresh();
    } catch (e) {
      l.dirty = true;
      setStatus(`Not saved: ${String(e)} Your text is still here; use Copy all to keep it.`);
    }
  }, [available, refresh]);

  useEffect(() => { refresh(); }, [refresh]);
  useEffect(() => {
    const flush = () => { save(); };
    const hidden = () => { if (document.visibilityState === "hidden") save(); };
    padOpen = true;
    document.addEventListener("visibilitychange", hidden);
    window.addEventListener("blur", flush);
    const off = listen("flush", async () => { await save(); invoke("flushed"); });
    return () => {
      document.removeEventListener("visibilitychange", hidden);
      window.removeEventListener("blur", flush);
      off.then((f) => f());
      padOpen = false;
      save(); // leaving the tab
    };
  }, [save]);

  const edit = (t: string) => {
    setText(t);
    live.current.text = t;
    live.current.dirty = true;
    setStatus("");
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(save, 500);
  };
  const open = async (n: number) => {
    await save();
    try {
      const body = await invoke<string>("note_get", { id: n });
      live.current = { id: n, text: body, dirty: false };
      setId(n); setText(body); setStatus("Saved");
    } catch (e) { toastError(e); }
  };
  const fresh = async () => {
    await save();
    live.current = { id: null, text: "", dirty: false };
    setId(null); setText(""); setStatus("");
    document.getElementById("note-text")?.focus();
  };
  const remove = async () => {
    if (id === null) return fresh();
    if (!await ask({ title: "Delete this note?", body: "This can’t be undone.", action: "Delete", danger: true })) return;
    try {
      await invoke("note_delete", { id }); live.current = { id: null, text: "", dirty: false }; setId(null); setText(""); setStatus(""); refresh();
      toast("Note deleted."); document.getElementById("note-text")?.focus();
    } catch (e) { toastError(e); }
  };
  const words = text.split(/\s+/).filter(Boolean).length;

  return (
    <div className="stack">
    <PageTop id="scratchpad" title="Scratchpad" hero={{ headline: ["Think out ", "loud", "."], glow: "var(--et-glow-scratchpad)",
      message: "Notes that save themselves as you write or dictate. Click in a note, hold your shortcut and speak: the text goes in at the cursor.",
      actions: <><button className="hero-btn" onClick={fresh}>New note</button>{words > 0 && <span className="hero-chip">{words.toLocaleString()} {words === 1 ? "word" : "words"} in this note</span>}</> }} />
    <div className="pad">
      <section className="panel pad-list">
        <button className="btn dark" onClick={fresh}>New note</button>
        <ListHead title="Notes" count={available && loaded ? list.length : undefined}
          danger={<button className="btn sm danger" aria-label="Delete all notes" disabled={!list.length} onClick={async () => {
            if (!await ask({ title: "Delete all notes?", body: "This can’t be undone. Export any you want to keep first.", action: "Delete all notes", danger: true })) return;
            try { await invoke("notes_clear"); live.current = { id: null, text: "", dirty: false }; setId(null); setText(""); refresh(); toast("All notes deleted."); } catch (e) { toastError(e); }
          }}>Delete all</button>} />
        <SearchBox label="Search notes" placeholder="Search notes" value={query} onChange={setQuery} />
        {!available && <Banner tone="red">Notes cannot be saved{dbError ? `: ${dbError}` : "."} You can still write here and use Copy all.</Banner>}
        {available && !loaded ? <SkeletonRows /> : list.length === 0 ? (
          query ? <NoMatch query={query} clear={() => setQuery("")} />
            : available && <Empty icon="scratchpad" title="No notes yet" text="Write or dictate; notes save as you go." action={<button className="btn primary" onClick={fresh}>New note</button>} />
        ) : (
          <ul className="entries" aria-label="Notes" onKeyDown={listArrows}>
            {list.map((n) => (
              <li key={n.id}>
                <button className={"note" + (n.id === id ? " on" : "")} aria-current={n.id === id ? "true" : undefined} onClick={() => open(n.id)}>
                  <span className="note-title">{n.title}</span>
                  <span className="small" title={new Date(n.updated_at).toLocaleString()}>{ago(n.updated_at)} · {n.words} {n.words === 1 ? "word" : "words"}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
      <section className="panel pad-editor">
        <textarea id="note-text" aria-label="Note" value={text} onChange={(e) => edit(e.target.value)} onBlur={() => save()}
          placeholder="Write or dictate here. Hold your shortcut and speak: the text goes in at the cursor." maxLength={100000} />
        <div className="row" style={{ justifyContent: "space-between" }}>
          <span className="small" role="status">{words} {words === 1 ? "word" : "words"}{status ? ` · ${status}` : ""}</span>
          <span className="row">
            <button className="btn sm tool" disabled={!text} onClick={async () => { try { await invoke("copy_text", { text }); toast("Copied."); } catch (e) { toastError(e); } }}><Icon name="copy" size={14} />Copy all</button>
            <button className="btn sm tool" aria-label="Export .txt" disabled={id === null} onClick={async () => { await save(); try { exported(await invoke<string>("note_export", { id, format: "txt" })); } catch (e) { toastError(e); } }}><Icon name="export" size={14} />.txt</button>
            <button className="btn sm tool" aria-label="Export .md" disabled={id === null} onClick={async () => { await save(); try { exported(await invoke<string>("note_export", { id, format: "md" })); } catch (e) { toastError(e); } }}><Icon name="export" size={14} />.md</button>
            <button className="btn sm danger" disabled={id === null && !text} onClick={remove}>Delete</button>
          </span>
        </div>
      </section>
    </div>
    <p className="small">Notes stay on this PC until you delete them; History’s settings never touch them.</p>
    </div>
  );
}
