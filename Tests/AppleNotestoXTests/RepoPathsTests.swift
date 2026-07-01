import XCTest
@testable import AppleNotestoX

final class RepoPathsTests: XCTestCase {
    func testFirstExistingPicksFirstPresentPath() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let real = tmp.appendingPathComponent("node")
        FileManager.default.createFile(atPath: real.path, contents: Data("x".utf8))
        let got = RepoPaths.firstExisting(["/no/such/node", real.path, "/also/missing"])
        XCTAssertEqual(got?.path, real.path)
    }

    func testFirstExistingReturnsNilWhenNoneExist() {
        XCTAssertNil(RepoPaths.firstExisting(["/no/such/a", "/no/such/b"]))
    }

    func testReviewPathsShareReviewDir() {
        XCTAssertEqual(RepoPaths.generateScript().deletingLastPathComponent(), RepoPaths.reviewDir())
        XCTAssertEqual(RepoPaths.indexHTML().lastPathComponent, "index.html")
        XCTAssertEqual(RepoPaths.studyDataJS().lastPathComponent, "study-data.js")
    }
}
