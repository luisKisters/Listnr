---
name: Listnr
description: Dark-first iOS audiobook player. Near-black ground, white ink ramp, one green accent, muted per-book cover tones. Calm groups, generous spacing, nothing decorative.
---
# Design

The mockups in `docs/mockups/` are the visual authority. This file states the rules they embody. When text and mockup disagree, the mockup wins.

## Visual system

- Ground: near-black (#050505 family). Ink: white ramp. Accent: green #2BFF3E, actions only. Per-book muted cover tones.
- Type: SF Pro only. SF Mono for machine values (times). No bundled fonts.
- Layout: content inset on both rails; spacing tokens s1–s9 from `docs/mockups/kit.css`; nothing touches the tab bar.
- No badges, caption labels, or emoji. Quiet text beats chips.
- Min iOS 26. Tab bar = native Liquid Glass `TabView`.

## App shell

- Four tabs, always present: Library · Audiobook · Reader · Scan.
- Reader and Scan show an under-construction screen in V0. No dead controls anywhere.
- Audiobook tab = player for the last-listened book. Paired titles share one position across formats.

## Library (mockup variant B)

- Large "Library" title. Filter is a value beside it ("All ⌄") that opens an in-place menu: All · Audiobooks · Ebooks · Paired · In progress. No filter row under the title.
- "+" on the right rail opens the import sheet (V1: pick a folder).
- Search filters as you type.
- Two resume rows (Listening / Reading) above "All books".
- Book row: cover left, title + author, meta line under. Progress is a band inside the cover's bottom edge (1px hairline over a 4px accent fill). No lines outside covers.
- Rows breathe: consistent bottom padding, grouped elements, no cramped stacking.

## Player (mockup variant A, decluttered)

Groups top to bottom, s5/s6 gaps between them:
1. Top row: back chevron, "AUDIOBOOK", moon (sleep) on the right rail with remaining time as quiet text.
2. Square cover on the rails, subtle dark scrim so light art does not glare.
3. Identity: title / author · narrator / chapter line. The chapter line is the only thing that opens Chapters, and carries a quiet chevron (down closed, up open) so it reads as tappable — one glyph, no box, no label word.
4. Scrubber with two times: elapsed left, remaining right.
5. Transport: prev chapter · back 15 · play (dominant) · forward 30 · next chapter.
6. Utility row: speed "1.0×" on the left rail, note pencil + quiet count on the right rail. No word labels.

- Chapters = wheel picker (`Picker` with `.pickerStyle(.wheel)`) shown in the cover's box, floating **over** the artwork, which stays visible behind it blurred and scrimmed. Blur and wheel fade in together, and the wheel takes the cover's exact frame, so opening or closing chapters moves nothing else on screen. Tick feedback = `UISelectionFeedbackGenerator`, commit on settle, no Done button.
  *Owner decision 2026-08-24 after device testing; replaces the earlier "cover or wheel, never both".*
- The cover takes the full rail width like every other element, and the vertical room that costs. The fixed margins sit at their floor and the flexible gap gives way first; only an SE-class frame, where a rail-width square cannot fit, shrinks the cover, and then only by the deficit.
- Speed cycles 1.0 → 1.2 → 1.5 → 1.75 → 2.0×. Sleep timer 15 / 30 / 60 / Off and really stops playback.
- No Listen / Read & Listen segment (post-MVP).

## Notes

- Pencil opens the note sheet without leaving the player. Opening pauses playback; Save or Cancel resumes if it was playing.
