#!/usr/bin/env bash
# Generate the sample audiobooks used by the app seed, the unit tests and the UI tests.
# Output: three small mono AAC files (m4a containers; the app treats m4b identically).
# Deterministic content: each book is a pure sine whose frequency changes every few
# seconds, so a listener (and a human tester) can hear that a seek actually moved.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p Fixtures

python3 - "$PWD" <<'PY'
import math, struct, sys, wave, os

root = sys.argv[1]

def write_wav(path, seconds, freq_plan, rate=22050):
    n = int(seconds * rate)
    frames = bytearray()
    for i in range(n):
        t = i / rate
        # pick frequency for this second from the plan (cycling)
        f = freq_plan[int(t) % len(freq_plan)]
        v = math.sin(2 * math.pi * f * t)
        # gentle envelope so looping between seconds never clicks
        env = min(1.0, (t % 1.0) * 8.0, (1.0 - (t % 1.0)) * 8.0)
        s = int(32000 * v * env)
        frames += struct.pack('<h', s)
    w = wave.open(path, 'wb')
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(bytes(frames)); w.close()

specs = [
    ("alpha",   96,  [220.0, 277.2, 330.0]),   # ~1.5 min, three tones cycling
    ("bravo",  120,  [196.0, 246.9, 293.7, 392.0]),
    ("charlie", 72,  [261.6, 329.6]),
]
for name, secs, plan in specs:
    wav = os.path.join(root, "Fixtures", name + ".wav")
    m4a = os.path.join(root, "Fixtures", name + ".m4a")
    write_wav(wav, secs, plan)
    print("wrote", wav)
PY

for f in Fixtures/*.wav; do
  out="${f%.wav}.m4a"
  afconvert -f m4af -d aac -b 48000 --soundcheck-generate "$f" "$out" || \
  afconvert -f m4af -d aac -b 48000 "$f" "$out"
  rm "$f"
done

ls -la Fixtures/
