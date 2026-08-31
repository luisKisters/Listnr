# Plan — Background transcription (2026-08-31)

Successor of `docs/plans/2026-08-22-listnr-v1.md` on `main`. Builds the transcriber that
`docs/plans/2026-08-24-scan-to-position.md` (branch `t3code/scan-to-position`) steps 0–2 describe,
and makes it **keep running when the phone is locked**. Nothing on `main` transcribes anything yet;
the scan branch has mockups and a Scan UI skeleton but no transcriber either.

Owner's ask (2026-08-31): "book transcription works in the background when I put my phone off."

## What iOS allows, and what we use

| Mechanism | Runs when locked? | Verdict |
|---|---|---|
| `BGContinuedProcessingTask` (iOS 26) | **Yes.** User starts it in the foreground; the system keeps it running after lock/backgrounding and shows a system progress pill (lock screen / Dynamic Island) with a cancel. Expires under thermal, battery or user action. | **Primary.** Deployment target is already iOS 26. |
| `BGProcessingTask` | Yes, but only when the system decides (idle, usually charging, minutes at a time). | **Resume fallback.** Advances a checkpointed job overnight if the continued task expired. |
| `audio` background mode (already on) | Yes, while the audiobook is playing. | Free bonus: no code. Playing a book while it transcribes keeps the app alive. |
| `beginBackgroundTask` | ~30 s. | Only to flush a checkpoint when nothing else holds the app. |
| Silent-audio hack | — | Rejected. App Store policy; also dishonest. |

Verified in this SDK (iPhoneOS26.5, `BackgroundTasks.framework/Headers`):
`BGContinuedProcessingTaskRequest(identifier:title:subtitle:)`, `.strategy` (`.queue` default,
`.fail`), `.requiredResources` (default = CPU + network; `.gpu` needs an entitlement we do **not**
have), `BGContinuedProcessingTask: BGTask & NSProgressReporting` with `updateTitle(_:subtitle:)`.
Identifier **must** be wildcard-shaped: `com.luisKisters.Listnr.transcribe.*` in
`BGTaskSchedulerPermittedIdentifiers`; each submission uses `…transcribe.<bookID>`. Registration
of continued-processing handlers is exempt from the "before launch finishes" rule. Tasks that show
no `progress` movement get expired, so progress must tick.

Consequences for the design:
1. **Checkpoint per chunk.** The job can be killed at any time (expiry, user cancel from the pill,
   low battery). Every finished chunk is written to disk; a restart continues from the checkpoint.
   This supersedes scan-plan step 2 item 4 ("cancel leaves no partial file") — the partial file *is*
   the feature.
2. **No GPU.** Core ML compute units = `.cpuAndNeuralEngine`. The ANE is available in the background;
   Metal is not without the entitlement.
3. **Progress is honest and frequent.** `task.progress.completedUnitCount` = seconds transcribed,
   updated after every chunk. Chunks are 5 minutes of audio, so on a phone at ~10–30× realtime the
   pill moves every 10–30 s.

## The shape of it

```
Scan tab  ▶  Transcription screen  ▶  "Transcribe book"
                                   │
                                   ▼
       TranscriptionJob (@MainActor)  ──submit──▶  BGContinuedProcessingTask (system pill)
              │  run(task:)                            │ expirationHandler → cancel → checkpoint
              ▼                                        ▼
       Transcriber (actor)  ── AVAssetReader 16 kHz mono ── FluidAudio Parakeet v3 ── words+times
              │  per 5-min chunk
              ▼
       Transcripts/<bookID>.partial.json  ──on last chunk──▶  Transcripts/<bookID>.json
```

One job at a time. A second "Prepare" while one runs is refused with the reason, not queued.

Global stop rule, unchanged: if a step's validation fails twice on the same cause, revert that
step's diff, write the reason into `docs/IDEAS.md`, and continue. Never leave the tree with a red
`scripts/verify.sh`. Preflight once: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Step 0 · FluidAudio dependency, pinned and verified

Files: `project.yml`, `Tests/Unit/TranscriberSmokeTests.swift` (new), `docs/TESTING.md`.

1. `project.yml`: add `packages: FluidAudio: { url: https://github.com/FluidInference/FluidAudio, from: "0.15.6" }`
   and `dependencies: [{ package: FluidAudio }]` on the `Listnr` target. `xcodegen generate`.
   Resolve once (`xcodebuild -resolvePackageDependencies`) and **read the checked-out source**
   under `~/Library/Developer/Xcode/DerivedData/…/SourcePackages/checkouts/FluidAudio` — the scan
   plan quoted the 0.12 API (`AsrModels.downloadAndLoad`, `AsrManager`, `transcribe(_:) -> ASRResult`,
   `ASRResult.tokenTimings: [TokenTiming]?`). Confirm the names on 0.15.x before writing a line
   against them, and find the hook that takes an `MLModelConfiguration` / compute-units setting.
2. Smoke test, **env-gated**: runs only when `LISTNR_ASR_SMOKE=1` is set, otherwise `XCTSkip`
   with the reason. It downloads ~1 GB of Core ML models on first run; that must never happen inside
   `scripts/test.sh dev` by accident. The test loads the models, transcribes `Fixtures/chapters.m4b`
   (45 s), and asserts non-empty text and non-empty, monotonic token timings inside the duration.
   Run it once with the gate on and record the wall time in the test's doc comment.
3. `docs/TESTING.md`: one row for the gated smoke test and how to enable it.

Stop rule: if `tokenTimings` is nil or empty for the fixture on 0.15.x, stop the whole plan and
report — the feature has no timestamps without it.

Validation: `scripts/verify.sh`, `LISTNR_ASR_SMOKE=1 scripts/test.sh dev` once, `scripts/test.sh dev` (must skip, fast).

---

## Step 1 · Transcript on disk, with a checkpoint

Files: `App/Sources/Transcript/Transcript.swift` (new), `Tests/Unit/TranscriptStoreTests.swift` (new),
`App/Sources/Store/ListnrStore.swift`.

1. `TranscriptWord { text: String; start: TimeInterval }` — `Codable, Sendable`. Two fields only
   (60k words ≈ 2 MB).
2. `Transcript { bookID: UUID; words: [TranscriptWord]; language: String?; createdAt: Date }`.
3. `TranscriptCheckpoint { bookID; nextOffset: TimeInterval; duration: TimeInterval; words }` —
   the same words plus where to continue. Written after every chunk.
4. `TranscriptStore` (enum with static funcs, like `CoverImageStore`): paths under
   `Application Support/Transcripts/` — `<bookID>.json` final, `<bookID>.partial.json` checkpoint.
   `load`, `save(_ transcript)` (atomic write to temp, then move; deletes the partial),
   `loadCheckpoint`, `saveCheckpoint`, `remove(bookID)`.
5. `Book.hasTranscript` is computed from the final file's existence — never a stored column.
6. `ListnrStore.apply(reconciliation)` removes both files when it removes a book row.

Validation, all pure I/O in a temp directory: transcript round-trip is identical; checkpoint
round-trip is identical; `save` removes the partial; `remove` removes both.

---

## Step 2 · The transcriber, chunked and resumable

Files: `App/Sources/Transcript/Transcriber.swift` (new), `Tests/Unit/TranscriptChunkingTests.swift` (new).

An `actor`, no UI, no SwiftData — the `LibraryIndexer` rule.

1. `protocol Transcribing: Sendable` with one method:
   `func transcribe(url: URL, duration: TimeInterval, from offset: TimeInterval, onChunk: @Sendable ([TranscriptWord], _ nextOffset: TimeInterval) async -> Void) async throws`.
   Two implementations: `Transcriber` (real) and `FakeTranscriber` in the test target (emits N
   fixed words per chunk, can be told to throw or hang). The fake exists because step 3's controller
   is untestable against a 1 GB model; it mirrors the `-mockengine` precedent.
2. Chunk math is a pure static: `Transcriber.windows(duration:from:window: 300) -> [ClosedRange<TimeInterval>]`.
   No overlap. A word cut on a 5-minute boundary is one bad token per 300 s; the shingle matcher in
   the scan plan tolerates that and it removes the dedupe logic entirely.
3. Per window: `AVAssetReader` with `timeRange` set to the window, output settings 16 kHz mono
   Float32 non-interleaved, read into `[Float]`, hand to FluidAudio, **add the window's start to
   every token's `startTime`**, map to `TranscriptWord`, call `onChunk`.
4. Models load once per actor instance with `computeUnits = .cpuAndNeuralEngine`. Downloading on
   first use is allowed inside the job (default resources include network).
5. Checks `Task.isCancelled` between windows and returns cleanly; the caller owns the checkpoint.

Validation: `windows` tests (exact division, remainder, `from` mid-window, `from >= duration` → empty).
A two-window run of the 45 s fixture with `window: 20` behind the same smoke gate: words equal the
single-window result and every `start` is within 0.2 s.

Stop rule (from the scan plan): if chunked timestamps drift against the whole-file result, fix the
offset — never widen a threshold to hide it.

---

## Step 3 · The job — foreground, continued, and resumed

Files: `App/Sources/Transcript/TranscriptionJob.swift` (new), `App/Sources/AppModel.swift`,
`App/Sources/ListnrApp.swift`, `project.yml` (Info.plist keys), `Tests/Unit/TranscriptionJobTests.swift` (new).

`@MainActor final class TranscriptionJob: ObservableObject`, owned by `AppModel`, injected with a
`Transcribing` and the folder-access closure it needs.

State, published: `enum State { idle, running(bookID: UUID, fraction: Double), failed(bookID: UUID, reason: String) }`.

1. **Info.plist** (via `project.yml` `info.properties`):
   `BGTaskSchedulerPermittedIdentifiers: [com.luisKisters.Listnr.transcribe.*, com.luisKisters.Listnr.transcribe-resume]`,
   `UIBackgroundModes: [audio, processing]`.
2. **Registration** in `ListnrApp.init` (before launch finishes, so both handlers are legal):
   the wildcard continued identifier and the resume identifier, both dispatching to the job.
3. **`start(book:)`**: refuse if a job is running (`playbackNotice`-style reason: "Already preparing
   <title>"). Otherwise submit a `BGContinuedProcessingTaskRequest(identifier: "…transcribe.\(book.id)",
   title: "Preparing \(book.title)", subtitle: "Listnr is transcribing for scan-to-position")`,
   strategy `.queue`, default resources. Then:
   - handler fires → `run(bookID:, task:)` inside it;
   - submit throws (simulator, or system refused) → `run(bookID:, task: nil)` immediately. The work
     still happens; it just pauses when the app leaves the foreground, and the checkpoint keeps it
     honest. The notice says so once: "Preparing in the app only — keep Listnr open."
4. **`run(bookID:, task:)`**: resolve the book, `folder.beginAccess()` (held for the run, released
   in `defer`), `TranscriptStore.loadCheckpoint` → `from`, call the transcriber. `onChunk` appends
   words, writes the checkpoint, sets `task?.progress.completedUnitCount = Int64(nextOffset)` (total
   = `Int64(duration)`), updates `fraction`, and `task?.updateTitle(_:subtitle:)` with "42 %".
   On the last chunk: `TranscriptStore.save`, `setTaskCompleted(success: true)`, `.idle`.
   `task.expirationHandler` → cancel the Swift `Task`; the checkpoint already on disk is the state.
   Thrown error → `.failed(reason)`, `setTaskCompleted(success: false)`; the checkpoint stays.
5. **Resume**: when the app becomes active (reuse `AppModel`'s foreground observer) and a
   `.partial.json` exists for a non-missing book and nothing is running → `start(book:)` again
   automatically. Resume is the foreground's job because continued tasks may only be submitted from
   the foreground.
6. **Overnight fallback**: whenever a checkpoint exists and no job runs (after expiry, after failure,
   at background), submit `BGProcessingTaskRequest("…transcribe-resume")` with
   `requiresExternalPower = true`, `requiresNetworkConnectivity = false`. Its handler runs the same
   `run(bookID:, task:)` (a `BGProcessingTask` has an `expirationHandler` too; progress calls become
   no-ops) and resubmits itself if the job did not finish. Cancel the pending request when a
   transcript completes.
7. **`stop(bookID:)`**: cancels the Swift `Task`, completes the system task, **keeps** the checkpoint
   (so "Stop" is "pause"). Deleting the checkpoint happens only through `TranscriptStore.remove` when
   the book row goes.

Tests, with `FakeTranscriber` and no `BGTaskScheduler` (pass `task: nil`): a run from zero writes a
checkpoint per chunk and the final file at the end; a run from an existing checkpoint starts at
`nextOffset` and keeps the earlier words; cancel mid-run leaves the checkpoint and no final file;
a throwing transcriber yields `.failed` with the checkpoint intact; `start` while running is refused.

Stop rule: if the wildcard registration is rejected at runtime, fall back to registering the exact
identifier `com.luisKisters.Listnr.transcribe` (no wildcard) with a single fixed submission id, and
note the reason in `docs/IDEAS.md`. Do not drop the continued task for a plain processing task.

---

## Step 4 · The Transcription screen — `docs/mockups/transcribe.html`, 1:1

Files: `App/Sources/Transcript/TranscriptionView.swift` (new), `App/Sources/Transcript/FillButton.swift` (new),
`App/Sources/ListnrApp.swift`, `App/Sources/AppModel.swift`, `Tests/UI/ListnrUITests.swift`,
`Tests/Unit/TranscriptionEstimateTests.swift` (new).

Mockup is the authority: `docs/mockups/transcribe.html` + the `.tx-*` / `.ios .fill` block at the end
of `docs/mockups/kit.css` (copied into this branch from the mockup worktree; serve with
`cd docs/mockups && python3 -m http.server 8123` and compare side by side).

**Where it lives.** The mockup is a full screen, not a sheet. It replaces the Scan tab's
under-construction screen: the Scan tab shows the Transcription screen for the **currently loaded
audiobook** (`model.currentBook`), because transcription is what scan-to-position needs first and the
tab otherwise leads nowhere. Without a loaded audiobook the screen keeps the heading and the model
job, and the book job reads "No audiobook loaded" with the button disabled (the mockup's `.35`
opacity state). When the real Scan tab lands, this screen moves behind its "Prepare this book" state.

**The screen**, top to bottom, from `kit.css`:
1. `Text("Transcription")` — 28 pt (`--t-2xl`) bold, tracking −0.025em, `s5` below the safe area.
2. `Text("Listnr reads the audio on this phone. Nothing leaves the device.")` — 14 pt `ink2`,
   line height 1.45, `s2` top margin.
3. Two **jobs**, each `s6` above: label 16 pt `ink` tracking −0.01em; key line 12 pt `ink3`, 2 pt
   below; then the fill button `s3` below.
   - Job 1 label `Speech model`, key `Parakeet · 1.2 GB · once per phone`. Button: `Download model`
     → `Downloading · 42%` → `Model ready`.
   - Job 2 label = book title, key = `<duration> · about <estimate> on this phone` (`27 h 55 min ·
     about 20 min on this phone`). Button: `Transcribe book` → `Transcribing · 42%` → `Transcribed`.
     Disabled until the model is ready.
4. Nothing else. No spinner, no separate bar, no tab-bar change. Content sits on the rails
   (`Theme.inset`).

**`FillButton`** — the button is its own progress bar. One view, parameters
`(label: String, fraction: Double, phase: idle | busy | done, disabled: Bool, action)`:
- 48 pt high, full width, radius 24, clipped; background `Theme.accent`, text `Theme.onAccent`,
  15 pt semibold, monospaced digits.
- A leading overlay of width `fraction × width` in `accent` mixed 68 % with black
  (`color-mix(in srgb, var(--accent) 68%, #000)` → compute once in `Theme` as `accentDeep`).
- `done`: background `Theme.raise2`, text `Theme.ink2`, no overlay.
- `disabled` and not busy/done: opacity 0.35. Pressed: opacity 0.7.
- Label `"\(verb) · \(Int(fraction * 100))%"` while busy. Tapping while busy **stops** the job
  (the mockup disables the button while busy; the app cannot, because a running transcription must
  be cancellable — the label stays as the mockup shows and the accessibility label says
  "Stop transcribing"). Every control works; nothing is inert.

**Model job.** `ModelDownload` state on `TranscriptionJob`: `missing | downloading(fraction) | ready`.
`ready` = FluidAudio's model directory has the files (check the real path on 0.15.x). Progress:
use FluidAudio's download progress callback if 0.15.x exposes one; if it does not, download with
`URLSession` into FluidAudio's expected directory using its file manifest, reporting bytes /
expected total — the percent must be a real fraction, never animated time. Starting a model
download from the book button is never implicit: the book button stays disabled until `ready`.

**Estimate.** `"about N min on this phone"` = duration ÷ measured speed. Speed = seconds of audio
per wall second, measured per chunk and stored in `UserDefaults` (`transcribeSpeed`); before any
measurement use 80×. Format: `< 1 min` → "under a minute", `< 60` → "about N min", else "about N h M min".
Pure function `TranscriptionEstimate.text(duration:speed:)`; unit-tested at the three boundaries.

**Launch args for tests and screenshots** (`-uitest`): `-faketranscriber` swaps in
`FakeTranscriber`, `-model ready|missing|downloading` sets the model state, `-transcribed`
starts with a finished transcript. The UI test drives: model missing → tap Download → `Model
ready` → tap Transcribe → label contains `Transcribing` → `Transcribed`.

Validation: `scripts/test.sh full`, `scripts/verify.sh`, then screen-by-screen against
`http://localhost:8123/transcribe.html` in all three button states.

---

## Step 5 · Docs and the device pass

Files: `docs/ARCHITECTURE.md`, `docs/TESTFLIGHT.md`, `docs/IDEAS.md`.

1. `docs/ARCHITECTURE.md`: a "Background transcription" paragraph — the table at the top of this
   plan, condensed to five lines, plus the checkpoint rule and the no-GPU rule.
2. `docs/TESTFLIGHT.md`: add the device checklist, because the simulator cannot prove this:
   1. Install on the iPhone, import a real M4B, open it, Scan tab → Download model → Transcribe book.
   2. Lock the phone immediately. Expect the system progress pill on the lock screen within seconds.
   3. Leave it locked 5 minutes. Unlock. Expect the button's percentage to have advanced and, if the
      pill was dismissed, the job to resume by itself on reopening.
   4. Cancel from the pill once. Expect "Stop" semantics: reopen → resumes from the checkpoint.
   5. Plug in overnight with the job stopped. Expect progress next morning (processing fallback).
3. `docs/IDEAS.md`: park "GPU in the background" (needs the continued-processing GPU entitlement;
   ANE is enough for Parakeet) and "chunk overlap + dedupe" (dropped; one bad token per 5 min).

---

## Step 6 · Evidence and the PR

Files: `scripts/evidence.sh`, `docs/reports/2026-08-31-transcription/*.png`.

1. `scripts/evidence.sh`: replace the `04-scan-construction.png` shot with four Transcription shots
   using the step 4 launch args: `07-transcribe-model-missing.png`, `08-transcribe-downloading.png`
   (`-model downloading`, fake fraction 0.42), `09-transcribe-running.png` (`-model ready
   -faketranscriber` mid-run), `10-transcribe-done.png` (`-transcribed`).
2. Copy those four plus `01-library.png` and `02-player.png` (unchanged, proof nothing else moved)
   into `docs/reports/2026-08-31-transcription/` and commit them — `artifacts/` is scratch, the
   report folder is history.
3. Commit in steps (one commit per plan step), push `t3code/background-book-transcription`, open the
   PR against `main` with `gh pr create`. Body: what runs in the background and how (the table at
   the top of this plan), the device checklist from `docs/TESTFLIGHT.md`, and the screenshots
   inline via `https://github.com/luisKisters/Listnr/blob/t3code/background-book-transcription/docs/reports/2026-08-31-transcription/<file>?raw=true`.

## Risks

1. **Continued-task duration is the system's call.** Apple gives no number. Thermal load from ANE
   inference is the likely limiter on a 6-hour book; the checkpoint plus foreground resume plus the
   overnight fallback is the whole answer, not any single mechanism.
2. **Model download.** ~1 GB, first run only, needs network. Stated in the UI before start.
3. **File access when locked.** The M4B lives in a user folder behind a security-scoped bookmark.
   Files "On My iPhone" read fine after first unlock; iCloud Drive files that are not downloaded do
   not — `AppModel.ensureLocal` already covers the check; reuse it and refuse to start with the same
   iCloud notice playback uses.
4. **Simulator cannot run BGTaskScheduler.** All scheduler paths degrade to `task: nil`; the unit
   tests cover the job without it; the device checklist covers the rest.
5. **API drift in FluidAudio.** 0.15.x may have renamed things since the scan plan was written.
   Step 0 reads the source first.
