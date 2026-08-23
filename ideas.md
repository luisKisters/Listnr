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
- **Player cover rail-to-rail on the device** — the mockup phone is `aspect-ratio:390/800`; a real
  iPhone 17 Pro has 402×729 usable, proportionally taller and narrower. A square cover on the rails
  (362pt) plus the step 3 margins (`s5` above, `s6` below, `s6` above the utility row, `s5` to the
  tab bar) needs 770pt of a 729pt column. Measured, not estimated. Reaching the rails would cost
  44pt taken out of those four margins and still leaves the cover 179pt short on an SE frame, so the
  screen would be rail-to-rail on one phone and badly inset on another. The cover stays square and
  inside the rails at whatever height is left. Revisit if the margins are ever reopened.
