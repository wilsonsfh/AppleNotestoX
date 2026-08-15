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

    static func assembleHTML(
        sections: [MergeSection],
        titleLine: String,
        stagedImages: [String: [StagedImage]],
        embedImages: Bool
    ) -> String {
        var html = "<div>\(escape(titleLine))</div>"
        for section in sections {
            html += "<h1>\(escape(section.header))</h1>"
            html += "<p>\(escape(section.bodyText))</p>"
            for noteID in section.sourceNoteIDs {
                guard let images = stagedImages[noteID] else { continue }
                for image in images {
                    if embedImages {
                        html += "<img src=\"file://\(image.localURL.path)\">"
                    } else {
                        html += "<p>[image from &quot;\(escape(image.sourceNoteTitle))&quot; — staged at \(image.localURL.path)]</p>"
                    }
                }
            }
        }
        return html
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
