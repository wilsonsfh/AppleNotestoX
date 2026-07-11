import Foundation

/// Turns a fetched Apple Note (HTML + ordered attachments) into a provenance-stamped
/// markdown file plus local image assets inside the wiki vault.
///
/// This is the testable core of the wiki export: it performs filesystem writes but
/// takes its input as plain data, so it can be exercised against a temp vault without
/// Apple Notes access. `WikiExportCoordinator` wraps it with the live Notes reader.
struct WikiExportAssembler: Sendable {
    private var fileManager: FileManager { .default }

    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"
    ]

    func assemble(
        noteID: String,
        title: String,
        modified: Date,
        content: AppleNoteContent,
        config: WikiVaultConfig,
        exported: Date = Date()
    ) throws -> WikiExportResult {
        try fileManager.createDirectory(at: config.journalDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: config.assetsDir, withIntermediateDirectories: true)

        let slug = WikiNaming.slug(from: title)
        let blocks = NoteConverter.convert(html: content.html, attachments: content.attachments)

        var warnings: [String] = []
        var assetPaths: [URL] = []
        var createdAssets: [WikiNaming.CreatedFile] = []
        var committed = false
        defer {
            if !committed {
                for output in createdAssets { WikiNaming.removeIfIdentityMatches(output) }
            }
        }
        var inlineByID: [UUID: String] = [:]
        var matchedLocalPaths = Set<URL>()
        var assetIndex = 0

        // 1. Place each image where its placeholder appears (document order).
        for block in blocks {
            guard case .imagePlaceholder(let id, let localPath) = block else { continue }
            guard let attachment = content.attachments.first(where: { $0.localURL == localPath }) else {
                warnings.append("placeholder had no matching attachment on disk")
                continue
            }
            assetIndex += 1
            if let saved = copyAsset(
                attachment: attachment,
                slug: slug,
                index: assetIndex,
                config: config,
                warnings: &warnings
            ) {
                assetPaths.append(saved.url)
                createdAssets.append(saved.createdFile)
                matchedLocalPaths.insert(attachment.localURL)
                inlineByID[id] = inlineMarkdown(for: attachment, savedName: saved.name, config: config)
            }
        }

        // 2. Render the body.
        let rendered = MarkdownRenderer.render(blocks, inlineAsset: { inlineByID[$0] })
        warnings.append(contentsOf: rendered.warnings)

        // 3. Copy + list any attachments never referenced inline.
        var unplacedLines: [String] = []
        for attachment in content.attachments where !matchedLocalPaths.contains(attachment.localURL) {
            assetIndex += 1
            if let saved = copyAsset(
                attachment: attachment,
                slug: slug,
                index: assetIndex,
                config: config,
                warnings: &warnings
            ) {
                assetPaths.append(saved.url)
                createdAssets.append(saved.createdFile)
                unplacedLines.append("- " + inlineMarkdown(for: attachment, savedName: saved.name, config: config))
            }
        }
        if !unplacedLines.isEmpty {
            warnings.append("\(unplacedLines.count) attachment(s) not referenced inline → appended to Unplaced section")
        }

        // 4. Assemble the file: frontmatter + body + optional unplaced section.
        let frontmatter = WikiNaming.frontmatter(noteID: noteID, title: title, modified: modified, exported: exported)
        var body = frontmatter + rendered.markdown
        if !unplacedLines.isEmpty {
            body += "\n## Unplaced attachments\n\n" + unplacedLines.joined(separator: "\n") + "\n"
        }

        // 5. Publish without replacing any entry created before or during this attempt.
        let markdownFile = try WikiNaming.publishTracked(
            data: Data(body.utf8),
            preferredName: WikiNaming.markdownFilename(date: modified, slug: slug),
            in: config.journalDir
        )
        committed = true

        let imageCount = assetPaths.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }.count
        return WikiExportResult(
            markdownPath: markdownFile.url,
            assetPaths: assetPaths,
            imageCount: imageCount,
            warnings: warnings
        )
    }

    // MARK: - Helpers

    private func copyAsset(
        attachment: AppleNoteAttachment,
        slug: String,
        index: Int,
        config: WikiVaultConfig,
        warnings: inout [String]
    ) -> (name: String, url: URL, createdFile: WikiNaming.CreatedFile)? {
        let ext = attachment.localURL.pathExtension
        let preferredName = WikiNaming.assetFilename(slug: slug, index: index, ext: ext)
        do {
            let createdFile = try WikiNaming.copyTracked(
                source: attachment.localURL,
                preferredName: preferredName,
                to: config.assetsDir
            )
            return (createdFile.url.lastPathComponent, createdFile.url, createdFile)
        } catch {
            warnings.append("failed to copy asset \(attachment.filename): \(error.localizedDescription)")
            return nil
        }
    }

    private func inlineMarkdown(for attachment: AppleNoteAttachment, savedName: String, config: WikiVaultConfig) -> String {
        let ext = URL(fileURLWithPath: savedName).pathExtension.lowercased()
        if Self.imageExts.contains(ext) {
            return "![[\(savedName)]]"
        }
        return "[\(attachment.filename)](\(config.assetsSubpath)/\(savedName))"
    }
}
