# HANDOFF — Scan feature orchestration (2026-08-24 evening)

For whichever agent picks this up. Read `AGENTS.md`, then
`docs/plans/2026-08-24-scan-to-position.md` (the spec; its end has the binding
Addendum A1/A2 and the Execution protocol). This file is only operational state.

## What was ordered

Owner wants the scan-to-position feature built entirely by `opencode/x-preview-f-free`
("Ox Alpha Free") subagents run via `opencode run --auto`; the main session only
orchestrates and verifies. Plus two owner tweaks, in the plan addendum:
A1 selector button flips to "Prepare this book" the moment an untranscribed book
settles in the drum · A2 model-download screen with animation, skipped when the
model is already on disk. No questions asked; heavy E2E; match the HTML mockup
exactly (`docs/mockups/scan.html#bar.lineunder` variant = button shape `bar`,
book line under frame).

## Infrastructure facts

- Xcode is open on this worktree's `Listnr.xcodeproj`. The xcode MCP bridge
  (`mcpbridge`, see `.mcp.json`) works when a workspace is open; without one
  `tools/list` hangs forever. Subagent MCP access is configured in
  `.opencode/opencode.json` (same bridge). Probe agent verified it end to end.
- The IDE window has a device destination selected → IDE build fails on signing.
  Irrelevant: verification authority is `scripts/test.sh dev` / `full` /
  `scripts/verify.sh` (explicit simulator destinations). Do not chase the IDE build.
- Subagents run like:
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; opencode run --model opencode/x-preview-f-free --auto --title <title> "<prompt>"`
  One transient provider failure ("Endpoint is unavailable") occurred ~22:00;
  retry after a short sleep worked pattern-wise.
- Agents make NO commits; working tree carries everything uncommitted,
  including older mockup edits from previous sessions (`docs/mockups/*` modified).
- Real test media lives in `~/Documents/audiobooks/` (three M4Bs incl.
  Känguru-Rebellion) — needed for Stage 5 honesty.

## Done and verified green (Stages = grouped plan steps)

| Stage | Plan steps | Result |
|---|---|---|
| 1 | 0 + 1 | FluidAudio 0.12.6 wired; ASR model cached in simulator; smoke test transcribes `Fixtures/speech.m4b` (36 tokens, conf 0.98); Transcript JSON store + `hasTranscript` + deletion tests. Note: `chapters.m4b` is a sine tone, useless for ASR — `speech.m4b` was added instead. |
| 2 | 2 + 3 | `Transcriber` actor (10-min windows, 4 s overlap, offset+dedupe, cancellable, temp-then-move); `PageMatcher` (5-word shingles, umlaut-preserving normalisation, vote clusters, conf ≥ 0.4 else no-match); chunk-vs-whole drift ≤ 0.11 s; all Step-3 test cases present. AppModel gained prepare/cancel + published progress. |
| 3 | 4 | `PageOCR` (Vision .accurate, de-DE/en-US, language correction); rendered-in-test German page OCRs at word match 1.0; OCR→matcher chain asserted. API is sync throwing; wrap in Task.detached later. |
| 4 | 5 + A1 + A2 | `ScanView` + `ScanState` (pure state machine) + `AsrModelCache` (stubbed both ways); all mockup states + `.noBook`; camera usage string; 13 unit tests. |
| 5 | 6 + 7 | `AppModel.jumpFromScan` (opens the scanned book if needed, seeks, persists, switches tab); `-scanfixture` (DEBUG only) injects page image + transcript; UI test `testScanJumpsToTheMatchedPosition` lands at 0.0 s delta; real M4Bs imported in simulator via the real picker; TESTFLIGHT.md real-camera checklist. |
| Review | — | Opus adversarial pass found 10 defects (stuck preparing state, camera stopped mid-capture, confidence ÷ hits, doubled progress, unread `preparationNotice`, uncallable cancel, A1 missing in mockup, fixture wiping transcripts, capture failure shown as no-match, inescapable reading state). All fixed. Confidence is now `best/totalShingles × best/hits`, so a repeated passage still lowers confidence. |

Every stage ended with `scripts/test.sh dev` + `scripts/verify.sh` ALL GATES GREEN.

Stages 4–5 were built by Opus 5 subagents (codex second opinion unavailable: this ChatGPT account rejects gpt-5.6-sol/5.4/5-codex). Final `scripts/test.sh full` + `scripts/verify.sh` green. Nothing committed.

## Open

- No book-deletion path exists in `ListnrStore` (rows only go `isMissing`), so plan step 1.5 "delete book → delete transcript" has no call site. Revisit when deletion is built.
- Real transcription of a full book and the real camera were not exercised (simulator); see `docs/TESTFLIGHT.md` checklist.
