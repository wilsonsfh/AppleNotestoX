import Foundation
import SwiftSoup

/// Converts Apple Notes HTML into plain text for LLM input. Block-level
/// elements (p, div, h1-h6, li) each contribute one line; inline tags are
/// unwrapped in place.
enum PlainTextExtractor {
    static func extract(html: String) -> String {
        guard let doc = try? SwiftSoup.parseBodyFragment(html), let body = doc.body() else {
            return ""
        }
        var lines: [String] = []
        collectLines(body, into: &lines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let contentBlockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "tr"
    ]

    private static func collectLines(_ element: Element, into lines: inout [String]) {
        for child in element.children() {
            let tag = child.tagName().lowercased()
            if contentBlockTags.contains(tag) {
                let text = (try? child.text()) ?? ""
                if !text.isEmpty { lines.append(text) }
            } else {
                collectLines(child, into: &lines)
            }
        }
        if element.children().isEmpty {
            let text = (try? element.text()) ?? ""
            if !text.isEmpty && lines.isEmpty { lines.append(text) }
        }
    }
}
