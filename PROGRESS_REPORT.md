# AppleNotestoX — Progress Report

Living log of shipped changes (newest at top). See `docs/superpowers/specs/` and
`docs/superpowers/plans/` for the design/plan behind each item.

## Project status: COMPLETE

Feature work is done. The app builds and launches from a clean `git clone` using Xcode
Command Line Tools alone (`make doctor && make run`). What remains is not development — it
is manual acceptance that requires a human at a Mac with the relevant permissions granted,
plus the `swift test` gate that needs full Xcode. Those are tracked below and are not
blocking anything.

## Status at a glance

| Capability | Status |
|---|---|
| **Portability — clean-clone install on a fresh Mac** | ✅ shipped; `make doctor` machine check, `make build/run/study/notion/check` entry points, runtime `review/` resolution (override → env → executable → cwd → source), no personal default vault path in either node tool. `make check` green: build + 103 node tests. |
| **Wiki Studio — Pass 1 (Study core + Synthesis backlog)** | ✅ shipped to `main` (`b75f665`…`8c413d7`); `swift build` green + logic run-verified (11 checks) + launch smoke (Study default, no crash); XCTest committed (run under Xcode). Spec/plan/mocks in `docs/`. |
| **Bugfix: Apple Notes reader launch-deadlock (osascript pipe drain) + faster date parse** | ✅ shipped to `main` (`2898d3a`); `swift build` green + run-verified (deadlock repro/fix + parser equivalence); XCTest committed (run under Xcode) |
| Apple Notes → Notion export (original feature) | ✅ shipped (pre-existing) |
| **P1: Apple Notes → LLM-Wiki bridge (markdown + assets, positions preserved)** | 🟡 code complete + build green + logic run-verified; **pending `swift test` under Xcode + manual screenshot-heavy acceptance-note check** |
| **Search + editorial workspace UI** | 🟡 `swift build`, standalone search/action-state/AppState harnesses, synthetic 900×600 and 1100×700 screenshots, and final code/design reviews green; **XCTest requires Xcode, and macOS TCC/Assistive Access blocked headed VoiceOver + keyboard automation** |
| **P2: video as a source (transcribe + keyframes → raw/)** | 🟡 code complete + build green + pure logic run-verified + Info.plist section verified; **pending real-video runtime test (Speech permission) under Xcode** |
| **P3: multi-modal review/study layer** | 🟡 code complete + all JS parses + generator/SM-2/data-layer run-verified; **pending browser runtime test (UI + TTS)** |
| **Notion → wiki importer (`tools/notion-import.mjs`)** | 🟡 syntax + help green; 103 passing Node tests cover security/download/publication/YAML safety, while a separate 12-check harness covers block/rich-text/page conversion; **live Notion API path remains pending** |

## Completed

### 2026-07-12 — Public searchable editorial wiki workflow
- **What:** shipped title/folder search with Command-F, native keyboard-selectable note/page rows,
  a persistent Personal Wiki action footer, isolated note/video progress channels, single-flight
  export guards, and the whole-app **Editorial Split Desk** SwiftUI redesign.
- **Safety:** hardened Swift and Node publication paths with collision-safe no-clobber writes,
  identity-aware rollback, YAML quoting, coordinator-owned temporary cleanup, bounded public-only
  Notion image downloads, response cancellation, raster signature checks, and synthetic demo data.
- **Public repository:** <https://github.com/wilsonsfh/AppleNotestoX> is public on default branch
  `main`; release commit `c653f3c49bb7cb8bf75485e71178ec6c6e1a3d68`, authored and committed by
  `wilsonsfh <74759808+wilsonsfh@users.noreply.github.com>`.
- **Docs:** root `README.md` covers motivation, benefits, architecture, design choices, trade-offs,
  tech stack, setup, workflows, privacy, specifications, verification, limitations, and learnings.
- **Verification:** `swift build` passed; 103 Notion importer security tests passed; six Swift safety
  harnesses plus search/action-state/AppState harnesses passed; review JavaScript syntax passed;
  staged diff and secret/history scans were clean; synthetic Study/Capture/Notion/Settings/Preview
  screenshots passed final visual review; staged release review returned **READY**.
- **Remaining external gates:** run XCTest under Xcode/CI; manually accept real Notes export,
  Speech/video, live Notion API/signed images, browser TTS, light mode, and headed VoiceOver/keyboard
  behavior. macOS Assistive Access blocked automation with TCC error `-25211`.

### 2026-06-30 — Wiki Studio Pass 1: Study core + Synthesis backlog
- **What:** Reframe toward a study-first hub centered on `Personal_LLM_Wiki`. A **Study | Capture**
  mode switch defaults to **Study**, where the wiki is the hero: big `concepts · cards` counts, a
  **Launch Wiki Review** button (opens `review/index.html`), a **Refresh study data** button (runs
  `review/generate.mjs` via the deadlock-safe `ProcessRunner`), a "jump back in" concept list, and a
  quieter **synthesis backlog** panel listing `raw/journal` notes with no matching `wiki/sources/`
  page (+ **Copy opencode prompt** / Reveal in Finder). Capture preserves the existing Apple
  Notes → Notion/Wiki + video flow unchanged. The app never writes `wiki/` (synthesis stays LLM-owned).
- **Files (new):** `Services/ProcessRunner.swift` (extracted), `Services/RepoPaths.swift`,
  `Models/StudyData.swift`, `Services/StudyDataService.swift`, `Services/SynthesisBacklog.swift`,
  `UI/StudyView.swift`; tests `RepoPathsTests`, `StudyDataParseTests`, `StudyDataServiceTests`,
  `SynthesisBacklogTests` (+ `ProcessRunnerTests` moved to the new type).
- **Files (modified):** `Services/AppleNotesService.swift` (uses `ProcessRunner`), `App/AppState.swift`
  (mode + study/backlog state & actions), `UI/ContentView.swift` (mode switch), `UI/SettingsView.swift`
  (Review-folder override).
- **Branch:** `main`. **Commits:** `b75f665` (ProcessRunner), `99d7ac4` (RepoPaths), `323921c`
  (StudyData), `826afca` (StudyDataService), `bac0a2c` (SynthesisBacklog), `329e5b5` (AppState),
  `6deff00` (StudyView), `8c413d7` (mode switch + Settings). Spec `a6d2d1c`.
- **Docs:** spec `docs/superpowers/specs/2026-06-30-wiki-studio-study-and-backlog-design.md`; plan
  `docs/superpowers/plans/2026-06-30-wiki-studio-study-and-backlog.md`; mocks
  `docs/mockups/2026-06-30-wiki-studio-{before-after,v2}.html`.
- **Verification:** `swift build` ✅ exit 0; pure logic (StudyData.parse ranking, SynthesisBacklog
  pending/split/prompt, RepoPaths.firstExisting) ✅ run-verified via standalone harness (11 assertions);
  launch smoke ✅ (opens in Study mode, no crash, main thread healthy); `node` resolves at
  `/opt/homebrew/bin/node`; `generate.mjs` regenerates configured vault study data successfully.
- **Remaining gates:** run `swift test` under Xcode/CI (adds `RepoPathsTests`, `StudyDataParseTests`,
  `StudyDataServiceTests`, `SynthesisBacklogTests`); manual click-through — Refresh regenerates + counts
  update, Launch opens the review app, backlog lists the pending notes + Copy prompt works, Capture
  flow intact.
- **Out of scope (later passes):** Pass 2 full hub shell + in-app **Browse** (rendered wiki pages);
  Pass 3 unified **Capture** menu (demote Notion); Pass 4 **X bookmarks** (paste-URL MVP first, OAuth
  sync only with a paid X tier).

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
  Keychain entry**; if none is available, the command exits with setup guidance. Keychain is
  preferred to avoid shell history. The importer lists accessible pages and supports interactive
  page selection (`1,3` or `all`), or `--page`/`--all`/`--list`.
- **Converter:** Notion blocks → markdown (headings, nested lists, to-dos, quote, callout,
  code, image, divider, bookmark, table rows) with rich-text annotations + links.
- **Files:** `tools/notion-import.mjs`. **Branch:** `feat/notion-import`.
- **Current verification:** `node --check` ✅; `--help` dry-run ✅; 103 passing Node tests cover
  security/download/publication/YAML safety; a separate 12-check harness covers blocks,
  `richTextToMd`, `pageTitle`, nesting, images, and order ✅.
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
- **Verification:** `node --check` on all 10 JS files ✅; generator run against the
  configured default vault with no orphaned links ✅; SM-2 engine
  (math + EF floor + lapse reset + persistence + streak) run-verified via `node`/`vm` ✅;
  data-layer integration with the sample (indexing, neighbors, edge/card integrity,
  partition) run-verified ✅.
- **Remaining gates (browser, test machine):** open `review/index.html` (or `python3 -m
  http.server -d review`) — run a flashcard session, explore the map, play a recap (TTS
  needs a click to start, esp. Safari). Then `node review/generate.mjs --vault <vault>`
  to study the selected vault.
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
  2. Manual acceptance on a machine with Notes Automation permission: export a
     **screenshot-heavy acceptance note**, open the vault in Obsidian, confirm screenshots sit beside the
     correct paragraphs, then run the `Personal_LLM_Wiki` ingest.
- **Not merged / not pushed:** lives on the feature branch; no git remote configured.
