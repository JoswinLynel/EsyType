"""WAV (any rate, 16-bit, mono or stereo) -> 16 kHz mono f32 with 0.3 s of silence before and 0.5 s after, as a
dictation has. Resampled with an FFT (band-limited), so the test audio itself adds no aliasing.

  python -I convert.py <folder with .wav>       writes <name>.f32 beside each file
"""
import sys
import wave
from pathlib import Path

import numpy as np


def load(path):
    with wave.open(str(path)) as w:
        rate, ch, width, n = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        assert width == 2, f"{path}: {8 * width}-bit audio, expected 16-bit"
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32768.0
    return x.reshape(-1, ch).mean(axis=1), rate


def to_16k(x, rate):
    if rate == 16000:
        return x
    n = int(round(len(x) * 16000 / rate))
    spec = np.fft.rfft(x)
    keep = n // 2 + 1
    out = np.zeros(keep, dtype=complex)
    out[: min(keep, len(spec))] = spec[: min(keep, len(spec))]
    return np.fft.irfft(out, n) * (n / len(x))


def main():
    folder = Path(sys.argv[1])
    for wav in sorted(folder.glob("*.wav")):
        x, rate = load(wav)
        y = np.concatenate([np.zeros(4800), to_16k(x, rate), np.zeros(8000)]).astype("<f4")
        wav.with_suffix(".f32").write_bytes(y.tobytes())
    print(f"converted {len(list(folder.glob('*.wav')))} files in {folder}")


if __name__ == "__main__":
    # self-check: a 1 kHz tone at 48 kHz keeps its level and frequency at 16 kHz
    t = np.arange(48000) / 48000
    y = to_16k(np.sin(2 * np.pi * 1000 * t).astype(np.float32), 48000)
    assert len(y) == 16000 and abs(np.abs(y).max() - 1) < 0.02 and np.argmax(np.abs(np.fft.rfft(y))) == 1000
    main()
