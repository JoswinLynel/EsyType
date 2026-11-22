"""Scores run.ps1 results: python -I score.py <results dir> <audio dir> [condition ...]

Raw engine output only (no Clean mode, no Dictionary), so recognition is measured apart from text cleaning.
Per condition:
  names      product names spelled exactly (case-sensitive, each expected occurrence), all voices and by accent
  false      product spellings in the ordinary sentences that are not in the reference (a brand where none was said)
  WER / CER  word and character error rates (lower-case, no punctuation, numbers spelled out: Tools/bench wer.py)
  S/D/I      substituted, deleted (missing) and inserted words; rep = a word repeated that the reference does not repeat
  time       mean seconds per clip; peak memory of the process
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, r"D:\AI Projects\Tools\bench\scripts")
from wer import norm  # noqa: E402

HERE = Path(__file__).parent
VOCAB = ["ChatGPT", "OpenAI", "Claude", "Gemini", "Copilot", "Perplexity", "Midjourney", "DALL-E", "WhatsApp", "Teams", "Excel",
         "PowerPoint", "Chrome", "Gmail", "GitHub", "GitLab", "Supabase", "Firebase", "Vercel", "Notion", "Airtable", "Canva", "Figma",
         "WordPress", "JavaScript", "TypeScript", "Python", "React", "Next.js", "Node.js", "PostgreSQL", "Power Automate", "Power BI",
         "Zapier", "Make.com", "n8n", "API", "SQL", "EsyAI", "EsyType"]
IN = {"heera", "ravi"}


def ops(r, h):
    """Substitutions, deletions, insertions of the cheapest alignment of word lists r -> h."""
    n, m = len(r), len(h)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = i
    for j in range(m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (r[i - 1] != h[j - 1]))
    s = de = ins = 0
    i, j = n, m
    while i or j:
        if i and j and d[i][j] == d[i - 1][j - 1] + (r[i - 1] != h[j - 1]):
            s += r[i - 1] != h[j - 1]; i -= 1; j -= 1
        elif i and d[i][j] == d[i - 1][j] + 1:
            de += 1; i -= 1
        else:
            ins += 1; j -= 1
    return s, de, ins


def chars(ws):
    return list(" ".join(ws))


def repeats(r, h):
    rr = sum(a == b for a, b in zip(r, r[1:]))
    return max(0, sum(a == b for a, b in zip(h, h[1:])) - rr)


def load(path):
    rows = [json.loads(l) for l in path.read_text(encoding="utf-8-sig").splitlines() if l.startswith("{")]
    return {Path(x["clip"]).stem: x for x in rows if "clip" in x}, next((x for x in rows if x.get("summary")), {})


def score(rows, summ, sents, libri):
    out = {}
    hit = {"all": [0, 0], "gb/us": [0, 0], "in": [0, 0]}
    false_hits = []
    groups = {"product": [0] * 6, "ordinary": [0] * 6, "mixed": [0] * 6, "librispeech": [0] * 6}   # errors, words, chars_err, chars, S..; reused below
    tot = {k: dict(e=0, n=0, ce=0, cn=0, s=0, d=0, i=0, rep=0, t=0.0, clips=0) for k in groups}
    for stem, x in rows.items():
        if stem in libri:
            kind, ref, names = "librispeech", libri[stem], []
        else:
            voice, sid = stem.split("-", 1)
            s = sents[sid]
            kind, ref, names = s["kind"], s["ref"], s.get("names", [])
            acc = "in" if voice in IN else "gb/us"
            for name in set(names):
                want, got = names.count(name), x["text"].count(name)
                for g in ("all", acc):
                    hit[g][0] += min(want, got); hit[g][1] += want
            if kind == "ordinary":
                false_hits += [f"{stem}: {v}" for v in VOCAB if v in x["text"] and v not in ref]
        r, h = norm(ref), norm(x["text"])
        s_, d_, i_ = ops(r, h)
        cs, cd, ci = ops(chars(r), chars(h))
        t = tot[kind]
        t["e"] += s_ + d_ + i_; t["n"] += len(r); t["ce"] += cs + cd + ci; t["cn"] += len(chars(r))
        t["s"] += s_; t["d"] += d_; t["i"] += i_; t["rep"] += repeats(r, h); t["t"] += x["transcribe_s"]; t["clips"] += 1
    out["names"] = {g: f"{a}/{b}" for g, (a, b) in hit.items()}
    out["false"] = false_hits
    out["groups"] = {k: dict(WER=f"{100 * v['e'] / max(1, v['n']):.1f}%", CER=f"{100 * v['ce'] / max(1, v['cn']):.1f}%",
                             SDI=f"{v['s']}/{v['d']}/{v['i']}", rep=v["rep"], words=v["n"], time=f"{v['t'] / max(1, v['clips']):.2f} s")
                     for k, v in tot.items() if v["clips"]}
    out["peak_mb"] = summ.get("peak_ws_mb")
    return out


def main():
    res, audio = Path(sys.argv[1]), Path(sys.argv[2])
    conds = sys.argv[3:] or sorted(p.stem for p in res.glob("*.jsonl"))
    sents = {s["id"]: s for s in json.loads((HERE / "sentences.json").read_text(encoding="utf-8"))}
    libri = {Path(c["file"]).stem: c["reference"] for c in json.loads((audio / "clips.json").read_text(encoding="utf-8"))}
    all_rows = {}
    for c in conds:
        rows, summ = load(res / f"{c}.jsonl")
        all_rows[c] = rows
        o = score(rows, summ, sents, libri)
        print(f"\n== {c}   peak memory {o['peak_mb']} MB")
        print(f"   product names exact: all {o['names']['all']}, British/US voices {o['names']['gb/us']}, Indian English voices {o['names']['in']}")
        print(f"   brand spellings where none was said ({len(o['false'])}): {'; '.join(o['false']) or '-'}")
        for k, g in o["groups"].items():
            print(f"   {k:12} WER {g['WER']:>6}  CER {g['CER']:>6}  S/D/I {g['SDI']:>9}  repeats {g['rep']}  words {g['words']:>4}  time/clip {g['time']}")
    if len(conds) > 1:   # sentences whose text differs between conditions
        base = conds[0]
        for c in conds[1:]:
            diff = [k for k in sorted(all_rows[base]) if k in all_rows[c] and all_rows[base][k]["text"] != all_rows[c][k]["text"]]
            print(f"\n== {base} -> {c}: {len(diff)} clips differ")
            for k in diff[:400]:
                print(f"   {k:14} {all_rows[base][k]['text']}\n   {'':14} {all_rows[c][k]['text']}")


if __name__ == "__main__":
    assert ops("a b c".split(), "a x c d".split()) == (1, 0, 1) and repeats("a b".split(), "a a b".split()) == 1
    main()
