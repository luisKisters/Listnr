# Parked and rejected ideas

Checked before re-proposing anything below.

- **UIPickerView tick sound for the chapter wheel** — there is no public API for the system
  picker click; faking it with a bundled audio file would sound wrong on every device.
  We use `UISelectionFeedbackGenerator` instead. Revisit only if Apple exposes the sound.
- **Automated TestFlight upload tonight** — needs an App Store Connect API key (or app-specific
  password) that is not present in this environment. Documented manual path lives in
  `docs/testflight.md`. Revisit when a key is added to the environment or CI.
- **Real container chapter metadata parsing (M4B chapters)** — deferred: seeded books use
  even-split synthetic chapters with display names, matching the mockup model exactly. Real
  `AVAsset` chapter reading lands with real user files, post-V0.
- **EPUB import / Reader implementation** — V0 shows an under-construction screen by decision
  (PRODUCT.md). Nothing to build until pairing exists.
- **Scan-to-sync** — same as above; Vision OCR pipeline is post-MVP.
