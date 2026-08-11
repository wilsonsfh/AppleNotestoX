# Apple Notes Search and Personal Wiki Export Design

**Date:** 2026-07-11
**Status:** Approved for implementation

## Problem

The Capture source pane exposes a checkbox for each Apple Note but provides no nearby next action. The existing export button lives in the window toolbar, is only useful after a destination is configured, and does not explain why it may be disabled. Pinned notes are present in the hierarchy but are not marked differently from unpinned notes, so notes are difficult to locate in a large library.

## Goals

- Make every loaded Apple Note easy to find regardless of pinned status.
- Make Command-F focus note search from anywhere in the app.
- Make the next step after selecting a note obvious.
- Make Personal LLM Wiki export the primary Capture workflow.
- Preserve the existing folder browser and Notion workflow.

## Non-Goals

- Searching full note bodies or attachments.
- Detecting or displaying Apple Notes pin state.
- Replacing the existing Notion archive flow.
- Automatically synthesizing raw exports into the wiki.

## Interaction Design

### Search

A visible search field sits below the Apple Notes header in the Capture source pane. It searches note titles and ancestor folder names using case- and diacritic-insensitive matching.

With an empty query, the existing disclosure-based folder hierarchy remains unchanged. With a non-empty query, the pane switches to a flat result list. Each result includes:

- the existing selection checkbox;
- the note title;
- its folder path for context;
- its relative modification date; and
- the existing archived marker when applicable.

Selection persists when the query changes or clears. An empty result state says that no notes match and offers a clear-search action.

Command-F switches the app to Capture mode when necessary and focuses the search field. Escape clears the query first; pressing Escape again releases search focus.

### Primary Export Action

A footer remains visible below the Apple Notes list and reflects the current workflow state:

| State | Footer behavior |
| --- | --- |
| No notes selected | Secondary text: `Select notes to export` |
| Notes selected, no vault | Prominent `Choose Personal Wiki...` button |
| Notes selected, vault ready | Prominent `Export N notes` button |
| Export running | Disabled progress indicator with current progress |
| Export complete | Success or failure summary in the footer |

Choosing a vault configures the destination but does not immediately export, avoiding an unexpected write. The user then explicitly clicks Export. The footer exports to the Personal LLM Wiki regardless of the secondary Notion destination controls.

The app defaults new sessions to the Wiki destination. Notion remains available in the destination pane and retains its existing archive action.

## Architecture

### Search State and Command

`AppState` owns the query and a monotonically increasing focus request value so the app-level Command-F command can communicate with `SourcePane` without coupling the application scene to a view-local `FocusState`.

The application command sets Capture mode and increments the focus request. `SourcePane` observes that request and focuses its search field.

### Filtering

A small pure helper derives searchable note rows from `AppleNotesHierarchy`. It computes each note's ancestor folder path once per filtering operation and returns deterministic results sorted by most recently modified, then title. This helper is independently unit tested.

Folder matches include notes contained by the matching folder or any descendant folder. No note body is fetched during search, keeping interaction immediate and avoiding AppleScript work per keystroke.

### Source Pane Footer

`SourcePane` derives its footer presentation from existing state: selected IDs, vault URL, archive status, and wiki progress. Vault selection reuses the current security-scoped bookmark behavior. The file-picker operation should be factored into the smallest shared function needed by `SourcePane` and `DestinationPane`; unrelated destination UI remains unchanged.

## Error Handling

- If Apple Notes permission is unavailable, the existing permission sheet remains authoritative.
- If no hierarchy is loaded, search is disabled and the existing loading or empty state is shown.
- If vault selection is cancelled, selection remains intact and no export begins.
- Export failures remain visible in the footer until another export begins or the selection changes.
- Search never mutates note selection or exported content.

## Accessibility and Keyboard Behavior

- The search field has the accessibility label `Search Apple Notes`.
- Command-F is exposed through the standard Find menu command.
- Each result remains a full-row selection target in addition to its checkbox icon.
- Footer status is text, not color-only.
- Button labels use singular/plural note wording.

## Testing

### Automated

- Empty query returns hierarchy mode rather than filtered results.
- Title matching is case- and diacritic-insensitive.
- Folder and ancestor-folder matching returns the expected notes.
- Results are deduplicated and deterministically sorted.
- Selection IDs survive query changes.
- Footer state covers no selection, missing vault, ready, running, success, and failure.

### Manual Acceptance

1. Launch in Study mode and press Command-F; Capture opens and search receives focus.
2. Search for a known pinned note title and confirm it appears with its folder path.
3. Search by folder name and confirm notes in that folder and descendants appear.
4. Select a result, clear search, and confirm it remains selected in the hierarchy.
5. With no vault configured, confirm the footer offers `Choose Personal Wiki...`.
6. Choose `Personal_LLM_Wiki`, confirm no automatic export occurs, then click `Export 1 note`.
7. Confirm progress and completion appear in the footer and the raw file is written to `raw/journal/`.
8. Switch to Notion and confirm the existing archive flow still works.

## Success Criteria

- Any loaded note can be reached by title or folder search without manually expanding folders.
- Command-F reliably exposes and focuses search.
- Selecting a note always reveals an understandable next step in the same pane.
- A first-time user can configure the Personal Wiki and export a note without discovering a toolbar-only action.
- Existing Notion and wiki export behavior remains functionally intact.
