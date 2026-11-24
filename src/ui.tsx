// Shared pieces of the window (design system section 8): icons, the confirmation dialog, toasts, banners and empty
// states. No libraries: the icons are drawn here in the design system's line style.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";

const PATHS: Record<string, ReactNode> = {
  dictation: <><rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5 11a7 7 0 0 0 14 0M12 18v3" /></>,
  history: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
  dictionary: <><path d="M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5z" /><path d="M5 19.5A1.5 1.5 0 0 0 6.5 21H19M9 7.5h6" /></>,
  snippets: <><rect x="4" y="4" width="16" height="16" rx="3" /><path d="M8 9h8M8 13h8M8 17h5" /></>,
  style: <><path d="M4 20l4-1 11-11-3-3L5 16z" /><path d="M14 6l3 3" /></>,
  scratchpad: <><path d="M6 3h8l5 5v13H6z" /><path d="M14 3v5h5M9 13h6M9 17h4" /></>,
  settings: <><circle cx="12" cy="12" r="3" /><path d="M12 2.5l1.6 2.6 3-.6.9 2.9 2.8 1.2-.9 2.9 1.6 2.5-2.5 1.7.1 3-3 .4-1.4 2.7L12 20.6l-2.7 1.1-1.5-2.7-3-.3.1-3.1-2.4-1.7 1.6-2.5-.9-2.9 2.8-1.2.9-2.9 3 .6z" /></>,
  meet: <><circle cx="9" cy="8" r="3" /><path d="M3.5 19a5.5 5.5 0 0 1 11 0" /><path d="M17 7.5a3.5 3.5 0 0 1 0 5M19.5 5a7 7 0 0 1 0 10" /></>,
  insights: <><path d="M4 20h16" /><rect x="5.5" y="11" width="3" height="6" rx="1" /><rect x="10.5" y="6" width="3" height="11" rx="1" /><rect x="15.5" y="9" width="3" height="8" rx="1" /></>,
  alert: <><path d="M12 3.5l9 16H3z" /><path d="M12 10v4M12 17v.01" /></>,
  info: <><circle cx="12" cy="12" r="9" /><path d="M12 11v5M12 8v.01" /></>,
  check: <path d="M5 12.5l4.5 4.5L19 7.5" />,
  close: <path d="M6 6l12 12M18 6L6 18" />,
  folder: <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />,
  search: <><circle cx="11" cy="11" r="6.5" /><path d="M16 16l4.5 4.5" /></>,
  lock: <><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></>,
};
export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  return (
    <svg className="icon" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">{PATHS[name]}</svg>
  );
}

// ---------- what the window remembers between launches ----------

let memory: Record<string, string> = {};
/** Loads the remembered values (last page, Settings section, folded banners) from EsyType's data folder. */
export async function loadMemory() { memory = await invoke<Record<string, string>>("ui_state").catch(() => ({})); }
export const remembered = (key: string): string | null => memory[key] ?? null;
/** A convenience only: if it cannot be saved, the window simply opens as new next time. */
export function remember(key: string, value: string) { memory[key] = value; invoke("ui_remember", { key, value }).catch(() => {}); }

// ---------- confirmation dialog ----------

/** `list`: lines shown as a list under the body. `check`: a tick box; its `value` is updated in place, so the caller reads it after the dialog closes. */
type Ask = { title: string; body?: string; list?: string[]; check?: { label: string; value: boolean }; action: string; danger?: boolean };
type Open = Ask & { resolve: (ok: boolean) => void };
let openDialog: ((d: Open) => void) | null = null;

/** Asks before something that cannot be undone. Resolves true only for the action button. */
export function ask(a: Ask): Promise<boolean> {
  return new Promise((resolve) => (openDialog ? openDialog({ ...a, resolve }) : resolve(false)));
}

/** True while a dialog is open: the rest of the window is then inert (not reachable by keyboard or screen reader). */
export function useDialogOpen() {
  const [open, setOpen] = useState(false);
  useEffect(() => { const f = (e: Event) => setOpen((e as CustomEvent<boolean>).detail); window.addEventListener("et-dialog", f); return () => window.removeEventListener("et-dialog", f); }, []);
  return open;
}

export function DialogHost() {
  const [d, setD] = useState<Open | null>(null);
  const cancel = useRef<HTMLButtonElement>(null);
  const action = useRef<HTMLButtonElement>(null);
  const before = useRef<HTMLElement | null>(null);
  const finish = useRef<(d: Open, ok: boolean) => void>(() => {});
  useEffect(() => {
    openDialog = (x) => { before.current = document.activeElement as HTMLElement | null; setD(x); };
    // Closing: focus goes back to where it was before anything else runs, so the caller sees it there. The window is
    // still inert until React catches up, and an inert element cannot take focus, so that is lifted first.
    finish.current = (x, ok) => {
      setD(null);
      const el = before.current;
      el?.closest("[inert]")?.removeAttribute("inert");
      el?.focus?.();
      x.resolve(ok);
    };
    return () => { openDialog = null; };
  }, []);
  useEffect(() => {
    window.dispatchEvent(new CustomEvent("et-dialog", { detail: d !== null }));
    if (!d) return;
    (d.danger ? cancel : action).current?.focus(); // a destructive action is never the default
    // Esc cancels wherever focus is (it can land outside the dialog when the window is brought back to the front).
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") { e.preventDefault(); finish.current(d, false); } };
    window.addEventListener("keydown", esc);
    return () => window.removeEventListener("keydown", esc);
  }, [d]);
  if (!d) return null;
  const close = (ok: boolean) => finish.current(d, ok);
  return (
    <div className="scrim" onMouseDown={(e) => e.target === e.currentTarget && close(false)}>
      <div className="dialog" role="dialog" aria-modal="true" aria-labelledby="dialog-title" aria-describedby={d.body ? "dialog-body" : undefined}
        onKeyDown={(e) => {
          if (e.key === "Tab") { // keep focus inside the dialog
            e.preventDefault();
            const items = Array.from(e.currentTarget.querySelectorAll<HTMLElement>("input, button"));
            const at = items.indexOf(document.activeElement as HTMLElement);
            items[(at + (e.shiftKey ? items.length - 1 : 1)) % items.length]?.focus();
          }
        }}>
        <h2 id="dialog-title">{d.title}</h2>
        {d.body && <p id="dialog-body" className="small">{d.body}</p>}
        {d.list && <ul className="dialog-list small">{d.list.map((x, i) => <li key={i}>{x}</li>)}</ul>}
        {d.check && <DialogCheck c={d.check} />}
        <div className="row dialog-actions">
          <button ref={cancel} className="btn" onClick={() => close(false)}>Cancel</button>
          <button ref={action} className={"btn " + (d.danger ? "danger-fill" : "primary")} onClick={() => close(true)}>{d.action}</button>
        </div>
      </div>
    </div>
  );
}

function DialogCheck({ c }: { c: NonNullable<Ask["check"]> }) {
  const [on, setOn] = useState(c.value);
  return (
    <label className="row" style={{ marginBottom: 12 }}>
      <input type="checkbox" checked={on} onChange={(e) => { c.value = e.target.checked; setOn(e.target.checked); }} />
      <span>{c.label}</span>
    </label>
  );
}

// ---------- toasts ----------

type Toast = { id: number; text: string; tone: "ok" | "error"; action?: { label: string; run: () => void } };
let pushToast: ((t: Omit<Toast, "id">) => void) | null = null;

/** A short message at the bottom of the window (6 s; errors 10 s), announced to screen readers. */
export function toast(text: string, action?: Toast["action"]) { pushToast?.({ text, tone: "ok", action }); }
export function toastError(e: unknown) { pushToast?.({ text: String(e), tone: "error" }); }
/** "Saved <file> in Downloads" with Show in folder, after an export. */
export function exported(path: string) {
  const file = path.split(/[\\/]/).pop();
  toast(`Saved ${file} in your Downloads folder.`, { label: "Show in folder", run: () => { invoke("show_in_folder", { path }).catch(toastError); } });
}

export function ToastHost() {
  const [list, setList] = useState<Toast[]>([]);
  useEffect(() => {
    let n = 0;
    pushToast = (t) => {
      const id = ++n;
      setList((l) => [...l.slice(-2), { ...t, id }]);
      window.setTimeout(() => setList((l) => l.filter((x) => x.id !== id)), t.tone === "error" ? 10000 : 6000);
    };
    return () => { pushToast = null; };
  }, []);
  return (
    <div className="toasts" role="status" aria-live="polite">
      {list.map((t) => (
        <div key={t.id} className={"toast " + t.tone}>
          <Icon name={t.tone === "error" ? "alert" : "check"} size={16} />
          <span>{t.text}</span>
          {t.action && <button className="btn sm" onClick={t.action.run}>{t.action.label}</button>}
          <button className="toast-close" aria-label="Dismiss" onClick={() => setList((l) => l.filter((x) => x.id !== t.id))}><Icon name="close" size={14} /></button>
        </div>
      ))}
    </div>
  );
}

// ---------- banners and empty states ----------

/** A lasting message in the page: red for something that does not work, amber for something to know. */
export function Banner({ tone, children, action }: { tone: "red" | "amber"; children: ReactNode; action?: ReactNode }) {
  return (
    <div className={"banner " + tone} role={tone === "red" ? "alert" : "status"}>
      <Icon name="alert" size={18} />
      <div className="banner-text">{children}</div>
      {action}
    </div>
  );
}

// ---------- lists: heading, search, loading, no match, keyboard ----------

/** A list's heading with its count, the page's actions on the right, and the red Delete all last. */
export function ListHead({ title, count, children, danger }: { title: string; count?: number; children?: ReactNode; danger?: ReactNode }) {
  return (
    <div className="list-head">
      <h2>{count === undefined ? title : `${title} (${count})`}</h2>
      <div className="row">{children}{danger && <span className="list-danger">{danger}</span>}</div>
    </div>
  );
}

/** Search box with a clear button; Esc clears it. `label` is its accessible name (the test suites use it). */
export function SearchBox({ label, placeholder, value, onChange }: { label: string; placeholder: string; value: string; onChange: (v: string) => void }) {
  return (
    <div className="search">
      <Icon name="search" size={16} />
      <input type="text" placeholder={placeholder} aria-label={label} value={value} onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Escape" && value) { e.preventDefault(); e.stopPropagation(); onChange(""); } }} />
      {value && <button className="search-clear" aria-label="Clear search" title="Clear search" onClick={() => onChange("")}><Icon name="close" size={14} /></button>}
    </div>
  );
}

export function NoMatch({ query, clear }: { query: string; clear: () => void }) {
  return (
    <div className="nomatch">
      <span className="small">{`Nothing matches "${query}".`}</span>
      <button className="btn sm" onClick={clear}>Clear search</button>
    </div>
  );
}

/** Shown until a list's first answer arrives, so an empty state never flashes up before the items. */
export function SkeletonRows() {
  return (
    <div aria-busy="true">
      {[0, 1, 2].map((i) => <div key={i} className="skel" style={{ height: 56 }} />)}
      <span className="sr-only">Loading…</span>
    </div>
  );
}

const FOCUSABLE = "button:not(:disabled), summary, a[href], select";

/** On a list: Up and Down move to the same button on the next or previous row (else its first). Text boxes keep their arrows. */
export function listArrows(e: React.KeyboardEvent<HTMLElement>) {
  if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
  const t = e.target as HTMLElement;
  if (t.matches("input, textarea, select") || t.closest(".snippet-editor")) return;
  const rows = Array.from(e.currentTarget.children) as HTMLElement[];
  const at = rows.findIndex((r) => r.contains(t));
  const next = rows[at + (e.key === "ArrowDown" ? 1 : -1)];
  if (at < 0 || !next) return;
  e.preventDefault();
  const items = Array.from(next.querySelectorAll<HTMLElement>(FOCUSABLE));
  (items.find((x) => x.textContent === t.textContent) ?? items[0])?.focus();
}

/** Keeps the keyboard in the list after a row is deleted. Call `deleting()` from the row's Delete (focus is on that
 * button then); once the list has changed, focus goes to the row now in its place, the one before, or the page's
 * empty or no-match button. */
export function useRefocus(items: unknown) {
  const list = useRef<HTMLUListElement>(null);
  const pending = useRef<{ at: number; rows: number } | null>(null);
  useEffect(() => {
    const rows = Array.from(list.current?.children ?? []) as HTMLElement[];
    if (!pending.current || rows.length === pending.current.rows) return; // other re-renders: wait for the row to go
    const i = pending.current.at;
    pending.current = null;
    const row = rows[i] ?? rows[i - 1];
    (row?.querySelector<HTMLElement>(FOCUSABLE) ?? document.querySelector<HTMLElement>(".empty button, .nomatch button"))?.focus();
  }, [items]);
  const deleting = () => {
    const rows = Array.from(list.current?.children ?? []);
    const at = rows.findIndex((r) => r.contains(document.activeElement));
    pending.current = at < 0 ? null : { at, rows: rows.length };
  };
  return { list, deleting };
}

/** Puts the cursor in a field by id, after the page has had a moment to show it. */
export function focusField(id: string) {
  setTimeout(() => { const el = document.getElementById(id) as HTMLInputElement | null; el?.focus(); el?.scrollIntoView({ block: "center" }); }, 50);
}

export function Empty({ icon, title, text, action }: { icon: IconName; title: string; text: string; action?: ReactNode }) {
  return (
    <div className="empty">
      <span className="well"><Icon name={icon} size={22} /></span>
      <p className="empty-title">{title}</p>
      <p className="small">{text}</p>
      {action}
    </div>
  );
}
