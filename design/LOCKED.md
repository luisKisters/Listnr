# Locked design decisions

Mockup wins over any written rule. These are locked; later iterations must not reopen them.

## App shell

- Four bottom tabs, always present: **Library · Audiobook · Reader · Scan**.
- Reader and Scan are under construction in V0: the tab shows an under-construction screen and
  nothing else. No dead controls anywhere.
- Library holds every title in every format. Resume cards ("Listening", "Reading") sit above the list.
- Audiobook tab = player for the last-listened audiobook. Reader tab (later) = last-read book.
  Paired titles share one position across formats.

## Library — variant A is chosen

- Title "Library" as large heading.
- Filter words in one row **under the title** (All · Audiobooks · Ebooks · Paired · In progress),
  active filter highlighted. Filters actually filter.
- Search field filters as you type.
- Two resume rows (Listening / Reading) above the "All books" section.
- Book row: cover left, title + author right, meta line under, progress line **under the cover only**
  — as wide as the cover and nothing else.
- Spacing rule (2026-08-22 feedback): bottom area of rows must breathe — consistent padding,
  no cramped stacking of progress line / meta line; elements are visually grouped.

## Player — variant A is chosen ("Cover top, controls low")

- Apple Music shape: top row with back chevron + format word; square cover on the content inset;
  identity (title, author · narrator); chapter row button; scrubber with three times
  (elapsed / chapter-left / remaining); transport = prev-chapter · back 15 · play · forward 30 · next chapter;
  utility row = Speed · Sleep · Chapters.
- Chapters opens **on top of** the cover, not in place of it: the wheel fills the cover's exact box
  while the artwork stays visible behind it, blurred and scrimmed, and blur + wheel fade in together.
  Opening or closing chapters therefore moves nothing else on screen.
  *Changed by the owner on 2026-08-24 after testing on device — this replaces the earlier locked
  trade "cover OR chapters visible, never both".*
- The cover is a square **on the rails** — exactly the content inset on both sides, the same span as
  the scrubber and the transport row — and it takes the vertical room that costs. The fixed margins
  are already at their floor; the flexible gap gives way first, and only an SE-class frame, where a
  rail-width square still does not fit, shrinks the cover, and then only by the deficit.
  *Owner decision, 2026-08-24.*
- The chapter line carries one quiet chevron (`chevron.down` closed, `chevron.up` open) so it reads
  as tappable. One glyph, no box and no label word. *Owner decision, 2026-08-24.*
- Chapter selection uses a **wheel picker** (the iOS time-picker drum), not a scrolling list.
  In SwiftUI this is native: `Picker` with `.pickerStyle(.wheel)`.
- Cover gets a **darkened treatment**: subtle scrim so light artwork does not glare at night;
  identity text stays outside the artwork.
- Speed cycles 1.0 → 1.2 → 1.5 → 1.75 → 2.0×. Sleep timer offers 15 / 30 / 60 / Off and really stops playback.
- No Listen / Read & Listen segment anywhere (post-MVP).
- Wheel click: use the system selection haptic (`UISelectionFeedbackGenerator`). There is no public
  API for the UIPickerView tick sound; do not fake it with audio files.

## Visual system

- Dark-first: near-black background (#050505 family), white ink ramp, purple accent for actions,
  per-book muted cover tones. SF Pro only, no bundled fonts. SF Mono for machine values (times).
- Alignment rails: content inset both sides; tab bar line at the bottom; guides overlay exists in
  mockups to verify rails.

## Capture

- Note capture is reachable from the player without leaving it (player top-row action).
  Saving a note pauses audio before and resumes after when it was playing.
