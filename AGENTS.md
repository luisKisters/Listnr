# Listnr — agent instructions

Listnr (iOS, Swift 6 + SwiftUI) — one book, three formats (paper / EPUB / audio), one shared position.
V0 = audiobook player + timestamped notes; Reader and Scan are visible tabs that say "under construction".

## The documents

| File | What it owns |
|---|---|
| `PRODUCT.md` | Product scope, V0 decisions, hard constraints, roadmap. Read before any feature work. |
| `ARCHITECTURE.md` | Stack decisions (AVFoundation, SwiftData, Vision later). |
| `design/LOCKED.md` | Locked UI decisions. Do not reopen them. Mockup wins over written rules. |
| `docs/plans/*.md` | Execution plans with validation commands and stop points. The current plan is the newest file there. |
| `docs/testing.md` | What is tested at which layer, and the commands. |
| `mockups/` | Interactive HTML mockups — the visual specification. Serve: `cd mockups && python3 -m http.server 8123`. |

Every UPPERCASE `.md` added under `docs/` belongs in this table.

## Commands

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # required on this machine
xcodegen generate            # regenerate Listnr.xcodeproj from project.yml (after adding files)
scripts/test.sh dev          # fast unit suite on the simulator
scripts/test.sh full         # unit + UI suite on the simulator
scripts/verify.sh            # grep gates + swiftlint + build + unit tests — run before every push
```

Never call raw `xcodebuild test` without `DEVELOPER_DIR` set — this machine's default is CommandLineTools.

## Before changing anything user-visible

1. Read `design/LOCKED.md`.
2. Open the mockup (`http://localhost:8123/library.html`, `audiobook.html`) and click through it.
When a written rule and the mockup disagree, **the mockup wins**.

## Standing rules

- Every tappable control works; no dead buttons. Unbuilt features show an under-construction screen.
- No emoji anywhere in app code or UI copy.
- Tests are written during implementation, per acceptance criterion — not retrofitted afterwards.
- Review order: review → fix → end-to-end. A failed E2E goes back to fix, never to review.
- Parked/rejected ideas go in `ideas.md` with a reason; check it before re-proposing anything.

## Parked ideas

See `ideas.md` at repo root.
