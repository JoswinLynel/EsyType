import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Banner, Empty, focusField, ListHead, listArrows, NoMatch, SearchBox, toast, useRefocus } from "./ui";

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

export function StylePage({ settings, save, cleanOn }: { settings: StyleSettings; save: (p: Partial<StyleSettings>) => Promise<void>; cleanOn: boolean }) {
  const [examples, setExamples] = useState<Record<string, string>>({});
  const [tryText, setTryText] = useState("");
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

  return (
    <>
      {!cleanOn && <Banner tone="amber">Styles apply in Clean mode. You are using Verbatim, so text goes in exactly as heard.</Banner>}
      <section className="panel">
        <h2>Styles</h2>
        <p className="small">EsyType finishes your text in the style set for the app you are dictating into. Rules change spellings, contractions, stock phrases and punctuation; they do not change tone or rewrite sentences.</p>
        <div className="cards styles">
          {STYLES.map((s) => (
            <div key={s.id} className="card">
              <span className="name">{s.name}</span>
              <span className="small">{s.what}</span>
              <span className="example">{examples[s.id] ?? ""}</span>
            </div>
          ))}
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
        <SearchBox label="Search app rules" placeholder="Search programs" value={query} onChange={setQuery} />
        {shown.length === 0 ? (
          query ? <NoMatch query={query} clear={() => setQuery("")} />
            : <Empty icon="style" title="No app rules yet" text={`Every app uses ${name(settings.style_default)}.`}
                action={<button className="btn primary" onClick={() => focusField("style-app")}>Add a rule</button>} />
        ) : (
          <ul className="entries" ref={list} onKeyDown={listArrows}>
            {shown.map((r) => (
              <li key={r.app} className="entry">
                <div className="row" style={{ justifyContent: "space-between" }}>
                  <b>{r.app}</b>
                  <span className="row">
                    <select aria-label={`Style for ${r.app}`} value={r.style} onChange={(e) => save({ style_rules: rules.map((x) => x.app === r.app ? { ...x, style: e.target.value } : x) })}>
                      {STYLES.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                    </select>
                    <button className="btn sm" onClick={async () => { deleting(); await save({ style_rules: rules.filter((x) => x.app !== r.app) }); toast(`Deleted the rule for ${r.app}.`); }}>Delete</button>
                  </span>
                </div>
              </li>
            ))}
          </ul>
        )}
        <div className="row" style={{ marginTop: 12 }}>
          <label className="field" style={{ flex: 1 }}>
            <span>Program</span>
            <input id="style-app" type="text" aria-label="Program" list="recent-apps" value={app} onChange={(e) => setApp(e.target.value)} placeholder="slack.exe" onKeyDown={(e) => e.key === "Enter" && addRule()} />
            <datalist id="recent-apps">{recent.map((a) => <option key={a} value={a} />)}</datalist>
          </label>
          <label className="field">
            <span>Style</span>
            <select aria-label="Style for new program" value={appStyle} onChange={(e) => setAppStyle(e.target.value)}>
              {STYLES.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          <button className="btn primary" style={{ alignSelf: "end" }} disabled={!app.trim()} onClick={addRule}>Add rule</button>
        </div>
        <p className="small">Programs are recognised by their file name only (as in History), never by window titles, so a browser has one style for every website.{recent.length ? " Suggestions come from programs in your History." : ""}</p>
      </section>

      <section className="panel">
        <h2>Custom style</h2>
        {([
          ["written_forms", "Write out spoken forms (\"gonna\" → \"going to\", \"yeah\" → \"yes\")"],
          ["expand_contractions", "Expand contractions with one meaning (\"don't\" → \"do not\")"],
          ["shorten_phrases", "Shorten stock phrases (\"in order to\" → \"to\")"],
          ["drop_hedges", "Drop \"basically\", \"actually\", \"literally\", \"honestly\" when set off by commas"],
        ] as const).map(([k, label]) => (
          <label key={k} className="row" style={{ marginTop: 8 }}>
            <input type="checkbox" checked={custom[k]} onChange={(e) => setCustom({ [k]: e.target.checked })} />
            <span>{label}</span>
          </label>
        ))}
        <label className="field" style={{ marginTop: 12, maxWidth: 360 }}>
          <span>Full stop at the end</span>
          <select value={custom.final_stop} onChange={(e) => setCustom({ final_stop: e.target.value as CustomStyle["final_stop"] })}>
            <option value="keep">As spoken</option>
            <option value="always">Always</option>
            <option value="never">Not on one-sentence messages</option>
          </select>
        </label>
      </section>

      <section className="panel">
        <h2>Try it</h2>
        <textarea aria-label="Try a sentence" value={tryText} onChange={(e) => setTryText(e.target.value)} placeholder="Type or paste a sentence to see it in each style." />
        {Object.keys(tried).length > 0 && (
          <dl className="tried">
            {STYLES.map((s) => <div key={s.id}><dt>{s.name}</dt><dd>{tried[s.id]}</dd></div>)}
          </dl>
        )}
      </section>
    </>
  );
}


