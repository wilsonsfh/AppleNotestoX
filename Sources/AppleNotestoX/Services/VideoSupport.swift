import Foundation

/// Pure helpers for video handling: format detection, audio chunking (Apple Speech
/// has a ~1-minute limit, so long audio must be split), and keyframe timestamp
/// selection. No AVFoundation here so it stays unit-testable without media.
enum VideoSupport {

    static let videoExts: Set<String> = [
        "mov", "mp4", "m4v", "qt", "avi", "mkv", "webm", "mpg", "mpeg"
    ]

    static func isVideo(ext: String) -> Bool { videoExts.contains(ext.lowercased()) }
    static func isVideo(url: URL) -> Bool { isVideo(ext: url.pathExtension) }

    /// Splits `[0, duration]` into consecutive windows each no longer than `maxChunk`.
    /// Returns `(start, length)` pairs. Empty when duration or maxChunk is non-positive.
    static func chunkRanges(duration: Double, maxChunk: Double = 55) -> [(start: Double, length: Double)] {
        guard duration > 0, maxChunk > 0 else { return [] }
        var ranges: [(start: Double, length: Double)] = []
        var start = 0.0
        while start < duration - 1e-6 {
            let length = min(maxChunk, duration - start)
            ranges.append((start, length))
            start += length
        }
        return ranges
    }

    /// `count` evenly spaced timestamps strictly inside `(0, duration)`,
    /// at `(i+1)/(count+1) * duration`. Empty when count or duration is non-positive.
    static func keyframeTimestamps(duration: Double, count: Int) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        return (0..<count).map { Double($0 + 1) / Double(count + 1) * duration }
    }
}
