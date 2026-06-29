import XCTest
@testable import AppleNotestoX

final class NoteConverterTests: XCTestCase {

    func test_paragraph() {
        let blocks = NoteConverter.convert(html: "<p>Hello world</p>", attachments: [])
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let rts) = blocks[0] {
            XCTAssertEqual(rts.count, 1)
            XCTAssertEqual(rts[0].content, "Hello world")
        } else { XCTFail("expected paragraph") }
    }

    func test_headings() {
        let blocks = NoteConverter.convert(
            html: "<h1>Title</h1><h2>Sub</h2><h3>Sub2</h3>",
            attachments: []
        )
        XCTAssertEqual(blocks.count, 3)
        guard case .heading1 = blocks[0] else { return XCTFail("h1") }
        guard case .heading2 = blocks[1] else { return XCTFail("h2") }
        guard case .heading3 = blocks[2] else { return XCTFail("h3") }
    }

    func test_bulletList() {
        let blocks = NoteConverter.convert(
            html: "<ul><li>A</li><li>B</li></ul>",
            attachments: []
        )
        XCTAssertEqual(blocks.count, 2)
        guard case .bulletedListItem(let a) = blocks[0], a.first?.content == "A" else {
            return XCTFail("a")
        }
        guard case .bulletedListItem(let b) = blocks[1], b.first?.content == "B" else {
            return XCTFail("b")
        }
    }

    func test_orderedList() {
        let blocks = NoteConverter.convert(
            html: "<ol><li>One</li><li>Two</li></ol>",
            attachments: []
        )
        XCTAssertEqual(blocks.count, 2)
        guard case .numberedListItem = blocks[0] else { return XCTFail() }
        guard case .numberedListItem = blocks[1] else { return XCTFail() }
    }

    func test_checklist_byClass() {
        let html = #"<ul class="check"><li class="checked">Done</li><li>Open</li></ul>"#
        let blocks = NoteConverter.convert(html: html, attachments: [])
        XCTAssertEqual(blocks.count, 2)
        guard case .toDo(_, let checked0) = blocks[0] else { return XCTFail() }
        XCTAssertTrue(checked0)
        guard case .toDo(_, let checked1) = blocks[1] else { return XCTFail() }
        XCTAssertFalse(checked1)
    }

    func test_checklist_byInput() {
        let html = #"<ul><li><input type="checkbox" checked> Done</li><li><input type="checkbox"> Open</li></ul>"#
        let blocks = NoteConverter.convert(html: html, attachments: [])
        XCTAssertEqual(blocks.count, 2)
        guard case .toDo(let rts0, let checked0) = blocks[0] else { return XCTFail() }
        XCTAssertTrue(checked0)
        XCTAssertTrue(rts0.map(\.content).joined().contains("Done"))
        guard case .toDo(_, let checked1) = blocks[1] else { return XCTFail() }
        XCTAssertFalse(checked1)
    }

    func test_richText_boldItalicLink() {
        let html = #"<p>plain <b>bold</b> <i>ital</i> <a href="https://x.test">link</a></p>"#
        let blocks = NoteConverter.convert(html: html, attachments: [])
        guard case .paragraph(let rts) = blocks.first else { return XCTFail() }
        XCTAssertTrue(rts.contains(where: { $0.content == "bold" && $0.bold }))
        XCTAssertTrue(rts.contains(where: { $0.content == "ital" && $0.italic }))
        XCTAssertTrue(rts.contains(where: { $0.content == "link" && $0.link?.absoluteString == "https://x.test" }))
    }

    func test_imagePosition_preserved() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fake.jpg")
        let attachments = [
            AppleNoteAttachment(id: "a1", filename: "fake.jpg", localURL: tmp)
        ]
        let html = "<p>Before</p><img src=\"x\"><p>After</p>"
        let blocks = NoteConverter.convert(html: html, attachments: attachments)
        XCTAssertEqual(blocks.count, 3)
        guard case .paragraph(let r0) = blocks[0], r0.first?.content == "Before" else { return XCTFail() }
        guard case .imagePlaceholder(_, let path) = blocks[1] else { return XCTFail("expected image at idx 1") }
        XCTAssertEqual(path, tmp)
        guard case .paragraph(let r2) = blocks[2], r2.first?.content == "After" else { return XCTFail() }
    }

    func test_multipleImages_mappedInOrder() {
        let a = AppleNoteAttachment(id: "1", filename: "a.jpg", localURL: URL(fileURLWithPath: "/tmp/a.jpg"))
        let b = AppleNoteAttachment(id: "2", filename: "b.jpg", localURL: URL(fileURLWithPath: "/tmp/b.jpg"))
        let html = "<p>A</p><img><p>B</p><img><p>C</p>"
        let blocks = NoteConverter.convert(html: html, attachments: [a, b])
        XCTAssertEqual(blocks.count, 5)
        if case .imagePlaceholder(_, let p1) = blocks[1] { XCTAssertEqual(p1, a.localURL) } else { XCTFail() }
        if case .imagePlaceholder(_, let p3) = blocks[3] { XCTAssertEqual(p3, b.localURL) } else { XCTFail() }
    }

    func test_imageWithoutAttachment_marksFailed() {
        let html = "<p>X</p><img>"
        let blocks = NoteConverter.convert(html: html, attachments: [])
        XCTAssertEqual(blocks.count, 2)
        guard case .imageFailed = blocks[1] else { return XCTFail("expected imageFailed") }
    }

    func test_divider() {
        let blocks = NoteConverter.convert(html: "<p>A</p><hr><p>B</p>", attachments: [])
        XCTAssertEqual(blocks.count, 3)
        guard case .divider = blocks[1] else { return XCTFail() }
    }

    func test_table_flatParagraphFallback() {
        let html = "<table><tr><td>x</td><td>y</td></tr><tr><td>1</td><td>2</td></tr></table>"
        let blocks = NoteConverter.convert(html: html, attachments: [])
        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(let r0) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(r0.first?.content, "x | y")
    }
}
