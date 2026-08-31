# Listnr — Tech Stack & Architecture

Goal: ship the MVP fast, native, no dead-end stack.

## Stack (all first-party where possible)
- **Language/UI**: Swift 6 + SwiftUI. iOS 17+ minimum (drops legacy pain, keeps 90%+ of devices).
- **Playback**: AVFoundation (`AVAudioEngine`/`AVPlayer`), `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` for lock screen, background-audio capability. M4B chapters via `AVAsset` metadata.
- **Persistence**: SwiftData (models: Book, AudioFile, Chapter, Note, ProgressState). It is CloudKit-ready for later sync. If SwiftData fights you, GRDB (SQLite) is the proven fallback.
- **Files**: books live in the app's Documents directory (visible in Files app). Import via `.fileImporter` + share extension. Security-scoped bookmarks for external folders.
- **OCR**: Vision framework (`VNRecognizeTextRequest` / new `RecognizeTextRequest`). On-device, fast, free.
- **Fuzzy match**: own module — normalize text, n-gram / token-based sliding window over the EPUB text with edit-distance scoring. Pure Swift, unit-testable, no dependency needed.
- **EPUB parsing**: EPUB = ZIP + XHTML. Use `ZIPFoundation` + `SwiftSoup` to extract plain text per chapter. (Readium Swift toolkit only if/when a full ebook *reader* view is added.)
- **ASR/TTS (post-MVP)**: FluidAudio (CoreML Parakeet ASR, VAD, diarization — on-device, Swift-native) is the primary candidate for transcribing audiobooks (alignment, scan-to-sync without EPUB) and voice notes; WhisperKit is the alternative — evaluate both, pick one stack. TTS: MLX/CoreML-based (e.g. Kokoro); MVP fallback `AVSpeechSynthesizer`.
- **Shortcuts**: App Intents framework (also powers Action button, widgets, Control Center control later).
- **Zero third-party SaaS.** No backend for MVP. Everything on-device.

## Architecture
- MVVM-ish with plain observable services; no heavy framework (no TCA — slows shipping).
- Feature modules as Swift Package targets once it grows; single app target for MVP.

```
App (SwiftUI)
 ├─ LibraryFeature      → import, book list, pairing EPUB↔audio
 ├─ PlayerFeature       → PlaybackService (AVFoundation), now-playing, speed, sleep
 ├─ NotesFeature        → NoteCapture sheet, notes list, jump-to-timestamp
 ├─ ScanFeature         → CameraView → OCRService (Vision) → MatchService (fuzzy)
 ├─ EbookKit            → EPUBParser (zip+xhtml→plain text w/ chapter offsets)
 ├─ AlignmentKit        → text-position ↔ audio-time map (v1: chapter+interpolation)
 └─ Storage             → SwiftData models + file manager
```

### Scan-to-sync flow (v1)
1. Vision OCR on the camera frame → recognized lines.
2. Normalize (lowercase, strip punctuation/hyphenation).
3. Fuzzy search in the paired EPUB's plain text → best chapter + character offset.
4. AlignmentKit maps offset → audio time: match EPUB chapter to M4B chapter, then linear interpolation by character position within the chapter. Good enough for v1; forced alignment later makes it word-exact.
5. Confirm card → set progress in player + store EPUB position.

## Background transcription

Scan-to-position needs a word-level transcript of the audiobook, and a 28-hour book cannot be
transcribed while the user stares at the screen. Four mechanisms, in order of what carries the work:

| Mechanism | Runs when locked? | Role |
|---|---|---|
| `BGContinuedProcessingTask` (iOS 26) | Yes — the user starts it in the foreground, the system keeps it alive and shows its own progress pill with a cancel. | **Primary.** Expires under thermal, battery or user action. |
| `BGProcessingTask` | Yes, when the system decides (idle, usually charging). | **Overnight fallback** for a job that expired. |
| `audio` background mode (already on) | Yes, while a book plays. | Free bonus, no code. |
| Silent-audio hack | — | Rejected: App Store policy, and dishonest. |

Two rules make it survivable:

- **Checkpoint per chunk.** Audio is transcribed in 5-minute windows; every finished window is
  written to `Application Support/Transcripts/<bookID>.partial.json`. The job can be killed at any
  instant, so the partial file *is* the feature — a restart continues from `nextOffset`. Only the
  last window promotes it to `<bookID>.json`. "Stop" keeps the checkpoint; it is a pause.
- **No GPU.** Core ML runs `.cpuAndNeuralEngine`. A continued-processing task may not touch the GPU
  without an entitlement Listnr does not have, and the ANE is available while the phone is locked.

Recognition is FluidAudio's Parakeet TDT v3 (Core ML, on-device, ~1.2 GB downloaded once per phone).
`Transcriber` is an actor with no UI and no SwiftData, like `LibraryIndexer`; `TranscriptionJob`
(`@MainActor`) owns the one running job and every scheduler path. Nothing leaves the device.

## Scaling path (why this stack doesn't dead-end)
- SwiftData → flip on CloudKit sync for multi-device.
- App Intents already built → Action button, widgets, Watch, Siri come almost free.
- AlignmentKit interface stays; swap interpolation for forced alignment without touching UI.
- TTS renders to normal audio files → the existing player/notes/scan pipeline just works on generated audiobooks.

## Ship plan (MVP milestones)
1. Import + library + M4B/MP3 player with background audio & lock screen. (This alone is a usable app.)
2. Notes with timestamps + notes list + jump.
3. EPUB pairing + parser + scan-to-sync.
4. TestFlight.
