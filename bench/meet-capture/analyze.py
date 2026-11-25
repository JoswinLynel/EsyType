"""Checks a meet-capture run against what the test played (test use only).

python -I analyze.py <dir> <summary.json> <plays.json> <sentence> [--keep-mic] [--echo]

- system.f32: where speech starts after each play (vs when it was played), and the text Whisper reads from each
  played stretch (word error rate against <sentence>)
- both files: length against the run's wall time (the shared timeline)
- --echo: Whisper's reading of the microphone track during each play (the speakers repeated by the microphone)
- mic.f32: its level during each play (the speakers reaching the microphone: the echo case for plan 9.3); the file is
  deleted afterwards, as it holds room sound, unless --keep-mic
"""
import json
import subprocess
import sys
from array import array
from pathlib import Path

sys.path.insert(0, r"D:\AI Projects\Tools\bench\scripts")
from wer import norm  # noqa: E402

RATE = 16000
BENCH = r"D:\AI Projects\Tools\bench\target\release\stt-bench.exe"
MODEL = r"D:\AI Projects\Tools\bench\models\ggml-base.en-q5_1.bin"


def load(p):
    a = array("f")
    a.frombytes(Path(p).read_bytes())
    return a


def rms(a, i, j):
    s = a[max(0, i):max(0, j)]
    return (sum(v * v for v in s) / len(s)) ** 0.5 if len(s) else 0.0


def onset(a, i, j, thr=0.01, win=160):
    """First 10 ms window from sample i (up to j) whose RMS passes thr."""
    for k in range(max(0, i), min(j, len(a)) - win, win):
        if rms(a, k, k + win) > thr:
            return k
    return None


def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev = cur
    return d[len(h)] / max(1, len(r))


def echo_lag(sysa, mic, i, j):
    """How much later the same speech sits in the microphone track than in the PC-sound track (ms), from the peak of
    the cross-correlation of their 1 ms loudness envelopes (lags -500..+1000 ms), and that peak's correlation (0..1)."""
    import numpy as np
    def env(a):
        x = np.asarray(a[max(0, i):j], dtype=np.float64)
        x = x[: len(x) // 16 * 16].reshape(-1, 16)
        e = np.sqrt((x * x).mean(axis=1))
        return (e - e.mean()) / (e.std() or 1.0)
    s, m = env(sysa), env(mic)
    n = min(len(s), len(m))
    s, m = s[:n], m[:n]
    best = max(((float(np.dot(s[max(0, -k):n - max(0, k)], m[max(0, k):n - max(0, -k)])) / (n - abs(k)), k) for k in range(-500, 1001)))
    return best[1], round(best[0], 3)


def quality(a):
    """Peak, clipped samples (|v| >= 0.999), DC offset, exact-zero samples (filled-in silence, or digital silence) and
    RMS per minute, in one pass of 1-second blocks."""
    peak = clipped = zeros = 0
    total = 0.0
    per_min, sq = [], 0.0
    for k in range(0, len(a), RATE):
        blk = a[k:k + RATE]
        for v in blk:
            av = abs(v)
            if av > peak:
                peak = av
            if av >= 0.999:
                clipped += 1
            if v == 0.0:
                zeros += 1
            total += v
            sq += v * v
        if (k // RATE + 1) % 60 == 0 or k + RATE >= len(a):
            n = min(len(a), k + RATE) - (k // (60 * RATE)) * 60 * RATE
            per_min.append(round((sq / max(1, n)) ** 0.5, 5))
            sq = 0.0
    return {"peak": round(peak, 4), "clipped_samples": clipped, "dc": round(total / max(1, len(a)), 6),
            "zero_fraction": round(zeros / max(1, len(a)), 4), "rms_per_minute": per_min}


def main():
    a = sys.argv[1:]
    d, summ, plays, sentence = Path(a[0]), json.loads(Path(a[1]).read_text(encoding="utf-8-sig")), json.loads(Path(a[2]).read_text(encoding="utf-8-sig")), a[3]
    sysa, mic = load(d / "system.f32"), load(d / "mic.f32")
    out = {"wall_s": summ["wall_s"], "system_s": len(sysa) / RATE, "mic_s": len(mic) / RATE,
           "cpu_pct_of_one_core": summ["cpu_pct_of_one_core"], "system": summ["system"], "mic": dict(summ["mic"]), "plays": []}
    for p in plays:
        at = int((p["start_unix_ms"] - summ["start_unix_ms"]) / 1000 * RATE)
        end = at + int(p["seconds"] * RATE)
        o = onset(sysa, at - RATE // 2, end)
        clip = d / f"play-{len(out['plays'])}.f32"
        seg = sysa[max(0, at - RATE // 2):end + RATE // 2]
        clip.write_bytes(seg.tobytes())
        r = subprocess.run([BENCH, MODEL, "4", "1", "0", str(clip)], capture_output=True, text=True)
        text = next((json.loads(l)["text"] for l in r.stdout.splitlines() if l.startswith("{") and "summary" not in l), "")
        clip.unlink()
        mic_heard = None
        if "--echo" in a:  # the microphone's stretch, transcribed the same way, then deleted with the file
            mclip = d / f"mic-play-{len(out['plays'])}.f32"
            mclip.write_bytes(mic[max(0, at - RATE // 2):end + RATE // 2].tobytes())
            r = subprocess.run([BENCH, MODEL, "4", "1", "0", str(mclip)], capture_output=True, text=True)
            mic_heard = next((json.loads(l)["text"] for l in r.stdout.splitlines() if l.startswith("{") and "summary" not in l), "")
            mclip.unlink()
            lag = echo_lag(sysa, mic, at - RATE // 2, end + RATE // 2)
        out["plays"].append({"mic_heard": mic_heard, "mic_wer": None if mic_heard is None else round(wer(sentence, mic_heard), 3),
                             "mic_after_system_ms": None if mic_heard is None else lag[0], "echo_correlation": None if mic_heard is None else lag[1],
                             "played_at_s": round(at / RATE, 3), "speech_found_at_s": None if o is None else round(o / RATE, 3),
                             "offset_ms": None if o is None else round((o - at) / RATE * 1000), "system_rms": round(rms(sysa, at, end), 4),
                             "mic_rms_during": round(rms(mic, at, end), 4), "heard": text, "wer": round(wer(sentence, text), 3)})
    out["mic_rms_overall"] = round(rms(mic, 0, len(mic)), 4)
    offs = [(p["played_at_s"], p["offset_ms"]) for p in out["plays"] if p["offset_ms"] is not None]
    if len(offs) > 1:
        mx, my = sum(x for x, _ in offs) / len(offs), sum(y for _, y in offs) / len(offs)
        den = sum((x - mx) ** 2 for x, _ in offs)
        out["offset_ms"] = {"min": min(y for _, y in offs), "max": max(y for _, y in offs),
                            "drift_ms_per_hour": round(sum((x - mx) * (y - my) for x, y in offs) / den * 3600, 2) if den else 0.0}
    try:
        out["quality"] = {"system": quality(sysa), "mic": quality(mic)}
    except Exception as e:  # a quality step must never keep the microphone file from being deleted
        out["quality"] = f"failed: {e}"
    if "--keep-mic" not in a:
        (d / "mic.f32").unlink()
        out["mic_file"] = "deleted after measuring"
    print(json.dumps(out, indent=1))


main()
