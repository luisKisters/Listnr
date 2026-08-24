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

# ---------------------------------------------------------------------------
# chapters.m4b — the indexer fixture. Carries a title, an artist, a composer
# (the narrator fallback) and three named chapters of deliberately uneven
# length, so a test cannot pass against an even split.
# `afconvert` cannot write chapter metadata; ffmpeg can, via an ffmetadata
# input. The chapter text track ends up with language "und", which is exactly
# the case LibraryIndexer's locale fallback exists for.
# ---------------------------------------------------------------------------
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
if [[ -x "$FFMPEG" ]]; then
  meta="$(mktemp -t listnr-ffmeta)"
  cat > "$meta" <<'META'
;FFMETADATA1
title=Der Test Roman
artist=Testautor
album=Der Test Roman
composer=Test Sprecher
[CHAPTER]
TIMEBASE=1/1000
START=0
END=7000
title=Prolog
[CHAPTER]
TIMEBASE=1/1000
START=7000
END=25000
title=Die Tiefsee
[CHAPTER]
TIMEBASE=1/1000
START=25000
END=45000
title=Kontakt
META
  "$FFMPEG" -v error -y -f lavfi -i "sine=frequency=300:duration=45:sample_rate=22050" \
    -ac 1 -i "$meta" -map 0:a -map_metadata 1 -map_chapters 1 \
    -c:a aac -b:a 48k -movflags +faststart -f mp4 Fixtures/chapters.m4b
  rm -f "$meta"
  echo "wrote Fixtures/chapters.m4b"
else
  echo "warning: $FFMPEG not found — Fixtures/chapters.m4b left untouched" >&2
fi

ls -la Fixtures/
