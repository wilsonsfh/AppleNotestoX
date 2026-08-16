import Foundation

/// Indexes an existing wiki vault's journal by `apple_note_id`, so re-running
/// an export can skip notes that haven't changed since they were last
/// written instead of creating a `-2` duplicate file every run.
enum WikiVaultIndex {
    struct Entry: Sendable, Equatable {
        let noteModifiedDay: String
        let markdownPath: URL
    }

    /// Scans every `.md` file directly inside `journalDir` and parses its
    /// frontmatter (see `WikiNaming.frontmatter`). Files that don't parse —
    /// a foreign file, or one with no recognizable frontmatter — are
    /// skipped rather than treated as an error; a missing/unreadable
    /// directory (e.g. first-ever export) yields an empty index.
    static func scan(journalDir: URL, fileManager: FileManager = .default) -> [String: Entry] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: journalDir, includingPropertiesForKeys: nil
        ) else {
            return [:]
        }
        var index: [String: Entry] = [:]
        for file in files where file.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let fields = WikiNaming.parseFrontmatter(text),
                  let noteID = fields["apple_note_id"],
                  let modified = fields["note_modified"] else { continue }
            index[noteID] = Entry(noteModifiedDay: modified, markdownPath: file)
        }
        return index
    }

    /// True when the vault already has an export for `noteID` whose
    /// recorded `note_modified` day matches the note's current modification
    /// date — i.e. re-exporting it right now would produce an identical
    /// duplicate rather than an update.
    static func isUpToDate(noteID: String, modified: Date, index: [String: Entry]) -> Bool {
        guard let entry = index[noteID] else { return false }
        return entry.noteModifiedDay == WikiNaming.isoDay(modified)
    }
}
