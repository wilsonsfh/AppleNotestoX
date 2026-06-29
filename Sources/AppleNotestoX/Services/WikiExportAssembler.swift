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
        var inlineByID: [UUID: String] = [:]
        var usedAssetNames = Set<String>()
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
                usedNames: &usedAssetNames,
                warnings: &warnings
            ) {
                assetPaths.append(saved.url)
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
                usedNames: &usedAssetNames,
                warnings: &warnings
            ) {
                assetPaths.append(saved.url)
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

        // 5. Write, collision-safe, into raw/journal/.
        let existing = Set((try? fileManager.contentsOfDirectory(atPath: config.journalDir.path)) ?? [])
        let mdName = WikiNaming.uniqueName(
            WikiNaming.markdownFilename(date: modified, slug: slug),
            existing: existing
        )
        let mdURL = config.journalDir.appendingPathComponent(mdName)
        try body.write(to: mdURL, atomically: true, encoding: .utf8)

        let imageCount = assetPaths.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }.count
        return WikiExportResult(
            markdownPath: mdURL,
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
        usedNames: inout Set<String>,
        warnings: inout [String]
    ) -> (name: String, url: URL)? {
        let ext = attachment.localURL.pathExtension
        var name = WikiNaming.assetFilename(slug: slug, index: index, ext: ext)
        name = WikiNaming.uniqueName(name, existing: usedNames)
        usedNames.insert(name)
        let dest = config.assetsDir.appendingPathComponent(name)
        do {
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: attachment.localURL, to: dest)
            return (name, dest)
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
