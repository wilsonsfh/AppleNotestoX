import Foundation

/// A timestamped chunk of recognized speech.
struct TranscriptSegment: Sendable, Equatable {
    let start: Double   // seconds from the start of the video
    let text: String
}

/// The result of transcribing a video's audio track.
struct VideoTranscript: Sendable, Equatable {
    let segments: [TranscriptSegment]
    let engine: String
    let durationSeconds: Double

    var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }
}
