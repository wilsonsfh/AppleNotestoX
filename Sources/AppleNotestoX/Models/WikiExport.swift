import Foundation

/// Where exported notes land inside the Obsidian LLM-wiki vault.
struct WikiVaultConfig: Sendable, Equatable {
    var vaultURL: URL
    var appleNotesSubpath: String = "raw/apple-notes"
    var legacyJournalSubpath: String = "raw/journal"
    var assetsSubpath: String = "raw/assets"

    var appleNotesDir: URL { vaultURL.appendingPathComponent(appleNotesSubpath, isDirectory: true) }
    var legacyJournalDir: URL { vaultURL.appendingPathComponent(legacyJournalSubpath, isDirectory: true) }
    var assetsDir: URL { vaultURL.appendingPathComponent(assetsSubpath, isDirectory: true) }

    /// Compatibility alias for integrations that store non-note capture under
    /// the Apple Notes root. New Apple Notes documents use a category folder.
    var journalDir: URL { appleNotesDir }

    /// New Apple Notes exports are grouped by content. The legacy journal is
    /// retained in scans so existing vaults remain readable during migration.
    var sourceNoteDirs: [URL] { [appleNotesDir, legacyJournalDir] }

    func appleNotesDir(for category: AppleNoteCategory) -> URL {
        appleNotesDir.appendingPathComponent(category.directoryName, isDirectory: true)
    }
}

struct WikiExportJob: Sendable {
    let noteIDs: [String]
    let config: WikiVaultConfig
    var transcribeVideos: Bool = false
}

struct WikiExportResult: Sendable, Equatable {
    let markdownPath: URL
    let assetPaths: [URL]
    let imageCount: Int
    let warnings: [String]
}

enum WikiExportStatus: Sendable, Equatable {
    case pending
    case fetching
    case converting
    case savingAssets(done: Int, total: Int)
    case writing
    case done(result: WikiExportResult)
    case skipped(reason: String)
    case failed(message: String)
}

struct WikiExportProgress: Identifiable, Sendable, Equatable {
    let id: String          // Apple note id
    var title: String
    var status: WikiExportStatus
}
