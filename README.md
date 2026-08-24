<div align="center">

<img src="docs/assets/listnr-icon-512.png" alt="Listnr" width="112">

# Listnr

**One book, three formats, one position.**

An iOS audiobook player that keeps paper, EPUB and audio on the same page —
and lets you scan a printed page with the camera to jump the audio to that spot.

</div>

---

## What it is

Listnr treats a book as one thing you own in up to three formats. It plays your own
DRM-free audiobooks, captures notes stamped to the exact second, and (from V1) reads a
photo of a paper page with on-device OCR to move every format to that position.

Whispersync-style sync without Amazon. Everything runs on the device — no account, no backend.

| | |
|---|---|
| **Platform** | iOS 17+, Swift 6, SwiftUI |
| **Storage** | SwiftData (CloudKit-ready) |
| **Audio** | AVFoundation, background playback, lock-screen controls |
| **OCR** | Vision, English + German |
| **Backend** | none |

## Status — V0 runs on the simulator and on device

<p align="left">
  <img src="artifacts/01-library.png" alt="Library" width="240">
  <img src="artifacts/02-player.png" alt="Player" width="240">
</p>

Working today:

- **Library** — live search, filter words that really filter, Listening/Reading resume rows,
  progress line under each cover.
- **Player** — scrimmed cover, chapter row, draggable three-time scrubber, prev/back-15/play/
  forward-30/next, speed up to 2×, sleep timer, chapter wheel picker with selection haptic.
- **Notes** — the note button pauses audio, the sheet lists existing notes with jump-to-timestamp,
  saving resumes playback.
- **Background audio** — AVAudioSession + MPRemoteCommandCenter (verify on a real device).

Under construction: the **Reader** and **Scan** tabs show an under-construction screen and nothing
else. No dead controls anywhere.

## Run it

```bash
xcodegen generate          # after adding or removing files
open Listnr.xcodeproj      # iPhone 17 Pro simulator, then Cmd+R
```

Launch straight into a tab with the `-tab` argument (`library`, `audiobook`, `reader`, `scan`).

## Verify it

```bash
scripts/verify.sh          # grep gates + swiftlint + build + unit tests
scripts/verify.sh --no-tests
scripts/test.sh dev        # unit suite only
scripts/test.sh full       # unit + UI golden paths
scripts/evidence.sh        # boots the simulator and writes artifacts/*.png
```

`verify.sh` fails the build on emoji in source, stray `print()`, `try!`, `fatalError`,
un-owned TODOs, and buttons without an accessibility label.

## Design

The mockups are the source of truth for the UI; written rules lose against them.

```bash
python3 -m http.server 8741 --directory mockups
```

- `mockups/library.html`, `audiobook.html`, `reader.html`, `scan.html` — the locked screens
- `mockups/icon.html` — the ten app-icon concepts, scheme toggle at the bottom
- `design/LOCKED.md` — decisions that later iterations must not reopen
- `design/icon/` — the icon master SVGs; `scripts/make-icons.sh` rasterizes them

Visual system: near-black `#050505`, white ink ramp, purple accent `#8B5CF6`, SF Pro only,
SF Mono for times. No badges, no explanatory caption strips.

## Layout

```
App/Sources/      Kit (engine, models, math) · Library · Player · Store · Construction · Theme
App/Resources/    Assets.xcassets (app icon)
Fixtures/         generated sine-wave audio for the sample library
Tests/Unit  UI/   XCTest suites
design/           LOCKED.md, icon masters
docs/             plans, testing, TestFlight, review notes
mockups/          the design source of truth
scripts/          verify · test · evidence · make-fixtures · make-icons
project.yml       XcodeGen definition — edit this, never the .xcodeproj
```

## Documents

- [PRODUCT.md](PRODUCT.md) — product truth, scope, roadmap
- [ARCHITECTURE.md](ARCHITECTURE.md) — stack decisions and why
- [design/LOCKED.md](design/LOCKED.md) — locked design decisions
- [docs/testflight.md](docs/testflight.md) — device and TestFlight steps
- [docs/testing.md](docs/testing.md) — what is tested and how

## Content policy

The sample library ships with generated sine-wave audio and invented titles. No real book text,
audio, or artwork is bundled. Bring your own DRM-free files.
