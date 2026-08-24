# Listnr — agent instructions

Listnr: iOS, Swift 6 + SwiftUI. One book, three formats (paper / EPUB / audio), one shared position. V0 = audiobook player + timestamped notes; Reader and Scan tabs say "under construction".

## Where to look

| Read | When |
|---|---|
| `docs/PRODUCT.md` | Before any feature work: scope, decisions, constraints, roadmap. |
| `docs/DESIGN.md` | Before anything user-visible: the visual rules. |
| `docs/mockups/` | Before anything user-visible: the visual authority. Mockup beats written rule. |
| `docs/ARCHITECTURE.md` | Before touching playback, storage, or import. |
| `docs/TESTING.md` | Before writing or running tests. |
| `docs/TESTFLIGHT.md` | When installing on a device or shipping. |
| `docs/IDEAS.md` | Before proposing something; parked and rejected ideas live here with reasons. |
| `docs/plans/` | The current plan is the newest file. Follow its validation steps and stop points. |
| `docs/reports/` | Past status reports and reviews. History only. |

Mockups: `index.html` is the entry; one HTML file per tab (`library`, `audiobook`, `reader`, `scan`); `kit.css` holds the tokens, `app.js` the behavior. Serve: `cd docs/mockups && python3 -m http.server 8123`.

Every UPPERCASE `.md` under `docs/` belongs in the table above.

## Commands

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # required; default here is CommandLineTools
xcodegen generate            # regenerate Listnr.xcodeproj from project.yml after adding files
scripts/test.sh dev          # fast unit suite on the simulator
scripts/test.sh full         # unit + UI suite
scripts/verify.sh            # grep gates + swiftlint + build + unit tests; run before every push
```

## Rules

- Minimal: every added instruction, file, or line must be the smallest thing that solves the actual ask.
- YAGNI: build what is asked, not what might be asked.
- No speculative abstraction: wait for the third occurrence before extracting.
- Fewest moving parts: one function over a hierarchy, one file over a tree, plain data over custom types, a direct call over indirection.
- Dependencies are deliberate: standard library first; add one only when it carries real weight.
- Delete, do not disable: no commented-out code, dead branches, or notes about obsolete requirements.
- Every tappable control works. Unbuilt features show an under-construction screen.
- No emoji in app code or UI copy. No badges or caption labels.
- Tests are written during implementation, per acceptance criterion.
- Review order: review → fix → end-to-end. A failed E2E goes back to fix, never to review.

## Communication

- Answer first. No preamble, no restating the question, no filler.
- Short sentences. Scannable. Technical terms are fine; wordiness is not.
- Cut fluff, never substance.
- Multi-step work: short numbered list, one action per step.
- Do the work with tools instead of asking the user to do it.
- End with one clear next step, or say what now works.
