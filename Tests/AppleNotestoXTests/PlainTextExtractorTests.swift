import XCTest
@testable import AppleNotestoX

final class PlainTextExtractorTests: XCTestCase {
    func test_stripsTagsAndPreservesWords() {
        let html = "<div><h1>Title</h1><p>Hello <b>world</b>.</p></div>"
        let text = PlainTextExtractor.extract(html: html)
        XCTAssertEqual(text, "Title\nHello world.")
    }

    func test_listItemsOnOwnLines() {
        let html = "<ul><li>One</li><li>Two</li></ul>"
        let text = PlainTextExtractor.extract(html: html)
        XCTAssertEqual(text, "One\nTwo")
    }

    func test_malformedHTML_returnsEmptyStringNotThrow() {
        let text = PlainTextExtractor.extract(html: "<div><p>unterminated")
        XCTAssertEqual(text, "unterminated")
    }

    func test_emptyInput_returnsEmptyString() {
        XCTAssertEqual(PlainTextExtractor.extract(html: ""), "")
    }
}
