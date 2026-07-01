import Foundation

/// A `raw/journal` note not yet mirrored by a `wiki/sources/<same-name>.md` page.
struct BacklogItem: Sendable, Equatable, Identifiable {
    let id: String      // filename, e.g. "2026-06-30-mindset.md"
    let date: String    // "YYYY-MM-DD" prefix, or "" if none
    let slug: String    // remainder without date + ".md"
    let url: URL
}

/// Surfaces what's captured in `raw/` but not yet synthesized into `wiki/`.
/// Heuristic v1: filename match between `raw/journal/*.md` and `wiki/sources/*.md`.
enum SynthesisBacklog {
    static func pending(rawJournal: [String], wikiSources: Set<String>) -> [String] {
        rawJournal.filter { !wikiSources.contains($0) }.sorted(by: >)
    }

    static func scan(vaultURL: URL, fileManager: FileManager = .default) -> [BacklogItem] {
        let journal = vaultURL.appendingPathComponent("raw/journal", isDirectory: true)
        let sources = vaultURL.appendingPathComponent("wiki/sources", isDirectory: true)
        let raw = mdFilenames(in: journal, fileManager: fileManager)
        let src = Set(mdFilenames(in: sources, fileManager: fileManager))
        return pending(rawJournal: raw, wikiSources: src).map { name in
            let (date, slug) = split(name)
            return BacklogItem(id: name, date: date, slug: slug,
                               url: journal.appendingPathComponent(name))
        }
    }

    static func opencodePrompt(_ items: [BacklogItem]) -> String {
        let list = items.map { "- raw/journal/\($0.id)" }.joined(separator: "\n")
        return """
        Synthesize these raw/ notes into the wiki per AGENTS.md — provenance-stamped, \
        with [[wikilinks]] and one wiki/sources/ page each:
        \(list)
        """
    }

    // MARK: helpers
    private static func mdFilenames(in dir: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: dir.path))?.filter { $0.hasSuffix(".md") } ?? []
    }

    private static func split(_ name: String) -> (date: String, slug: String) {
        let base = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        if base.count >= 11,
           base.prefix(10).allSatisfy({ $0.isNumber || $0 == "-" }),
           base.dropFirst(10).first == "-" {
            return (String(base.prefix(10)), String(base.dropFirst(11)))
        }
        return ("", base)
    }
}
