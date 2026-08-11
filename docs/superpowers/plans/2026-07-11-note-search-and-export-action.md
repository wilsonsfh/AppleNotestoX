# Apple Notes Search and Personal Wiki Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Command-F note search and an obvious, always-visible Personal Wiki export action beside the Apple Notes selection workflow.

**Architecture:** Keep filtering and footer-state decisions in small pure Swift types, then bind them to the existing observable `AppState`. `SourcePane` owns view focus while an app-level request counter bridges the Find menu command to the focused search field.

**Tech Stack:** Swift 6, SwiftUI, Observation, AppKit, XCTest, macOS 14+.

## Global Constraints

- Swift tools 6.0 and `.macOS(.v14)`; no new dependencies.
- Search note titles and ancestor folder names only, case- and diacritic-insensitively.
- Preserve the empty-query folder hierarchy and the existing Notion workflow.
- Personal Wiki export is the primary Capture action and defaults to the Wiki destination.
- Choosing a vault must not automatically export.
- XCTest cannot execute on this machine because only Command Line Tools are installed; `swift build` and `git diff --check` are mandatory local gates.
- Do not commit, push, or publish unless the user separately requests it.

## File Map

- Create `Sources/AppleNotestoX/Services/AppleNoteSearch.swift`: pure note/folder filtering.
- Create `Sources/AppleNotestoX/Models/PersonalWikiActionState.swift`: pure footer-state resolution.
- Create `Tests/AppleNotestoXTests/AppleNoteSearchTests.swift`: search behavior coverage.
- Create `Tests/AppleNotestoXTests/PersonalWikiActionStateTests.swift`: footer-state coverage.
- Modify `Sources/AppleNotestoX/App/AppState.swift`: search request and selection methods; default destination.
- Modify `Sources/AppleNotestoX/App/AppleNotestoXApp.swift`: standard Command-F command.
- Modify `Sources/AppleNotestoX/UI/SourcePane.swift`: visible search, flat results, footer action.
- Modify `Sources/AppleNotestoX/UI/DestinationPane.swift`: share vault directory picker.
- Modify `Sources/AppleNotestoX/UI/ContentView.swift`: remove the duplicate toolbar wiki action.

---

### Task 1: Pure Apple Notes Search

**Files:**
- Create: `Tests/AppleNotestoXTests/AppleNoteSearchTests.swift`
- Create: `Sources/AppleNotestoX/Services/AppleNoteSearch.swift`

**Interfaces:**
- Produces: `AppleNoteSearchResult` with `note: AppleNote` and `folderPath: String`.
- Produces: `AppleNoteSearch.results(in:matching:) -> [AppleNoteSearchResult]?`; `nil` means hierarchy mode.

- [ ] **Step 1: Write failing search tests**

Cover an empty query, title matching, diacritic-insensitive matching, ancestor-folder matching, deduplication, and modified-date/title ordering. Build a hierarchy with root `Personal`, child `Ideas`, and notes named `Cafe Plan`, `Résumé`, and `Weekly Review`. Assert that `"personal"` returns both descendant notes and that `"resume"` finds `Résumé`.

- [ ] **Step 2: Attempt the focused test gate**

Run: `swift test --filter AppleNoteSearchTests`

Expected on Xcode/CI before implementation: compile failure because `AppleNoteSearch` is undefined. Expected locally: infrastructure failure `no such module 'XCTest'`; record this without weakening the test.

- [ ] **Step 3: Implement the pure search helper**

```swift
import Foundation

struct AppleNoteSearchResult: Identifiable, Equatable {
    let note: AppleNote
    let folderPath: String
    var id: String { note.id }
}

enum AppleNoteSearch {
    static func results(in hierarchy: AppleNotesHierarchy, matching rawQuery: String) -> [AppleNoteSearchResult]? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        return hierarchy.notes.values.compactMap { note in
            let path = folderPath(for: note.folderID, in: hierarchy)
            guard matches(note.name, query) || matches(path, query) else { return nil }
            return AppleNoteSearchResult(note: note, folderPath: path)
        }.sorted {
            if $0.note.modifiedAt != $1.note.modifiedAt {
                return $0.note.modifiedAt > $1.note.modifiedAt
            }
            return $0.note.name.localizedCaseInsensitiveCompare($1.note.name) == .orderedAscending
        }
    }

    private static func matches(_ value: String, _ query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func folderPath(for folderID: String, in hierarchy: AppleNotesHierarchy) -> String {
        var names: [String] = []
        var currentID: String? = folderID
        var visited: Set<String> = []
        while let id = currentID, visited.insert(id).inserted, let folder = hierarchy.folders[id] {
            names.append(folder.name)
            currentID = folder.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}
```

- [ ] **Step 4: Run available gates**

Run `swift build`, then retry `swift test --filter AppleNoteSearchTests` when XCTest is available. Expected: build succeeds; all search tests pass under Xcode/CI.

---

### Task 2: Personal Wiki Footer State

**Files:**
- Create: `Tests/AppleNotestoXTests/PersonalWikiActionStateTests.swift`
- Create: `Sources/AppleNotestoX/Models/PersonalWikiActionState.swift`

**Interfaces:**
- Produces: `PersonalWikiActionState.resolve(selectedCount:hasVault:isExporting:progress:)`.

- [ ] **Step 1: Write failing state tests**

Assert all five states: `.selectNotes`, `.chooseVault(noteCount:)`, `.ready(noteCount:)`, `.exporting(done:total:)`, and `.completed(done:failed:)`. Construct progress values with `.pending`, `.failed(message:)`, and `.done(result:)` statuses.

- [ ] **Step 2: Attempt the focused test gate**

Run: `swift test --filter PersonalWikiActionStateTests`

Expected before implementation: undefined-type failure under Xcode/CI; local XCTest infrastructure failure is acceptable and must be recorded.

- [ ] **Step 3: Implement deterministic state resolution**

```swift
import Foundation

enum PersonalWikiActionState: Equatable {
    case selectNotes
    case chooseVault(noteCount: Int)
    case ready(noteCount: Int)
    case exporting(done: Int, total: Int)
    case completed(done: Int, failed: Int)

    static func resolve(selectedCount: Int, hasVault: Bool, isExporting: Bool,
                        progress: [WikiExportProgress]) -> Self {
        let done = progress.filter { if case .done = $0.status { true } else { false } }.count
        let failed = progress.filter { if case .failed = $0.status { true } else { false } }.count
        if isExporting {
            return .exporting(done: done, total: max(selectedCount, progress.count))
        }
        if !progress.isEmpty, done + failed == progress.count {
            return .completed(done: done, failed: failed)
        }
        guard selectedCount > 0 else { return .selectNotes }
        guard hasVault else { return .chooseVault(noteCount: selectedCount) }
        return .ready(noteCount: selectedCount)
    }
}
```

- [ ] **Step 4: Run available gates**

Run `swift build`; run the focused XCTest under Xcode/CI. Expected: build and tests pass.

---

### Task 3: App-Level Find and Selection State

**Files:**
- Modify: `Sources/AppleNotestoX/App/AppState.swift`
- Modify: `Sources/AppleNotestoX/App/AppleNotestoXApp.swift`

**Interfaces:**
- Produces: `noteSearchQuery`, `noteSearchFocusRequest`, `requestNoteSearch()`, and `toggleNoteSelection(_:)` on `AppState`.

- [ ] **Step 1: Add state behavior before UI wiring**

Set `exportDestination` to `.wiki`. Add the two search properties and these methods:

```swift
func requestNoteSearch() {
    appMode = .capture
    noteSearchFocusRequest &+= 1
}

func toggleNoteSelection(_ noteID: String) {
    guard !isArchiving else { return }
    if !wikiProgress.isEmpty { wikiProgress = [] }
    if selectedNoteIDs.remove(noteID) == nil { selectedNoteIDs.insert(noteID) }
}
```

- [ ] **Step 2: Add the application Find command**

Add to the `WindowGroup` scene:

```swift
.commands {
    CommandGroup(after: .textEditing) {
        Button("Find Notes") { state.requestNoteSearch() }
            .keyboardShortcut("f", modifiers: .command)
    }
}
```

- [ ] **Step 3: Compile the state and command changes**

Run: `swift build`

Expected: successful build with no actor-isolation or duplicate-shortcut errors.

---

### Task 4: Search UI and Intuitive Export Footer

**Files:**
- Modify: `Sources/AppleNotestoX/UI/SourcePane.swift`
- Modify: `Sources/AppleNotestoX/UI/DestinationPane.swift`
- Modify: `Sources/AppleNotestoX/UI/ContentView.swift`

**Interfaces:**
- Consumes: `AppleNoteSearch.results`, `PersonalWikiActionState.resolve`, and the new `AppState` methods.
- Produces: `pickVaultDirectory() -> URL?`, shared by both panes.

- [ ] **Step 1: Add visible, focusable search**

Add a `@FocusState` to `SourcePane`, bind a rounded `TextField("Search notes and folders", text: $state.noteSearchQuery)` below the header, and focus it when `noteSearchFocusRequest` changes. Use `onExitCommand` to clear a non-empty query, then release focus when already empty.

- [ ] **Step 2: Render flat results without changing selection semantics**

When `AppleNoteSearch.results` is non-nil, show matching `AppleNoteRow` values with their `folderPath`. When it is nil, preserve the existing folder tree. Change every row tap to `state.toggleNoteSelection(note.id)` and show a clear-search empty state when results are empty.

- [ ] **Step 3: Add the persistent footer**

Resolve `PersonalWikiActionState` from current state. Render:

- `.selectNotes`: `Select notes to export` secondary text.
- `.chooseVault`: prominent `Choose Personal Wiki...`; call `pickVaultDirectory`, then `state.chooseVault` only.
- `.ready`: prominent `Export N notes to Personal Wiki`; call `state.runWikiExport()`.
- `.exporting`: progress indicator plus `Exporting done/total`.
- `.completed`: success/failure text, including both counts when failures exist.

Use `.keyboardShortcut(.return, modifiers: [.command])` on the ready export button and singular `note` when count is one.

- [ ] **Step 4: Share the vault picker and remove the duplicate action**

Move the existing `NSOpenPanel` directory configuration into an internal `@MainActor func pickVaultDirectory() -> URL?` in `DestinationPane.swift`. Reuse it from both panes. Remove only the Wiki export toolbar button from `ContentView`; retain the Notion `Archive...` toolbar button.

- [ ] **Step 5: Run objective verification**

Run:

```bash
swift build
git diff --check
```

Expected: both commands exit successfully. Retry both focused XCTest filters under Xcode/CI when available.

- [ ] **Step 6: Run manual acceptance**

Launch with `swift run AppleNotestoX`. Verify Command-F from Study enters Capture and focuses search; title/folder search finds a known pinned note; selection survives query clearing; missing-vault state offers the picker; choosing the vault does not export; the next click exports; progress/completion are visible; Notion Archive remains available.
