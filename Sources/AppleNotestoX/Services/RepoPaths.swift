import Foundation

/// Resolves paths to the bundled-alongside `review/` tooling and the `node` binary.
///
/// Resolution is **runtime-first** so an installed binary keeps working after it is
/// copied off the build machine. `#filePath` is only the last resort, because it bakes
/// in the *build* machine's absolute source path.
///
/// Order: UserDefaults override → `APPLENOTESTOX_REVIEW_DIR` env → next to the running
/// executable → walking up from the executable (SwiftPM `.build/<config>/` layout) →
/// current working directory → `#filePath` (source checkout).
enum RepoPaths {
    static let reviewFolderOverrideKey = "review_folder_override"
    static let reviewDirEnvKey = "APPLENOTESTOX_REVIEW_DIR"

    /// First path in `paths` that exists on disk, as a file URL.
    static func firstExisting(_ paths: [String], fileManager: FileManager = .default) -> URL? {
        for p in paths where fileManager.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// A directory only counts as the review folder if it actually holds the tooling.
    static func isReviewDir(_ url: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent("index.html").path)
    }

    /// repo root = <root>/Sources/AppleNotestoX/Services/RepoPaths.swift → up 4.
    /// Build-time path; valid only on the machine that compiled the binary.
    private static func sourceCheckoutRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Services
            .deletingLastPathComponent()   // AppleNotestoX
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repo root
    }

    /// Candidate review directories, most explicit first.
    static func reviewDirCandidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL? = Bundle.main.executableURL,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> [URL] {
        var candidates: [URL] = []

        if let override = UserDefaults.standard.string(forKey: reviewFolderOverrideKey), !override.isEmpty {
            candidates.append(URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true))
        }
        if let fromEnv = environment[reviewDirEnvKey], !fromEnv.isEmpty {
            candidates.append(URL(fileURLWithPath: (fromEnv as NSString).expandingTildeInPath, isDirectory: true))
        }
        if let executableURL {
            // Alongside the binary (an installed layout), then walk up far enough to
            // escape `.build/arm64-apple-macosx/debug/` back to a checkout root.
            var dir = executableURL.deletingLastPathComponent()
            for _ in 0..<5 {
                candidates.append(dir.appendingPathComponent("review", isDirectory: true))
                dir = dir.deletingLastPathComponent()
            }
        }
        candidates.append(URL(fileURLWithPath: currentDirectory, isDirectory: true)
            .appendingPathComponent("review", isDirectory: true))
        candidates.append(sourceCheckoutRoot().appendingPathComponent("review", isDirectory: true))

        return candidates
    }

    static func reviewDir() -> URL {
        let candidates = reviewDirCandidates()
        // An explicit override is honoured even if it is not populated yet, so the user
        // sees their own path in errors rather than a silently different fallback.
        if let override = UserDefaults.standard.string(forKey: reviewFolderOverrideKey), !override.isEmpty {
            return candidates[0]
        }
        return candidates.first(where: { isReviewDir($0) }) ?? candidates[candidates.count - 1]
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
