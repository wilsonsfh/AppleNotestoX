import XCTest
@testable import AppleNotestoX

final class WikiExportAssemblerTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeAttachment(_ name: String, bytes: Data = Data([0, 1, 2])) throws -> AppleNoteAttachment {
        let dir = tmp.appendingPathComponent("att-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try bytes.write(to: url)
        return AppleNoteAttachment(id: UUID().uuidString, filename: name, localURL: url)
    }

    func testInterleavedTextAndImagesPreservesOrder() throws {
        let a1 = try makeAttachment("shot1.png")
        let a2 = try makeAttachment("shot2.png")
        let html = "<div>Intro</div><img><div>Middle</div><img><div>End</div>"
        let content = AppleNoteContent(html: html, attachments: [a1, a2])
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))

        let r = try WikiExportAssembler().assemble(
            noteID: "n1", title: "Glints Journal", modified: Date(timeIntervalSince1970: 0),
            content: content, config: cfg, exported: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(r.imageCount, 2)
        XCTAssertEqual(r.assetPaths.count, 2)
        let md = try String(contentsOf: r.markdownPath, encoding: .utf8)
        let iIntro = md.range(of: "Intro")!.lowerBound
        let iImg1 = md.range(of: "glints-journal-01.png")!.lowerBound
        let iMid = md.range(of: "Middle")!.lowerBound
        let iImg2 = md.range(of: "glints-journal-02.png")!.lowerBound
        let iEnd = md.range(of: "End")!.lowerBound
        XCTAssertTrue(iIntro < iImg1 && iImg1 < iMid && iMid < iImg2 && iImg2 < iEnd)
        XCTAssertTrue(md.hasPrefix("---\n"))
        XCTAssertTrue(md.contains("apple_note_id: n1"))
        XCTAssertEqual(r.markdownPath.lastPathComponent, "1970-01-01-glints-journal.md")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: cfg.assetsDir.appendingPathComponent("glints-journal-01.png").path))
    }

    func testMoreAttachmentsThanImagesGoUnplaced() throws {
        let a1 = try makeAttachment("a.png")
        let a2 = try makeAttachment("b.pdf")     // non-image, no <img> for it
        let html = "<div>Only one image</div><img>"
        let content = AppleNoteContent(html: html, attachments: [a1, a2])
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))

        let r = try WikiExportAssembler().assemble(
            noteID: "n2", title: "T", modified: Date(timeIntervalSince1970: 0),
            content: content, config: cfg, exported: Date(timeIntervalSince1970: 0))

        let md = try String(contentsOf: r.markdownPath, encoding: .utf8)
        XCTAssertTrue(md.contains("## Unplaced attachments"))
        XCTAssertTrue(md.contains("b.pdf"))
        XCTAssertFalse(r.warnings.isEmpty)
        XCTAssertEqual(r.imageCount, 1)
    }

    func testFilenameCollisionSuffixes() throws {
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))
        try FileManager.default.createDirectory(at: cfg.journalDir, withIntermediateDirectories: true)
        try "x".write(to: cfg.journalDir.appendingPathComponent("1970-01-01-t.md"),
                      atomically: true, encoding: .utf8)
        let content = AppleNoteContent(html: "<div>hi</div>", attachments: [])

        let r = try WikiExportAssembler().assemble(
            noteID: "n3", title: "T", modified: Date(timeIntervalSince1970: 0),
            content: content, config: cfg, exported: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(r.markdownPath.lastPathComponent, "1970-01-01-t-2.md")
    }
}
