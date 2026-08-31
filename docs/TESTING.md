# Testing

Written during implementation, per acceptance criterion — never retrofitted.

| Layer | Proves | Command |
|---|---|---|
| Unit (`ListnrTests`) | Chapter math, filtering/sort/search, note pause/resume policy, engine sleep timer, now-playing payload, formatting | `scripts/test.sh dev` |
| UI (`ListnrUITests`) | Golden paths: tabs + construction screens, filters/search, row → player, play/pause, chapter wheel seeks, speed/sleep, note round-trip, Transcription screen both jobs | `scripts/test.sh full` |
| ASR smoke (`TranscriberSmokeTests`) | The real Parakeet models produce text and non-empty, monotonic token timings | see below — **off by default** |

Both run on the iPhone 17 Pro simulator with deterministic inputs: `-uitest` forces the
in-memory store and the fixed sample library, `-mockengine` swaps AVFoundation for the
deterministic engine. No test depends on wall-clock time or network. Covers are picsum-free
gradient placeholders, so tests never touch the network either.

`-faketranscriber` is the third deterministic swap: it replaces the 1.2 GB Parakeet models
with `FakeTranscriber`, which emits fixed words per window. `-model ready|missing|downloading`
pins the Transcription screen's model job, and `-transcribed` starts with a finished transcript.

## The ASR smoke test

One test touches the real models. It is gated on `LISTNR_ASR_SMOKE=1` because the first run
downloads about 1 GB of Core ML models — that must never happen inside `scripts/test.sh dev`
by accident.

The gate has to reach the *test process*, and `xcodebuild`'s `TEST_RUNNER_` prefix does not
propagate into a hosted unit-test bundle. The scheme's test action therefore carries
`LISTNR_ASR_SMOKE: $(LISTNR_ASR_SMOKE)` (in `project.yml`), which is empty on a normal run and
picks up a build setting passed on the command line:

```bash
xcodebuild test -project Listnr.xcodeproj -scheme Listnr \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ListnrTests/TranscriberSmokeTests LISTNR_ASR_SMOKE=1
```

The fixture is `Fixtures/speech.m4a` — `say`-rendered speech, written by
`scripts/make-fixtures.sh`. The other fixtures are pure sine tones, and a recogniser has
nothing to recognise in a 300 Hz sine.

Measured wall time (iPhone 17 Pro simulator, Xcode 26, FluidAudio 0.15.6): **16 s for both
tests with the models already on disk** (1.7 s for the whole-file run, 7.2 s for the chunked
comparison). The very first run adds the ~1.2 GB model download, which is network-bound.

## Determinism rules

- Every launch argument combination is set in `ListnrUITests.launch()`.
- Absence assertions poll (`waitAbsent`), presence uses `waitForExistence`.
- Row queries target list rows by their "… by …" label shape; pinned resume cards
  ("Resume listening/reading: …") stay above filters by design and must not be matched.

## Pre-push gate

`scripts/verify.sh` runs grep gates (no emoji in app code, accessibility labels on controls,
no `print` in app targets, no force-try in app code), `swiftlint`, a build and the unit suite.
