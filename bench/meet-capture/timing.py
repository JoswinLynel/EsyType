"""Timing of a meet-capture --tones run (test use only): python -I timing.py <dir> [--keep-mic]

For each tone the probe played (log lines {"tone", "handed_s", "playback_est_s"} in <dir>/capture.jsonl):
  system_ms   where the tone starts in system.f32, after it was handed to Windows (capture latency of the PC sound)
  mic_ms      the same in mic.f32, if the microphone heard it (sound from the speakers through the air)
  mic_minus_system_ms   how far the microphone track is from the PC-sound track for the same sound
  *_len_ms    the tone's length in the track (played: 200 ms); a different length means samples lost or doubled
Then the spread and trend of each over the run (drift: ms per hour, least squares).
mic.f32 is deleted afterwards (room sound), unless --keep-mic.
"""
import json
import sys
from array import array
from pathlib import Path
from statistics import median

RATE = 16000
WIN = 16  # 1 ms


def load(p):
    a = array("f")
    a.frombytes(Path(p).read_bytes())
    return a


def rms(a, i, j):
    s = a[max(0, i):max(0, min(j, len(a)))]
    return (sum(v * v for v in s) / len(s)) ** 0.5 if len(s) else 0.0


def find(a, at, before=0.3, after=1.5):
    """Start and length (ms) of the tone near sample `at`: 1 ms windows above a threshold set from the window's peak
    and the noise before it. None if nothing stands out from the noise."""
    i0, i1 = max(0, at - int(before * RATE)), min(len(a), at + int(after * RATE))
    wins = [rms(a, k, k + WIN) for k in range(i0, i1 - WIN, WIN)]
    if not wins:
        return None
    noise = median(wins[: max(1, int(before * 1000 * 0.5))])
    peak = max(wins)
    if peak < max(0.002, 8 * noise):
        return None
    thr = max(0.25 * peak, 4 * noise)
    on = next(k for k, w in enumerate(wins) if w > thr)
    off = on
    while off + 1 < len(wins) and max(wins[off + 1: off + 11] or [0]) > thr:  # end: 10 ms below threshold
        off += 1
    return ((i0 + on * WIN) / RATE, (off - on + 1) * WIN / RATE * 1000, peak, noise)


def trend(xs, ys):
    """Least-squares slope (per second of xs) and the spread of ys."""
    if len(xs) < 2:
        return 0.0
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    den = sum((x - mx) ** 2 for x in xs)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else 0.0


def main():
    d = Path(sys.argv[1])
    lines = [json.loads(l) for l in (d / "capture.jsonl").read_text(encoding="utf-8-sig").splitlines() if l.startswith("{")]
    tones = [l for l in lines if "tone" in l]
    summ = next(l for l in lines if l.get("summary"))
    sysa, mic = load(d / "system.f32"), load(d / "mic.f32")
    rows = []
    for t in tones:
        at = int(t["handed_s"] * RATE)
        s, m = find(sysa, at), find(mic, at)
        rows.append({"tone": t["tone"], "handed_s": t["handed_s"], "cpal_latency_est_ms": round((t["playback_est_s"] - t["handed_s"]) * 1000, 1),
                     "system_ms": None if s is None else round((s[0] - t["handed_s"]) * 1000, 1), "system_len_ms": None if s is None else s[1],
                     "mic_ms": None if m is None else round((m[0] - t["handed_s"]) * 1000, 1), "mic_len_ms": None if m is None else m[1],
                     "mic_level": None if m is None else round(m[2], 4), "mic_noise": None if m is None else round(m[3], 5),
                     "mic_minus_system_ms": None if s is None or m is None else round((m[0] - s[0]) * 1000, 1)})
    out = {"tones": len(tones), "wall_s": summ["wall_s"], "system_s": len(sysa) / RATE, "mic_s": len(mic) / RATE,
           "system_stats": summ["system"], "mic_stats": summ["mic"], "rows": rows}
    for k in ("system_ms", "mic_ms", "mic_minus_system_ms", "system_len_ms", "mic_len_ms"):
        pts = [(r["handed_s"], r[k]) for r in rows if r[k] is not None]
        if pts:
            v = [y for _, y in pts]
            out[k] = {"found": len(pts), "median": median(v), "min": min(v), "max": max(v),
                      "drift_ms_per_hour": round(trend([x for x, _ in pts], v) * 3600, 2)}
    if "--keep-mic" not in sys.argv:
        (d / "mic.f32").unlink()
        out["mic_file"] = "deleted after measuring"
    print(json.dumps(out, indent=1))


main()
