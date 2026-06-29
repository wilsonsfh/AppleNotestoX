import Foundation

/// Pure naming + provenance helpers for the wiki export destination.
///
/// All functions are deterministic and side-effect free so they can be unit
/// tested without touching the filesystem or Apple Notes.
enum WikiNaming {

    /// Kebab-cases a note title for use in filenames: lowercased, non-alphanumerics
    /// collapsed to single hyphens, trimmed. Falls back to `"note"` when empty.
    static func slug(from title: String) -> String {
        let lower = title.lowercased()
        let mapped = lower.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let collapsed = String(mapped)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: "-")
        return collapsed.isEmpty ? "note" : collapsed
    }

    /// `YYYY-MM-DD` in a stable (UTC, POSIX) calendar so output is deterministic.
    static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// `YYYY-MM-DD-<slug>.md`
    static func markdownFilename(date: Date, slug: String) -> String {
        "\(isoDay(date))-\(slug).md"
    }

    /// `<slug>-NN.<ext>` with `NN` zero-padded to two digits and a lowercased extension.
    static func assetFilename(slug: String, index: Int, ext: String) -> String {
        let nn = String(format: "%02d", index)
        let cleaned = ext.lowercased()
        let safeExt = cleaned.isEmpty ? "dat" : cleaned
        return "\(slug)-\(nn).\(safeExt)"
    }

    /// Returns `name` if unused, otherwise appends `-2`, `-3`, … before the extension.
    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            if !existing.contains(candidate) { return candidate }
            i += 1
        }
    }

    /// Provenance frontmatter block (YAML + an immutability banner) written at the
    /// top of every exported note, satisfying the vault's "raw/ is immutable +
    /// origin-marked" rule. Ends with a trailing blank line.
    static func frontmatter(noteID: String, title: String, modified: Date, exported: Date) -> String {
        """
        ---
        origin: user-stated
        source_type: journal
        source_app: apple-notes
        apple_note_id: \(noteID)
        title: \(title)
        note_modified: \(isoDay(modified))
        exported: \(isoDay(exported))
        ---
        > Provenance: exported verbatim from Apple Notes. Immutable — synthesize into
        > wiki/, don't edit here.

        """
    }
}
