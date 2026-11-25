import { createRoot } from "react-dom/client";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

/** EsyMeet's "Meeting detected" prompt (plan 8.2): a capsule at the top of the screen, like the recording pill. It never
 *  takes the keyboard and never records by itself; Start transcription starts the meeting session. */
function Prompt() {
  const [app, setApp] = useState("");
  const capsule = useRef<HTMLDivElement>(null);

  useEffect(() => {
    invoke<boolean>("transparency_effects").then((on) => { document.documentElement.dataset.glass = on ? "on" : "off"; }).catch(() => {});
    const a = listen<{ app: string | null }>("prompt", (e) => setApp(e.payload.app ?? ""));
    return () => { a.then((f) => f()); };
  }, []);

  // The window is exactly the capsule's size and follows it.
  useLayoutEffect(() => {
    const el = capsule.current;
    if (!el) return;
    const send = () => invoke("prompt_shape", { w: el.offsetWidth, h: el.offsetHeight }).catch(() => {});
    send();
    const ro = new ResizeObserver(send);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div className="pill-wrap">
      <div ref={capsule} className="pill meet-prompt" role="status" aria-live="polite" aria-label={app ? `Meeting detected: ${app}` : undefined}>
        <span className="meet-icon" aria-hidden="true">
          <svg width="16" height="16" viewBox="0 0 20 20"><circle cx="7" cy="6.5" r="3" fill="none" stroke="currentColor" strokeWidth="1.6" /><path d="M1.8 17c.6-3.2 2.7-5 5.2-5s4.6 1.8 5.2 5" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" /><path d="M14 5.2c1 .9 1.5 2 1.5 3.3s-.5 2.4-1.5 3.3M16.4 3c1.6 1.5 2.4 3.4 2.4 5.5s-.8 4-2.4 5.5" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" /></svg>
        </span>
        <span className="meet-text">
          <span className="meet-title">Meeting detected · {app}</span>
          <span className="meet-note">Let people know you're transcribing.</span>
        </span>
        <button className="copy" onClick={() => invoke("meet_answer", { start: true })}>Start transcription</button>
        <button className="copy quiet" onClick={() => invoke("meet_answer", { start: false })}>Not now</button>
      </div>
    </div>
  );
}

createRoot(document.getElementById("root")!).render(<Prompt />);
