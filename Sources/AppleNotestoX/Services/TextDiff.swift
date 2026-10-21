import Foundation

/// Line-level diff between two note bodies, used to show what changed
/// between duplicate exports of the same note (git-diff style) instead of
/// asking the user to pick a survivor blind.
enum TextDiff {
    enum Line: Equatable {
        case unchanged(String)
        case added(String)
        case removed(String)
    }

    static func diff(old: String, new: String) -> [Line] {
        let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")
        return diff(oldLines: oldLines, newLines: newLines)
    }

    /// Longest-common-subsequence table walked backward to recover the
    /// interleaved unchanged/added/removed lines.
    private static func diff(oldLines: [String], newLines: [String]) -> [Line] {
        let m = oldLines.count
        let n = newLines.count
        guard m > 0, n > 0 else {
            return oldLines.map { .removed($0) } + newLines.map { .added($0) }
        }

        var table = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                if oldLines[i] == newLines[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var result: [Line] = []
        var i = 0, j = 0
        while i < m && j < n {
            if oldLines[i] == newLines[j] {
                result.append(.unchanged(oldLines[i]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(.removed(oldLines[i]))
                i += 1
            } else {
                result.append(.added(newLines[j]))
                j += 1
            }
        }
        while i < m { result.append(.removed(oldLines[i])); i += 1 }
        while j < n { result.append(.added(newLines[j])); j += 1 }
        return result
    }
}
