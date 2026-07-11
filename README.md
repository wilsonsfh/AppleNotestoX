# AppleNotestoX

AppleNotestoX is a macOS app for turning Apple Notes into durable, reviewable knowledge. It exports selected notes to a local Personal Wiki or Notion, preserves inline media placement, can ingest video as an on-device transcript with keyframes, and pairs the resulting wiki with a static study app.

The project is local-first by default: capture writes provenance-stamped source material to disk, while interpretation and cross-linking remain a separate, LLM-owned synthesis step.

## Motivation

Apple Notes is excellent for fast capture, but a large, screenshot-heavy library is difficult to search, connect, and revisit as a body of knowledge. Copying notes into another tool by hand loses time and often loses the relationship between text and images. Storage alone also does not create learning: useful material needs provenance, synthesis, links, and repeated review.

AppleNotestoX connects those stages without replacing the tools that already work:

- Apple Notes remains the capture source.
- A filesystem wiki provides inspectable, portable Markdown and assets.
- An LLM synthesizes immutable raw material into connected knowledge.
- A no-build review app turns the synthesized wiki into flashcards, a concept map, and narrated recaps.
- Notion remains available as an export destination and an import source.

## Why Use It

- **Preserve context:** Personal Wiki export copies original images without re-encoding and embeds them in document order beside the surrounding text.
- **Keep provenance:** every Apple Notes wiki export is stamped with its source, note identifier, title, modification date, and export date.
- **Separate evidence from interpretation:** captures land in `raw/`; the app never writes synthesized pages under `wiki/`.
- **Stay local by default:** Apple Notes reading, wiki export, study-data generation, and supported Speech transcription run on the Mac.
- **Use the same material in several ways:** export to Markdown, send to Notion, transcribe video, or study an existing wiki.
- **Make large note libraries navigable:** search Apple Notes by note title or folder path, or press Command-F from anywhere in the app.

## What It Does

- Reads the Apple Notes account/folder/note hierarchy through AppleScript and supports multi-select export.
- Searches note titles and full folder paths case- and diacritic-insensitively; results show their folder context and sort newest first.
- Exposes search through the field in Capture mode and the application-wide **Command-F** command.
- Exports selected notes as Markdown to `raw/journal/` and copies screenshots and other attachments to `raw/assets/`.
- Preserves inline image position where Apple Notes supplies matching attachment placeholders; unmatched files are retained in an **Unplaced attachments** section with warnings.
- Leaves Apple Notes untouched during Personal Wiki export.
- Includes a persistent **Personal Wiki** footer for choosing a vault, exporting selected notes, and seeing progress or completion state.
- Exports Apple Notes to a selected Notion page, including uploaded images, with optional post-export leave, move, or delete behavior shown in the preview flow.
- Imports accessible Notion pages into the same `raw/journal/` and `raw/assets/` contract through `tools/notion-import.mjs`.
- Imports a video, or optionally processes video attachments in notes, using Apple Speech plus evenly spaced keyframes.
- Surfaces raw journal files that do not yet have same-named `wiki/sources/` pages and can copy an opencode synthesis prompt.
- Generates a static review dataset from `wiki/**/*.md` and opens a dependency-free review app with SM-2 flashcards, a force-directed concept map, and Web Speech narrated recaps.

## Architecture and Data Flow

```text
Apple Notes --AppleScript--> HTML + ordered attachments
                              |
                              v
                         NoteConverter
                         /           \
                        v             v
                 MarkdownRenderer   Notion blocks
                        |             |
                        v             v
Personal Wiki/raw/journal + raw/assets   Notion API
              |
              |  LLM-owned synthesis (outside this app)
              v
Personal Wiki/wiki/**/*.md
              |
              |  Node generator
              v
review/study-data.js --> static review app

Video file --> AVFoundation audio chunks + keyframes
             --> on-device Apple Speech --> raw/journal + raw/assets

Notion API --> Node importer --> raw/journal + raw/assets
```

The SwiftUI app coordinates work through observable `AppState` and actor-backed services. Conversion is separated from live integrations so Markdown rendering, naming, search, study parsing, and other pure logic can be tested without reading a real Notes library or calling Notion.

## Design Choices and Tradeoffs

- **Immutable raw, derived wiki:** `raw/journal/` and `raw/assets/` preserve source evidence; `wiki/` is derived synthesis. This adds an explicit ingest step but prevents the app from silently rewriting interpretation as fact.
- **LLM-owned synthesis:** the app identifies the backlog and prepares a prompt, but does not generate `wiki/` pages. Users retain control over the model, instructions, review, and provenance rules.
- **Reuse the document intermediate representation:** the existing Notion-oriented block model also feeds Markdown. This minimized risk to the Notion path, although some type names remain destination-specific.
- **Position over compression:** wiki exports copy original assets and map placeholders in document order. This favors fidelity and local storage use; malformed Notes HTML can still require review, so mismatches produce visible warnings rather than silent reordering.
- **Native integrations over hosted services:** AppleScript, AVFoundation, Speech, Keychain, and security-scoped bookmarks keep the core small and Mac-native. The tradeoff is macOS-only operation and explicit local permissions.
- **Forced on-device Speech:** transcription refuses a network fallback when the current locale does not support on-device recognition. Privacy is stronger, but availability and transcription quality depend on Apple's local recognizer.
- **Static review app:** vanilla HTML, CSS, and JavaScript can open from `file://` and keeps study data portable. Review history is browser-local rather than synchronized across devices.

## Tech Stack

- Swift 6 package and SwiftUI for the macOS application
- AppKit and Accessibility APIs for native windows, commands, file panels, and announcements
- AppleScript via `osascript` for Apple Notes access
- SwiftSoup for HTML parsing
- KeychainAccess for the optional Notion integration token
- AVFoundation and Apple Speech for local video processing
- Node.js ES modules for the study generator and Notion importer
- Vanilla HTML, CSS, Canvas, Web Speech, and `localStorage` for the static review app

## Requirements

### Required for the macOS app

- macOS 14 or later
- A Swift 6 toolchain; Xcode is recommended and is required for the XCTest gate described below
- Apple Notes and permission to control Notes at **System Settings > Privacy & Security > Automation**
- Read/write access to any Personal Wiki folder you choose

### Required only for specific workflows

- Node.js 18 or later for `review/generate.mjs` and `tools/notion-import.mjs`
- Speech Recognition permission, an on-device-capable locale, and a local video file for video transcription
- A Notion integration token, network access, and pages shared with that integration for Notion workflows
- An LLM-capable tool such as opencode, plus your own wiki instructions, for the synthesis step

### Optional

- Obsidian or another Markdown reader for browsing the wiki; exports are ordinary files
- Python 3 if you prefer serving the review app over HTTP instead of opening it directly

## Build and Run

Clone the repository, then build and launch the executable:

```bash
git clone https://github.com/wilsonsfh/AppleNotestoX.git
cd AppleNotestoX
swift build
swift run AppleNotestoX
```

On first Notes access, grant Automation permission. If it was denied, enable **AppleNotestoX > Notes** in System Settings and reload the app.

Run the Swift test suite with an Xcode-selected toolchain:

```bash
swift test
```

## Apple Notes to Personal Wiki

The destination vault must follow this contract:

```text
your-wiki/
  raw/
    journal/   # provenance-stamped Markdown source notes
    assets/    # original screenshots, attachments, videos, and keyframes
  wiki/
    sources/   # LLM-created source syntheses
```

1. Launch the app and switch to **Capture**.
2. Search by title or folder with the search field or **Command-F**, then select one or more notes.
3. Keep **Personal Wiki** selected and choose the root of your wiki folder.
4. Use the **Personal Wiki** footer to export the selected notes. Command-Return is available when the wiki action is ready.
5. Inspect the new files in `raw/journal/` and `raw/assets/`, including any visible attachment warnings.
6. Ask your LLM workflow to synthesize the new raw files into `wiki/sources/` and related concept pages. The app deliberately does not perform this step.
7. Return to **Study** to see unsynthesized raw files, copy an opencode prompt, refresh study data, or launch the review app.

## Notion and Video Workflows

### Apple Notes to Notion

Create a Notion integration, share destination pages with it, add the token in AppleNotestoX Settings, select notes and a destination page, then preview the archive. This path sends content to Notion and can optionally move or delete source notes after export; review the selected disposition before confirming.

### Notion to Personal Wiki

Node 18+ is required. Token resolution is `--token`, `NOTION_TOKEN`, then the token saved by AppleNotestoX in macOS Keychain. Prefer saving the token in AppleNotestoX Settings so it stays out of shell history. If none is available, the command exits with setup guidance.

```bash
node tools/notion-import.mjs --vault /path/to/your-wiki --list
export NOTION_PAGE_ID="your-page-id"
node tools/notion-import.mjs --vault /path/to/your-wiki --page "$NOTION_PAGE_ID"
```

The importer writes Markdown and downloaded images into `raw/`. Remote image downloads are restricted to validated public HTTP(S) targets, bounded by redirects/time/bytes, raster-signature checked, and published collision-safely. The 103 passing Node tests cover importer security, download handling, collision-safe publication, and YAML safety; a separate 12-check harness covers block, rich-text, and page conversion. Syntax and help output are also verified. Live Notion API behavior remains a first-run acceptance gate.

### Video to Personal Wiki

Choose a vault, then use **Import video** in Capture mode, or enable **Transcribe video attachments** before exporting notes. The app splits audio into chunks of at most 55 seconds, requests Apple Speech with on-device recognition required, extracts six evenly spaced keyframes by default, copies the source video, and writes a machine-transcribed Markdown note to `raw/journal/` with media in `raw/assets/`.

Real-video acceptance with Speech permission is still pending; review transcripts before treating them as accurate source text.

## Study and Review

The committed sample lets the static app open without a vault:

```bash
open review/index.html
```

Generate private study data from your synthesized wiki, then reload the page:

```bash
node review/generate.mjs --vault /path/to/your-wiki
open review/index.html
```

`review/study-data.js` is generated and gitignored. If browser `file://` restrictions interfere, serve the directory locally:

```bash
python3 -m http.server -d review 8080
```

Then open `http://localhost:8080`. Flashcard scheduling and streaks stay in that browser's `localStorage`; recap narration uses browser Web Speech and may require a click to begin.

## Privacy and Safety

- Personal Wiki export is local filesystem I/O and never modifies the source Apple Note.
- Apple Speech is configured to require on-device recognition and refuses silent network fallback.
- Notion is the explicit networked integration in the Swift/Node capture pipeline: exporting or importing sends requests to Notion's API and downloads user-authorized page content.
- Review narration uses browser Web Speech. It prefers a local English voice, but browser/platform fallback voices may be network-backed.
- The Notion token is stored in macOS Keychain by the app. Avoid committing tokens or passing them in shell history when an environment variable or Keychain is available.
- Vault access is user-selected and persisted as a security-scoped bookmark where available.
- App-created Notes attachment and keyframe temporary directories are marker-scoped and cleaned by their consuming coordinators on success and failure.
- Generated personal study data is written to `review/study-data.js`, which is ignored by Git. Only a curated sample dataset is committed.
- Raw exports can contain everything present in the selected source, including sensitive text and media. Inspect them before sharing a vault or repository.
- The `raw/`/`wiki/` boundary is a convention enforced by this app's write paths, not an access-control system. Your synthesis tooling must preserve it.

## Verification, Status, and Limitations

| Area | Verified in this repository | Pending or limited |
|---|---|---|
| Swift app | `swift build` recorded green; launch smoke completed; pure-logic harnesses cover Notes process handling, date parsing, wiki rendering/assembly, video helpers, study parsing, and backlog behavior | Full committed XCTest suite requires Xcode; the documented Command Line Tools environment reports missing `XCTest` |
| Apple Notes to wiki | Code complete; Markdown, provenance, naming, collision handling, positional assets, and warning paths were logic-verified | Manual acceptance against a real screenshot-heavy note and Notes Automation permission remains pending |
| Search and editorial UI | `swift build`, standalone search/action-state/AppState harnesses, synthetic 900×600 and 1100×700 screenshots, and final code/design reviews are green | XCTest still requires Xcode; macOS TCC/Assistive Access blocked headed VoiceOver and keyboard automation |
| Video | Build, pure video-support/transcript logic, and embedded Speech usage descriptions were verified | Real `.mov` import, Speech permission, and long-video timestamp acceptance remain pending |
| Review app | JavaScript syntax, generator output, SM-2 behavior, and sample-data integration were verified | Manual browser UI, TTS, and accessibility click-through remains pending |
| Notion importer | Syntax and help output are verified; 103 passing Node tests cover security, downloads, publication, and YAML safety; a separate 12-check harness covers block, rich-text, and page conversion | Live Notion API calls and signed image downloads remain a first-run integration gate |

Known limitations include macOS-only capture, best-effort conversion for complex Notes HTML, heuristic filename matching for the synthesis backlog, browser-local review history, no speaker diarization, no remote-video/YouTube ingestion, and no automated LLM synthesis. The repository currently has no license; public source availability does not by itself grant reuse rights.

See `PROGRESS_REPORT.md` for the evidence and remaining gates behind these summaries.

## Specifications and Repository Map

```text
Package.swift                         Swift 6 package and macOS 14 target
Sources/AppleNotestoX/App/            app lifecycle and state coordination
Sources/AppleNotestoX/Models/         Notes, Notion, wiki, transcript, and study models
Sources/AppleNotestoX/Services/       integrations, conversion, export, search, and study services
Sources/AppleNotestoX/UI/             SwiftUI capture, destination, study, settings, and preview views
Tests/AppleNotestoXTests/             committed XCTest coverage
review/                               static study app, generator, sample, and review documentation
tools/notion-import.mjs               Notion-to-raw importer
docs/superpowers/specs/               approved feature and UI design specifications
docs/superpowers/plans/               implementation plans
PROGRESS_REPORT.md                    verification evidence and delivery history
```

Start with these specifications:

- `docs/superpowers/specs/2026-06-29-apple-notes-to-wiki-bridge-design.md`
- `docs/superpowers/specs/2026-06-29-video-as-a-source-design.md`
- `docs/superpowers/specs/2026-06-29-review-layer-design.md`
- `docs/superpowers/specs/2026-06-30-wiki-studio-study-and-backlog-design.md`
- `docs/superpowers/specs/2026-07-12-editorial-workspace-redesign-design.md`

## Transferable Learnings

- Preserve immutable evidence before asking an LLM to summarize it; derived knowledge can be regenerated, source material cannot.
- Make provenance and failure visible in the artifact, not only in logs.
- Separate pure conversion from permissioned integrations so most behavior is testable without private data or external services.
- Reuse a neutral-enough intermediate representation before duplicating parsing pipelines, but rename it when destination-specific terminology begins to distort the model.
- Treat media ordering as data. Positional fidelity matters more than aggressive optimization for visual notes.
- Prefer explicit operation states such as selecting, exporting, completed, and failed over inferring user intent from scattered booleans.
- Ship synthetic or curated fixtures for demos and keep generated personal data ignored.
- Report manual, permissioned, and external-service acceptance gates separately from build and pure-logic verification.

## Author

Created by [Wilson Soon](https://github.com/wilsonsfh), with implementation assistance from opencode.
