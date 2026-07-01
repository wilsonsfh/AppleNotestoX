import Foundation

enum StudyError: Error, LocalizedError {
    case scriptMissing(String)
    case generatorFailed(String)
    case studyDataUnreadable

    var errorDescription: String? {
        switch self {
        case .scriptMissing(let p): return "Can't find the study generator at \(p). Set the Review folder in Settings."
        case .generatorFailed(let m): return "Study generator failed: \(m)"
        case .studyDataUnreadable: return "Couldn't read study-data.js after generating."
        }
    }
}

/// Runs `review/generate.mjs` against a vault, then reads the produced `study-data.js`.
enum StudyDataService {
    /// Read the current snapshot without regenerating (nil if never generated).
    static func loadExisting() -> StudyData? {
        guard let js = try? String(contentsOf: RepoPaths.studyDataJS(), encoding: .utf8) else { return nil }
        return StudyData.parse(js)
    }

    /// Regenerate from the vault, then parse the result.
    static func refresh(vaultURL: URL) async throws -> StudyData {
        let script = RepoPaths.generateScript()
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw StudyError.scriptMissing(script.path)
        }
        let out = RepoPaths.studyDataJS()
        let node = RepoPaths.nodeInvocation()
        let args = node.argPrefix + [script.path, "--vault", vaultURL.path, "--out", out.path]

        let result = try await ProcessRunner.run(executableURL: node.executable, arguments: args)
        guard result.status == 0 else {
            let msg = result.stderr.isEmpty ? result.stdout : result.stderr
            throw StudyError.generatorFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = loadExisting() else { throw StudyError.studyDataUnreadable }
        return data
    }
}
