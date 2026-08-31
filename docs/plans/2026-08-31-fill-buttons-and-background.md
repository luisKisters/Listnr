# Plan — Fill buttons and background preparation (2026-08-31)

On top of `docs/plans/2026-08-24-scan-to-position.md` (built, uncommitted until `eb1255e`).
Owner's ask: the **model download button and the "Prepare this book" button become fill
buttons** — the button is its own progress bar — and **preparation and the download keep running
when the phone is locked**. Nothing else on the Scan screen changes.

Built by `opencode-go/glm-5.3-flash` agents (`opencode run --auto`), one stage each; the main
session verifies every stage with `scripts/verify.sh` and `scripts/test.sh dev|full`.

## Visual authority

`docs/mockups/transcribe.html` + the `.ios .fill` block at the end of `docs/mockups/kit.css`
(both from `/Users/kisters/.t3/worktrees/audiobookr/t3code-3633dd77/docs/mockups/`, copied here):

- The pill keeps its colour (`accent`, text `onAccent`). A leading overlay of width
  `fraction × width` in **`accentDeep`** = accent mixed 68 % with black
  (`color-mix(in srgb, var(--accent) 68%, #000)`). Overlay width animates linearly.
- Label while busy: `"<Verb> · 42%"`, tabular digits. Verbs: `Downloading`, `Preparing`.
- Done: background `raise2`, text `ink2`, no overlay (`Model ready`).
- Disabled and not busy: opacity 0.35. Pressed: opacity 0.7.
- No separate bar, no spinner, no ring.

## Background — what iOS allows (verified in the iOS 26.5 SDK headers)

`BGContinuedProcessingTask` (iOS 26): started in the foreground, keeps running after lock with a
system progress pill and a cancel. Default resources = CPU + network; no GPU (Core ML stays on
`.cpuAndNeuralEngine`). Must report progress via `task.progress` or it gets expired. One exact
identifier — wildcard registration returned `false` on 26.5 — so `com.luisKisters.Listnr.transcribe`
serves both the download and the preparation, one at a time. `BGProcessingTask`
(`…transcribe-resume`, `requiresExternalPower`) advances a checkpointed preparation overnight.
When submission fails (simulator, or a refusing phone) the work runs in-app exactly as today.

Reference implementation to copy from, read-only:
`/Users/kisters/.t3/worktrees/audiobookr/t3code-3633dd77/App/Sources/Transcript/TranscriptionJob.swift`
and `…/ListnrApp.swift` (registration) and `…/project.yml` (Info.plist keys).

---

## Stage A · `FillButton`, and the two buttons that use it

Files: `App/Sources/Scan/FillButton.swift` (new), `App/Sources/Theme.swift` (`accentDeep`),
`App/Sources/Scan/ScanView.swift`.

1. `FillButton(label: String, fraction: Double?, done: Bool, disabled: Bool, action)`: height 56
   (the Scan key's height today), `Capsule`, clipped; the rules above. `fraction == nil` → plain pill.
2. Scan key: `.working(fraction)` where `fraction != nil` renders as the fill button with the
   label `Downloading · N%` when `isDownloadingModel`, else `Preparing · N%`. `.working(nil)`
   (reading, searching) keeps today's spinner. `.word` and `.shutter` unchanged.
3. `ModelDownloadSheet`: the button becomes a fill button — `Download model` → `Downloading · N%`
   (tap = stop, as today) → the sheet closes on `.ready` as today. Delete the hairline `progress(_:)`
   view; the button is the bar now. Copy stays.
4. Accessibility labels unchanged.

Validation: `scripts/verify.sh`; `scripts/test.sh full` (existing UI tests must still pass).

## Stage B · Checkpointed, resumable transcription

Files: `App/Sources/Transcript/Transcript.swift`, `App/Sources/Transcript/Transcriber.swift`,
`Tests/Unit/TranscriptTests.swift`, `Tests/Unit/TranscriberChunkingTests.swift`.

1. `TranscriptCheckpoint { bookID, nextOffset: TimeInterval, duration: TimeInterval, words }`,
   stored at `Transcripts/<bookID>.partial.json`: `Transcript.saveCheckpoint`, `loadCheckpoint`,
   `deleteCheckpoint`. `Transcriber.write` deletes the partial after the final move.
2. `Transcriber.transcribe(url:bookID:from:onProgress:)` — `from` defaults to 0. The reader's
   `timeRange` starts at `from`; `windowStart = from`; the first window after a resume drops the
   overlap exactly like a non-first window (`firstWindow = from == 0`), so no word is doubled.
   After every full window the checkpoint is written (words so far + `nextOffset = windowStart`).
3. `AppModel.runPreparation` loads the checkpoint, passes `from`, and seeds `preparationProgress`
   with `nextOffset / duration`. Cancel keeps the checkpoint; "Stop" is "pause".

Validation: unit tests — checkpoint round-trip; a run of `Fixtures/speech.m4b` stopped after one
window and resumed from its checkpoint yields the same words as one uninterrupted run (behind the
existing `LISTNR_ASR_SMOKE` gate); `scripts/verify.sh`.

## Stage C · The background job

Files: `project.yml`, `App/Sources/ListnrApp.swift`, `App/Sources/AppModel.swift`.

1. `project.yml` Info.plist: `UIBackgroundModes: [audio, processing]`,
   `BGTaskSchedulerPermittedIdentifiers: [com.luisKisters.Listnr.transcribe, com.luisKisters.Listnr.transcribe-resume]`.
   `xcodegen generate`.
2. `ListnrApp.init` registers both handlers before launch finishes and stores each `register`
   result; an unregistered identifier is never submitted (submitting one raises an ObjC exception).
3. `AppModel.prepareForScanning` and `downloadModel(then:)` submit a
   `BGContinuedProcessingTaskRequest(identifier: …transcribe, title:, subtitle:)` (`.queue`);
   the handler runs the pending work inside the task: `task.progress.totalUnitCount = 100`,
   `completedUnitCount` from the fraction, `expirationHandler` cancels the Swift task,
   `setTaskCompleted` at the end. Submission failure → run in-app as today (the existing
   `beginBackgroundTask` stays as the 30 s flush).
4. Foreground resume: in the existing foreground observer, if a checkpoint exists for a
   non-missing book, the model is ready and nothing runs → `prepareForScanning(bookID:)` again.
5. Overnight: after cancel/expiry/failure with a checkpoint on disk, submit the
   `…transcribe-resume` `BGProcessingTaskRequest` (`requiresExternalPower = true`); its handler runs
   the same preparation and resubmits if unfinished. Cancel the pending request on completion.
6. `ModelDownloadSheet` copy: drop "Keep Listnr open — it stops when the phone locks." — it no
   longer does. `ScanView` `.notPrepared` sub-line already says preparation runs in the background.

Validation: `scripts/verify.sh`, `scripts/test.sh full`.

## Stage D · Evidence, device, PR

1. `scripts/evidence.sh`: add Scan shots for the fill states (`-scanfixture`-style launch args
   already exist; add `-model downloading` / `-preparing` overrides if needed) →
   `docs/reports/2026-08-31-fill-buttons/`.
2. `docs/TESTFLIGHT.md` device checklist: prepare → lock → pill appears → progress advances →
   cancel from pill → reopen resumes from the checkpoint; same for the download.
3. Device build: `DEVELOPMENT_TEAM: 4C8444267Z` in `project.yml`; build + install on
   `Luis iPhone` (`DD1849A7-182C-539C-8FFE-303B9D58971D`).
4. Commit per stage, push `t3code/scan-to-position`, open the PR against `main`.
