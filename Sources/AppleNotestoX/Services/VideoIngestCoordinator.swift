import Foundation

/// Runs `VideoTranscriptionService` for one video and writes a self-contained
/// transcript note (+ keyframes + a copy of the source video) into the wiki vault,
/// reusing P1's naming/vault conventions.
actor VideoIngestCoordinator {
    private let service: VideoTranscriptionService

    init(service: VideoTranscriptionService = VideoTranscriptionService()) {
        self.service = service
    }

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg"]

    func ingest(
        videoURL: URL,
        title: String?,
        modified: Date,
        config: WikiVaultConfig,
        sourceApp: String,
        keyframeCount: Int = 6
    ) async throws -> WikiExportResult {
        let fm = FileManager.default
        try fm.createDirectory(at: config.journalDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: config.assetsDir, withIntermediateDirectories: true)

        let effectiveTitle = title ?? videoURL.deletingPathExtension().lastPathComponent
        let slug = WikiNaming.slug(from: effectiveTitle)

        let (transcript, keyframes) = try await service.transcribe(videoURL: videoURL, keyframeCount: keyframeCount)

        var usedNames = Set<String>()
        var assetPaths: [URL] = []
        var keyframePairs: [(t: Double, filename: String)] = []
        var warnings: [String] = []

        // Keyframes.
        for (index, frame) in keyframes.enumerated() {
            var name = WikiNaming.assetFilename(slug: "\(slug)-kf", index: index + 1, ext: "png")
            name = WikiNaming.uniqueName(name, existing: usedNames)
            usedNames.insert(name)
            let dest = config.assetsDir.appendingPathComponent(name)
            do {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: frame.url, to: dest)
                assetPaths.append(dest)
                keyframePairs.append((frame.t, name))
            } catch {
                warnings.append("failed to copy keyframe: \(error.localizedDescription)")
            }
        }

        // A copy of the source video, so the note is self-contained.
        let videoExt = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        var videoName = WikiNaming.assetFilename(slug: "\(slug)-video", index: 1, ext: videoExt)
        videoName = WikiNaming.uniqueName(videoName, existing: usedNames)
        usedNames.insert(videoName)
        let videoDest = config.assetsDir.appendingPathComponent(videoName)
        do {
            if fm.fileExists(atPath: videoDest.path) { try fm.removeItem(at: videoDest) }
            try fm.copyItem(at: videoURL, to: videoDest)
            assetPaths.append(videoDest)
        } catch {
            warnings.append("failed to copy source video: \(error.localizedDescription)")
        }

        // Markdown note.
        let body = TranscriptDocument.markdown(
            transcript: transcript,
            keyframes: keyframePairs,
            title: effectiveTitle,
            sourceName: videoURL.lastPathComponent,
            sourceApp: sourceApp,
            modified: modified,
            exported: Date()
        )
        let existing = Set((try? fm.contentsOfDirectory(atPath: config.journalDir.path)) ?? [])
        let mdName = WikiNaming.uniqueName(
            "\(WikiNaming.isoDay(modified))-\(slug)-transcript.md",
            existing: existing
        )
        let mdURL = config.journalDir.appendingPathComponent(mdName)
        try body.write(to: mdURL, atomically: true, encoding: .utf8)

        let imageCount = assetPaths.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }.count
        return WikiExportResult(markdownPath: mdURL, assetPaths: assetPaths, imageCount: imageCount, warnings: warnings)
    }
}
