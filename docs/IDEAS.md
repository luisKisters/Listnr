# Parked and rejected ideas

Checked before re-proposing anything below.

- **UIPickerView tick sound for the chapter wheel** — there is no public API for the system
  picker click; faking it with a bundled audio file would sound wrong on every device.
  We use `UISelectionFeedbackGenerator` instead. Revisit only if Apple exposes the sound.
- **Automated TestFlight upload tonight** — needs an App Store Connect API key (or app-specific
  password) that is not present in this environment. Documented manual path lives in
  `docs/TESTFLIGHT.md`. Revisit when a key is added to the environment or CI.
- **Real container chapter metadata parsing (M4B chapters)** — deferred: seeded books use
  even-split synthetic chapters with display names, matching the mockup model exactly. Real
  `AVAsset` chapter reading lands with real user files, post-V0.
- **EPUB import / Reader implementation** — V0 shows an under-construction screen by decision
  (PRODUCT.md). Nothing to build until pairing exists.
- **Scan-to-sync** — same as above; Vision OCR pipeline is post-MVP.
- **Player cover rail-to-rail on the device** — the mockup phone is `aspect-ratio:390/800`; a real
  iPhone 17 Pro has 402×729 usable, proportionally taller and narrower. A square cover on the rails
  (362pt) plus the step 3 margins (`s5` above, `s6` below, `s6` above the utility row, `s5` to the
  tab bar) needs 770pt of a 729pt column. Measured, not estimated. Reaching the rails would cost
  44pt taken out of those four margins and still leaves the cover 179pt short on an SE frame, so the
  screen would be rail-to-rail on one phone and badly inset on another. The cover stays square and
  inside the rails at whatever height is left. Revisit if the margins are ever reopened.
- **`AVPlayer` instead of `AVAudioPlayer` for iCloud files** — parked as the escalation, not the
  fix. `AVAudioPlayer(contentsOf:)` needs the whole file locally, so step 5 checks
  `ubiquitousItemDownloadingStatus`, calls `startDownloadingUbiquitousItem(at:)` and shows
  "Downloading from iCloud — this book plays once the file is local." instead of failing silently.
  Swap the engine to `AVPlayer` (it streams; the `PlayerEngine` protocol exists for exactly that)
  only if that download path turns out to be flaky for the 20-hour files this app is for.
- **Import speed is disk-bound, not code-bound** — measured 2026-08-24 against the owner's three
  real M4Bs (228/359/200 MB, 12/66/4 chapters). First scan: 1173 s. Second scan of the same files,
  page cache warm: **0.1 s**. Every individual `AVAsset` call is instant (`load(.duration)`,
  `.commonMetadata`, artwork `dataValue`, `loadChapterMetadataGroups` — 0.057 s in total for one
  file). So the cost is the first read of the bytes off disk, on a volume that is 93 % full, not
  anything the indexer does. No optimisation is warranted in the indexer. If the first import ever
  needs to feel faster, the lever is progress reporting per file, not parsing.
- **GPU for background transcription** — parked. A `BGContinuedProcessingTask` may request
  `.gpu` in `requiredResources` only with the `com.apple.developer.background-tasks.continued-processing.gpu`
  entitlement, which Listnr does not have. Core ML runs `.cpuAndNeuralEngine` instead, and the ANE
  is available while the phone is locked, so Parakeet has what it needs. Revisit only if ANE
  throughput turns out to be the limiter on a real book.
- **Chunk overlap and dedupe for transcription** — dropped, not deferred. Windows are 5 minutes
  and do not overlap, so a word cut on a boundary costs one bad token per 300 s. The scan matcher
  is a shingle matcher and tolerates that. Overlap would buy a token and cost a whole
  deduplication pass; that trade is not worth making.
- **Deleting a transcript when a book row goes** — nothing to hook. The library never deletes book
  rows: a vanished file is marked `isMissing` so notes and position survive, and `removeFolder`
  keeps its books for the same reason. Deleting the transcript on `isMissing` would throw away
  hours of work every time an external drive is unplugged. `TranscriptStore.remove(bookID:)` exists
  for whenever real row deletion lands.
- **Wildcard `BGContinuedProcessingTask` identifiers** — rejected by the OS, not by us. The plan
  wanted `com.luisKisters.Listnr.transcribe.*` in `BGTaskSchedulerPermittedIdentifiers` so every
  book could submit `…transcribe.<bookID>`. Measured on iOS 26.5 (simulator, 2026-08-31):
  `register(forTaskWithIdentifier: "com.luisKisters.Listnr.transcribe.*")` returns **false**, and
  submitting an identifier with no registered handler kills the app with an Objective-C exception
  that Swift's `try` cannot catch. The fallback in the plan's step 3 stop rule is what ships: one
  exact identifier `com.luisKisters.Listnr.transcribe`, and the model's pending-work field
  carries which book it is for — only one job runs at a time anyway. Revisit if a later iOS
  actually supports wildcard registration.

## Read-along (requested 2026-08-24)

Owner wants a **read-along** mode: the text and the audio move together, the way an ebook and its
narration do when they are aligned. Same transcript the scan feature builds, used continuously
instead of once — the word being spoken is the word being highlighted.

Not scoped yet. It depends on two things that do not exist: the transcript
(`docs/plans/2026-08-24-scan-to-position.md`) and the EPUB reader. Once both land, read-along is
mostly a matter of driving a highlight from the player's position through the same alignment the
matcher already computes, so it should be built on top of them rather than beside them.
