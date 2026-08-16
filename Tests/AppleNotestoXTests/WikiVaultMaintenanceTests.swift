import XCTest
@testable import AppleNotestoX

final class WikiVaultMaintenanceTests: XCTestCase {
    private var tmp: URL!
    private var config: WikiVaultConfig!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        config = WikiVaultConfig(vaultURL: tmp)
        try FileManager.default.createDirectory(at: config.journalDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.assetsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Deletes straight from the temp vault instead of moving to the real
    /// Trash, so these tests never touch the machine's actual Trash.
    private func makeMaintenance() -> WikiVaultMaintenance {
        WikiVaultMaintenance(remove: { url in try FileManager.default.removeItem(at: url) })
    }

    @discardableResult
    private func writeJournal(_ body: String, frontmatter: String, filename: String) throws -> URL {
        let url = config.journalDir.appendingPathComponent(filename)
        try (frontmatter + body).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func fm(noteID: String, title: String, modified: Date = Date(timeIntervalSince1970: 0)) -> String {
        WikiNaming.frontmatter(noteID: noteID, title: title, modified: modified, exported: modified)
    }

    func test_findDuplicates_surfacesNotesWithMultipleJournalFiles() async throws {
        try writeJournal("body", frontmatter: fm(noteID: "A", title: "Cafe"), filename: "cafe.md")
        try writeJournal("body", frontmatter: fm(noteID: "A", title: "Cafe"), filename: "cafe-2.md")
        try writeJournal("body", frontmatter: fm(noteID: "B", title: "Solo"), filename: "solo.md")

        let groups = await makeMaintenance().findDuplicates(config: config)

        XCTAssertEqual(groups.map(\.noteID), ["A"])
        XCTAssertEqual(groups[0].entries.count, 2)
    }

    func test_delete_removesTheMarkdownFile() async throws {
        let url = try writeJournal("body", frontmatter: fm(noteID: "A", title: "Cafe"), filename: "cafe.md")
        let entry = WikiVaultIndex.Entry(
            noteID: "A", noteModifiedDay: "1970-01-01", exportedDay: "1970-01-01", title: "Cafe", markdownPath: url
        )

        try await makeMaintenance().delete(entry: entry, config: config)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_delete_removesAssetsOnlyThatFileReferenced() async throws {
        try Data([0]).write(to: config.assetsDir.appendingPathComponent("cafe-01.png"))
        let url = try writeJournal(
            "![[cafe-01.png]]", frontmatter: fm(noteID: "A", title: "Cafe"), filename: "cafe-2.md"
        )
        let entry = WikiVaultIndex.Entry(
            noteID: "A", noteModifiedDay: "1970-01-01", exportedDay: "1970-01-01", title: "Cafe", markdownPath: url
        )

        try await makeMaintenance().delete(entry: entry, config: config)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: config.assetsDir.appendingPathComponent("cafe-01.png").path)
        )
    }

    func test_delete_keepsAssetsStillReferencedByAnotherRemainingFile() async throws {
        try Data([0]).write(to: config.assetsDir.appendingPathComponent("cafe-01.png"))
        // Two duplicate journal files that happen to reference the same (shared) asset name.
        try writeJournal("![[cafe-01.png]]", frontmatter: fm(noteID: "A", title: "Cafe"), filename: "cafe.md")
        let deleted = try writeJournal(
            "![[cafe-01.png]]", frontmatter: fm(noteID: "A", title: "Cafe"), filename: "cafe-2.md"
        )
        let entry = WikiVaultIndex.Entry(
            noteID: "A", noteModifiedDay: "1970-01-01", exportedDay: "1970-01-01", title: "Cafe", markdownPath: deleted
        )

        try await makeMaintenance().delete(entry: entry, config: config)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: config.assetsDir.appendingPathComponent("cafe-01.png").path)
        )
    }

    func test_delete_missingFile_throws() async {
        let entry = WikiVaultIndex.Entry(
            noteID: "A", noteModifiedDay: "1970-01-01", exportedDay: nil, title: "Cafe",
            markdownPath: config.journalDir.appendingPathComponent("does-not-exist.md")
        )

        do {
            try await makeMaintenance().delete(entry: entry, config: config)
            XCTFail("expected throw")
        } catch {
            // expected — removing a file that doesn't exist throws
        }
    }
}
