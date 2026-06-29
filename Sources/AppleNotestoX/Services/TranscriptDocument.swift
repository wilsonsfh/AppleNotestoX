import Foundation

/// Pure formatter: turns a `VideoTranscript` + keyframes into a provenance-stamped
/// markdown note, with keyframes embedded inline at their timestamps for multi-modal
/// review. No I/O.
enum TranscriptDocument {

    /// - Parameter keyframes: `(t, filename)` pairs; emitted inline just before the
    ///   first transcript segment whose start time reaches `t`.
    static func markdown(
        transcript: VideoTranscript,
        keyframes: [(t: Double, filename: String)],
        title: String,
        sourceName: String,
        sourceApp: String,
        modified: Date,
        exported: Date
    ) -> String {
        let frontmatter = """
        ---
        origin: transcribed
        source_type: video-transcript
        source_app: \(sourceApp)
        engine: \(transcript.engine)
        source_video: \(sourceName)
        duration_seconds: \(Int(transcript.durationSeconds.rounded()))
        title: \(title)
        note_modified: \(WikiNaming.isoDay(modified))
        exported: \(WikiNaming.isoDay(exported))
        ---
        > Provenance: MACHINE-TRANSCRIBED (\(transcript.engine)). May contain errors.
        > Treat as lower-confidence; synthesize into wiki/, don't edit here.


        """

        var lines: [String] = ["## Transcript", ""]
        let sortedKeyframes = keyframes.sorted { $0.t < $1.t }
        var kfIndex = 0

        func flushKeyframes(upTo time: Double) {
            while kfIndex < sortedKeyframes.count && sortedKeyframes[kfIndex].t <= time {
                lines.append("![[\(sortedKeyframes[kfIndex].filename)]]")
                lines.append("")
                kfIndex += 1
            }
        }

        if transcript.segments.isEmpty {
            lines.append("_(no speech recognized)_")
        }
        for segment in transcript.segments {
            flushKeyframes(upTo: segment.start)
            lines.append("**[\(mmss(segment.start))]** \(segment.text)")
        }
        // Any keyframes beyond the last segment.
        while kfIndex < sortedKeyframes.count {
            lines.append("![[\(sortedKeyframes[kfIndex].filename)]]")
            lines.append("")
            kfIndex += 1
        }

        return frontmatter + lines.joined(separator: "\n") + "\n"
    }

    /// `M:SS` (e.g. 65 → "1:05").
    static func mmss(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
