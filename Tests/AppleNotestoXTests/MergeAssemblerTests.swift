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

    func test_assembleHTML_escapesStagedPath() {
        let sections = [MergeSection(header: "H", bodyText: "T", sourceNoteIDs: ["A"])]
        let image = StagedImage(
            sourceNoteID: "A", sourceNoteTitle: "N",
            localURL: URL(fileURLWithPath: "/tmp/run/a<b>&\"c\".png")
        )
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: ["A": [image]], embedImages: false
        )
        XCTAssertTrue(html.contains("staged at /tmp/run/a&lt;b&gt;&amp;&quot;c&quot;.png]"))
        XCTAssertFalse(html.contains("<b>"))
    }

    func test_assembleHTML_appendsRunDirectoryPointer_whenEmbedDisabled() {
        let sections = [MergeSection(header: "H", bodyText: "T", sourceNoteIDs: ["A"])]
        let image = StagedImage(
            sourceNoteID: "A", sourceNoteTitle: "N",
            localURL: URL(fileURLWithPath: "/tmp/run/a.png")
        )
        let runDir = URL(fileURLWithPath: "/tmp/run", isDirectory: true)

        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: ["A": [image]],
            embedImages: false, runDirectory: runDir
        )
        XCTAssertTrue(html.hasSuffix("<p>Images for this merge are staged at /tmp/run</p>"))

        // Not appended when there is nothing staged.
        let empty = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: [:],
            embedImages: false, runDirectory: runDir
        )
        XCTAssertFalse(empty.contains("Images for this merge are staged at"))

        // Not appended when images are embedded inline.
        let embedded = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: ["A": [image]],
            embedImages: true, runDirectory: runDir
        )
        XCTAssertFalse(embedded.contains("Images for this merge are staged at"))
    }

    func test_assembleHTML_escapesHTMLSpecialCharsInBodyText() {
        let sections = [MergeSection(header: "H", bodyText: "5 < 10 & \"quoted\"", sourceNoteIDs: [])]
        let html = MergeAssembler.assembleHTML(sections: sections, titleLine: "T", stagedImages: [:], embedImages: true)
        XCTAssertTrue(html.contains("5 &lt; 10 &amp; &quot;quoted&quot;"))
    }
}
