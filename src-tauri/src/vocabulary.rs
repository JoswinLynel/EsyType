//! Built-in product, brand and technology names (docs/plans/recognition-accuracy-plan.md, Proposal A).
//!
//! Corrections for what Whisper writes instead of a product name, of two kinds only:
//! - a form that is not an English word ("Superbase", "chat GPT", "N8N", "github"), or
//! - a phrase whose context makes the product certain ("Microsoft co-pilot", "power automate").
//! Names that are also ordinary words (Claude, Gemini, Notion, Python, Excel, React, Teams, Canva, Word, Make) and
//! spaced forms made of two ordinary words ("word press", "power point", "air table") are never listed: a rule would
//! change ordinary sentences. Measured on 22 Nov: product names 59% -> 81% right, ordinary sentences unchanged.
//!
//! Applied by the Dictionary matcher after the user's own entries (theirs win), never stored, exported or deleted.
use crate::dictionary::Entry;

/// What Whisper writes (any case; variants separated by "|"; spaces stand for spaces, hyphens or a dot) -> written.
const LIST: &[(&str, &str)] = &[
    ("chat gpt|chatgpt|chat g p t|chat gbt|chat g b t", "ChatGPT"),
    ("openai", "OpenAI"),
    ("supabase|superbase|supbase|supa base", "Supabase"),
    ("firebase", "Firebase"),
    ("vercel|versal", "Vercel"),
    ("microsoft co pilot|microsoft copilot", "Microsoft Copilot"),
    ("github copilot|github co pilot|git hub co pilot", "GitHub Copilot"),
    ("github|git hub", "GitHub"),
    ("gitlab|git lab", "GitLab"),
    ("n8n", "n8n"),
    ("node js|nodejs", "Node.js"),
    ("next js|nextjs", "Next.js"),
    ("make com", "Make.com"),
    ("airtable", "Airtable"),
    ("postgresql|postgres ql|postgres q l|postgre sql", "PostgreSQL"),
    ("power automate", "Power Automate"),
    ("power bi|powerbi", "Power BI"),
    ("javascript", "JavaScript"),
    ("typescript", "TypeScript"),
    ("wordpress", "WordPress"),
    ("whatsapp|whats app", "WhatsApp"),
    ("powerpoint", "PowerPoint"),
    ("gmail", "Gmail"),
    ("figma", "Figma"),
    ("zapier", "Zapier"),
    ("midjourney", "Midjourney"),
    ("dall e", "DALL-E"),
    ("esytype", "EsyType"),
    ("esyai", "EsyAI"),
];

/// The list as Dictionary corrections. Ids are negative: they are not rows of the user's Dictionary.
pub fn entries() -> Vec<Entry> {
    LIST.iter()
        .flat_map(|(heard, write)| heard.split('|').map(move |h| (h, *write)))
        .enumerate()
        .map(|(k, (h, w))| Entry { id: -(k as i64) - 1, kind: "correction".into(), term: h.into(), replacement: Some(w.into()), uses: 0 })
        .collect()
}

/// For the Dictionary page: each written name with the forms it corrects.
pub fn names() -> Vec<(&'static str, Vec<&'static str>)> {
    LIST.iter().map(|(heard, write)| (*write, heard.split('|').collect())).collect()
}

#[cfg(test)]
mod tests {
    use crate::dictionary::Matcher;

    fn apply(m: &Matcher, t: &str) -> String {
        m.apply(t, false).0
    }

    /// Real engine output from the 22 Nov benchmark (Base, five voices), and what it should become.
    #[test]
    fn corrects_what_whisper_wrote() {
        let m = Matcher::new(&super::entries());
        for (heard, want) in [
            ("I'm using chat GPT to transcribe certain things", "I'm using ChatGPT to transcribe certain things"),
            ("Chat GPT wrote the draft, then chatgpt fixed it.", "ChatGPT wrote the draft, then ChatGPT fixed it."),
            ("OpenAI developed chat GPT.", "OpenAI developed ChatGPT."),
            ("The application uses React, Next.js and Superbase", "The application uses React, Next.js and Supabase"),
            ("The application uses React, next.js and Supbase", "The application uses React, Next.js and Supabase"),
            ("I created the website using WordPress and Versal.", "I created the website using WordPress and Vercel."),
            ("Microsoft Co-pilot drafted the email for me.", "Microsoft Copilot drafted the email for me."),
            ("Zapier and N8N automate our workflows.", "Zapier and n8n automate our workflows."),
            ("The code lives on GITLab and runs on node.js", "The code lives on GitLab and runs on Node.js"),
            ("I use GIT Hub to manage my projects", "I use GitHub to manage my projects"),
            ("After lunch I'll check github and then call my sister.", "After lunch I'll check GitHub and then call my sister."),
            ("We connected make.com to airtable last week.", "We connected Make.com to Airtable last week."),
            ("We keep the data in Firebase and Postgres QL.", "We keep the data in Firebase and PostgreSQL."),
            ("We keep the data in Firebase and PostgresQL.", "We keep the data in Firebase and PostgreSQL."),
            ("Can you connect power automate to Microsoft Teams?", "Can you connect Power Automate to Microsoft Teams?"),
            ("ChatGPT's answer was long.", "ChatGPT's answer was long."),
            ("chat gpt's answer was long.", "ChatGPT's answer was long."),
        ] {
            assert_eq!(apply(&m, heard), want, "{heard}");
        }
    }

    /// Ordinary English the list must never touch.
    #[test]
    fn leaves_ordinary_english_alone() {
        let m = Matcher::new(&super::entries());
        for t in [
            "The cat clawed at the door all night.",
            "The co-pilot landed the plane safely.",
            "Type the word, press enter and wait.",
            "Plug the charger into the power point.",
            "The air table was broken again.",
            "Make a cup of tea for the whole team.",
            "Open the AI settings, then an open AI model.",
            "The power went out. Automate the backups.",
            "We stopped mid journey for lunch.",
            "Next, just add some salt.",
            "It's easy. Type it.",
            "The python escaped from the zoo.",
            "Write the java, script it later.",
            "Hello Dolly, said Dali.",
            "Make, com and go.",
            "Git, hub of the town.",
        ] {
            assert_eq!(apply(&m, t), t);
        }
    }

    /// The user's own Dictionary wins over the built-in list.
    #[test]
    fn users_entries_come_first() {
        let mut v = vec![crate::dictionary::Entry { id: 7, kind: "correction".into(), term: "github".into(), replacement: Some("GitHub Enterprise".into()), uses: 0 }];
        v.extend(super::entries());
        let m = Matcher::new(&v);
        assert_eq!(apply(&m, "Open github now."), "Open GitHub Enterprise now.");
        assert_eq!(m.apply("Open github now.", false).2, vec![7]);
        assert_eq!(apply(&m, "Ask chat GPT."), "Ask ChatGPT.");
        assert_eq!(m.hint(), "Glossary: GitHub Enterprise.", "built-in names never go into the hint");
    }

    /// Measurement, not a check: runs saved engine output (bench/accuracy/run.ps1) through the app's own Dictionary
    /// matcher and Clean mode, with and without the built-in list, and writes `<condition>-<variant>.jsonl` beside it
    /// for bench/accuracy/score.py.  ESYTYPE_ACCURACY=<results dir> cargo test --release measure_saved -- --ignored
    #[test]
    #[ignore]
    fn measure_saved_transcripts() {
        let dir = std::path::PathBuf::from(std::env::var("ESYTYPE_ACCURACY").expect("ESYTYPE_ACCURACY: the results folder"));
        let o = crate::settings::Settings::default().clean().unwrap();
        for cond in ["baseline", "prompt"] {
            let saved = std::fs::read_to_string(dir.join(format!("{cond}.jsonl"))).unwrap();
            for (variant, builtins, clean) in [("verbatim", false, false), ("verbatim-builtin", true, false), ("clean", false, true), ("clean-builtin", true, true)] {
                let m = Matcher::new(&if builtins { super::entries() } else { vec![] });
                let mut out = String::new();
                for line in saved.lines().map(|l| l.trim_start_matches('\u{feff}')).filter(|l| l.starts_with('{')) {
                    let mut v: serde_json::Value = serde_json::from_str(line).unwrap();
                    if let Some(t) = v["text"].as_str().map(String::from) {
                        let (d, written, _) = m.apply(&t, clean);
                        v["text"] = if clean { crate::dictionary::restore(&crate::clean::apply_styled(&d, &o, None), &written) } else { d }.into();
                    }
                    out.push_str(&v.to_string());
                    out.push('\n');
                }
                std::fs::write(dir.join(format!("{cond}-{variant}.jsonl")), out).unwrap();
            }
        }
    }

    #[test]
    fn list_is_well_formed() {
        let e = super::entries();
        assert!(e.iter().all(|x| x.id < 0 && x.kind == "correction" && x.replacement.is_some()));
        let mut seen = std::collections::HashSet::new();
        assert!(e.iter().all(|x| seen.insert(x.term.to_lowercase())), "a heard form is listed twice");
    }
}
