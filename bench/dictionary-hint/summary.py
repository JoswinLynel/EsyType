"""Scores measure.ps1 results: python -I summary.py <results dir> <audio dir>"""
import json, re, sys
from pathlib import Path

out, audio = Path(sys.argv[1]), Path(sys.argv[2])
meta = {Path(m["clip"]).name: m for m in json.loads(Path(out, "clips.json").read_text(encoding="utf-8-sig"))}
refs = {c["file"].replace(".wav", ".f32"): c["reference"] for c in json.loads(Path(audio, "clips.json").read_text(encoding="utf-8"))}

def words(s):
    return re.sub(r"[^a-z0-9' ]", " ", s.lower()).split()

def errors(r, h):
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev = cur
    return d[len(h)]

def load(cond):
    rows = [json.loads(l) for l in Path(out, f"{cond}.jsonl").read_text(encoding="utf-8-sig").splitlines() if l.startswith("{") and '"clip"' in l]
    return {Path(r["clip"]).name: r for r in rows}

res = {c: load(c) for c in ("none", "glossary")}
print(f"{'':12}{'none':>12}{'glossary':>12}")
for cond in res:
    r = res[cond]
    names = [(k, v) for k, v in r.items() if k in meta]
    exact = sum(meta[k]["term"] in v["text"] for k, v in names)
    loose = sum(meta[k]["term"].lower() in v["text"].lower() for k, v in names)
    other = [(k, v) for k, v in names]
    lib = [(k, v) for k, v in r.items() if k in refs]
    n = sum(len(words(refs[k])) for k, _ in lib)
    e = sum(errors(words(refs[k]), words(v["text"])) for k, v in lib)
    t_names = sum(v["transcribe_s"] for _, v in names) / max(1, len(names))
    t_lib = sum(v["transcribe_s"] for _, v in lib) / max(1, len(lib))
    res[cond] = dict(exact=f"{exact}/{len(names)}", loose=f"{loose}/{len(names)}", wer=f"{100*e/n:.1f}% ({e}/{n})", t_names=f"{t_names:.2f} s", t_lib=f"{t_lib:.2f} s",
                     silence=r.get("silence.f32", {}).get("text", "?"), noise=r.get("noise.f32", {}).get("text", "?"), rows=r)
for key, label in [("exact", "term exact"), ("loose", "term any case"), ("wer", "WER bench"), ("t_names", "time/name"), ("t_lib", "time/bench"), ("silence", "silence"), ("noise", "noise")]:
    print(f"{label:12}{res['none'][key]!s:>12}{res['glossary'][key]!s:>12}")
print("\nPer clip (none | glossary), terms only:")
for k in sorted(meta):
    a, b = res["none"]["rows"][k]["text"], res["glossary"]["rows"][k]["text"]
    t = meta[k]["term"]
    print(f"{k:24} {'Y' if t in a else '.'}{'Y' if t in b else '.'}  {a}  |  {b}")
