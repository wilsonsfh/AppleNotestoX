import XCTest
@testable import AppleNotestoX

final class TriageAssetStoreTests: XCTestCase {
    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TriageAssetStoreTests-\(UUID().uuidString)")
    }

    func test_makeRunDirectory_createsUniqueDirectoryUnderRoot() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TriageAssetStore(root: root)

        let dir1 = try await store.makeRunDirectory()
        let dir2 = try await store.makeRunDirectory()

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir2.path))
        XCTAssertNotEqual(dir1, dir2)
        XCTAssertEqual(dir1.deletingLastPathComponent().path, root.path)
    }

    func test_stage_copiesFileIntoRunDirectory() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TriageAssetStore(root: root)
        let runDir = try await store.makeRunDirectory()

        let sourceFile = root.appendingPathComponent("source.txt")
        try "hello".data(using: .utf8)!.write(to: sourceFile)

        let staged = try await store.stage(fileAt: sourceFile, filename: "staged.txt", into: runDir)

        XCTAssertEqual(staged.lastPathComponent, "staged.txt")
        XCTAssertEqual(staged.deletingLastPathComponent().path, runDir.path)
        XCTAssertEqual(try String(contentsOf: staged, encoding: .utf8), "hello")
    }

    func test_deleteRunDirectory_removesIt() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TriageAssetStore(root: root)
        let runDir = try await store.makeRunDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.path))

        await store.deleteRunDirectory(runDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: runDir.path))
    }

    func test_deleteRunDirectory_missingDirectory_doesNotThrow() async {
        let root = makeTempRoot()
        let store = TriageAssetStore(root: root)
        await store.deleteRunDirectory(root.appendingPathComponent("does-not-exist"))
        // No assertion needed — the test passes if this doesn't crash/throw.
    }
}
