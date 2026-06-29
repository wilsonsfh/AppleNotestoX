# Video as a Source (P2) — Design

- **Date:** 2026-06-29
- **Status:** Approved (owner-delegated: "complete all priorities; recommended option each time")
- **Project:** `AppleNotestoX` (Swift, macOS 14+)
- **Depends on:** P1 (wiki export) — reuses `WikiNaming`, `WikiVaultConfig`, vault layout.

## 1. Problem & scope

Bring **video** into the wiki as a first-class source: transcribe it to text and
pull representative keyframes, then write a provenance-stamped **transcript note**
into the vault for the existing LLM-wiki ingest to synthesize.

**In scope (P2):**
- Transcribe a **video file the user imports** (`.mov/.mp4/.m4v/…`) and/or a **video
  attachment found inside an Apple Note** during wiki export.
- Extract evenly-spaced **keyframes** and embed them at their timestamps.
- Write `raw/journal/YYYY-MM-DD-<slug>-transcript.md` + keyframes in `raw/assets/`,
  clearly marked **machine-transcribed**.

**Out of scope (later):** YouTube/remote URLs (needs `yt-dlp`); speaker diarization;
editing transcripts in-app; live recording. Noted as follow-ups.

## 2. Decisions (recommended)

1. **Engine:** Apple **`SFSpeechRecognizer`** (on-device) behind a `Transcriber`
   protocol. Zero model download, SwiftPM/no-Xcode friendly. **WhisperKit** is the
   documented upgrade path (swap the protocol impl).
2. **Chunking:** split extracted audio into **≤55s** windows (Apple's ~1-min limit),
   transcribe each, concatenate with running timestamps. Non-negotiable for correctness.
3. **Audio/keyframes:** AVFoundation `AVAssetExportSession` (preset `AppleM4A`, per-chunk
   `timeRange`, completion-handler API) + `AVAssetImageGenerator.generateCGImagesAsynchronously`.
   macOS-14-safe APIs wrapped in continuations.
4. **Output:** a standalone transcript note (does not mutate P1 notes). Keyframes embedded
   inline at their timestamps for multi-modal review.
5. **Provenance:** `origin: transcribed`, `source_type: video-transcript`, `engine`,
   and a visible banner that it is **machine-transcribed and may contain errors** — so
   wiki synthesis treats it as lower-confidence than human text.
6. **Permission:** embed `Info.plist` with `NSSpeechRecognitionUsageDescription`
   (and `NSAppleEventsUsageDescription` for the existing Notes automation) via a linker
   `-sectcreate __TEXT __info_plist` flag in `Package.swift`.

## 3. Architecture & components

**Pure (unit-testable without media/permission):**
- `Services/VideoSupport.swift`
  - `videoExts: Set<String>`, `isVideo(ext:)`, `isVideo(url:)`
  - `chunkRanges(duration:maxChunk:) -> [(start: Double, length: Double)]`
  - `keyframeTimestamps(duration:count:) -> [Double]`
- `Models/Transcript.swift`
  - `TranscriptSegment { start: Double; text: String }`
  - `VideoTranscript { segments:[TranscriptSegment]; engine:String; durationSeconds:Double }` + `fullText`
- `Services/TranscriptDocument.swift`
  - `markdown(transcript:keyframes:title:sourceName:modified:exported:) -> String`
    (frontmatter + interleaved keyframe embeds + `**[mm:ss]**` segments). Pure.

**Runtime (build-verified here; needs the test machine):**
- `Services/Transcriber.swift` — `protocol AudioTranscriber: Sendable { func transcribe(audioFileURL: URL) async throws -> String }`
- `Services/AppleSpeechTranscriber.swift` — `SFSpeechURLRecognitionRequest`,
  `requiresOnDeviceRecognition = supportsOnDeviceRecognition`, `addsPunctuation = true`,
  authorization check; throws a clear error if denied/unavailable.
- `Services/VideoTranscriptionService.swift` — orchestrates: load asset → extract m4a →
  for each `chunkRange` export sub-audio → transcribe → merge into `VideoTranscript`;
  extract `keyframeTimestamps` → save PNGs. Returns `(VideoTranscript, [keyframe URLs])`.
- `Services/VideoIngestCoordinator.swift` — given a video URL + `WikiVaultConfig`,
  runs the service, formats via `TranscriptDocument`, writes the note + keyframes
  (collision-safe, reusing `WikiNaming`). Streams progress (mirrors P1 coordinator).

**Integration (additive):**
- `AppState`: `importVideo(url:)` (NSOpenPanel for video) + `transcribeNoteVideos` toggle;
  when a wiki export note has video attachments and the toggle is on, run the
  `VideoIngestCoordinator` on each after the note is written.
- `DestinationPane` (Wiki pane): an **"Import video…"** button + a "Transcribe video
  attachments" toggle.
- `Package.swift`: linker `-sectcreate` Info.plist; new `AppleNotestoX-Info.plist`.

## 4. Output shape

```
raw/journal/2026-06-29-standup-recording-transcript.md
raw/assets/standup-recording-kf-01.png … (keyframes at timestamps)
```
Frontmatter:
```yaml
---
origin: transcribed
source_type: video-transcript
source_app: apple-notes        # or "imported-file"
engine: apple-speech (on-device)
source_video: standup.mov
duration_seconds: 372
note_modified: YYYY-MM-DD
exported: YYYY-MM-DD
---
> Provenance: MACHINE-TRANSCRIBED (Apple Speech, on-device). May contain errors.
> Treat as lower-confidence; synthesize into wiki/, don't edit here.
```

## 5. Error handling / guardrails

- Speech not authorized / on-device unsupported for locale → fail with a clear,
  actionable error; never silently fall back to network.
- No audio track in video → write a keyframes-only note + warning (still useful).
- Per-chunk transcription failure → record `[unintelligible @mm:ss]`, continue; never abort.
- Long videos → chunked; running offsets keep timestamps correct.
- Transcript clearly labeled machine-generated (provenance) — accuracy guardrail.
- Source video left in place; original copied to `raw/assets/` so the note is self-contained.

## 6. Testing

- **Pure unit tests** (run under Xcode/CI; verified here via `swiftc` harness):
  - `VideoSupport.chunkRanges` (130s/55 → [(0,55),(55,55),(110,20)]; exact-multiple; <max).
  - `VideoSupport.keyframeTimestamps` (count evenly spaced, bounded, ordered).
  - `VideoSupport.isVideo` (ext set, case-insensitive).
  - `TranscriptDocument.markdown` (frontmatter keys; mm:ss formatting; keyframe interleave order; machine-transcribed banner).
- **Runtime gates (test machine):** real `.mov` import → transcript+keyframes; Apple Note
  with a video attachment → transcript note; permission prompt appears (Info.plist embedded).
