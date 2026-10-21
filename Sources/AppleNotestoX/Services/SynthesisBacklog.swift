import Foundation

/// An Apple Notes raw document not yet mirrored by `wiki/sources/<same-name>.md`.
struct BacklogItem: Sendable, Equatable, Identifiable {
    let id: String
    let date: String
    let slug: String
    let url: URL
}

/// Surfaces Apple Notes source documents that have not been synthesized yet.
enum SynthesisBacklog {
    static func pending(rawJournal: [String], wikiSources: Set<String>) -> [String] {
        rawJournal.filter { !wikiSources.contains($0) }.sorted(by: >)
    }

    static func scan(vaultURL: URL, fileManager: FileManager = .default) -> [BacklogItem] {
        let noteRoots = [
            vaultURL.appendingPathComponent("raw/apple-notes", isDirectory: true),
            vaultURL.appendingPathComponent("raw/journal", isDirectory: true)
        ]
        let sources = vaultURL.appendingPathComponent("wiki/sources", isDirectory: true)
        let rawFiles = markdownFiles(in: noteRoots, fileManager: fileManager)
        let sourceNames = Set(markdownFilenames(in: sources, fileManager: fileManager))
        let pendingNames = Set(pending(rawJournal: rawFiles.map(\.lastPathComponent), wikiSources: sourceNames))

        return rawFiles
            .filter { pendingNames.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { file in
                let name = file.lastPathComponent
                let (date, slug) = split(name)
                return BacklogItem(id: name, date: date, slug: slug, url: file)
            }
    }

    static func opencodePrompt(_ items: [BacklogItem]) -> String {
        let list = items.map { "- \(rawRelativePath($0.url))" }.joined(separator: "\n")
        return """
        Synthesize raw/ notes into wiki per AGENTS.md: provenance-stamped,
        [[wikilinks]], and one wiki/sources/ page each:
        \(list)
        """
    }

    private static func markdownFilenames(in directory: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: directory.path))?.filter { $0.hasSuffix(".md") } ?? []
    }

    private static func markdownFiles(in roots: [URL], fileManager: FileManager) -> [URL] {
        roots.flatMap { root -> [URL] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "md" }
        }
    }

    private static func split(_ name: String) -> (date: String, slug: String) {
        let base = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        guard base.count >= 11,
              base.prefix(10).allSatisfy({ $0.isNumber || $0 == "-" }),
              base.dropFirst(10).first == "-" else {
            return ("", base)
        }
        return (String(base.prefix(10)), String(base.dropFirst(11)))
    }

    private static func rawRelativePath(_ url: URL) -> String {
        let path = url.path
        guard let range = path.range(of: "/raw/") else { return path }
        return "raw/" + path[range.upperBound...]
    }
}
