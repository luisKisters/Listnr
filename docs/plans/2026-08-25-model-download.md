# Plan — the model download that survives

Date: 2026-08-25. Follows `2026-08-24-scan-to-position.md` (Addendum A2).

## Problem

The ASR model download (~460 MB, once per install) is unusable today:

1. No progress. `ScanView.startModelDownload()` (`App/Sources/Scan/ScanView.swift:459`)
   ignores FluidAudio's `progressHandler:`.
2. It dies. The download runs in a view-local `Task`. Dismissing the sheet, switching
   tab, or the phone locking kills it. FluidAudio cannot resume; the next try starts at 0.
3. It dismisses by accident. A plain `.sheet` closes on a tap outside, without asking.
4. The button sequence hides the real first step. For an unprepared book the bar says
   "Prepare this book" even when the model is missing, and the sheet pops up as a surprise.

## Decisions

- The download lives in `AppModel`, not the view. One published state.
- Progress is the honest fraction from FluidAudio. No fake bar.
- No pause. FluidAudio has no resume, so "pause" would lie. **Stop** is offered and
  named as what it is: the next download starts over.
- The download runs while the app is in the foreground only. iOS gives ~30 s after
  backgrounding via `beginBackgroundTask`; the sheet says so in one line. A true
  background transfer needs a `URLSession` background session FluidAudio does not
  expose. Not now.
- After the download the queued book starts preparing at once. The user already tapped.
- Mockup first, then app. The mockup stays the authority.

## Steps

### 1 · Mockup

Files: `docs/mockups/app.js`, `docs/mockups/scan.html`.

1. `Phone` gets `model: 'missing' | 'downloading' | 'ready'` and `modelFrac`.
2. `scanScreen`, `notprepared` branch (`app.js:1020`) and the A1 drum branch (`:1005`):
   when `model !== 'ready'` the key reads **"Download the model"** (`sc-model`), not
   "Prepare this book".
3. Tapping `sc-model` opens a bottom sheet in the phone frame: title "The audio AI model",
   one line "Matching a page needs the speech model on this device. It downloads once
   and stays. Keep Listnr open — it stops when the phone locks.", bar button
   **"Download"**, quiet **"Not now"**.
4. While downloading: the sheet shows a progress bar and percent, the bar button becomes
   **"Stop"**; tap outside does nothing. The Scan key under the sheet shows the same
   percent in the `working` style.
5. Done: sheet closes itself, the queued book goes straight to `preparing`.
6. Failed: the sheet line becomes "The model could not be downloaded. Check the
   connection and try again.", button **"Try again"**, quiet **"Not now"**.
7. Rails: add a `model` option (`missing / downloading / ready`) so every state is visible.

Stop point: open `scan.html`, walk missing → download → stop → download → done →
preparing, then failed → try again.

### 2 · AppModel owns the download

Files: `App/Sources/AppModel.swift`, `App/Sources/Scan/AsrModelCache.swift`,
`Tests/Unit/ScanStateTests.swift`.

1. `enum ModelDownload: Equatable { case missing, downloading(Double), failed, ready }`.
2. `@Published private(set) var modelDownload: ModelDownload`, set in `init` from
   `AsrModelCache.onDisk().isDownloaded()`; re-checked on `didBecomeActive` (the
   existing foreground observer).
3. `func downloadModel(then bookID: UUID?)`: guards against double start; starts a
   `Task` held in `modelDownloadTask`; calls `AsrModels.downloadAndLoad(version: .v3,
   progressHandler:)` and publishes the fraction; wraps the work in
   `UIApplication.beginBackgroundTask` / `endBackgroundTask`; on success sets `.ready`
   and, if `bookID` is set, calls `prepareForScanning(bookID:)`; on error sets `.failed`;
   on cancel sets `.missing`.
4. `func stopModelDownload()` cancels the task.
5. `prepareForScanning` guards `modelDownload == .ready`.
6. The cache check is injectable for tests as it is today (`AsrModelCache.present/.absent`).

Tests: state machine only — missing → downloading → ready runs the queued book;
failed keeps `preparationProgress` nil; stop returns to `.missing`; `.present` cache
means `.ready` at init and no sheet ever.

### 3 · The Scan tab follows the model state

Files: `App/Sources/Scan/ScanState.swift`, `App/Sources/Scan/ScanView.swift`,
`Tests/Unit/ScanStateTests.swift`.

1. `ScanLogic.key` gains `modelReady: Bool`. For `.notPrepared` and the A1 drum row it
   returns `.word("Download the model")` when false; `.working(fraction)` while
   `.downloading`. Tests for both.
2. `ScanView`: delete `download`, `pendingPreparationID`, `startModelDownload`. The
   sheet binds to `model.modelDownload`: presented when the user tapped "Download the
   model" and the state is not `.ready`. `.interactiveDismissDisabled(isDownloading)`.
3. `ModelDownloadSheet` renders the four states from step 1 of the mockup; buttons call
   `model.downloadModel(then:)`, `model.stopModelDownload()`, dismiss. A11y labels on all.
4. No dead controls: "Not now" only when not downloading; "Stop" only while downloading.

### 4 · Verify

1. `scripts/test.sh full` and `scripts/verify.sh` green.
2. Xcode MCP: render the `ModelDownloadSheet` previews (offer, downloading, failed).
3. Device: `xcodebuild … -destination id=DD1849A7-…` then
   `xcrun devicectl device install app` over Wi-Fi. Walk the real download once on the
   phone: progress moves, lock the phone → sheet says it stopped, Stop → Download again,
   done → book starts preparing. Add the pass to `docs/TESTFLIGHT.md`.

## Not in this plan

- Resumable or true background downloads (needs a FluidAudio fork).
- Sharing the model with other apps (sandbox forbids it).
- A settings screen for deleting the model.
