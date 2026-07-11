import XCTest
@testable import AppleNotestoX

final class TemporaryFileCleanupTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func serviceSource(_ filename: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/AppleNotestoX/Services/\(filename)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testAppleNotesCleanupRemovesOnlyMarkedDirectories() throws {
        let owned = tmp.appendingPathComponent("owned")
        let callerOwned = tmp.appendingPathComponent("caller")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: callerOwned, withIntermediateDirectories: true)
        try AppleNotesService.markTemporaryDirectoryOwned(owned)
        let ownedFile = owned.appendingPathComponent("one.png")
        let callerFile = callerOwned.appendingPathComponent("two.png")
        try Data().write(to: ownedFile)
        try Data().write(to: callerFile)
        let content = AppleNoteContent(html: "", attachments: [
            AppleNoteAttachment(id: "1", filename: "one.png", localURL: ownedFile),
            AppleNoteAttachment(id: "2", filename: "two.png", localURL: callerFile)
        ])

        AppleNotesService.cleanupTemporaryAttachments(in: content)

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: callerFile.path))
    }

    func testAppleNotesEmptyContentDoesNotTransferTemporaryDirectoryOwnership() {
        XCTAssertFalse(AppleNotesService.hasTemporaryAttachments(
            AppleNoteContent(html: "text", attachments: [])
        ))
    }

    func testVideoCleanupRemovesOnlyMarkedKeyframeDirectories() throws {
        let owned = tmp.appendingPathComponent("owned-keyframes")
        let callerOwned = tmp.appendingPathComponent("caller-keyframes")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: callerOwned, withIntermediateDirectories: true)
        try VideoTranscriptionService.markTemporaryDirectoryOwned(owned)
        let ownedFrame = owned.appendingPathComponent("one.png")
        let callerFrame = callerOwned.appendingPathComponent("two.png")
        try Data().write(to: ownedFrame)
        try Data().write(to: callerFrame)

        VideoTranscriptionService.cleanupTemporaryKeyframes([
            (t: 0, url: ownedFrame),
            (t: 1, url: callerFrame)
        ])

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: callerFrame.path))
    }

    func testCleanupOwnershipLivesInConsumersNotAssembler() throws {
        let cleanup = "defer { AppleNotesService.cleanupTemporaryAttachments(in: content) }"
        let fetchThenCleanup = "        let content = try await notes.fetchNote(id: noteID)\n        \(cleanup)"

        XCTAssertFalse(try serviceSource("WikiExportAssembler.swift").contains(cleanup))
        XCTAssertTrue(try serviceSource("WikiExportCoordinator.swift").contains(fetchThenCleanup))
        XCTAssertTrue(try serviceSource("ArchiveCoordinator.swift").contains(fetchThenCleanup))
    }

    func testExportersUseExclusivePublicationAndRollbackContracts() throws {
        for filename in ["WikiExportAssembler.swift", "VideoIngestCoordinator.swift"] {
            let source = try serviceSource(filename)
            XCTAssertTrue(source.contains("var committed = false"), filename)
            XCTAssertTrue(source.contains("if !committed"), filename)
            XCTAssertTrue(source.contains("committed = true"), filename)
            XCTAssertTrue(source.contains("try WikiNaming.publishTracked("), filename)
            XCTAssertTrue(source.contains("try WikiNaming.copyTracked("), filename)
            XCTAssertTrue(source.contains("WikiNaming.removeIfIdentityMatches(output)"), filename)
        }
    }
}
