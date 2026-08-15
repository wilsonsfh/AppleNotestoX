import XCTest
@testable import AppleNotestoX

final class MergeAssemblerTests: XCTestCase {
    func test_titleLine_includesISODate() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 15
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(MergeAssembler.titleLine(date: date), "Merged Notes — 2026-08-15")
    }

    func test_assembleHTML_oneHeadingPerSection_noImages() {
        let sections = [
            MergeSection(header: "Work", bodyText: "Line one", sourceNoteIDs: ["A"]),
            MergeSection(header: "Health", bodyText: "Line two", sourceNoteIDs: ["B"])
        ]
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "Merged Notes — 2026-08-15",
            stagedImages: [:], embedImages: true
        )
        XCTAssertTrue(html.hasPrefix("<div>Merged Notes — 2026-08-15</div>"))
        XCTAssertTrue(html.contains("<h1>Work</h1>"))
        XCTAssertTrue(html.contains("<p>Line one</p>"))
        XCTAssertTrue(html.contains("<h1>Health</h1>"))
        XCTAssertTrue(html.contains("<p>Line two</p>"))
    }

    func test_assembleHTML_embedsImagesInline_whenEnabled() {
        let sections = [MergeSection(header: "Recipes", bodyText: "Text", sourceNoteIDs: ["A"])]
        let image = StagedImage(sourceNoteID: "A", sourceNoteTitle: "Pasta", localURL: URL(fileURLWithPath: "/tmp/run/pasta.png"))
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: ["A": [image]], embedImages: true
        )
        XCTAssertTrue(html.contains("<img src=\"file:///tmp/run/pasta.png\">"))
    }

    func test_assembleHTML_referencesImages_whenEmbedDisabled() {
        let sections = [MergeSection(header: "Recipes", bodyText: "Text", sourceNoteIDs: ["A"])]
        let image = StagedImage(sourceNoteID: "A", sourceNoteTitle: "Pasta", localURL: URL(fileURLWithPath: "/tmp/run/pasta.png"))
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: ["A": [image]], embedImages: false
        )
        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("[image from &quot;Pasta&quot; — staged at /tmp/run/pasta.png]"))
    }

    func test_assembleHTML_escapesHTMLSpecialCharsInBodyText() {
        let sections = [MergeSection(header: "H", bodyText: "5 < 10 & \"quoted\"", sourceNoteIDs: [])]
        let html = MergeAssembler.assembleHTML(sections: sections, titleLine: "T", stagedImages: [:], embedImages: true)
        XCTAssertTrue(html.contains("5 &lt; 10 &amp; &quot;quoted&quot;"))
    }
}
