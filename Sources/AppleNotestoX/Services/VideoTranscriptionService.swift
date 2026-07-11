import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Orchestrates: extract per-chunk audio → transcribe each (≤~1 min for Apple Speech)
/// → merge with running offsets; and extract evenly-spaced keyframes. Uses
/// macOS-14-safe completion-handler AVFoundation APIs wrapped in continuations.
struct VideoTranscriptionService: Sendable {
    static let temporaryDirectoryMarkerName = ".applenotestox-keyframes"
    private static let temporaryDirectoryMarkerContents = Data("video-keyframes\n".utf8)

    let transcriber: AudioTranscriber
    let maxChunk: Double

    init(transcriber: AudioTranscriber = AppleSpeechTranscriber(), maxChunk: Double = 55) {
        self.transcriber = transcriber
        self.maxChunk = maxChunk
    }

    static func markTemporaryDirectoryOwned(_ directory: URL) throws {
        try temporaryDirectoryMarkerContents.write(
            to: directory.appendingPathComponent(temporaryDirectoryMarkerName),
            options: .atomic
        )
    }

    static func cleanupTemporaryKeyframes(_ keyframes: [(t: Double, url: URL)]) {
        let fileManager = FileManager.default
        let directories = Set(keyframes.map { $0.url.deletingLastPathComponent() })
        for directory in directories {
            let marker = directory.appendingPathComponent(temporaryDirectoryMarkerName)
            guard (try? Data(contentsOf: marker)) == temporaryDirectoryMarkerContents else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    enum VideoError: LocalizedError {
        case exportUnavailable
        case exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .exportUnavailable: return "Could not create an audio export session for this video."
            case .exportFailed(let m): return "Audio export failed: \(m)"
            }
        }
    }

    func transcribe(videoURL: URL, keyframeCount: Int = 6) async throws -> (VideoTranscript, [(t: Double, url: URL)]) {
        let asset = AVURLAsset(url: videoURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))

        var segments: [TranscriptSegment] = []
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            for range in VideoSupport.chunkRanges(duration: duration, maxChunk: maxChunk) {
                let chunkURL = try await exportAudioChunk(asset: asset, start: range.start, length: range.length)
                defer { try? FileManager.default.removeItem(at: chunkURL) }
                do {
                    let text = try await transcriber.transcribe(audioFileURL: chunkURL)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        segments.append(TranscriptSegment(start: range.start, text: trimmed))
                    }
                } catch {
                    segments.append(TranscriptSegment(start: range.start,
                                                       text: "[unintelligible @\(TranscriptDocument.mmss(range.start))]"))
                }
            }
        }

        let transcript = VideoTranscript(segments: segments,
                                         engine: "apple-speech (on-device)",
                                         durationSeconds: duration)
        let keyframes = try await extractKeyframes(
            asset: asset,
            timestamps: VideoSupport.keyframeTimestamps(duration: duration, count: keyframeCount)
        )
        return (transcript, keyframes)
    }

    // MARK: - AVFoundation (completion-handler APIs, macOS 14-safe)

    private func exportAudioChunk(asset: AVURLAsset, start: Double, length: Double) async throws -> URL {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoError.exportUnavailable
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: out)
            }
        }
        export.outputURL = out
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            export.exportAsynchronously {
                switch export.status {
                case .completed: cont.resume()
                case .failed, .cancelled:
                    cont.resume(throwing: VideoError.exportFailed(export.error?.localizedDescription ?? "unknown"))
                default:
                    cont.resume(throwing: VideoError.exportFailed("unexpected status"))
                }
            }
        }
        completed = true
        return out
    }

    private func extractKeyframes(asset: AVURLAsset, timestamps: [Double]) async throws -> [(t: Double, url: URL)] {
        guard !timestamps.isEmpty else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var transferredToConsumer = false
        defer {
            if !transferredToConsumer {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        try Self.markTemporaryDirectoryOwned(dir)

        let times = timestamps.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
        let results = KeyframeResults()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let counter = Counter(total: times.count) { cont.resume() }
            generator.generateCGImagesAsynchronously(forTimes: times) { requested, image, _, result, _ in
                if let image, result == .succeeded {
                    let seconds = CMTimeGetSeconds(requested)
                    let url = dir.appendingPathComponent(String(format: "kf-%08d.png", Int(seconds * 1000)))
                    if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil)
                        if CGImageDestinationFinalize(dest) {
                            results.add(t: seconds, url: url)
                        }
                    }
                }
                counter.decrement()
            }
        }
        let sorted = results.sorted
        transferredToConsumer = !sorted.isEmpty
        return sorted
    }
}

// MARK: - Concurrency-safe collectors

private final class KeyframeResults: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(t: Double, url: URL)] = []
    func add(t: Double, url: URL) { lock.lock(); items.append((t, url)); lock.unlock() }
    var sorted: [(t: Double, url: URL)] { lock.lock(); defer { lock.unlock() }; return items.sorted { $0.t < $1.t } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n: Int
    private var fired = false
    private let onZero: () -> Void
    init(total: Int, onZero: @escaping () -> Void) {
        self.n = total
        self.onZero = onZero
        if total <= 0 { fired = true; onZero() }
    }
    func decrement() {
        lock.lock()
        n -= 1
        let fire = n <= 0 && !fired
        if fire { fired = true }
        lock.unlock()
        if fire { onZero() }
    }
}
