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
