import XCTest
@testable import AppleNotestoX

final class WikiNamingTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSlugKebabsAndStrips() {
        XCTAssertEqual(WikiNaming.slug(from: "Project Journal — 2026!"), "project-journal-2026")
        XCTAssertEqual(WikiNaming.slug(from: "  Multiple   spaces "), "multiple-spaces")
        XCTAssertEqual(WikiNaming.slug(from: ""), "note")
    }

    func testIsoDay() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 24; comps.hour = 17
        comps.timeZone = TimeZone(identifier: "UTC")
        let d = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(WikiNaming.isoDay(d), "2026-03-24")
    }

    func testMarkdownAndAssetFilenames() {
        XCTAssertEqual(WikiNaming.markdownFilename(date: Date(timeIntervalSince1970: 0), slug: "x"), "1970-01-01-x.md")
        XCTAssertEqual(WikiNaming.assetFilename(slug: "project-journal", index: 1, ext: "png"), "project-journal-01.png")
        XCTAssertEqual(WikiNaming.assetFilename(slug: "project-journal", index: 12, ext: "JPG"), "project-journal-12.jpg")
    }

    func testUniqueName() {
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: []), "a.md")
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: ["a.md"]), "a-2.md")
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: ["a.md", "a-2.md"]), "a-3.md")
    }

    func testPublishDataPreservesExistingAndCaseVariantFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("Note.md")
        try Data("old".utf8).write(to: existing)

        let published = try WikiNaming.publish(
            data: Data("new".utf8),
            preferredName: "note.md",
            in: directory
        )

        XCTAssertEqual(try Data(contentsOf: existing), Data("old".utf8))
        XCTAssertEqual(published.lastPathComponent, "note-2.md")
        XCTAssertEqual(try Data(contentsOf: published), Data("new".utf8))
    }

    func testPublishDataTreatsUnicodeNormalizationsAsCollisions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let decomposed = "cafe\u{301}.md"
        try Data("old".utf8).write(to: directory.appendingPathComponent(decomposed))

        let published = try WikiNaming.publish(
            data: Data("new".utf8),
            preferredName: "caf\u{E9}.md",
            in: directory
        )

        XCTAssertEqual(published.lastPathComponent, "caf\u{E9}-2.md")
    }

    func testConcurrentPublicationsRetrySuffixesWithoutReplacement() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for value in ["first", "second"] {
                group.addTask {
                    try WikiNaming.publish(
                        data: Data(value.utf8),
                        preferredName: "race.md",
                        in: directory
                    )
                }
            }
            var results: [URL] = []
            for try await result in group { results.append(result) }
            return results
        }

        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["race.md", "race-2.md"])
        XCTAssertEqual(Set(try urls.map { try String(contentsOf: $0, encoding: .utf8) }), ["first", "second"])
    }

    func testConcurrentCopiesRetrySuffixesWithoutDroppingEitherFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sources = try ["first", "second"].map { value -> URL in
            let source = directory.appendingPathComponent("source-\(value)")
            try Data(value.utf8).write(to: source)
            return source
        }
        let destination = directory.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for source in sources {
                group.addTask {
                    try WikiNaming.copy(source: source, preferredName: "asset.png", to: destination)
                }
            }
            var results: [URL] = []
            for try await result in group { results.append(result) }
            return results
        }

        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["asset.png", "asset-2.png"])
        XCTAssertEqual(Set(try urls.map { try String(contentsOf: $0, encoding: .utf8) }), ["first", "second"])
    }

    func testIdentityAwareRollbackDeletesUnchangedCreatedFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let created = try WikiNaming.publishTracked(
            data: Data("owned".utf8),
            preferredName: "owned.md",
            in: directory
        )

        WikiNaming.removeIfIdentityMatches(created)

        XCTAssertFalse(FileManager.default.fileExists(atPath: created.url.path))
    }

    func testIdentityAwareRollbackPreservesReplacementAtSamePath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let created = try WikiNaming.publishTracked(
            data: Data("owned".utf8),
            preferredName: "owned.md",
            in: directory
        )
        try FileManager.default.removeItem(at: created.url)
        try Data("replacement".utf8).write(to: created.url)

        WikiNaming.removeIfIdentityMatches(created)

        XCTAssertEqual(try Data(contentsOf: created.url), Data("replacement".utf8))
    }

    func testYAMLScalarAlwaysQuotesAndEscapesStrings() {
        XCTAssertEqual(WikiNaming.yamlScalar("plain"), #""plain""#)
        XCTAssertEqual(
            WikiNaming.yamlScalar("a: b\nquoted \"value\" \\ path"),
            #""a: b\nquoted \"value\" \\ path""#
        )
        XCTAssertEqual(WikiNaming.yamlScalar("yes"), #""yes""#)
    }

    func testFrontmatterContainsKeys() {
        let fm = WikiNaming.frontmatter(noteID: "x-123", title: "Project Journal",
                                        modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(fm.hasPrefix("---\n"))
        XCTAssertTrue(fm.contains(#"origin: "user-stated""#))
        XCTAssertTrue(fm.contains(#"source_app: "apple-notes""#))
        XCTAssertTrue(fm.contains(#"apple_note_id: "x-123""#))
        XCTAssertTrue(fm.contains(#"title: "Project Journal""#))
        XCTAssertTrue(fm.contains("Provenance:"))
        XCTAssertFalse(fm.localizedCaseInsensitiveContains("verbatim"))
    }

    func testFrontmatterQuotesUnsafeValues() {
        let fm = WikiNaming.frontmatter(
            noteID: "id: 1\nnext",
            title: "A: title \"quoted\"",
            modified: Date(timeIntervalSince1970: 0),
            exported: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(fm.contains(#"apple_note_id: "id: 1\nnext""#))
        XCTAssertTrue(fm.contains(#"title: "A: title \"quoted\"""#))
    }

    func testParseFrontmatterRoundTripsSimpleValues() {
        let fm = WikiNaming.frontmatter(
            noteID: "x-123", title: "Project Journal",
            modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 86400)
        )

        let fields = WikiNaming.parseFrontmatter(fm)

        XCTAssertEqual(fields?["apple_note_id"], "x-123")
        XCTAssertEqual(fields?["title"], "Project Journal")
        XCTAssertEqual(fields?["note_modified"], "1970-01-01")
        XCTAssertEqual(fields?["exported"], "1970-01-02")
        XCTAssertEqual(fields?["source_app"], "apple-notes")
    }

    func testParseFrontmatterRoundTripsEscapedValues() {
        let fm = WikiNaming.frontmatter(
            noteID: "id: 1\nnext",
            title: "A: title \"quoted\" \\ path",
            modified: Date(timeIntervalSince1970: 0),
            exported: Date(timeIntervalSince1970: 0)
        )

        let fields = WikiNaming.parseFrontmatter(fm)

        XCTAssertEqual(fields?["apple_note_id"], "id: 1\nnext")
        XCTAssertEqual(fields?["title"], "A: title \"quoted\" \\ path")
    }

    func testParseFrontmatterReturnsNilForNonFrontmatterContent() {
        XCTAssertNil(WikiNaming.parseFrontmatter("# Just a heading\n\nSome body text."))
        XCTAssertNil(WikiNaming.parseFrontmatter(""))
    }
}
