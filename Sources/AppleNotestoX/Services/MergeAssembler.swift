import Foundation

/// Assembles one Apple Notes-compatible HTML document from LLM-categorized
/// sections. Pure function — no I/O, no actor isolation needed.
enum MergeAssembler {
    static func titleLine(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return "Merged Notes — \(formatter.string(from: date))"
    }

    /// - Parameter sourceNoteTitles: maps each merged note's id to its
    ///   original title, so every section can list which notes fed it.
    static func assembleHTML(
        sections: [MergeSection],
        titleLine: String,
        sourceNoteTitles: [String: String]
    ) -> String {
        var html = "<div>\(escape(titleLine))</div>"
        for section in sections {
            html += "<h1>\(escape(section.header))</h1>"
            html += "<ul>"
            for line in bulletLines(from: section.bodyText) {
                html += "<li>\(escape(line))</li>"
            }
            html += "</ul>"

            let titles = section.sourceNoteIDs.compactMap { sourceNoteTitles[$0] }
            if !titles.isEmpty {
                html += "<p><em>Sources: \(escape(titles.joined(separator: ", ")))</em></p>"
            }
        }
        return html
    }

    /// Splits LLM-produced body text into individual bullet points. The
    /// model is asked for one point per line, but strips any leading
    /// bullet marker (`-`, `*`, `•`) it adds anyway, and falls back to
    /// treating the whole text as one point if it returned a single line.
    private static func bulletLines(from bodyText: String) -> [String] {
        let lines = bodyText
            .components(separatedBy: .newlines)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                while let first = trimmed.first, "-*•".contains(first) {
                    trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return trimmed
            }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? [bodyText.trimmingCharacters(in: .whitespaces)] : lines
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
