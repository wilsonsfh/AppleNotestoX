import Foundation

/// Persistent local staging area for attachment files during one Merge to
/// Note run, so images survive past `AppleNotesService.fetchNote`'s
/// per-note OS temp-dir cleanup. Purely a staging aid — not a permanent
/// archive; callers delete a run's directory once it is no longer needed.
actor TriageAssetStore {
    private let root: URL
    private let fileManager: FileManager

    init(root: URL = TriageAssetStore.defaultRoot(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("AppleNotestoX/TriageAssets", isDirectory: true)
    }

    func makeRunDirectory() throws -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func stage(fileAt sourceURL: URL, filename: String, into runDirectory: URL) throws -> URL {
        let destination = runDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func deleteRunDirectory(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
