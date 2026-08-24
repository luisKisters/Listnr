# Testing

Written during implementation, per acceptance criterion — never retrofitted.

| Layer | Proves | Command |
|---|---|---|
| Unit (`ListnrTests`) | Chapter math, filtering/sort/search, note pause/resume policy, engine sleep timer, now-playing payload, formatting | `scripts/test.sh dev` |
| UI (`ListnrUITests`) | Golden paths: tabs + construction screens, filters/search, row → player, play/pause, chapter wheel seeks, speed/sleep, note round-trip | `scripts/test.sh full` |

Both run on the iPhone 17 Pro simulator with deterministic inputs: `-uitest` forces the
in-memory store and the fixed sample library, `-mockengine` swaps AVFoundation for the
deterministic engine. No test depends on wall-clock time or network. Covers are picsum-free
gradient placeholders, so tests never touch the network either.

## Determinism rules

- Every launch argument combination is set in `ListnrUITests.launch()`.
- Absence assertions poll (`waitAbsent`), presence uses `waitForExistence`.
- Row queries target list rows by their "… by …" label shape; pinned resume cards
  ("Resume listening/reading: …") stay above filters by design and must not be matched.

## Pre-push gate

`scripts/verify.sh` runs grep gates (no emoji in app code, accessibility labels on controls,
no `print` in app targets, no force-try in app code), `swiftlint`, a build and the unit suite.
