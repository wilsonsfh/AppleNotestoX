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
            noteID: "n1", title: "Project Journal", modified: Date(timeIntervalSince1970: 0),
            content: content, config: cfg, exported: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(r.imageCount, 2)
        XCTAssertEqual(r.assetPaths.count, 2)
        let md = try String(contentsOf: r.markdownPath, encoding: .utf8)
        let iIntro = md.range(of: "Intro")!.lowerBound
        let iImg1 = md.range(of: "project-journal-01.png")!.lowerBound
        let iMid = md.range(of: "Middle")!.lowerBound
        let iImg2 = md.range(of: "project-journal-02.png")!.lowerBound
        let iEnd = md.range(of: "End")!.lowerBound
        XCTAssertTrue(iIntro < iImg1 && iImg1 < iMid && iMid < iImg2 && iImg2 < iEnd)
        XCTAssertTrue(md.hasPrefix("---\n"))
        XCTAssertTrue(md.contains(#"apple_note_id: "n1""#))
        XCTAssertEqual(r.markdownPath.lastPathComponent, "1970-01-01-project-journal.md")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: cfg.assetsDir.appendingPathComponent("project-journal-01.png").path))
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

    func testExistingAssetCollisionPreservesOriginalAndUsesSuffix() throws {
        let attachment = try makeAttachment("new.png", bytes: Data("new".utf8))
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))
        try FileManager.default.createDirectory(at: cfg.assetsDir, withIntermediateDirectories: true)
        let existing = cfg.assetsDir.appendingPathComponent("t-01.png")
        try Data("original".utf8).write(to: existing)

        let result = try WikiExportAssembler().assemble(
            noteID: "n4",
            title: "T",
            modified: Date(timeIntervalSince1970: 0),
            content: AppleNoteContent(html: "<img>", attachments: [attachment]),
            config: cfg,
            exported: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(try Data(contentsOf: existing), Data("original".utf8))
        XCTAssertEqual(result.assetPaths.map(\.lastPathComponent), ["t-01-2.png"])
        XCTAssertEqual(try Data(contentsOf: result.assetPaths[0]), Data("new".utf8))
    }

    func testMarkdownPublicationFailureRollsBackOnlyAttemptAssets() throws {
        let attachment = try makeAttachment("new.png", bytes: Data("new".utf8))
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))
        try FileManager.default.createDirectory(at: cfg.journalDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cfg.assetsDir, withIntermediateDirectories: true)
        let retained = cfg.assetsDir.appendingPathComponent("unrelated.png")
        try Data("retained".utf8).write(to: retained)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: cfg.journalDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cfg.journalDir.path)
        }

        XCTAssertThrowsError(try WikiExportAssembler().assemble(
            noteID: "rollback",
            title: "T",
            modified: Date(timeIntervalSince1970: 0),
            content: AppleNoteContent(html: "<img>", attachments: [attachment]),
            config: cfg,
            exported: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cfg.assetsDir.path), ["unrelated.png"])
        XCTAssertEqual(try Data(contentsOf: retained), Data("retained".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.localURL.path))
    }

    func testAssemblerDoesNotCleanMarkedCallerInput() throws {
        let owned = tmp.appendingPathComponent("AppleNotestoX-owned")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try AppleNotesService.markTemporaryDirectoryOwned(owned)
        let attachmentURL = owned.appendingPathComponent("image.png")
        try Data("image".utf8).write(to: attachmentURL)

        _ = try WikiExportAssembler().assemble(
            noteID: "n5",
            title: "T",
            modified: Date(timeIntervalSince1970: 0),
            content: AppleNoteContent(
                html: "<img>",
                attachments: [AppleNoteAttachment(id: "a", filename: "image.png", localURL: attachmentURL)]
            ),
            config: WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault")),
            exported: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentURL.path))
    }

    func testCallerOwnedAttachmentDirectoryIsNotCleaned() throws {
        let attachment = try makeAttachment("caller.png")

        _ = try WikiExportAssembler().assemble(
            noteID: "n6",
            title: "T",
            modified: Date(timeIntervalSince1970: 0),
            content: AppleNoteContent(html: "<img>", attachments: [attachment]),
            config: WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault")),
            exported: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.localURL.path))
    }
}
