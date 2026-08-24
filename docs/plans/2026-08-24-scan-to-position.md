# Plan — Scan to position (2026-08-24)

Successor of `docs/plans/2026-08-22-listnr-v1.md`. V1 plays the owner's own M4B files with real
chapters. This plan builds the feature the app exists for: **point the camera at a page of the
paper book and the audiobook jumps to that spot.**

Binding decisions (owner, 2026-08-24): transcription is **on demand, per book, in the background** —
nothing is transcribed until asked · the jump is **always confirmed**, never automatic · the Scan
tab is where this lives · ebook↔audiobook mapping reuses the same matcher but comes **after** this,
with the reader · notes on ebook highlights are parked, not forgotten.

Design source of truth, in this order: `docs/mockups/scan.html` + `docs/mockups/app.js` +
`docs/mockups/kit.css` → `docs/DESIGN.md` → this plan. Serve with
`cd docs/mockups && python3 -m http.server 8123`.

Global stop rule, unchanged: if a step's validation fails twice on the same cause, revert that
step's diff, write the reason into `docs/IDEAS.md`, and continue. Never leave the tree with a red
`scripts/verify.sh`.

---

## The shape of it

```
page  →  Vision OCR  →  ~300 words of noisy German
                              ↓
transcript (word + start time, from FluidAudio)  →  shingle index
                              ↓
                    vote → best position + confidence
                              ↓
             confirm sheet → engine.seek() → Audiobook tab
```

Three things can each be wrong: the OCR, the ASR, and the match. The confirm step exists because
the third one cannot be made certain — the user is the check, and that is cheaper than pretending.

---

## Step 0 · FluidAudio dependency and a smoke test

Files: `project.yml`, `Tests/Unit/TranscriberSmokeTests.swift` (new).

Verified against the source at `github.com/FluidInference/FluidAudio` (0.12.x): `Package.swift`
declares `.iOS(.v17)`, so the iOS 26 target is fine. The batch API is
`AsrModels.downloadAndLoad(version: .v3)` → `AsrManager(config:)` → `loadModels` →
`transcribe(samples) -> ASRResult`. `ASRResult.tokenTimings: [TokenTiming]?` gives
`token`, `startTime`, `endTime`, `confidence` — **this is the field the whole feature rests on**.
German is supported (`TokenLanguageFilter.german = "de"`).

1. Add the package to `project.yml` under `packages:` and to the `Listnr` target's `dependencies`.
   `xcodegen generate`.
2. Smoke test: load the models, transcribe `Fixtures/chapters.m4b` (45 s, already in the repo),
   assert a non-empty `text` and a non-empty `tokenTimings` whose times are monotonic and inside
   the file's duration.

Stop rule: model download needs the network. If it is unavailable the test must **skip loudly**
(`XCTSkip`), never fail silently and never assert on a fixture it could not fetch.

Validation: `scripts/verify.sh`, `scripts/test.sh dev`.

---

## Step 1 · Transcript as stored data

Files: `App/Sources/Transcript/Transcript.swift` (new), `App/Sources/Store/ListnrStore.swift`.

1. `TranscriptWord`: `text: String`, `start: TimeInterval`. That is all a jump needs — end times
   and confidences are dropped on write. A 6.5-hour book is roughly 60k words; keeping two fields
   keeps the file near 2 MB instead of five times that.
2. `Transcript`: `bookID`, `words: [TranscriptWord]`, `language: String?`, `createdAt`.
3. Stored as JSON at `Application Support/Transcripts/<bookID>.json`, beside `Covers/`. Not in
   SwiftData — it is a large opaque blob and nothing queries inside it.
4. `Book` gains `hasTranscript: Bool` (computed from the file's existence, not a stored column, so
   it cannot drift from the truth on disk).
5. Deleting a book's row deletes its transcript. A missing file simply means "not prepared".

Validation: round-trip test — write, read, identical words and times.

---

## Step 2 · The transcriber

Files: `App/Sources/Transcript/Transcriber.swift` (new), `App/Sources/AppModel.swift`.

An `actor`, off the main actor, with **no UI and no SwiftData** inside it — the same rule
`LibraryIndexer` follows.

1. Decode with `AVAssetReader` to **16 kHz mono Float32**, which is what Parakeet expects.
2. **Chunk it.** A 6.5-hour book is about 375 M samples; handing that to `transcribe` in one call
   will exhaust memory on a phone. Read in windows of about 10 minutes with a few seconds of
   overlap, transcribe each, and **offset each chunk's `startTime` by the window's own offset**.
   Drop tokens landing in the overlap of the previous window so words are not duplicated.
3. Report progress as `seconds transcribed / total duration`. This is an honest fraction — unlike
   the import scan, transcription genuinely knows how far through it is, so the UI may show it.
4. Cancellable. Cancelling leaves no partial file: write to a temp path and move into place only
   on success.
5. `AppModel.prepareForScanning(bookID:)` starts it, publishes progress, and holds the security
   scope for the file's folder while it runs (the same rule playback follows).

Stop rule: if chunked timestamps drift against the whole-file result on the 45 s fixture, fix the
offsets — do not paper over it by widening the match threshold in step 3.

Validation: transcribe the fixture in two forced chunks; assert the word list and times match the
single-chunk result within 0.2 s.

---

## Step 3 · The matcher — pure, and the part worth testing hardest

Files: `App/Sources/Transcript/PageMatcher.swift` (new), `Tests/Unit/PageMatcherTests.swift` (new).

No camera, no Vision, no I/O — text in, position out, so it is testable without hardware.

1. **Normalise** both sides identically: lowercase, strip punctuation and digits, collapse
   whitespace. **Keep umlauts** — the ASR emits them and so does the print. Do not fold to ASCII.
2. **Index** the transcript as overlapping 5-word shingles → the word indices where each occurs.
3. **Vote**: shingle the OCR text, look each up, and cluster the hits by transcript position. The
   best cluster wins; its earliest word's `start` is the proposed timestamp.
4. **Confidence** = matched shingles / total OCR shingles. Below a threshold, report **no match**
   rather than a bad guess. A wrong confident jump is worse than an honest miss.
5. Return the matched span too, so the UI can quote back what it recognised.

Why shingles and not edit distance: OCR and ASR each corrupt a scattering of words, but rarely the
same ones. Requiring only *some* 5-grams to survive is robust to both, and it is a dictionary
lookup rather than an O(n·m) alignment over 60k words.

Tests, all pure: an exact passage matches at the right index; a passage with 10 % of words
corrupted still matches; a passage from a different book reports no match; an empty or
two-word input reports no match rather than matching at 0; the same passage occurring twice
returns the higher-voted cluster and a lowered confidence.

---

## Step 4 · OCR

Files: `App/Sources/Scan/PageOCR.swift` (new), `Tests/Unit/PageOCRTests.swift` (new).

`VNRecognizeTextRequest`, `.accurate`, `recognitionLanguages = ["de-DE", "en-US"]`,
`usesLanguageCorrection = true`. Returns the page's text in reading order, plus a mean confidence.

Test against a **rendered page image**, generated in the test rather than committed as a fixture
(the repo keeps no binary fixtures beyond the audio): render a known German passage into an image
with `ImageRenderer` at a page-like size and serif face, OCR it, and assert the recovered text
matches the source above a word-level threshold.

**Known limitation, stated rather than hidden**: this proves OCR + matcher. It does not prove that
the *printed* book and the *narrated* audiobook use identical words. For an unabridged reading they
are near-identical, which is the case this feature targets; an abridged or dramatised edition
(the owner's "Die unendliche Geschichte" is a Hörspiel) will match poorly, and the confirm step is
what protects the user from that.

---

## Step 5 · The Scan tab

Files: `App/Sources/Scan/ScanView.swift` (new), `App/Sources/Scan/CameraController.swift` (new),
`App/Sources/AppModel.swift`, `App/Info.plist`.

Build the five states exactly as `docs/mockups/scan.html` shows them:

1. **Idle** — live `AVCaptureSession` preview on the rails, the book being matched named above it,
   one shutter key, "Point at a page".
2. **Reading** — frozen frame, "Reading the page…", **no progress bar** (no honest fraction).
3. **Match** — the recognised snippet quoted back, the proposed timestamp and chapter, then
   "Not this one" / "Jump here".
4. **No match** — one plain line and "Try again".
5. **Not prepared** — one sentence and "Prepare this book", then the transcription progress.

`App/Info.plist` gains `NSCameraUsageDescription`. Without a loaded audiobook the tab says so
rather than opening a camera that can lead nowhere.

Stop rule: no dead controls. The shutter is disabled with a reason, never inert.

---

## Step 6 · The jump

Files: `App/Sources/AppModel.swift`, `Tests/UI/ListnrUITests.swift`.

"Jump here" seeks the engine to the matched time, persists the position, and switches to the
Audiobook tab so the user lands where they can see what happened. "Not this one" returns to idle
and keeps the frame, so a second attempt does not need a second photo.

---

## Step 7 · End to end

A UI test with a launch argument that injects a **fixed page image** and a **fixed transcript**,
so the whole chain runs without a camera: injected image → real OCR → real matcher → confirm →
assert the engine's position is within a couple of seconds of the truth, and that the tab switched.

The simulator has no camera, so this is the only honest automated end-to-end. The device checklist
in `docs/TESTFLIGHT.md` gains the real-camera pass.

---

## Not in this plan, deliberately

- **The EPUB reader**, and with it ebook↔audiobook mapping. The matcher in step 3 is written to be
  reused: an EPUB chapter's text is just another string to match against the transcript. That is
  the next plan, and it is where highlights live.
- **Notes on ebook highlights.** The owner asked for this to be kept in mind, not built.
- **Re-transcription when a file changes.** The transcript is keyed to the book, and a replaced
  file keeps its row today. Revisit if it bites.

## Risks

1. **Transcription time on a phone.** Parakeet claims ~190x realtime on an M4 Pro; an A-series
   phone will be slower and thermally limited. A 6.5-hour book could take well over half an hour.
   This is why it is on demand and in the background, and why progress is shown.
2. **Model download size.** Parakeet TDT v3 is 0.6 B parameters. First use downloads it. The UI
   must say so before it starts, not after.
3. **Hörspiel-type editions will not match.** Dramatised audio is not the printed text. Expect no
   match and let the confirm step do its job.
4. **Memory during chunking.** The chunk window is the lever; if a phone still spikes, halve it
   before reaching for anything cleverer.
5. **`tokenTimings` is optional.** If a config returns nil timings the feature is dead in the
   water — assert it early, in step 0, not in step 6.
