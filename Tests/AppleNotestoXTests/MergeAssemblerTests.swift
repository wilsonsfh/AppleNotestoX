import XCTest
@testable import AppleNotestoX

final class MergeAssemblerTests: XCTestCase {
    func test_titleLine_includesISODate() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 15
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(MergeAssembler.titleLine(date: date), "Merged Notes — 2026-08-15")
    }

    func test_assembleHTML_oneHeadingPerSection_bulletedBody() {
        let sections = [
            MergeSection(header: "Work", bodyText: "Line one\nLine two", sourceNoteIDs: ["A"]),
            MergeSection(header: "Health", bodyText: "Line three", sourceNoteIDs: ["B"])
        ]
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "Merged Notes — 2026-08-15",
            sourceNoteTitles: ["A": "Note A", "B": "Note B"]
        )
        XCTAssertTrue(html.hasPrefix("<div>Merged Notes — 2026-08-15</div>"))
        XCTAssertTrue(html.contains("<h1>Work</h1>"))
        XCTAssertTrue(html.contains("<ul><li>Line one</li><li>Line two</li></ul>"))
        XCTAssertTrue(html.contains("<h1>Health</h1>"))
        XCTAssertTrue(html.contains("<ul><li>Line three</li></ul>"))
    }

    func test_assembleHTML_stripsLeadingBulletMarkers() {
        let sections = [MergeSection(header: "H", bodyText: "- Point one\n* Point two\n• Point three", sourceNoteIDs: [])]
        let html = MergeAssembler.assembleHTML(sections: sections, titleLine: "T", sourceNoteTitles: [:])
        XCTAssertTrue(html.contains("<ul><li>Point one</li><li>Point two</li><li>Point three</li></ul>"))
    }

    func test_assembleHTML_fallsBackToSingleBullet_whenBodyIsOneLine() {
        let sections = [MergeSection(header: "H", bodyText: "Just one line", sourceNoteIDs: [])]
        let html = MergeAssembler.assembleHTML(sections: sections, titleLine: "T", sourceNoteTitles: [:])
        XCTAssertTrue(html.contains("<ul><li>Just one line</li></ul>"))
    }

    func test_assembleHTML_listsSourceNoteTitles() {
        let sections = [MergeSection(header: "Recipes", bodyText: "Text", sourceNoteIDs: ["A", "B"])]
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T",
            sourceNoteTitles: ["A": "Pasta night", "B": "Soup ideas"]
        )
        XCTAssertTrue(html.contains("<p><em>Sources: Pasta night, Soup ideas</em></p>"))
    }

    func test_assembleHTML_omitsSourcesLine_whenNoTitlesKnown() {
        let sections = [MergeSection(header: "Recipes", bodyText: "Text", sourceNoteIDs: ["missing"])]
        let html = MergeAssembler.assembleHTML(sections: sections, titleLine: "T", sourceNoteTitles: [:])
        XCTAssertFalse(html.contains("Sources:"))
    }

    func test_assembleHTML_escapesHTMLSpecialCharsInBodyTextAndTitles() {
        let sections = [MergeSection(header: "H", bodyText: "5 < 10 & \"quoted\"", sourceNoteIDs: ["A"])]
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", sourceNoteTitles: ["A": "Tom & Jerry"]
        )
        XCTAssertTrue(html.contains("5 &lt; 10 &amp; &quot;quoted&quot;"))
        XCTAssertTrue(html.contains("Tom &amp; Jerry"))
    }
}
