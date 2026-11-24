import { useEffect, useState, type ReactNode } from "react";
import { PageTop } from "./hero";
import { invoke } from "@tauri-apps/api/core";
import { Banner, Empty, focusField, Icon, ListHead, listArrows, NoMatch, SearchBox, Switch, toast, useRefocus } from "./ui";

export type StyleRule = { app: string; style: string };
export type CustomStyle = { written_forms: boolean; expand_contractions: boolean; shorten_phrases: boolean; drop_hedges: boolean; final_stop: "keep" | "always" | "never" };
export type StyleSettings = { style_default: string; style_rules: StyleRule[]; style_custom: CustomStyle };

const STYLES: { id: string; name: string; what: string }[] = [
  { id: "standard", name: "Standard", what: "Nothing beyond Clean." },
  { id: "professional", name: "Professional", what: "Spoken forms written out (\"gonna\" → \"going to\", \"yeah\" → \"yes\"); ends with a full stop." },
  { id: "formal", name: "Formal", what: "Professional, plus contractions with one meaning expanded (\"don't\" → \"do not\")." },
  { id: "casual", name: "Casual", what: "No full stop at the end of a one-sentence message, as in chat." },
  { id: "concise", name: "Concise", what: "Stock phrases shortened (\"in order to\" → \"to\"); \"basically,\" and similar dropped." },
  { id: "custom", name: "Custom", what: "Your own choice of the switches below." },
];
const EXAMPLE = "yeah I'm gonna send it tomorrow in order to check, basically.";
const name = (id: string) => STYLES.find((s) => s.id === id)?.name ?? id;

export function StylePage({ settings, save, cleanOn, top, clean }: { settings: StyleSettings; save: (p: Partial<StyleSettings>) => Promise<void>; cleanOn: boolean; top?: ReactNode; clean?: ReactNode }) {
  const [examples, setExamples] = useState<Record<string, string>>({});
  const [tryText, setTryText] = useState(EXAMPLE);
  const [tried, setTried] = useState<Record<string, string>>({});
  const [app, setApp] = useState("");
  const [appStyle, setAppStyle] = useState("professional");
  const [recent, setRecent] = useState<string[]>([]);
  const [query, setQuery] = useState("");

  useEffect(() => { invoke<Record<string, string>>("style_preview", { text: EXAMPLE }).then(setExamples); }, [settings.style_custom]);
  useEffect(() => { invoke<string[]>("recent_apps").then(setRecent).catch(() => setRecent([])); }, []);
  useEffect(() => {
    if (!tryText.trim()) { setTried({}); return; }
    const t = setTimeout(() => invoke<Record<string, string>>("style_preview", { text: tryText }).then(setTried), 250);
    return () => clearTimeout(t);
  }, [tryText, settings.style_custom]);

  const rules = settings.style_rules;
  const shown = rules.filter((r) => !query || r.app.toLowerCase().includes(query.toLowerCase()));
  const { list, deleting } = useRefocus(shown);
  const addRule = async () => {
    const a = app.trim();
    if (!a) return;
    await save({ style_rules: [...rules.filter((r) => r.app.toLowerCase() !== a.toLowerCase()), { app: a, style: appStyle }] });
    setApp("");
  };
  const custom = settings.style_custom;
  const setCustom = (p: Partial<CustomStyle>) => save({ style_custom: { ...custom, ...p } });
  const uses = (id: string) => rules.filter((r) => r.style === id).length;

  return (
    <div className="stack">
      <PageTop id="style" title="Style" hero={{ headline: ["Write like ", "you", ", in every app."], glow: "var(--et-mark-amber)",
        message: "EsyType finishes your words in the style you set for each app: written-out forms for email, chat-style for messages. It never changes your tone or rewrites sentences.",
        actions: <>{(["professional", "casual", "concise"] as const).map((id) => (
          <button key={id} className="hero-chip act" aria-pressed={settings.style_default === id} title={`Use ${name(id)} for other apps`} onClick={() => save({ style_default: id })}>{name(id)}</button>
        ))}</> }} />
      {top}
      {!cleanOn && <Banner tone="amber">Styles apply in Clean mode. You are using Verbatim, so text goes in exactly as heard.</Banner>}
      <section className="panel">
        <h2>Styles</h2>
        <p className="small">Click a style to use it for every app without its own rule. Examples show the same sentence in each style.</p>
        <div className="style-grid" role="radiogroup" aria-label="Style for other apps (cards)">
          {STYLES.map((s) => {
            const on = settings.style_default === s.id;
            return (
              <button key={s.id} role="radio" aria-checked={on} className={"style-card" + (on ? " on" : "")} onClick={() => save({ style_default: s.id })}>
                <span className="style-name">{s.name}{on ? <span className="tag">Other apps</span> : uses(s.id) ? <span className="tag quiet">{uses(s.id)} {uses(s.id) === 1 ? "app" : "apps"}</span> : null}</span>
                <span className="small">{s.what}</span>
                <span className="example">{examples[s.id] ?? ""}</span>
              </button>
            );
          })}
        </div>
        <label className="field" style={{ marginTop: 16, maxWidth: 360 }}>
          <span>Style for other apps</span>
          <select value={settings.style_default} onChange={(e) => save({ style_default: e.target.value })}>
            {STYLES.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
      </section>

      <section className="panel">
        <ListHead title="Apps" count={rules.length} />
        <SearchBox label="Search app rules" placeholder="Search apps" value={query} onChange={setQuery} />
        {shown.length === 0 ? (
          query ? <NoMatch query={query} clear={() => setQuery("")} />
            : <Empty icon="style" title="No app rules yet" text={`Every app uses ${name(settings.style_default)}.`}
                action={<button className="btn dark" onClick={() => focusField("style-app")}>Add a rule</button>} />
        ) : (
          <ul className="entries lrows" ref={list} onKeyDown={listArrows}>
            {shown.map((r) => (
              <li key={r.app} className="lrow">
                <span className="ltile app" aria-hidden="true">{r.app.replace(/\.exe$/i, "").slice(0, 1).toUpperCase()}</span>
                <div className="lmain"><span className="lwords"><b>{r.app}</b></span></div>
                <select aria-label={`Style for ${r.app}`} value={r.style} onChange={(e) => save({ style_rules: rules.map((x) => x.app === r.app ? { ...x, style: e.target.value } : x) })}>
                  {STYLES.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
                <button className="icon-btn danger" aria-label="Delete" title={`Delete the rule for ${r.app}`} onClick={async () => { deleting(); await save({ style_rules: rules.filter((x) => x.app !== r.app) }); toast(`Deleted the rule for ${r.app}.`); }}>
                  <Icon name="trash" size={14} />
                </button>
              </li>
            ))}
          </ul>
        )}
        <div className="row add-row" style={{ marginTop: 12 }}>
          <label className="field" style={{ flex: 1 }}>
            <span>App</span>
            <input id="style-app" type="text" aria-label="Program" list="recent-apps" value={app} onChange={(e) => setApp(e.target.value)} placeholder="Choose or type an app, such as slack.exe" onKeyDown={(e) => e.key === "Enter" && addRule()} />
            <datalist id="recent-apps">{recent.map((a) => <option key={a} value={a} />)}</datalist>
          </label>
          <label className="field">
            <span>Style</span>
            <select aria-label="Style for new program" value={appStyle} onChange={(e) => setAppStyle(e.target.value)}>
              {STYLES.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          <button className="btn primary" disabled={!app.trim()} onClick={addRule}>Add rule</button>
        </div>
        <p className="small">Apps are recognised by their file name only (as in History), never by window titles, so a browser has one style for every website.{recent.length ? " Suggestions come from apps in your History." : ""}</p>
      </section>

      <section className="panel">
        <h2>Custom style</h2>
        {([
          ["written_forms", "Write out spoken forms", "“gonna” → “going to”, “yeah” → “yes”"],
          ["expand_contractions", "Expand contractions with one meaning", "“don’t” → “do not”"],
          ["shorten_phrases", "Shorten stock phrases", "“in order to” → “to”"],
          ["drop_hedges", "Drop basically, actually, literally, honestly", "when set off by commas"],
        ] as const).map(([k, title, detail]) => (
          <div key={k} className="switch-row">
            <span><span className="switch-title">{title}</span><span className="small">{detail}</span></span>
            <Switch on={custom[k]} set={(on) => setCustom({ [k]: on })} label={`${title} (${detail})`} />
          </div>
        ))}
        <span className="field-label">Full stop at the end</span>
        <div className="seg" role="group" aria-label="Full stop at the end">
          {([["keep", "As spoken"], ["always", "Always"], ["never", "Never"]] as const).map(([v, label]) => (
            <button key={v} className={custom.final_stop === v ? "on" : ""} aria-pressed={custom.final_stop === v} title={v === "never" ? "Not on one-sentence messages" : undefined} onClick={() => setCustom({ final_stop: v })}>{label}</button>
          ))}
        </div>
      </section>

      {clean}

      <section className="panel">
        <h2>Try it</h2>
        <textarea className="try-box" aria-label="Try a sentence" value={tryText} onChange={(e) => setTryText(e.target.value)} placeholder="Type or paste a sentence to see it in each style." />
        {Object.keys(tried).length > 0 && (
          <div className="try-grid">
            {STYLES.map((s) => <div key={s.id} className="try-card"><span className="field-label">{s.name}</span><span>{tried[s.id]}</span></div>)}
          </div>
        )}
      </section>
    </div>
  );
}
