# Plan — bring Listnr to the locked mockups (Library B · Player A)

Source of truth: `mockups/library.html`, `mockups/audiobook.html`, `design/LOCKED.md`.
Existing app (`Listnr.xcodeproj`, PR #1) implements the OLD Library A + busy Player A. This plan migrates it.
Each step ends with a validation; stop when red.

## 1 · Sync tokens (½ h)
- `App/Sources/Theme.swift` ← `mockups/kit.css`: spacing s1–s9, type scale, inset rail 20, cover 64 (rows) / full-width square (player), accent purple `#8B5CF6` + neon `#2bff3e` behind one `Scheme` enum (default purple).
- Validation: build green; one `ThemeTests` asserting the token values.

## 2 · Library → variant B (2 h)
- Remove the filter-word row. Header: large title left, filter value + chevron right (`Menu` with All · Audiobooks · Ebooks · Paired · In progress).
- Row: 64px square cover, progress band inside the cover's bottom edge (1px hairline + 4px accent fill), meta line plain text. Resume rows (Listening / Reading) same grammar.
- Validation: UI test "filter menu → Ebooks shows 2 rows"; snapshot of a row at 390 vs `mockups` screenshot, guides-equivalent: leading edge 20, cover 64.

## 3 · Player → decluttered A (2 h)
- Identity block: title / author · narrator / chapter line (tap = wheel picker in the cover box).
- Delete the list-icon chapter row and the utility labels + Chapters item; utility = "1.0×" left rail, moon right rail.
- Scrubber: two times only. Gaps s5/s6 between groups; transport centered low.
- Validation: UI test "chapter line opens wheel, selection seeks"; no view touches the tab bar at 390×844 and 320×568 (layout test on frames).

## 4 · Device install (½ h) — Way A in `docs/testflight.md`
- Xcode → Signing (paid team) → Run on iPhone. Signature valid ~1 year; no TestFlight needed.
- Validation: app on phone, background audio + lock-screen controls with a real M4B from Files.

## 5 · Real files (1 day)
- Import via `.fileImporter` / share sheet; read real `AVAsset` chapters (replace synthetic even-split).
- Validation: import an own M4B, chapters match, position persists across relaunch.

## 6 · Notes = part of V0 (½ day) — app already has it; align to the mockup: pencil + quiet count on the player's right rail, sheet = pause glyph + live timestamp + chapter, bare editor, Cancel/Save, existing notes newest-first (tap seeks). Opening pauses; Save/Cancel resume only if it was playing.

## 7 · Later (in order): EPUB import + pairing → Reader tab → Scan-to-sync (Vision) → read-along → TestFlight external.
