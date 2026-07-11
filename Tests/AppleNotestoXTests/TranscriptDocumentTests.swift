import XCTest
@testable import AppleNotestoX

final class TranscriptDocumentTests: XCTestCase {
    func testMMSS() {
        XCTAssertEqual(TranscriptDocument.mmss(65), "1:05")
        XCTAssertEqual(TranscriptDocument.mmss(0), "0:00")
        XCTAssertEqual(TranscriptDocument.mmss(3661), "61:01")
    }

    func testMarkdownFrontmatterAndInterleave() {
        let transcript = VideoTranscript(segments: [
            TranscriptSegment(start: 0, text: "Hello there."),
            TranscriptSegment(start: 60, text: "Second chunk.")
        ], engine: "apple-speech (on-device)", durationSeconds: 120)

        let md = TranscriptDocument.markdown(
            transcript: transcript,
            keyframes: [(t: 0, filename: "vid-kf-01.png"), (t: 60, filename: "vid-kf-02.png")],
            title: "Standup", sourceName: "standup.mov", sourceApp: "imported-file",
            modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(md.hasPrefix("---\n"))
        XCTAssertTrue(md.contains(#"origin: "transcribed""#))
        XCTAssertTrue(md.contains(#"source_type: "video-transcript""#))
        XCTAssertTrue(md.contains(#"engine: "apple-speech (on-device)""#))
        XCTAssertTrue(md.contains("MACHINE-TRANSCRIBED"))
        XCTAssertTrue(md.contains("**[0:00]** Hello there."))
        XCTAssertTrue(md.contains("**[1:00]** Second chunk."))

        let kf1 = md.range(of: "vid-kf-01.png")!.lowerBound
        let seg1 = md.range(of: "Hello there.")!.lowerBound
        XCTAssertTrue(kf1 < seg1, "keyframe@0 should precede first segment")
        let kf2 = md.range(of: "vid-kf-02.png")!.lowerBound
        let seg2 = md.range(of: "Second chunk.")!.lowerBound
        XCTAssertTrue(kf2 < seg2, "keyframe@60 should precede second segment")
    }

    func testMarkdownQuotesUnsafeFrontmatterStrings() {
        let md = TranscriptDocument.markdown(
            transcript: VideoTranscript(
                segments: [],
                engine: "engine: local\nnext",
                durationSeconds: 1
            ),
            keyframes: [],
            title: "Title: \"unsafe\"",
            sourceName: "video: one.mov",
            sourceApp: "yes",
            modified: Date(timeIntervalSince1970: 0),
            exported: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(md.contains(#"source_app: "yes""#))
        XCTAssertTrue(md.contains(#"engine: "engine: local\nnext""#))
        XCTAssertTrue(md.contains(#"source_video: "video: one.mov""#))
        XCTAssertTrue(md.contains(#"title: "Title: \"unsafe\"""#))
    }

    func testEmptyTranscriptStillProducesNote() {
        let md = TranscriptDocument.markdown(
            transcript: VideoTranscript(segments: [], engine: "e", durationSeconds: 5),
            keyframes: [], title: "T", sourceName: "x.mov", sourceApp: "imported-file",
            modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(md.contains("(no speech recognized)"))
    }
}
