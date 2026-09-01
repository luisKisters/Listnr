# Plan — Scan book switch (2026-09-01)

On top of `docs/plans/2026-08-31-fill-buttons-and-background.md` (built, uncommitted).

Problem: the Scan book drum (`bookDrum` in `ScanView.swift`) needs an extra tap on the close X after picking a different book. Entering `.selecting` also stopped the camera, so closing left a blank viewfinder until restart.

## Goal

Picking a different book on the drum closes the drum at once and the live viewfinder is back immediately. Picking the same book leaves the drum open. The camera session keeps running while the drum is open.

## Code changes

- `App/Sources/Scan/ScanView.swift`:
  - `bookDrum` `Picker` binding setter: after `scanBookID = newValue` also `selectorOpen = false` (inline). Only runs on an actual change; settling on the same value does not fire the setter.
  - `onChange(of: state)`: `if new == .idle { camera.start() } else if new != .reading && new != .selecting { camera.stop() }` — do not stop for `.selecting`. Comment updated. No new types.
- `docs/mockups/app.js` — already done:
  - `Phone.prototype.scanPick(id)`: early return if `!id || id === st.book`; else `st.sel = false`, `st.scan = 'idle'`, `st.book = id`. Comment above it updated to say settling on a different row closes the drum so the viewfinder is back at once; same book leaves it up.
- `docs/DESIGN.md`, `docs/PRODUCT.md`: already checked — no sentence describes the drum staying up, so no change.

## Acceptance criteria

1. Different book closes the drum and shows that book's not-prepared frame — UI test `testPickingAnotherBookClosesTheSelector` in `Tests/UI/ListnrUITests.swift` (like `testScanJumpsToTheMatchedPosition`: launch `-uitest -mockengine -scanfixture -tab scan`, tap button `Book to match against: <title>`, `app.pickerWheels.firstMatch` `adjust(toPickerWheelValue:)` to another sample title, `waitAbsent` wheel and selector label is `Book to match against: <new>`; under `-scanfixture` only the current book has a transcript, so the stage shows that book's not-prepared frame and the shutter is not asserted).
2. Same book does not close — drum stays until the X; existing close-X path. No new test.
3. `ScanLogic.state` with `selectorOpen == false` returns `.idle` regardless of other scan state — already covered in `Tests/Unit/ScanStateTests.swift` (`testEveryScanPhaseHasItsOwnState` etc.). Not duplicated.

## Validation

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
scripts/verify.sh
scripts/test.sh full
```

## Stop points

None.
