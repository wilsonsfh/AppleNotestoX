# Merge to Note: LLM-Categorized Single-Note Consolidation

**Date:** 2026-08-15
**Status:** Approved for implementation

## Problem

Apple Notes accumulates many small, scattered notes over time. There is no way today to
select a batch of them, have an LLM group their content by topic, and get back one
consolidated note — organized under topic headers — written back into Apple Notes itself.
AppleNotestoX today is one-way and read-only toward Notes: it exports selected notes out to
a Personal Wiki or Notion, but never writes anything back.

## Goals

- Let the owner tick any notes from the full Apple Notes library (reusing the existing
  search + multi-select picker).
- Send the ticked notes' content to an LLM that freely invents topic headers based on what
  it reads, and organizes all the content into sections under those headers.
- Write the result back into Apple Notes as **one new note**, with header formatting per
  section.
- Preview the merged draft before it is written, since note creation is not undoable via
  the app.
- Leave every original ticked note completely untouched — no move, no delete.
- Each run rebuilds the merged note fresh from whatever is currently ticked. There is no
  append-to-previous-run behavior.
- Carry attachments along where practical, using a local staging area, rather than
  dropping them.
- Use a free/cheap LLM (Groq-hosted Llama) since categorization is a simple task, not one
  that needs a frontier model.

## Non-Goals

- Deleting, moving, or otherwise mutating the original ticked notes.
- Multi-run accumulation into a persistent merged note (that is future work if it proves
  useful; today's Personal Wiki path already handles durable, cross-session synthesis).
- User-defined/fixed category taxonomies — categories are decided by the LLM per run.
- Any change to the existing Personal Wiki / Notion export flows.

## Interaction Design

### Tab rename

The **Capture tab is renamed to "Transfer/Transform"** everywhere it appears in the UI
(window tab label, any user-facing copy referencing "Capture"). It now covers both existing
export flows and the new merge flow. The internal `AppState.AppMode.capture` case name is
left as-is — this is a display-only rename to keep the diff scoped to the UI layer.

### Third destination

`DestinationPane`'s existing segmented "Send to" picker (`Personal Wiki` / `Notion`) gets a
third option, `Merge to Note`, following the same `AppState.ExportDestination`-driven
pattern already used for the other two. Selecting it swaps in a new `mergePane`, styled
consistently with `wikiPane`/`notionPane`.

The merge pane shows:

- A live count: "`N` notes selected"
- Groq API key status (a link to Settings if missing, matching the existing "No
  Integration Token" empty state used for Notion)
- A `Preview & Merge…` button, enabled when notes are selected and a Groq key is present

### Preview

Clicking `Preview & Merge…` runs the fetch → categorize → assemble pipeline (see
Architecture) and opens `MergePreviewSheet`, styled like the existing `PreviewSheet`:

- Lists the LLM-chosen section headers with a content preview under each
- Shows which original notes fed each section
- `Cancel` / `Create in Apple Notes` actions, matching the existing sheet's footer pattern
- On confirm, writes the note and reports success/failure; on cancel, discards the draft
  and clears any staged images for that run

### Settings

`SettingsView` gains a `Groq API Key` field, mirroring the existing Notion token field:
entered value is stored in Keychain (`groq_api_key`) via the same `Keychain(service:
"com.applenotestox.app")` instance already used for `notion_token`.

## Architecture

### New components

| Component | Mirrors | Responsibility |
|---|---|---|
| `GroqService` (actor) | `NotionService` | HTTP calls to Groq's OpenAI-compatible chat completions endpoint; Keychain-stored API key; retry/backoff on 429 |
| `TriageAssetStore` | `AppleNotesService`'s temp-dir marker/cleanup pattern | Persistent local staging folder for attachment files during one merge run, so they outlive `fetchNote`'s per-note OS temp dirs |
| `MergeCoordinator` | `WikiExportCoordinator` / `ArchiveCoordinator` | Orchestrates the full fetch → categorize → stage → assemble → write pipeline; exposes an `AsyncStream` of progress snapshots, same shape as the existing coordinators |
| `AppleNotesService.createNote(title:body:)` | `moveNote`/`deleteNote` (already argv-based AppleScript, avoiding string-interpolation injection) | New write capability; the app has been read-only toward Notes until now |
| `MergePreviewSheet` | `PreviewSheet` | Preview UI shown before the write happens |

### Data flow

```
Tick notes (existing picker) → select "Merge to Note" destination → Preview & Merge
  MergeCoordinator.run(selectedNoteIDs):
    1. fetchNote(id:) per note (existing) → HTML body + attachments in an OS temp dir
    2. Strip HTML → plain text per note (reuse NoteConverter's existing text-extraction path)
    3. Copy attachment files → TriageAssetStore/<run-uuid>/
       (must happen before AppleNotesService's temp-dir cleanup fires)
    4. GroqService.categorize([(noteTitle, plainText, attachmentFilenames)])
       → strict JSON: [{header, bodyText, sourceNoteIDs}]
    5. Assemble one HTML document:
       - one heading element per section header
       - section body text as paragraphs
       - inline <img src="file://…"> for that section's source notes' staged images
         (see Risk below for the fallback if this does not work)
  → MergePreviewSheet renders the assembled draft for confirmation
  → confirm → AppleNotesService.createNote(title:, body:) → one new Apple Note
  → TriageAssetStore/<run-uuid>/ deleted on success (staging only — see Risk for the
    one case where it is kept instead)
  → cancel → discard draft, delete TriageAssetStore/<run-uuid>/, no Apple Notes write
```

Originals are never moved, deleted, or edited at any step.

### Groq integration

- Endpoint: `https://api.groq.com/openai/v1/chat/completions`
- Model: a current Llama model on Groq's free tier (e.g. `llama-3.3-70b-versatile`) —
  exact model string is a implementation-time detail, not a design commitment, since Groq's
  available models change
- Single request per merge run containing all selected notes' titles + extracted plain
  text; the prompt instructs the model to return strict JSON matching the section schema
  above and to invent however many headers the content warrants
- Same HTTP plumbing shape as `NotionService.rawRequest`: Bearer token from Keychain,
  429 → exponential backoff up to a bounded retry count, non-2xx → surfaced error

### AppleScript note creation

```applescript
on run argv
    set bodyHTML to item 1 of argv
    tell application "Notes"
        set theNote to make new note with properties {body:bodyHTML}
    end tell
    return (id of theNote) as string
end run
```

Apple Notes derives a note's displayed title from the first line of its body — there is no
separate settable `name` property on creation. The assembled HTML's first line therefore
carries the title (e.g. `Merged Notes — 2026-08-15`), and `createNote` takes only `body`,
not a separate `title` parameter. `MergeCoordinator` is responsible for putting a sensible
first line into the assembled document.

The body is passed as an `argv` item (`--` + item, exactly like the existing
`moveScript`/`deleteScript`), never string-interpolated into the AppleScript source — this
is required to safely handle arbitrary note content (quotes, backslashes, unicode) and
matches the existing script-safety pattern in `AppleNotesService`.

## Risk: image embedding is unverified

Apple Notes' AppleScript dictionary has no documented command for attaching an image file
to a note on creation. The candidate technique — setting `body` to HTML containing
`<img src="file:///…">` — is used informally elsewhere but has not been verified against
this app's Notes/macOS version.

**First implementation step is a standalone spike**, before any other code is written:
create a throwaway note via `osascript` using this technique and confirm Notes actually
imports it as a real inline image, not a broken link or plain text.

- **If it works:** proceed with the design as written — images embed inline per section,
  staged via `TriageAssetStore`, deleted after a successful write.
- **If it does not work:** fall back to text references instead of embeds. Each section's
  assembled text includes a line like `[image from "<original note title>" — staged at
  TriageAssets/<run-id>/<filename>]`, and in this fallback case `TriageAssetStore/<run-uuid>/`
  is **not** deleted after the write (it becomes the only copy of the image reference),
  with a note in the merged document's final line pointing at the folder.

The spike's outcome determines which of these two branches `MergeCoordinator` implements;
the implementation plan must not assume the embed path succeeds.

## Error Handling

| Failure | Behavior |
|---|---|
| Groq call fails (network, 401, rate-limited past retry budget) | Surface `errorMessage` in `AppState`; no note created; staged images for the run cleaned up |
| `createNote` AppleScript fails | Same — error surfaced, no partial note left behind (AppleScript's `make new note` is atomic — it either returns an id or throws) |
| Empty selection or missing Groq key | `Preview & Merge…` disabled in the UI, matching the existing `canStartWikiExport`-style guard pattern |
| Groq returns malformed JSON | Treated as a Groq call failure (one retry with a stricter re-prompt, then surface the error) |

## Testing

- **Pure logic, unit-testable without live Notes/network** (same tier as existing
  `NoteConverter`/`MarkdownRenderer` tests): HTML → plain-text stripping, Groq JSON
  response parsing, HTML document assembly from categorized sections, title-line
  derivation.
- **Manual acceptance gates** (same category as the existing Automation-permission gates
  documented in the app's README): the image-embedding spike itself, `createNote` against
  a real Notes library, and a live Groq API round-trip.

## Open Items Deferred to Implementation

- Exact Groq model string (pick the current recommended free-tier Llama model at
  implementation time).
- Retry count / backoff constants for `GroqService` (match `NotionService`'s existing
  constants unless a reason emerges to diverge).
