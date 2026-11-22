"""Applies a candidate built-in correction list to saved transcripts, offline, to measure it before any code changes:
names fixed in the product sentences, and every change made to the ordinary sentences and LibriSpeech (must be none).

  python -I simulate-rules.py <results dir> <condition>

Matching mirrors the Dictionary: whole words, any case, a phrase's words separated by spaces or hyphens.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
# heard (any case; "|" separates variants) -> written. Only forms that are not ordinary English, or phrases whose
# context makes the product certain ("Microsoft co-pilot", not "co-pilot").
RULES = [
    ("chat gpt|chatgpt|chat g p t|chat gbt|chat g b t", "ChatGPT"),
    ("superbase|supbase|supa base", "Supabase"),
    ("versal|vercell", "Vercel"),
    ("microsoft co pilot|microsoft co. pilot|microsoft copilot", "Microsoft Copilot"),
    ("n8n|n 8 n|n eight n", "n8n"),
    ("node.js|node js", "Node.js"),
    ("next.js|next js", "Next.js"),
    ("git hub|github", "GitHub"),
    ("git lab|gitlab", "GitLab"),
    ("air table|airtable", "Airtable"),
    ("postgres ql|postgresql|postgres q l|postgre sql", "PostgreSQL"),
    ("make.com", "Make.com"),
    ("power automate", "Power Automate"),
    ("power bi|powerbi", "Power BI"),
    ("java script|javascript", "JavaScript"),
    ("type script|typescript", "TypeScript"),
    ("word press|wordpress", "WordPress"),
    ("whats app|whatsapp", "WhatsApp"),
    ("power point|powerpoint", "PowerPoint"),
    ("open ai|openai", "OpenAI"),
    ("dall e|dall-e", "DALL-E"),
    ("esyai|esy ai", "EsyAI"),
    ("esytype|esy type", "EsyType"),
]


def compile_rules():
    out = []
    for heard, write in RULES:
        for v in heard.split("|"):
            words = [re.escape(w) for w in re.split(r"[ \-]+", v)]
            out.append((re.compile(r"(?<![\w.])" + r"[ \-]+".join(words) + r"(?![\w])", re.I), write))
    return out


def apply(text, rules):
    for rx, write in rules:
        text = rx.sub(write, text)
    return text


def main():
    res, cond = Path(sys.argv[1]), sys.argv[2]
    sents = {s["id"]: s for s in json.loads((HERE / "sentences.json").read_text(encoding="utf-8"))}
    rules = compile_rules()
    rows = [json.loads(l) for l in (res / f"{cond}.jsonl").read_text(encoding="utf-8-sig").splitlines() if l.startswith("{") and '"clip"' in l]
    before = after = want = 0
    changed_other = []
    for x in rows:
        stem = Path(x["clip"]).stem
        new = apply(x["text"], rules)
        s = sents.get(stem.split("-", 1)[1]) if "-" in stem else None
        if s and s.get("names"):
            for n in set(s["names"]):
                k = s["names"].count(n)
                want += k; before += min(k, x["text"].count(n)); after += min(k, new.count(n))
        elif new != x["text"]:
            changed_other.append(f"{stem}: {x['text']}  ->  {new}")
    print(f"{cond}: names {before}/{want} -> {after}/{want}; ordinary and LibriSpeech texts changed: {len(changed_other)}")
    for c in changed_other:
        print("   ", c)


if __name__ == "__main__":
    r = compile_rules()
    assert apply("I use chat GPT and Superbase.", r) == "I use ChatGPT and Supabase."
    assert apply("The co-pilot landed. Microsoft Co-pilot helps.", r) == "The co-pilot landed. Microsoft Copilot helps."
    assert apply("Open the window.", r) == "Open the window."
    main()
