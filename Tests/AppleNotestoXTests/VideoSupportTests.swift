import XCTest
@testable import AppleNotestoX

final class VideoSupportTests: XCTestCase {
    private func assertRanges(_ got: [(start: Double, length: Double)], _ want: [(Double, Double)],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "count", file: file, line: line)
        for (g, w) in zip(got, want) {
            XCTAssertEqual(g.start, w.0, accuracy: 1e-6, file: file, line: line)
            XCTAssertEqual(g.length, w.1, accuracy: 1e-6, file: file, line: line)
        }
    }

    func testChunkRanges() {
        assertRanges(VideoSupport.chunkRanges(duration: 130, maxChunk: 55), [(0, 55), (55, 55), (110, 20)])
        assertRanges(VideoSupport.chunkRanges(duration: 110, maxChunk: 55), [(0, 55), (55, 55)])
        assertRanges(VideoSupport.chunkRanges(duration: 30, maxChunk: 55), [(0, 30)])
        XCTAssertTrue(VideoSupport.chunkRanges(duration: 0, maxChunk: 55).isEmpty)
        XCTAssertTrue(VideoSupport.chunkRanges(duration: 60, maxChunk: 0).isEmpty)
    }

    func testKeyframeTimestamps() {
        XCTAssertEqual(VideoSupport.keyframeTimestamps(duration: 100, count: 3), [25, 50, 75])
        XCTAssertTrue(VideoSupport.keyframeTimestamps(duration: 100, count: 0).isEmpty)
        XCTAssertTrue(VideoSupport.keyframeTimestamps(duration: 0, count: 3).isEmpty)
    }

    func testIsVideo() {
        XCTAssertTrue(VideoSupport.isVideo(ext: "MOV"))
        XCTAssertTrue(VideoSupport.isVideo(ext: "mp4"))
        XCTAssertFalse(VideoSupport.isVideo(ext: "png"))
        XCTAssertTrue(VideoSupport.isVideo(url: URL(fileURLWithPath: "/x/a.MP4")))
        XCTAssertFalse(VideoSupport.isVideo(url: URL(fileURLWithPath: "/x/a.pdf")))
    }
}
