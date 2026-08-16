import XCTest
@testable import AppleNotestoX

final class AppStateSearchTests: XCTestCase {
    @MainActor
    func testDefaultsToMergeToNoteExportDestination() {
        let state = AppState()

        XCTAssertEqual(state.exportDestination, .mergeToNote)
    }

    @MainActor
    func testWikiExportOperationDefaultsToIdle() {
        let state = AppState()

        XCTAssertFalse(state.isExportingToWiki)
    }

    @MainActor
    func testVideoImportDefaultsToIdleAndProgressChannelsAreIndependent() {
        let state = AppState()
        let noteProgress = WikiExportProgress(
            id: "note", title: "Note", status: .done(result: makeResult()))
        let videoProgress = WikiExportProgress(
            id: "video", title: "Video", status: .converting)

        XCTAssertFalse(state.isArchiving)
        XCTAssertTrue(state.videoProgress.isEmpty)

        state.wikiProgress = [noteProgress]
        state.videoProgress = [videoProgress]
        state.videoProgress.removeAll()

        XCTAssertEqual(state.wikiProgress, [noteProgress])
        XCTAssertTrue(state.videoProgress.isEmpty)

        state.videoProgress = [videoProgress]
        state.wikiProgress.removeAll()

        XCTAssertEqual(state.videoProgress, [videoProgress])
    }

    @MainActor
    func testWikiExportGateRequiresAllOperationsToBeIdle() {
        let state = AppState()

        XCTAssertTrue(state.canStartWikiExport)

        state.isArchiving = true
        XCTAssertFalse(state.canStartWikiExport)

        state.isArchiving = false
        state.isExportingToWiki = true
        XCTAssertFalse(state.canStartWikiExport)
    }

    @MainActor
    func testRequestNoteSearchSwitchesToCaptureAndIncrementsFocusRequest() {
        let state = AppState()
        state.appMode = .study

        state.requestNoteSearch()
        state.requestNoteSearch()

        XCTAssertEqual(state.appMode, .capture)
        XCTAssertEqual(state.noteSearchFocusRequest, 2)
    }

    @MainActor
    func testToggleNoteSelectionClearsWikiProgressAndTogglesSelection() {
        let state = AppState()
        state.selectedNoteIDs = ["selected"]
        state.wikiProgress = [
            WikiExportProgress(
                id: "selected",
                title: "Selected",
                status: .done(result: makeResult())
            )
        ]

        state.toggleNoteSelection("selected")

        XCTAssertTrue(state.wikiProgress.isEmpty)
        XCTAssertFalse(state.selectedNoteIDs.contains("selected"))

        state.toggleNoteSelection("new")

        XCTAssertTrue(state.selectedNoteIDs.contains("new"))
    }

    @MainActor
    func testToggleNoteSelectionDoesNotMutateSelectionOrWikiProgressWhileArchiving() {
        let state = AppState()
        state.isArchiving = true
        state.selectedNoteIDs = ["selected"]
        state.wikiProgress = [
            WikiExportProgress(
                id: "selected",
                title: "Selected",
                status: .done(result: makeResult())
            )
        ]
        let originalProgress = state.wikiProgress

        state.toggleNoteSelection("selected")
        state.toggleNoteSelection("new")

        XCTAssertEqual(state.selectedNoteIDs, ["selected"])
        XCTAssertEqual(state.wikiProgress, originalProgress)
    }

    @MainActor
    func testToggleFolderSelectionSelectsAllNotesInFolderAndSubfolders() {
        let state = AppState()
        state.hierarchy = makeHierarchy()

        state.toggleFolderSelection("personal")

        XCTAssertEqual(state.selectedNoteIDs, ["weekly-review", "cafe-plan", "resume"])
    }

    @MainActor
    func testToggleFolderSelectionDeselectsWhenFullySelected() {
        let state = AppState()
        state.hierarchy = makeHierarchy()
        state.selectedNoteIDs = ["weekly-review", "cafe-plan", "resume"]

        state.toggleFolderSelection("personal")

        XCTAssertTrue(state.selectedNoteIDs.isEmpty)
    }

    @MainActor
    func testToggleFolderSelectionCompletesPartialSelectionRatherThanClearingIt() {
        let state = AppState()
        state.hierarchy = makeHierarchy()
        state.selectedNoteIDs = ["cafe-plan"]

        state.toggleFolderSelection("personal")

        XCTAssertEqual(state.selectedNoteIDs, ["weekly-review", "cafe-plan", "resume"])
    }

    @MainActor
    func testToggleFolderSelectionDoesNothingWhileArchivingOrWithoutHierarchy() {
        let state = AppState()
        state.hierarchy = makeHierarchy()
        state.isArchiving = true

        state.toggleFolderSelection("personal")
        XCTAssertTrue(state.selectedNoteIDs.isEmpty)

        state.isArchiving = false
        state.hierarchy = nil

        state.toggleFolderSelection("personal")
        XCTAssertTrue(state.selectedNoteIDs.isEmpty)
    }

    private func makeHierarchy() -> AppleNotesHierarchy {
        AppleNotesHierarchy(
            folders: [
                "personal": AppleFolder(
                    id: "personal", name: "Personal", accountName: "iCloud", parentID: nil,
                    childFolderIDs: ["ideas"], noteIDs: ["weekly-review"]
                ),
                "ideas": AppleFolder(
                    id: "ideas", name: "Ideas", accountName: "iCloud", parentID: "personal",
                    childFolderIDs: [], noteIDs: ["cafe-plan", "resume"]
                ),
            ],
            notes: [
                "weekly-review": AppleNote(id: "weekly-review", name: "Weekly Review", folderID: "personal", modifiedAt: Date(timeIntervalSince1970: 0)),
                "cafe-plan": AppleNote(id: "cafe-plan", name: "Cafe Plan", folderID: "ideas", modifiedAt: Date(timeIntervalSince1970: 0)),
                "resume": AppleNote(id: "resume", name: "Résumé", folderID: "ideas", modifiedAt: Date(timeIntervalSince1970: 0)),
            ],
            rootFolderIDs: ["personal"]
        )
    }

    private func makeResult() -> WikiExportResult {
        WikiExportResult(
            markdownPath: URL(fileURLWithPath: "/tmp/note.md"),
            assetPaths: [],
            imageCount: 0,
            warnings: []
        )
    }
}
