import XCTest
@testable import AppleNotestoX

final class PersonalWikiActionStateTests: XCTestCase {
    func testResolveSelectsNotesWhenNothingIsSelected() {
        XCTAssertEqual(
            PersonalWikiActionState.resolve(
                selectedCount: 0, hasVault: false, isExporting: false, progress: []),
            .selectNotes)
    }

    func testResolveChoosesVaultWhenNotesAreSelectedWithoutVault() {
        XCTAssertEqual(
            PersonalWikiActionState.resolve(
                selectedCount: 3, hasVault: false, isExporting: false, progress: []),
            .chooseVault(noteCount: 3))
    }

    func testResolveIsReadyWhenNotesAndVaultAreAvailable() {
        XCTAssertEqual(
            PersonalWikiActionState.resolve(
                selectedCount: 3, hasVault: true, isExporting: false, progress: []),
            .ready(noteCount: 3))
    }

    func testResolveReportsExportingBeforeCompletedProgress() {
        let progress = [
            makeProgress(id: "one", status: .done(result: makeResult())),
            makeProgress(id: "two", status: .failed(message: "No access")),
            makeProgress(id: "three", status: .pending)
        ]

        XCTAssertEqual(
            PersonalWikiActionState.resolve(
                selectedCount: 2, hasVault: false, isExporting: true, progress: progress),
            .exporting(done: 1, total: 3))
    }

    func testResolveExportingKeepsSelectedCountWhenProgressIsPartial() {
        let progress = [
            makeProgress(id: "one", status: .done(result: makeResult())),
            makeProgress(id: "two", status: .pending)
        ]

        XCTAssertEqual(
            PersonalWikiActionState.resolve(
                selectedCount: 5, hasVault: true, isExporting: true, progress: progress),
            .exporting(done: 1, total: 5))
    }

    func testResolvePartialNonterminalProgressDoesNotComplete() {
        let progress = [
            makeProgress(id: "one", status: .done(result: makeResult())),
            makeProgress(id: "two", status: .pending)
        ]

        XCTAssertEqual(
            PersonalWikiActionState.resolve(
                selectedCount: 2, hasVault: true, isExporting: false, progress: progress),
            .ready(noteCount: 2))
    }

    func testResolveCompletesWhenAllProgressIsTerminal() {
        let progress = [
            makeProgress(id: "one", status: .done(result: makeResult())),
            makeProgress(id: "two", status: .failed(message: "No access"))
        ]

        XCTAssertEqual(
            PersonalWikiActionState.resolve(
                selectedCount: 0, hasVault: false, isExporting: false, progress: progress),
            .completed(done: 1, failed: 1))
    }

    private func makeProgress(id: String, status: WikiExportStatus) -> WikiExportProgress {
        WikiExportProgress(id: id, title: id, status: status)
    }

    private func makeResult() -> WikiExportResult {
        WikiExportResult(
            markdownPath: URL(fileURLWithPath: "/tmp/note.md"),
            assetPaths: [],
            imageCount: 0,
            warnings: [])
    }
}
