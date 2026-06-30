# AppleNotestoX — Progress Report

Living log of shipped changes (newest at top). See `docs/superpowers/specs/` and
`docs/superpowers/plans/` for the design/plan behind each item.

## Status at a glance

| Capability | Status |
|---|---|
| **Bugfix: Apple Notes reader launch-deadlock (osascript pipe drain) + faster date parse** | ✅ shipped to `main` (`2898d3a`); `swift build` green + run-verified (deadlock repro/fix + parser equivalence); XCTest committed (run under Xcode) |
| Apple Notes → Notion export (original feature) | ✅ shipped (pre-existing) |
| **P1: Apple Notes → LLM-Wiki bridge (markdown + assets, positions preserved)** | 🟡 code complete + build green + logic run-verified; **pending `swift test` under Xcode + manual Glints acceptance** |
| **P2: video as a source (transcribe + keyframes → raw/)** | 🟡 code complete + build green + pure logic run-verified + Info.plist section verified; **pending real-video runtime test (Speech permission) under Xcode** |
| **P3: multi-modal review/study layer** | 🟡 code complete + all JS parses + generator/SM-2/data-layer run-verified; **pending browser runtime test (UI + TTS)** |
| **Notion → wiki importer (`tools/notion-import.mjs`)** | 🟡 pure blocks→markdown converter run-verified (12 checks) + `--help` ok; **live Notion API path NOT fact-checked (per request) — verify on first run with your token** |

## Completed

### 2026-06-30 — Bugfix: Apple Notes reader launch-deadlock + faster date parse
- **Symptom (reported):** the Swift app "hangs" and the **Wiki tab "has nothing"**. Root-caused
  to a single defect: `AppleNotesService.runScript()` called `Process.waitUntilExit()` **before**
  draining the stdout pipe. Once osascript's output exceeded the ~64 KB OS pipe buffer (any
  non-trivial Notes library), the child blocked writing into a full pipe while the app blocked
  waiting for it to exit → **deadlock at launch**. With the hierarchy never loading, no notes were
  selectable, so the Wiki tab had nothing to export (and "Export to wiki" stayed disabled).
- **Diagnosis evidence:** launched the built binary and `sample`d it — a worker thread parked at
  `AppleNotesService.swift:59` (`waitUntilExit`) with a live `osascript` child; an isolated
  `swift` harness confirmed the exact pattern deadlocks at 300 KB and completes when drained first.
- **Fix:** extracted a testable `runProcess(executableURL:arguments:)` that **drains stdout +
  stderr concurrently** (stderr on a worker thread via a lock-guarded `DataBox`), then waits.
  `runScript()` is now a thin wrapper preserving the osascript args + error mapping
  (`permissionDenied` / `scriptFailed`).
- **Also:** replaced the per-note `DateFormatter` (ICU, visibly CPU-heavy in the sample) in
  `parseHierarchy` with a fast hand-rolled `parseNoteDate()` + cached gregorian calendar.
- **Files (modified):** `Services/AppleNotesService.swift`. **Files (new tests):**
  `Tests/AppleNotestoXTests/ProcessRunnerTests.swift`, `Tests/AppleNotestoXTests/NoteDateParseTests.swift`.
- **Branch:** `main`. **Commit:** `2898d3a` (pushed to `origin/main`).
- **Verification:** `swift build` ✅ exit 0; shipped `runProcess` algorithm run-verified via
  standalone harness (512 KB stdout → no deadlock, stderr+nonzero status captured, plain stdout) ✅;
  `parseNoteDate` run-verified equivalent to `DateFormatter` across samples + rejects malformed ✅.
- **Remaining gate:** XCTest can't run in this environment (Command Line Tools only, no Xcode →
  `swift test` reports "no such module 'XCTest'"). Run the two committed suites under **Xcode/CI**:
  `swift test --filter ProcessRunnerTests` and `swift test --filter NoteDateParseTests`.

### 2026-06-29 — Notion → wiki importer (`tools/notion-import.mjs`)
- **What:** One-command Node importer (no Xcode) that pulls Notion pages into the vault's
  `raw/journal/` as provenance-stamped markdown + downloaded images in `raw/assets/`, so
  opencode can ingest them — the "intuitive Notion path" (parallels the Apple Notes export).
- **UX:** token resolves from `--token` → `$NOTION_TOKEN` → the **AppleNotestoX app's
  Keychain entry** → prompt; lists accessible pages and lets you pick interactively
  (`1,3` or `all`), or `--page`/`--all`/`--list`.
- **Converter:** Notion blocks → markdown (headings, nested lists, to-dos, quote, callout,
  code, image, divider, bookmark, table rows) with rich-text annotations + links.
- **Files:** `tools/notion-import.mjs`. **Branch:** `feat/notion-import`.
- **Verification:** `node --check` ✅; `--help` dry-run ✅; pure converter + `richTextToMd`
  + `pageTitle` + nesting/image/order — 12 assertions run-verified via harness ✅.
- **Important caveat:** the **live Notion API calls** (`/search`, `/blocks/*/children`,
  image download) were built from stable API knowledge (`Notion-Version: 2022-06-28`) and
  **NOT live-fact-checked** (per request). Verify on first run: create an integration at
  notion.so/my-integrations, share pages with it, then
  `node tools/notion-import.mjs --vault ~/Projects/Personal_LLM_Wiki`.
- **Out of scope:** databases/sub-page recursion beyond shared pages, Notion-export-zip path.

### 2026-06-29 — P3: Multi-modal review/study layer (flashcards + map + recap)
- **What:** A dependency-free, no-build static web app (`review/`) + Node generator that
  turns the wiki into an active study experience: **flashcards with SM-2 spaced repetition**
  (localStorage history + streak), a **force-directed concept map** (canvas) with a detail
  panel, and **narrated recaps** (Web Speech TTS auto-advancing slides). Dark + light themes,
  `prefers-reduced-motion`, keyboard review loop, Direction-B design (`mockups/compare.html`).
- **Files (new):** `review/generate.mjs`, `review/index.html`, `review/styles.css`,
  `review/study-data.sample.js`, `review/README.md`, and `review/js/`:
  `ui.js`, `data.js`, `srs.js`, `tts.js`, `flashcards.js`, `graph.js`, `recap.js`, `app.js`.
  `.gitignore` ignores generated `review/study-data.js`.
- **Branch:** `feat/review-layer`. **Commits:** `ffb1bed` (design), `361658e`, `874a195`,
  `f169c2d`, `1bc87b6`, `4b36ee4`, `b414826` (+ this report).
- **Design tools:** Figma MCP / Mobbin / MagicPath / MagicPatterns are paid and **not
  connected** in this environment → applied `frontend-design` principles directly,
  benchmarked to Airfoil/Linear/Stripe. Not a Cloudflare app, so Kumo not used.
- **Verification:** `node --check` on all 10 JS files ✅; generator run on real
  `Personal_LLM_Wiki` → 15 concepts / 15 cards / 58 edges / 0 orphans ✅; SM-2 engine
  (math + EF floor + lapse reset + persistence + streak) run-verified via `node`/`vm` ✅;
  data-layer integration with the sample (indexing, neighbors, edge/card integrity,
  partition) run-verified ✅.
- **Remaining gates (browser, test machine):** open `review/index.html` (or `python3 -m
  http.server -d review`) — run a flashcard session, explore the map, play a recap (TTS
  needs a click to start, esp. Safari). Then `node review/generate.mjs --vault <vault>`
  to study your real wiki.
- **Out of scope (later):** multi-device SR sync, in-app card authoring, real video export.

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
