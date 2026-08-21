# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Native Swift 6 + SwiftUI, iOS 17+. Confirmed choices in ARCHITECTURE.md: AVFoundation playback, SwiftData storage (CloudKit-ready), Vision OCR, own fuzzy-match module, ZIPFoundation + SwiftSoup for EPUB text. No backend for MVP; everything on-device. The mockup.html in this repo is a design artifact only, not the product stack.

## Users

Primary user: Luis (the developer) — reads the same book across paper, EPUB, and audiobook, and listens with headphones while away from the phone. Has ADHD; capture of a fleeting thought must cost near-zero friction. Dictates a lot; German and English books. Secondary audience later: App Store customers with the same multi-format reading habit ("me first, App Store later").

## Product Purpose

One iOS app that treats a book as one thing with three formats (paper, EPUB, audio) and one shared position. It plays audiobooks, captures timestamped notes instantly, and lets you scan a physical page with the camera to jump the audiobook (and EPUB position) to that exact spot. Success: the fastest possible MVP that Luis uses daily, without a throwaway architecture.

## Positioning

Whispersync-style position sync without Amazon: works with DRM-free files you own, entirely on-device, and bridges the *paper* book too via camera OCR — something Audible/Kindle cannot do. Notes are first-class and tied to audio timestamps, not an afterthought.

## Operating Context

- Listening happens with the phone locked or pocketed; notes are usually triggered mid-listen.
- Books arrive as files: M4B (with chapters), MP3 sets, EPUB — imported via Files app or share sheet.
- The same title may exist in two or three formats; user pairs them per book.
- Reading also happens in KOReader and Apple Books; exported notes land in Obsidian (Markdown).
- Languages: English and German for UI content matching — OCR and fuzzy matching must handle both.

## Capabilities and Constraints

### V0 (confirmed 2026-08-21)
Pure M4B/audiobook player only — nothing else built out, but UI leaves quiet space for later features. Player UI modeled closely on Audible's player (Luis likes it: chapter row, transport lineup, bottom utility row). Personal use on Luis's phone first; maybe a waitlist page later to gauge interest.

### App structure (confirmed 2026-08-21)
Four bottom tabs: **Library · Audiobook · Reader · Scan**.
- Library = everything (all titles, any format), with filters (audiobooks / ebooks / paired / in progress).
- Audiobook tab = the player, always showing the last-listened audiobook.
- Reader tab = the ebook reader, always showing the last-read book.
- Coupling: when an ebook and an audiobook are paired they are one title with one position — opening either tab for it continues at the shared position; progress written in one is reflected in the other. Unpaired titles only appear in the tab of their format.
- Scan tab = scan-to-sync.
- Player is NOT Audible's "Listen / Read & Listen" segment at the top; read-along lives later as an option in the player's bottom utility row / via the Reader tab.
- V0 mock rule: features not built (Reader, Scan, read-along, sync) show an "Under construction" screen; every control that exists must work — no dead buttons.

### MVP (confirmed scope)
1. Audiobook player: M4B chapters, MP3, multi-file books; background audio; lock-screen controls; speed control; sleep timer optional.
2. Timestamped text notes: one tap opens a sheet, audio **auto-pauses and resumes on save** (confirmed default; setting to change). Notes list per book; tapping a note jumps playback.
3. Scan-to-sync: camera → on-device Vision OCR → fuzzy match against paired EPUB text → mapped audio timestamp → confirm → progress set in both formats.
4. Import and manual EPUB↔audio pairing.

### Hard constraints
- iOS gives **no API for "press both volume buttons"**. Working substitutes: Action button → App Intent, Lock Screen / Control Center widget (iOS 18 ControlWidget), Back Tap → Shortcut, Live Activity button.
- DRM-free files only; never touch Audible/Kindle DRM.
- All ML (OCR, later ASR/TTS) runs on-device; no cloud inference.

### Roadmap ideas (post-MVP, rough priority)

**Capture**
- Voice notes: record → on-device transcription (WhisperKit); store audio + transcript + timestamp.
- Action-button / lock-screen / Back-Tap triggers for instant voice capture (see constraints above).
- App Intents for everything (note, play, jump) so Shortcuts users build their own triggers.
- Interactive widget and Live Activity with a Note button.

**Sync between formats**
- Text↔time alignment map: v1 chapter matching + linear interpolation; later forced alignment via on-device ASR for word-level sync. Candidate library: FluidAudio (FluidInference, Swift, CoreML Parakeet ASR + VAD + diarization, on-device) to transcribe the audiobook — then OCR'd page text can match against the transcript directly, even without a paired EPUB. Evaluate against WhisperKit; pick one ASR stack for both voice notes and alignment.
- Read-along mode: EPUB text highlighted in sync with audio. Luis explicitly wants this as an Audible-style "Listen / Read & Listen" toggle in the player (confirmed 2026-08-21, "feature für später" — not V0).
- Scan → save matched paragraph as a highlight, not just jump.
- KOReader / Apple Books handoff: export progress + highlights (Markdown/JSON); maybe KOReader sync-server protocol.

**TTS (ebook → audiobook)**
- On-device neural TTS (Kokoro via MLX/CoreML; AVSpeechSynthesizer as fallback) for EPUBs without an audiobook.
- Pre-render chapters to audio files in background → normal player, notes, and scan all just work.
- Generated audio has exact text↔time alignment for free → perfect scan-to-sync and read-along.

**Notes & knowledge**
- Markdown export per book (Obsidian-friendly) with deep links back to timestamps.
- Auto-attach context: last ~30 s transcript or aligned EPUB paragraph per note.
- Tags, note types (thought, quote, vocab), review views.

**Player QoL**
- Smart rewind after pause, silence trimming, per-book speed, EQ/voice boost, bookmarks, listening stats.

**Later / big**
- CloudKit sync of metadata, progress, notes; Watch app; cross-device shared position; metadata/cover lookup; barcode scan to pair paper editions.

## Evidence on Hand

No real book files, covers, or user data in the repo yet. Mockups must use clearly plausible sample books and must not fabricate testimonials, ratings, or store claims. ARCHITECTURE.md and mockup.html exist as design/planning artifacts.

## Product Principles

1. Capture beats everything: a thought must be saved in under two seconds from a locked phone.
2. One book, one position: every feature reinforces the shared-progress model across formats.
3. On-device and file-based: user owns the files; no accounts, no cloud dependency for core use.
4. Ship the smallest daily-usable slice first; architecture may scale but never delays the MVP.
5. Native to the platform: iOS affordances (App Intents, widgets, lock screen) over custom re-inventions.

## Accessibility & Inclusion

Dictation-first user; voice input paths matter. Dynamic Type and VoiceOver expected for App Store phase; no additional confirmed requirements yet.
