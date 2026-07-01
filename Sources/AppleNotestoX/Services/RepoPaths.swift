import Foundation

/// Resolves paths to the bundled-alongside `review/` tooling and the `node` binary.
/// The repo root is derived from this source file's compile-time path (`#filePath`);
/// a UserDefaults override (`review_folder_override`) wins when set — useful if the
/// app is ever run from outside the checkout.
enum RepoPaths {
    static let reviewFolderOverrideKey = "review_folder_override"

    /// First path in `paths` that exists on disk, as a file URL.
    static func firstExisting(_ paths: [String], fileManager: FileManager = .default) -> URL? {
        for p in paths where fileManager.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// repo root = <root>/Sources/AppleNotestoX/Services/RepoPaths.swift → up 4.
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Services
            .deletingLastPathComponent()   // AppleNotestoX
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repo root
    }

    static func reviewDir() -> URL {
        if let override = UserDefaults.standard.string(forKey: reviewFolderOverrideKey), !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return repoRoot().appendingPathComponent("review", isDirectory: true)
    }

    static func generateScript() -> URL { reviewDir().appendingPathComponent("generate.mjs") }
    static func indexHTML() -> URL { reviewDir().appendingPathComponent("index.html") }
    static func studyDataJS() -> URL { reviewDir().appendingPathComponent("study-data.js") }

    /// Prefer an absolute `node`; fall back to `/usr/bin/env node` (uses PATH).
    static func nodeInvocation() -> (executable: URL, argPrefix: [String]) {
        if let node = firstExisting(["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]) {
            return (node, [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["node"])
    }
}
