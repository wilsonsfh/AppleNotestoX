import Foundation

/// Where exported notes land inside the Obsidian LLM-wiki vault.
struct WikiVaultConfig: Sendable, Equatable {
    var vaultURL: URL
    var journalSubpath: String = "raw/journal"
    var assetsSubpath: String = "raw/assets"

    var journalDir: URL { vaultURL.appendingPathComponent(journalSubpath, isDirectory: true) }
    var assetsDir: URL { vaultURL.appendingPathComponent(assetsSubpath, isDirectory: true) }
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
