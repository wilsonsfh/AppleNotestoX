import Foundation
import SwiftSoup

/// Converts Apple Notes HTML into plain text for LLM input.
///
/// Walks the DOM in document order, flattening a run of inline content
/// (text nodes plus inline elements such as `<span>`/`<b>`) into a single
/// line, and starting a new line whenever it hits a block-level element
/// (p, h1-h6, li, blockquote, tr) or a `<br>`. Container elements (div, ul,
/// body, ...) contribute no line of their own — they're only recursed into.
/// Every text node reachable from the body ends up in exactly one line;
/// none are silently dropped because an earlier sibling already produced
/// output.
enum PlainTextExtractor {
    static func extract(html: String) -> String {
        guard let doc = try? SwiftSoup.parseBodyFragment(html), let body = doc.body() else {
            return ""
        }
        var lines: [String] = []
        var buffer = ""
        collectLines(body, into: &lines, buffer: &buffer)
        flush(&buffer, into: &lines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let contentBlockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "tr"
    ]

    /// Recursively walks `element`'s child nodes in order, appending
    /// completed lines to `lines` and accumulating in-progress inline text
    /// in `buffer`. `buffer` is shared across the whole recursive walk so
    /// that inline content split across sibling elements (e.g. adjacent
    /// `<span>`s) is combined into one line instead of being lost.
    private static func collectLines(_ element: Element, into lines: inout [String], buffer: inout String) {
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                buffer += textNode.text()
            } else if let childElement = node as? Element {
                let tag = childElement.tagName().lowercased()
                if tag == "br" {
                    flush(&buffer, into: &lines)
                } else if contentBlockTags.contains(tag) {
                    flush(&buffer, into: &lines)
                    let text = (try? childElement.text()) ?? ""
                    if !text.isEmpty { lines.append(text) }
                } else {
                    collectLines(childElement, into: &lines, buffer: &buffer)
                }
            }
        }
    }

    private static func flush(_ buffer: inout String, into lines: inout [String]) {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lines.append(trimmed) }
        buffer = ""
    }
}
