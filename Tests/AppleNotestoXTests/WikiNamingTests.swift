import XCTest
@testable import AppleNotestoX

final class WikiNamingTests: XCTestCase {
    func testSlugKebabsAndStrips() {
        XCTAssertEqual(WikiNaming.slug(from: "Glints Journal — 2026!"), "glints-journal-2026")
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
        XCTAssertEqual(WikiNaming.assetFilename(slug: "glints", index: 1, ext: "png"), "glints-01.png")
        XCTAssertEqual(WikiNaming.assetFilename(slug: "glints", index: 12, ext: "JPG"), "glints-12.jpg")
    }

    func testUniqueName() {
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: []), "a.md")
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: ["a.md"]), "a-2.md")
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: ["a.md", "a-2.md"]), "a-3.md")
    }

    func testFrontmatterContainsKeys() {
        let fm = WikiNaming.frontmatter(noteID: "x-123", title: "Glints",
                                        modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(fm.hasPrefix("---\n"))
        XCTAssertTrue(fm.contains("origin: user-stated"))
        XCTAssertTrue(fm.contains("source_app: apple-notes"))
        XCTAssertTrue(fm.contains("apple_note_id: x-123"))
        XCTAssertTrue(fm.contains("title: Glints"))
        XCTAssertTrue(fm.contains("Provenance:"))
    }
}
