# Locked design decisions

Mockup wins over any written rule. These are locked; later iterations must not reopen them.

## App shell

- Four bottom tabs, always present: **Library · Audiobook · Reader · Scan**.
- Reader and Scan are under construction in V0: the tab shows an under-construction screen and
  nothing else. No dead controls anywhere.
- Library holds every title in every format. Resume cards ("Listening", "Reading") sit above the list.
- Audiobook tab = player for the last-listened audiobook. Reader tab (later) = last-read book.
  Paired titles share one position across formats.

## Library — variant B is chosen (2026-08-22, supersedes A)

- Title "Library" as large heading.
- Filter lives in the header as a value next to the title: "All ⌄". Tapping opens an in-place menu
  (All · Audiobooks · Ebooks · Paired · In progress). Filters actually filter. No filter row under the title.
- Search field filters as you type.
- Two resume rows (Listening / Reading) above the "All books" section.
- Book row: cover left, title + author right, meta line under. Progress is a band **inside the cover's
  bottom edge** (1px hairline over a 4px accent fill, inside the cover bounds). No lines outside covers.
- Spacing rule (2026-08-22 feedback): bottom area of rows must breathe — consistent padding,
  no cramped stacking of progress line / meta line; elements are visually grouped.

## Player — variant A is chosen, decluttered (2026-08-22)

- Apple Music shape, four calm groups with scale spacing: (1) top row back chevron + "AUDIOBOOK";
  (2) square cover on the inset rails; (3) identity block = title / author · narrator / **chapter line**
  (the chapter line is the only thing that opens Chapters); (4) scrubber with two times (elapsed left,
  remaining right — no in-chapter time); (5) transport prev-chapter · back 15 · play (dominant) · forward 30 ·
  next-chapter; (6) quiet utility row: "1.0×" on the left rail, moon (sleep) on the right rail — no word labels,
  no Chapters item. Gaps: s5/s6 tokens between groups; nothing touches the tab bar.
- Chapters (wheel) opens in the cover's box: cover OR wheel visible, never both (locked trade).
- Chapter selection uses a **wheel picker** (the iOS time-picker drum), not a scrolling list.
  In SwiftUI this is native: `Picker` with `.pickerStyle(.wheel)`.
- Cover gets a **darkened treatment**: subtle scrim so light artwork does not glare at night;
  identity text stays outside the artwork.
- Speed cycles 1.0 → 1.2 → 1.5 → 1.75 → 2.0×. Sleep timer offers 15 / 30 / 60 / Off and really stops playback.
- 2026-08-22 swap: sleep (moon) sits in the TOP row on the right rail (remaining time as quiet text beside it); the NOTE pencil + quiet count sits in the bottom utility row on the right rail (thumb zone), speed on the left rail.
- Library header: "Library" title, then "All ⌄" filter value and a "+" on the right rail. "+" opens the import sheet (V1: choose a folder; mock shows file rows).
- Scheme locked: Purple. Min iOS 26; tab bar = native Liquid Glass TabView.
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
