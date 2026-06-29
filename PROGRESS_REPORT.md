# AppleNotestoX — Progress Report

Living log of shipped changes (newest at top). See `docs/superpowers/specs/` and
`docs/superpowers/plans/` for the design/plan behind each item.

## Status at a glance

| Capability | Status |
|---|---|
| Apple Notes → Notion export (original feature) | ✅ shipped (pre-existing) |
| **P1: Apple Notes → LLM-Wiki bridge (markdown + assets, positions preserved)** | 🟡 code complete + build green + logic run-verified; **pending `swift test` under Xcode + manual Glints acceptance** |
| P2: video as a source (transcribe → raw/) | ⬜ not started |
| P3: multi-modal review/study layer | ⬜ not started |

## Completed

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
