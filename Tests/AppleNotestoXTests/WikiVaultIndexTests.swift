import XCTest
@testable import AppleNotestoX

final class WikiVaultIndexTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func write(_ frontmatter: String, filename: String) throws {
        try frontmatter.write(to: tmp.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    func test_scan_indexesFilesByAppleNoteID() throws {
        let fm = WikiNaming.frontmatter(
            noteID: "note-A", title: "Cafe Plan",
            modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0)
        )
        try write(fm, filename: "2026-08-16-cafe-plan.md")

        let index = WikiVaultIndex.scan(journalDir: tmp)

        XCTAssertEqual(index["note-A"]?.noteModifiedDay, "1970-01-01")
        XCTAssertEqual(index["note-A"]?.markdownPath.lastPathComponent, "2026-08-16-cafe-plan.md")
    }

    func test_scan_ignoresNonMarkdownAndUnparsableFiles() throws {
        try "not frontmatter".write(to: tmp.appendingPathComponent("stray.md"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2]).write(to: tmp.appendingPathComponent("image.png"))

        let index = WikiVaultIndex.scan(journalDir: tmp)

        XCTAssertTrue(index.isEmpty)
    }

    func test_scan_missingDirectory_returnsEmptyIndex() {
        let missing = tmp.appendingPathComponent("does-not-exist")
        XCTAssertTrue(WikiVaultIndex.scan(journalDir: missing).isEmpty)
    }

    func test_isUpToDate_trueWhenModifiedDayMatchesIndexedEntry() throws {
        let fm = WikiNaming.frontmatter(
            noteID: "note-A", title: "Cafe Plan",
            modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0)
        )
        try write(fm, filename: "2026-08-16-cafe-plan.md")
        let index = WikiVaultIndex.scan(journalDir: tmp)

        XCTAssertTrue(WikiVaultIndex.isUpToDate(noteID: "note-A", modified: Date(timeIntervalSince1970: 0), index: index))
    }

    func test_isUpToDate_falseWhenNoteModifiedSinceLastExport() throws {
        let fm = WikiNaming.frontmatter(
            noteID: "note-A", title: "Cafe Plan",
            modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0)
        )
        try write(fm, filename: "2026-08-16-cafe-plan.md")
        let index = WikiVaultIndex.scan(journalDir: tmp)

        XCTAssertFalse(WikiVaultIndex.isUpToDate(noteID: "note-A", modified: Date(timeIntervalSince1970: 86_400 * 5), index: index))
    }

    func test_isUpToDate_falseWhenNoteIDNotIndexed() {
        XCTAssertFalse(WikiVaultIndex.isUpToDate(noteID: "unknown", modified: Date(), index: [:]))
    }
}
