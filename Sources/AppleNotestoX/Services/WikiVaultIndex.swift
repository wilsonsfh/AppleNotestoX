import Foundation

/// Indexes an existing wiki vault's journal by `apple_note_id`, so re-running
/// an export can skip notes that haven't changed since they were last
/// written instead of creating a `-2` duplicate file every run — and so
/// `WikiDuplicateFinder` can spot notes with more than one exported file.
enum WikiVaultIndex {
    struct Entry: Sendable, Equatable {
        let noteID: String
        let noteModifiedDay: String
        let exportedDay: String?
        let title: String?
        let markdownPath: URL
        /// The body text after the frontmatter block, used for diffing
        /// duplicate exports and for cross-note content-similarity checks.
        let content: String
    }

    /// Every parsed `.md` entry under the supplied Apple Notes directories, keyed by
    /// `apple_note_id`. More than one entry under a key means duplicate
    /// exports of the same note. Files that don't parse — a foreign file,
    /// or one with no recognizable frontmatter — are skipped rather than
    /// treated as an error; a missing/unreadable directory (e.g. first-ever
    /// export) yields an empty index.
    static func scan(journalDir: URL, fileManager: FileManager = .default) -> [String: [Entry]] {
        scan(noteDirs: [journalDir], fileManager: fileManager)
    }

    static func scan(noteDirs: [URL], fileManager: FileManager = .default) -> [String: [Entry]] {
        var index: [String: [Entry]] = [:]
        var visited = Set<URL>()
        for root in noteDirs {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension.lowercased() == "md" {
                guard visited.insert(file.standardizedFileURL).inserted else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let fields = WikiNaming.parseFrontmatter(text),
                  let noteID = fields["apple_note_id"],
                  let modified = fields["note_modified"] else { continue }
            let entry = Entry(
                noteID: noteID,
                noteModifiedDay: modified,
                exportedDay: fields["exported"],
                title: fields["title"],
                markdownPath: file,
                content: WikiVaultIndex.bodyContent(of: text)
            )
            index[noteID, default: []].append(entry)
            }
        }
        return index
    }

    /// The text after the frontmatter's closing `---` marker, trimmed of
    /// surrounding whitespace. Empty when there's no frontmatter block.
    private static func bodyContent(of text: String) -> String {
        guard text.hasPrefix("---\n") else { return "" }
        let afterOpening = text.dropFirst(4)
        guard let closingRange = afterOpening.range(of: "\n---") else { return "" }
        let afterClosing = afterOpening[closingRange.upperBound...]
        return stripProvenanceBanner(afterClosing.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Every export starts with the same `> Provenance: …` blockquote from
    /// `WikiNaming.frontmatter`. Left in, its shingles are shared by every
    /// note and push short, unrelated notes over the similarity threshold.
    private static func stripProvenanceBanner(_ body: String) -> String {
        guard body.hasPrefix("> Provenance:") else { return body }
        let lines = body.components(separatedBy: "\n")
        let rest = lines.drop { $0.hasPrefix(">") }
        return rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the vault already has an export for `noteID` whose
    /// recorded `note_modified` day matches the note's current modification
    /// date — i.e. re-exporting it right now would produce an identical
    /// duplicate rather than an update.
    static func isUpToDate(noteID: String, modified: Date, index: [String: [Entry]]) -> Bool {
        guard let entries = index[noteID] else { return false }
        let day = WikiNaming.isoDay(modified)
        return entries.contains { $0.noteModifiedDay == day }
    }
}
