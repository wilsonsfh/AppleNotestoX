import XCTest
@testable import AppleNotestoX

final class MarkdownRendererTests: XCTestCase {
    private func rt(_ s: String, bold: Bool = false, italic: Bool = false,
                    code: Bool = false, link: URL? = nil) -> NotionRichText {
        NotionRichText(content: s, bold: bold, italic: italic, strikethrough: false,
                       underline: false, code: code, link: link)
    }

    func testHeadingAndParagraphAreBlankLineSeparated() {
        let out = MarkdownRenderer.render([
            .heading1([rt("Title")]),
            .paragraph([rt("Hello "), rt("world", bold: true)])
        ], inlineAsset: { _ in nil })
        XCTAssertEqual(out.markdown, "# Title\n\nHello **world**\n")
    }

    func testListsStayTightOtherBlocksSpaced() {
        let out = MarkdownRenderer.render([
            .bulletedListItem([rt("a")]), .numberedListItem([rt("b")]),
            .toDo([rt("c")], checked: false), .toDo([rt("d")], checked: true),
            .quote([rt("q")]), .code([rt("x=1")], language: "swift"), .divider
        ], inlineAsset: { _ in nil })
        XCTAssertEqual(out.markdown,
            "- a\n1. b\n- [ ] c\n- [x] d\n\n> q\n\n```swift\nx=1\n```\n\n---\n")
    }

    func testRichTextStylesAndLink() {
        let out = MarkdownRenderer.render([
            .paragraph([rt("i", italic: true), rt(" "), rt("c", code: true), rt(" "),
                        rt("link", link: URL(string: "https://x.test")!)])
        ], inlineAsset: { _ in nil })
        XCTAssertEqual(out.markdown, "*i* `c` [link](https://x.test)\n")
    }

    func testImagePlaceholderEmbedAndMissing() {
        let id = UUID()
        let ok = MarkdownRenderer.render(
            [.imagePlaceholder(id: id, localPath: URL(fileURLWithPath: "/tmp/x"))],
            inlineAsset: { $0 == id ? "![[glints-01.png]]" : nil })
        XCTAssertEqual(ok.markdown, "![[glints-01.png]]\n")
        XCTAssertTrue(ok.warnings.isEmpty)

        let missing = MarkdownRenderer.render(
            [.imagePlaceholder(id: UUID(), localPath: URL(fileURLWithPath: "/tmp/x"))],
            inlineAsset: { _ in nil })
        XCTAssertTrue(missing.markdown.contains("> [!warning]"))
        XCTAssertEqual(missing.warnings.count, 1)
    }

    func testImageFailedBlockWarns() {
        let out = MarkdownRenderer.render([.imageFailed(message: "no matching attachment")],
                                          inlineAsset: { _ in nil })
        XCTAssertTrue(out.markdown.contains("> [!warning]"))
        XCTAssertEqual(out.warnings.count, 1)
    }
}
