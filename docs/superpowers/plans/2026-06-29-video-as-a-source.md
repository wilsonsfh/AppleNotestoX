# Video as a Source (P2) Implementation Plan

> REQUIRED SUB-SKILL: superpowers:executing-plans. Steps tracked via checkboxes.

**Goal:** Transcribe video (imported file or Apple Note attachment) + extract keyframes, and write a provenance-stamped transcript note into the wiki vault.

**Architecture:** Apple Speech (on-device) behind an `AudioTranscriber` protocol; AVFoundation for audio/keyframe extraction (macOS-14 completion-handler APIs); pure `VideoSupport`/`TranscriptDocument` for testable logic; `VideoIngestCoordinator` writes the note reusing P1's `WikiNaming`/`WikiVaultConfig`.

## Global Constraints
- macOS 14+: use `exportAsynchronously(completionHandler:)` and `generateCGImagesAsynchronously(forTimes:)` (async `export(to:as:)`/`image(at:)` are macOS 15/16).
- Chunk audio ≤ 55s (Apple ~1-min limit).
- `requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition`; never silently go online.
- Embed `NSSpeechRecognitionUsageDescription` via linker; do not break the Notion path.
- Explicit-pathspec commits.

## Tasks

### Task 1: `VideoSupport` (pure) + tests
- Create `Sources/AppleNotestoX/Services/VideoSupport.swift`, `Tests/AppleNotestoXTests/VideoSupportTests.swift`.
- `videoExts = ["mov","mp4","m4v","qt","avi","mkv","webm","mpg","mpeg"]`
- `isVideo(ext:)` / `isVideo(url:)` (lowercased).
- `chunkRanges(duration:maxChunk:=55)` → consecutive `(start,length)` covering `[0,duration]`, each ≤ max; empty if duration ≤ 0.
- `keyframeTimestamps(duration:count:)` → `count` points at `(i+1)/(count+1)*duration`; `[]` if count≤0 or duration≤0.
- Verify: chunkRanges(130,55)=[(0,55),(55,55),(110,20)]; (110,55)=[(0,55),(55,55)]; (30,55)=[(0,30)]; keyframeTimestamps(100,3)=[25,50,75].

### Task 2: `Transcript` model (pure)
- Create `Sources/AppleNotestoX/Models/Transcript.swift`: `TranscriptSegment`, `VideoTranscript` (+ `fullText` joining segment text with spaces).

### Task 3: `TranscriptDocument` (pure) + tests
- Create `Sources/AppleNotestoX/Services/TranscriptDocument.swift`, `Tests/.../TranscriptDocumentTests.swift`.
- `static func markdown(transcript:keyframes:title:sourceName:sourceApp:modified:exported:) -> String`
  - `keyframes: [(t: Double, filename: String)]` sorted by `t`.
  - Frontmatter (origin: transcribed, source_type: video-transcript, engine, source_video, duration_seconds, dates) + machine-transcribed banner.
  - Body: `## Transcript`, then walk segments in order; before a segment whose `start >= nextKeyframe.t`, emit `![[filename]]`; emit `**[mm:ss]** text` per segment.
  - `mmss(_:)` → `"M:SS"` (or `"MM:SS"`), zero-padded seconds.
- Verify: frontmatter keys present; banner present; a keyframe at t=0 appears before first segment; mm:ss formatting (65→"1:05").

### Task 4: `AudioTranscriber` protocol + `AppleSpeechTranscriber` (runtime)
- Create `Sources/AppleNotestoX/Services/Transcriber.swift` (protocol) and `AppleSpeechTranscriber.swift`.
- `protocol AudioTranscriber: Sendable { func transcribe(audioFileURL: URL) async throws -> String }`
- Apple impl: authorize; `SFSpeechRecognizer(locale:)`; `SFSpeechURLRecognitionRequest`; on-device + punctuation; continuation on `result.isFinal`. Clear errors.
- Verify: `swift build`.

### Task 5: `VideoTranscriptionService` + `VideoIngestCoordinator` (runtime)
- `VideoTranscriptionService.transcribe(videoURL:keyframeCount:) async throws -> (VideoTranscript, [URL])`: load `AVURLAsset`; duration; extract full m4a (temp); per `chunkRanges` export sub-audio (timeRange) → transcribe → append segments with offset; `keyframeTimestamps` → save PNGs to a temp dir.
- `VideoIngestCoordinator.ingest(videoURL:title:config:sourceApp:) async throws -> WikiExportResult`: run service; copy keyframes to `raw/assets/` (`<slug>-kf-NN.png`, collision-safe); copy original video to assets; `TranscriptDocument.markdown(...)`; write `raw/journal/<date>-<slug>-transcript.md` (collision-safe).
- Verify: `swift build`.

### Task 6: AppState + UI + Info.plist
- `AppState`: `videoCoordinator`; `importVideo(url:)`; `transcribeNoteVideos` toggle; in `runWikiExport`, after each note, if toggle on, ingest its video attachments.
- `DestinationPane` Wiki pane: "Import video…" button (NSOpenPanel, video types) + "Transcribe video attachments" Toggle.
- `Package.swift`: add `linkerSettings: [.unsafeFlags(["-Xlinker","-sectcreate","-Xlinker","__TEXT","-Xlinker","__info_plist","-Xlinker","AppleNotestoX-Info.plist"])]`; create `AppleNotestoX-Info.plist`.
- Verify: `swift build`; confirm `__info_plist` section embedded (`otool`/`size`).

### Task 7: Verify + commit + PROGRESS_REPORT + merge
- `swift build`; run `swiftc` harness for VideoSupport + TranscriptDocument; atomic commits; update PROGRESS_REPORT; merge to main.
