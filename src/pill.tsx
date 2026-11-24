import { createRoot } from "react-dom/client";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

type State = "hidden" | "listening" | "recording" | "processing" | "inserting" | "done" | "error" | "unsure" | "copied" | "cleaned" | "undone";
const BARS = 32;
/** The status dot (Mac design: RecordingPill): red while listening, grey while working, green when typed, amber otherwise. */
const DOT: Record<State, string> = {
  hidden: "", listening: "rec", recording: "rec", processing: "busy", inserting: "busy", done: "ok", cleaned: "ok", undone: "ok", copied: "warn", error: "warn", unsure: "warn",
};

const Close = () => <svg width="12" height="12" viewBox="0 0 14 14" aria-hidden="true"><path d="M2 2l10 10M12 2L2 12" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" /></svg>;

function Pill() {
  const [state, setState] = useState<State>("hidden");
  const [message, setMessage] = useState("");
  const [levels, setLevels] = useState<number[]>(() => Array(BARS).fill(0));
  const [seconds, setSeconds] = useState(0);
  const [note, setNote] = useState("");
  const [undo, setUndo] = useState(false);
  const started = useRef(0);
  const capsule = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Frosted glass only while Windows' Transparency effects are on (as in the main window).
    invoke<boolean>("transparency_effects").then((on) => { document.documentElement.dataset.glass = on ? "on" : "off"; }).catch(() => {});
    const a = listen<{ state: State; message: string }>("pill", (e) => {
      setState(e.payload.state);
      setMessage(e.payload.message);
      if (e.payload.state === "listening") {
        setUndo(false);
        setLevels(Array(BARS).fill(0));
        setSeconds(0);
        setNote("");
      }
      if (e.payload.state === "recording") started.current = Date.now();
    });
    const b = listen<number>("level", (e) => setLevels((l) => [...l.slice(1), e.payload]));
    const c = listen<string>("note", (e) => setNote(e.payload));
    const d = listen<{ undo: boolean }>("actions", (e) => setUndo(e.payload.undo));
    return () => {
      a.then((f) => f());
      b.then((f) => f());
      c.then((f) => f());
      d.then((f) => f());
    };
  }, []);

  useEffect(() => {
    if (state !== "recording") return;
    const t = setInterval(() => setSeconds(Math.floor((Date.now() - started.current) / 1000)), 250);
    return () => clearInterval(t);
  }, [state]);

  // The window is exactly the pill's size, so the frosted glass is the pill: it follows the pill as it grows and shrinks.
  useLayoutEffect(() => {
    const el = capsule.current;
    if (!el) return;
    const send = () => invoke("pill_shape", { w: el.offsetWidth, h: el.offsetHeight }).catch(() => {}); // layout size: the entrance scale does not change it
    send();
    const ro = new ResizeObserver(send);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const recording = state === "recording" || state === "listening";
  const handsFree = state === "recording" && message === "hands-free";
  const label: Record<State, string> = {
    hidden: "", listening: "Listening…", recording: "", processing: "Transcribing…", inserting: "Typing…", done: message ? `Typed · ${message}` : "Typed", error: message,
    unsure: `Not typed: ${message}`, copied: "Copied. Press Ctrl+V to paste", cleaned: message ? `Typed · ${message}` : "Typed · cleaned", undone: message,
  };
  return (
    <div className="pill-wrap">
      <div ref={capsule} className={"pill" + (state === "error" || state === "unsure" ? " err" : "")} role="status" aria-live="polite">
        <span className={"pill-dot " + DOT[state]} aria-hidden="true" />
        {state === "recording" ? (
          <div className="bars" aria-hidden="true">
            {levels.map((l, i) => {
              const centre = 1 - Math.abs(i - BARS / 2) / (BARS / 2);
              return <i key={i} style={{ height: `${Math.max(2, Math.min(28, l * 28 * (0.45 + 0.55 * centre)))}px` }} />;
            })}
          </div>
        ) : (
          <div className="label" title={label[state]}>{label[state]}</div>
        )}
        {handsFree && <span className="pill-mode">Hands-free</span>}
        {note && state === "recording" && <span className="time" style={{ color: "var(--et-amber)" }} title={note} aria-label={note}>Default mic</span>}
        {state === "recording" && <span className="time">{Math.floor(seconds / 60)}:{String(seconds % 60).padStart(2, "0")}</span>}
        {state === "unsure" && <button className="copy" onClick={() => invoke("pill_copy")}>Copy</button>}
        {state === "cleaned" && (undo
          ? <button className="copy quiet" title="Replace the text with what you said, before Clean tidied it" onClick={() => invoke("pill_use_original")}>Use original</button>
          : <button className="copy quiet" title="Copy what you said before Clean mode tidied it" onClick={() => invoke("pill_original")}>Original</button>)}
        {(state === "done" || state === "cleaned") && undo && <button className="copy" title="Undo this dictation (Ctrl+Z in the app)" onClick={() => invoke("pill_undo")}>Undo</button>}
        {handsFree && (
          <button className="icon" title="Stop and type" aria-label="Stop" onClick={() => invoke("pill_stop")}>
            <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><rect x="1" y="1" width="10" height="10" rx="2.5" fill="currentColor" /></svg>
          </button>
        )}
        <button className="icon" title={recording ? "Cancel (Esc)" : "Close"} aria-label={recording ? "Cancel" : "Close"} onClick={() => invoke("pill_cancel")}><Close /></button>
      </div>
    </div>
  );
}

createRoot(document.getElementById("root")!).render(<Pill />);
