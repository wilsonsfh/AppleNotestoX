# Apple Notes → LLM-Wiki Bridge (P1) — Design

- **Date:** 2026-06-29
- **Status:** Approved (design); ready for implementation plan
- **Project:** `AppleNotestoX` (Swift, macOS 14+, SwiftUI)
- **Author/owner:** Wilson Soon (with opencode)

---

## 1. Problem

The owner has years of unsystematic notes in **Apple Notes** — many heavily
multi-modal (lots of inline screenshots). Today the only "learning" workflow is
manually copy-pasting them into Notion, which is *"minimal and chunking and thus
not very helpful."* The goal is to ingest these notes into a **multi-modal,
savable, reviewable** knowledge base — text + visual (+ later video) — where an
LLM does the synthesis and cross-linking.

The owner already has the pieces for this and wants to **build on them**, not
start over.

## 2. Context — existing assets

| Asset | What it does | Reused here |
|---|---|---|
| `AppleNotestoX` (this repo) | macOS SwiftUI app that exports Apple Notes → **Notion**, preserving image position | Yes — the base we extend |
| `~/Projects/Personal_LLM_Wiki` | Obsidian vault running Karpathy's "LLM Wiki" pattern (`raw/` immutable sources → `wiki/` LLM-generated, cross-linked). Ingest/query/lint workflows in its `AGENTS.md` | Yes — the **destination** |
| Separate work-only vault | Same pattern, isolated from the default vault | No (acceptance note belongs in the default vault) |

Key existing code in `AppleNotestoX`:

- `Services/AppleNotesService.swift` — AppleScript (`osascript`) reader. `fetchNote(id:)`
  saves every attachment to a temp dir **in document order** and returns
  `AppleNoteContent(html, attachments)`.
- `Services/NoteConverter.swift` — walks the note HTML **in document order** and
  emits an ordered `[NotionBlock]`, placing an `imagePlaceholder` exactly where
  each `<img>`/`<object>` appears (`NoteConverter.swift:5`). The block model is
  "Notion" in name only — it is effectively a neutral document IR.
- `Services/ImagePipeline.swift` — `resizeToFit(localURL:)` is a pure resize/encode
  function (Notion coupling lives only in `uploadResized`).
- `App/AppState.swift`, `UI/SourcePane.swift`, `UI/DestinationPane.swift` — a
  working GUI: browse the Notes tree, **multi-select notes** (`selectedNoteIDs`),
  pick a destination, run with a streamed progress UI.

## 3. Scope

### In scope (P1)
A new **"Export to wiki"** destination in the existing GUI that writes a selected
Apple Note (text + screenshots, **positions preserved**) into the
`Personal_LLM_Wiki` vault as a provenance-stamped markdown file plus local image
assets — ready for the wiki's existing LLM ingest workflow.

**Acceptance/test case:** a **screenshot-heavy acceptance note**
exports faithfully, with each screenshot beside the correct paragraph.

### Out of scope (later sub-projects)
- **P2 — Video as a source:** transcribe video attachments / screen-recordings →
  `raw/`. (P1 copies non-image attachments and links them, but does not transcribe.)
- **P3 — Multi-modal review/study layer:** flashcards/spaced-repetition, visual
  concept maps, audio/short-video recaps over the synthesized wiki.
- The wiki **ingest/synthesis** itself — that is the existing `Personal_LLM_Wiki`
  `AGENTS.md` workflow; P1 only produces the `raw/` input.

## 4. Decisions taken (recommended options, owner-delegated)

1. **Form factor:** GUI **"Export to wiki"** destination (not CLI). Reuses the
   existing note-selection + progress UI → lowest ongoing cognitive effort and
   most code reuse. (A scriptable CLI can be added later for P2/P3 by reusing the
   same services.)
2. **Converter strategy (Approach A):** keep `NoteConverter` untouched; add a pure
   `MarkdownRenderer` over `[NotionBlock]` + a file sink. Max reuse, no risk to the
   working Notion path. A future `NotionBlock → DocBlock` rename (Approach C) is the
   natural refactor if P2 motivates it.
3. **Destination folder:** `raw/journal/` (owner-authored notes, per the vault's
   `AGENTS.md`).
4. **Filename:** `YYYY-MM-DD-<slug>.md`, dated by the note's `modifiedAt`.
5. **Images:** copy **originals** (no re-encode) into `raw/assets/`, named
   `<slug>-NN.<ext>` in document order. Best fidelity for visual review + P3.
   (`ImagePipeline.resizeToFit` stays available but unused by default.)
6. **Image references:** Obsidian embeds `![[<slug>-NN.ext]]` (Obsidian is the
   primary reader; `raw/assets/` is its attachment folder, so bare filenames resolve).
7. **Source note:** left untouched (`disposition = .leave`). Apple Notes stays the
   origin; `raw/` is an immutable copy.

## 5. Architecture & components

Approach A. Nothing in the Notion path changes; all additions are additive.

### New files
- **`Models/WikiExport.swift`**
  - `WikiVaultConfig { vaultURL: URL; journalSubpath: String = "raw/journal"; assetsSubpath: String = "raw/assets" }`
  - `WikiExportJob { noteIDs: [String]; config: WikiVaultConfig }`
  - `WikiExportResult { markdownPath: URL; assetPaths: [URL]; imageCount: Int; warnings: [String] }`
  - `WikiExportProgress` / `WikiExportStatus` (mirror `NoteArchiveProgress`/`NoteArchiveStatus`
    so the existing progress UI can render it: `pending`, `fetching`, `converting`,
    `savingAssets(done:total:)`, `writing`, `done(result:)`, `failed(message:)`).
- **`Services/MarkdownRenderer.swift`** — pure, no I/O:
  `static func render(_ blocks: [NotionBlock], assetFilename: (UUID) -> String?) -> RenderOutput`
  where `RenderOutput { markdown: String; warnings: [String] }`.
  - Block mapping: `heading1/2/3 → #/##/###`; `paragraph → text`;
    `bulletedListItem → "- "`; `numberedListItem → "1. "`; `toDo → "- [ ] "/"- [x] "`;
    `quote → "> "`; `code → fenced ```` ``` ````; `divider → "---"`.
  - Rich text (`NotionRichText`) → `**bold**`, `*italic*`, `~~strike~~`,
    `` `code` ``, `[text](href)`, with sensible nesting; `\n` runs preserved.
  - `imagePlaceholder(id,_)` → `![[filename]]` when `assetFilename(id)` returns a
    name; otherwise a `> [!warning] missing image` callout + a warning string.
  - `imageUploaded`/`imageFailed` (Notion-only cases) are not expected here; if seen,
    emit a warning callout (defensive).
- **`Services/WikiExportCoordinator.swift`** — actor mirroring `ArchiveCoordinator`,
  returns `AsyncStream<[WikiExportProgress]>`. Per note:
  1. `fetching` → `notes.fetchNote(id)`.
  2. `converting` → `NoteConverter.convert(html, attachments)`.
  3. `savingAssets(done,total)` → slugify title; copy each attachment's original
     bytes → `raw/assets/<slug>-NN.<ext>`. Each `imagePlaceholder(id, localPath)`
     carries the attachment's `localPath` (== `AppleNoteAttachment.localURL`), so the
     coordinator maps `localPath → savedFilename` from the copy step, then exposes a
     `placeholderID → savedFilename` lookup to the renderer.
  4. `writing` → `MarkdownRenderer.render(...)`; prepend provenance frontmatter;
     write `raw/journal/YYYY-MM-DD-<slug>.md` (collision-safe `-2`, `-3`).
  5. `done(result)`; never mutates the source note.

### Touched (additive)
- **`App/AppState.swift`** — `exportDestination: {.notion, .wiki}`; persisted
  `vaultURL` (security-scoped bookmark in `UserDefaults`); `runWikiExport()`
  paralleling `runArchive()`, reusing the progress stream.
- **`UI/DestinationPane.swift`** — a Notion / **Wiki** segmented switch. Wiki mode
  shows the saved vault path + a "Choose…" button (`NSOpenPanel`, security-scoped).
- **`UI/ContentView.swift`** — toolbar action label becomes **"Export to wiki"** in
  Wiki mode; enabled when `selectedNoteIDs` non-empty and a vault is chosen.

### Reused unchanged
`AppleNotesService`, `NoteConverter`, `SourcePane` + `selectedNoteIDs`, the
progress stream + toolbar status, `PreviewSheet` (optional preview).

## 6. Output shape (in the vault)

```
Personal_LLM_Wiki/
  raw/
    journal/2026-03-24-project-journal.md     # new
    assets/project-journal-01.png             # new (original bytes)
            project-journal-02.png
            ...
```

Provenance frontmatter auto-stamped (satisfies the vault `AGENTS.md` "raw/ is
immutable + origin-marked" rule):

```yaml
---
origin: user-stated
source_type: journal
source_app: apple-notes
apple_note_id: <id>
title: <note name>
note_modified: YYYY-MM-DD
exported: YYYY-MM-DD
---
> Provenance: exported verbatim from Apple Notes. Immutable — synthesize into
> wiki/, don't edit here.
```

## 7. Data flow

1. Select note(s) in `SourcePane`; Wiki mode on; vault chosen → **"Export to wiki."**
2. `AppState.runWikiExport()` → `WikiExportCoordinator.export(job)` →
   `AsyncStream<[WikiExportProgress]>` rendered by the existing toolbar/progress UI.
3. Per note: `fetching → converting → savingAssets → writing → done` (see §5).
4. Source note untouched. Final status:
   *"Exported → raw/journal/X.md (N images). Now ask opencode to ingest."*

## 8. Image↔text pairing & error handling

Pairing is **positional** (Nth attachment ↔ Nth `<img>`/`<object>` in document
order — the existing `NoteConverter` behavior). All failure modes are made
**visible and non-destructive**:

- **More `<img>` than attachments** → `NoteConverter` emits `imageFailed`; renderer
  writes `> [!warning] missing image NN` + a warning. No silent drift.
- **More attachments than `<img>`** → leftovers copied and appended under an
  **`## Unplaced attachments`** section + warning. Nothing lost.
- **Non-image attachment in an image slot** (PDF/video/scan) → copied to assets,
  emitted as a link `[filename](raw/assets/...)`. (Transcription is P2.)
- **Attachment save fails** (AppleScript `ATTERR`) → skip + warning; never abort.
- **Per-note fetch/convert/write failure** → mark that note `failed(message)`,
  continue the batch (mirrors `ArchiveCoordinator`).
- **Filename collision** → suffix `-2`, `-3`.
- **Vault path missing / not writable** → preflight check with a clear error
  before the run starts.

Warnings surface both in the status line and as Obsidian callouts in the written
file, so they are visible during review.

## 9. Testing

- **`MarkdownRenderer` unit tests (golden output):** every block type; rich-text
  combinations (bold/italic/link/code, nested, `\n`); image embed vs non-image
  link; missing-image callout. Style mirrors `Tests/.../NoteConverterTests.swift`.
- **Pairing/edge-case tests:** counts equal; more imgs; more attachments
  (→ unplaced section); non-image attachment; `ATTERR`. Assert warnings + ordering.
- **Provenance/frontmatter test:** correct YAML, slug derivation, date from
  `modifiedAt`, collision suffixing.
- **Integration test with a synthetic screenshot-heavy note fixture (acceptance gate):** capture
  its exported HTML + attachment list once into `Tests/Fixtures/`, run end-to-end
  into a temp vault dir, assert (a) image count preserved, (b) embeds land beside
  the correct surrounding text, (c) file written with provenance.
- **Manual acceptance:** open the temp/real vault in Obsidian and eyeball that
  screenshots sit next to the right paragraphs; then run the wiki ingest.

The pure logic (`MarkdownRenderer`, pairing, frontmatter) is fully unit-testable
without macOS Notes access. The live Apple Notes read + GUI is verified manually
on the owner's machine (requires Automation permission).

## 10. Risks

- **Positional pairing drift** — the main correctness risk for screenshot-heavy
  notes. Mitigated by the visible warnings + unplaced section above; if it proves
  fragile on the screenshot-heavy acceptance note, a follow-up can correlate attachment identifiers from
  the note HTML (deferred — YAGNI until observed).
- **Sandbox/file access** — writing into an arbitrary vault folder needs a
  security-scoped bookmark; handled in `AppState`/Settings.
- **Markdown fidelity** — tables and deeply nested lists are best-effort (inherited
  from `NoteConverter`); acceptable for journal notes, revisit if needed.

## 11. Out-of-scope follow-ups (tracked for later)

- P2: video attachment transcription + keyframe extraction into `raw/`.
- P3: review/study layer (flashcards, concept maps, audio/video recaps).
- Optional: shared library target + thin CLI (Approach C) for unattended/batch runs.
