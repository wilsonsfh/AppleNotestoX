import Foundation

/// Finds and removes duplicate exports in a Personal Wiki vault — notes
/// that ended up with more than one file in `raw/journal/`, typically
/// leftovers from before `WikiExportCoordinator` started deduping re-runs.
/// Deletions go to the Trash (never a permanent `removeItem`), since this
/// is a user-triggered destructive action on real exported content.
actor WikiVaultMaintenance {
    private let fileManager: FileManager
    private let remove: @Sendable (URL) throws -> Void

    /// `remove` defaults to moving files to the Trash. Tests inject a plain
    /// `removeItem` instead, so exercising the delete/asset-cleanup logic
    /// against a disposable temp vault never touches the real Trash.
    init(fileManager: FileManager = .default, remove: (@Sendable (URL) throws -> Void)? = nil) {
        self.fileManager = fileManager
        self.remove = remove ?? { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }

    func findDuplicates(config: WikiVaultConfig) -> [WikiDuplicateFinder.Group] {
        let index = WikiVaultIndex.scan(journalDir: config.journalDir, fileManager: fileManager)
        return WikiDuplicateFinder.duplicateGroups(in: index)
    }

    /// Removes `entry`'s markdown file, plus any asset it references that no
    /// other `.md` file remaining in the journal still references.
    func delete(entry: WikiVaultIndex.Entry, config: WikiVaultConfig) throws {
        let referenced = referencedAssets(of: entry.markdownPath, config: config)

        try remove(entry.markdownPath)

        guard !referenced.isEmpty else { return }
        let stillReferenced = assetsStillReferenced(in: config.journalDir, config: config)
        for name in referenced where !stillReferenced.contains(name) {
            try? remove(config.assetsDir.appendingPathComponent(name))
        }
    }

    private func referencedAssets(of markdownFile: URL, config: WikiVaultConfig) -> Set<String> {
        guard let text = try? String(contentsOf: markdownFile, encoding: .utf8) else { return [] }
        return WikiDuplicateAssets.referencedAssetFilenames(in: text, assetsSubpath: config.assetsSubpath)
    }

    private func assetsStillReferenced(in journalDir: URL, config: WikiVaultConfig) -> Set<String> {
        guard let files = try? fileManager.contentsOfDirectory(
            at: journalDir, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var referenced: Set<String> = []
        for file in files where file.pathExtension.lowercased() == "md" {
            referenced.formUnion(referencedAssets(of: file, config: config))
        }
        return referenced
    }
}
