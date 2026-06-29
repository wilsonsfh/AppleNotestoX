# AppleNotestoX — Progress Report

Living log of shipped changes (newest at top). See `docs/superpowers/specs/` and
`docs/superpowers/plans/` for the design/plan behind each item.

## Status at a glance

| Capability | Status |
|---|---|
| Apple Notes → Notion export (original feature) | ✅ shipped (pre-existing) |
| **P1: Apple Notes → LLM-Wiki bridge (markdown + assets, positions preserved)** | 🟡 code complete + build green + logic run-verified; **pending `swift test` under Xcode + manual Glints acceptance** |
| **P2: video as a source (transcribe + keyframes → raw/)** | 🟡 code complete + build green + pure logic run-verified + Info.plist section verified; **pending real-video runtime test (Speech permission) under Xcode** |
| P3: multi-modal review/study layer | ⬜ not started |

## Completed

### 2026-06-29 — P2: Video as a source (on-device transcription + keyframes)
- **What:** Import a video file (or transcribe video attachments inside an Apple Note)
  → on-device Apple Speech transcription (chunked ≤55s to respect the ~1-min limit) +
  evenly-spaced keyframes → a provenance-stamped, **machine-transcribed** transcript note
  in `raw/journal/` with keyframes embedded at their timestamps in `raw/assets/`.
- **Files (new):** `Services/VideoSupport.swift`, `Models/Transcript.swift`,
  `Services/TranscriptDocument.swift`, `Services/Transcriber.swift`,
  `Services/AppleSpeechTranscriber.swift`, `Services/VideoTranscriptionService.swift`,
  `Services/VideoIngestCoordinator.swift`, `AppleNotestoX-Info.plist`; tests
  `VideoSupportTests`, `TranscriptDocumentTests`.
- **Files (modified):** `Models/WikiExport.swift` (`transcribeVideos` flag),
  `Services/WikiExportCoordinator.swift` (transcribe note videos), `App/AppState.swift`
  (`importVideo`, toggle), `UI/DestinationPane.swift` (Import video + toggle),
  `Package.swift` (linker `-sectcreate` Info.plist).
- **Branch:** `feat/video-source`. **Commits:** `e387786`, `d21351e`, `26db2eb`,
  `04cf214`, `db08174`, `f9d8a84`.
- **Design:** Apple Speech (on-device) behind an `AudioTranscriber` protocol — zero model
  download, no-Xcode-friendly; **WhisperKit is the documented upgrade path**. Fact-checked
  against Apple docs (Speech ~1-min limit → chunking; `NSSpeechRecognitionUsageDescription`
  required → embedded & **verified** via `otool -P`).
- **Verification:** `swift build` ✅; `VideoSupport` + `TranscriptDocument` (22 assertions)
  ✅ run-verified via `swiftc` harness; embedded `__info_plist` (636 bytes, both usage keys)
  ✅ verified. XCTest suites committed.
- **Remaining gates:** run a real `.mov` import on a machine with Xcode + Speech permission
  (first run prompts); confirm transcript + keyframes; long-video chunk timestamps.
- **Out of scope (later):** YouTube/remote URLs (`yt-dlp`), speaker diarization.

### 2026-06-29 — P1: Apple Notes → LLM-Wiki "Export to wiki" destination
- **What:** Added a GUI **"Export to wiki"** destination to `AppleNotestoX`. A selected
  Apple Note is written into the `Personal_LLM_Wiki` vault as a provenance-stamped
  markdown file in `raw/journal/`, with original screenshots copied to `raw/assets/`
  and embedded **at their correct positions** relative to the text. Reuses the existing
  `AppleNotesService` reader, position-preserving `NoteConverter`, and note-selection +
  progress UI (Approach A — Notion path untouched).
- **Files (new):** `Services/WikiNaming.swift`, `Services/MarkdownRenderer.swift`,
  `Services/WikiExportAssembler.swift`, `Services/WikiExportCoordinator.swift`,
  `Models/WikiExport.swift`; tests `WikiNamingTests`, `MarkdownRendererTests`,
  `WikiExportAssemblerTests`.
- **Files (modified, additive):** `App/AppState.swift` (destination toggle, persisted
  vault security-scoped bookmark, `runWikiExport()`), `UI/DestinationPane.swift`
  (Notion/Wiki segmented switch + vault chooser), `UI/ContentView.swift`
  (destination-aware toolbar action + progress labels).
- **Branch:** `feat/wiki-export-bridge`. **Commits:** `3ca73e9`, `c33d343`, `b37e716`,
  `a1a1453`, `6ec2882`, `47ecab1`, `777140a` (+ docs `3dc4711` spec, `493cd13` plan).
- **Verification:**
  - `swift build` ✅ green (full app, incl. new code + UI).
  - Pure logic (`WikiNaming`, `MarkdownRenderer`) and the **assembler** (order
    preservation, unplaced/non-image handling, filename collisions) ✅ **run-verified**
    via a temporary `swiftc` harness (37 assertions) — because XCTest can't run in this
    environment (Command Line Tools only, no Xcode → `swift test` reports "no such
    module 'XCTest'").
  - XCTest suites are written and committed, ready to run under Xcode/CI.
- **Remaining gates (not yet done):**
  1. Run `swift test` once Xcode is installed (or in CI) to exercise the committed XCTest suites.
  2. Manual acceptance on a machine with Notes Automation permission: export the real
     **Glints** note, open the vault in Obsidian, confirm screenshots sit beside the
     correct paragraphs, then run the `Personal_LLM_Wiki` ingest.
- **Not merged / not pushed:** lives on the feature branch; no git remote configured.
