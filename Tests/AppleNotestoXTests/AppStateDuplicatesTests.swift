import XCTest
@testable import AppleNotestoX

final class AppStateDuplicatesTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func writeDuplicateJournal(in vault: URL, noteID: String, title: String, count: Int) throws {
        let journalDir = WikiVaultConfig(vaultURL: vault).journalDir
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        for i in 0..<count {
            let modified = Date(timeIntervalSince1970: 0)
            let exported = Date(timeIntervalSince1970: TimeInterval(i * 86_400))
            let fm = WikiNaming.frontmatter(noteID: noteID, title: title, modified: modified, exported: exported)
            let filename = i == 0 ? "\(title.lowercased()).md" : "\(title.lowercased())-\(i + 1).md"
            try fm.write(to: journalDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    func testToggleDuplicateSelectionAddsAndRemoves() {
        let state = AppState()
        let path = URL(fileURLWithPath: "/tmp/a.md")

        state.toggleDuplicateSelection(path)
        XCTAssertTrue(state.selectedDuplicatePaths.contains(path))

        state.toggleDuplicateSelection(path)
        XCTAssertFalse(state.selectedDuplicatePaths.contains(path))
    }

    @MainActor
    func testScanForDuplicatesPreselectsEveryEntryExceptTheNewest() async throws {
        try writeDuplicateJournal(in: tmp, noteID: "A", title: "Cafe", count: 3)
        let state = AppState()
        state.vaultURL = tmp

        await state.scanForDuplicates()

        XCTAssertEqual(state.duplicateGroups.count, 1)
        let group = state.duplicateGroups[0]
        XCTAssertEqual(group.entries.count, 3)
        // Newest (index 0, sorted first) stays unselected; the other two are pre-checked.
        XCTAssertFalse(state.selectedDuplicatePaths.contains(group.entries[0].markdownPath))
        XCTAssertTrue(state.selectedDuplicatePaths.contains(group.entries[1].markdownPath))
        XCTAssertTrue(state.selectedDuplicatePaths.contains(group.entries[2].markdownPath))
    }

    @MainActor
    func testScanForDuplicatesWithNoVault_doesNothing() async {
        let state = AppState()
        state.vaultURL = nil

        await state.scanForDuplicates()

        XCTAssertTrue(state.duplicateGroups.isEmpty)
        XCTAssertFalse(state.isScanningDuplicates)
    }

    @MainActor
    func testDeleteSelectedDuplicatesWithNothingSelected_doesNothing() async throws {
        try writeDuplicateJournal(in: tmp, noteID: "A", title: "Cafe", count: 2)
        let state = AppState()
        state.vaultURL = tmp
        state.selectedDuplicatePaths = []

        await state.deleteSelectedDuplicates()

        XCTAssertFalse(state.isDeletingDuplicates)
    }

    // Note: the actual delete-and-rescan path (deleteSelectedDuplicates with
    // a non-empty selection) is intentionally not exercised here — AppState
    // always constructs its real WikiVaultMaintenance with the Trash-based
    // default remover (AppState has no dependency-injection seam for it),
    // so driving that path from a test would move real files to the
    // machine's Trash. WikiVaultMaintenanceTests covers the delete/asset-
    // cleanup logic itself against an injected, temp-dir-only remover.
}
