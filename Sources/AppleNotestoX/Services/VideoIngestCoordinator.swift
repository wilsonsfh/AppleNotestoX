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
        defer { VideoTranscriptionService.cleanupTemporaryKeyframes(keyframes) }

        var assetPaths: [URL] = []
        var createdAssets: [WikiNaming.CreatedFile] = []
        var committed = false
        defer {
            if !committed {
                for output in createdAssets { WikiNaming.removeIfIdentityMatches(output) }
            }
        }
        var keyframePairs: [(t: Double, filename: String)] = []
        var warnings: [String] = []

        // Keyframes.
        for (index, frame) in keyframes.enumerated() {
            let preferredName = WikiNaming.assetFilename(slug: "\(slug)-kf", index: index + 1, ext: "png")
            do {
                let createdFile = try WikiNaming.copyTracked(
                    source: frame.url,
                    preferredName: preferredName,
                    to: config.assetsDir
                )
                assetPaths.append(createdFile.url)
                createdAssets.append(createdFile)
                keyframePairs.append((frame.t, createdFile.url.lastPathComponent))
            } catch {
                warnings.append("failed to copy keyframe: \(error.localizedDescription)")
            }
        }

        // A copy of the source video, so the note is self-contained.
        let videoExt = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        let preferredVideoName = WikiNaming.assetFilename(slug: "\(slug)-video", index: 1, ext: videoExt)
        do {
            let createdFile = try WikiNaming.copyTracked(
                source: videoURL,
                preferredName: preferredVideoName,
                to: config.assetsDir
            )
            assetPaths.append(createdFile.url)
            createdAssets.append(createdFile)
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
        let markdownFile = try WikiNaming.publishTracked(
            data: Data(body.utf8),
            preferredName: "\(WikiNaming.isoDay(modified))-\(slug)-transcript.md",
            in: config.journalDir
        )
        committed = true

        let imageCount = assetPaths.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }.count
        return WikiExportResult(markdownPath: markdownFile.url, assetPaths: assetPaths, imageCount: imageCount, warnings: warnings)
    }
}
