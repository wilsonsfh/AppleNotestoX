import Foundation
import SwiftSoup

/// Converts Apple Notes HTML body into an ordered array of NotionBlocks.
///
/// Image positioning is preserved by walking the DOM in document order and emitting
/// `imagePlaceholder` blocks where each `<img>` or `<object>` appears. Placeholders are
/// later swapped for `imageUploaded`/`imageFailed` by the coordinator.
enum NoteConverter {

    static func convert(html: String, attachments: [AppleNoteAttachment]) -> [NotionBlock] {
        var imageIter = attachments.makeIterator()
        let walker = Walker { imageIter.next() }
        do {
            let doc = try SwiftSoup.parseBodyFragment(html)
            guard let body = doc.body() else { return [] }
            for node in body.getChildNodes() {
                walker.process(node: node)
            }
        } catch {
            return [.paragraph([NotionRichText(content: "[failed to parse note body]")])]
        }
        return walker.finalize()
    }

    // MARK: - Walker

    private final class Walker {
        private var blocks: [NotionBlock] = []
        private var pending: [NotionRichText] = []
        private let nextAttachment: () -> AppleNoteAttachment?

        init(nextAttachment: @escaping () -> AppleNoteAttachment?) {
            self.nextAttachment = nextAttachment
        }

        func finalize() -> [NotionBlock] {
            flushParagraph()
            return blocks
        }

        private func flushParagraph() {
            let trimmed = trimRichText(pending)
            if !trimmed.isEmpty {
                blocks.append(.paragraph(trimmed))
            }
            pending = []
        }

        func process(node: Node) {
            if let textNode = node as? TextNode {
                appendText(textNode.text(), with: NotionRichText(content: ""))
                return
            }
            guard let element = node as? Element else { return }
            let tag = element.tagName().lowercased()

            switch tag {
            case "h1":
                flushParagraph()
                blocks.append(.heading1(collectInline(element, base: NotionRichText(content: ""))))
            case "h2":
                flushParagraph()
                blocks.append(.heading2(collectInline(element, base: NotionRichText(content: ""))))
            case "h3", "h4", "h5", "h6":
                flushParagraph()
                blocks.append(.heading3(collectInline(element, base: NotionRichText(content: ""))))
            case "p", "div":
                flushParagraph()
                processBlockContainer(element)
                flushParagraph()
            case "ul", "ol":
                flushParagraph()
                processList(element, ordered: tag == "ol")
            case "li":
                // Stray <li> outside a list — treat as bulleted item.
                flushParagraph()
                blocks.append(.bulletedListItem(collectInline(element, base: NotionRichText(content: ""))))
            case "blockquote":
                flushParagraph()
                blocks.append(.quote(collectInline(element, base: NotionRichText(content: ""))))
            case "pre":
                flushParagraph()
                blocks.append(.code(collectInline(element, base: NotionRichText(content: "")), language: "plain text"))
            case "hr":
                flushParagraph()
                blocks.append(.divider)
            case "table":
                flushParagraph()
                processTable(element)
            case "br":
                appendText("\n", with: NotionRichText(content: ""))
            case "img", "object":
                flushParagraph()
                emitImage()
            default:
                // Inline or unknown wrapper — keep walking children with this element's annotations.
                let base = applyTagAnnotations(NotionRichText(content: ""), tag: tag, element: element)
                processBlockContainer(element, base: base)
            }
        }

        private func processBlockContainer(_ element: Element, base: NotionRichText = NotionRichText(content: "")) {
            for child in element.getChildNodes() {
                if let text = child as? TextNode {
                    appendText(text.text(), with: base)
                } else if let el = child as? Element {
                    let tag = el.tagName().lowercased()
                    if Self.isBlockTag(tag) || tag == "img" || tag == "object" {
                        process(node: el)
                    } else if tag == "br" {
                        appendText("\n", with: base)
                    } else {
                        let merged = applyTagAnnotations(base, tag: tag, element: el)
                        for grand in el.getChildNodes() {
                            collectInlineNode(grand, base: merged, into: &pending)
                        }
                    }
                }
            }
        }

        private func processList(_ element: Element, ordered: Bool) {
            // Detect "checklist" semantics: container or items marked accordingly.
            let containerClass = (try? element.attr("class")) ?? ""
            let containerIsCheck = containerClass.lowercased().contains("check")
            for child in element.children() where child.tagName().lowercased() == "li" {
                let liClass = (try? child.attr("class")) ?? ""
                let hasCheckboxInput = (try? !child.select("input[type=checkbox]").isEmpty()) ?? false
                let isCheckItem = containerIsCheck || liClass.lowercased().contains("check") || hasCheckboxInput

                let rts = collectInline(child, base: NotionRichText(content: ""), strippingCheckboxes: true)
                if isCheckItem {
                    let checked = liClass.lowercased().contains("checked") ||
                        ((try? !child.select("input[type=checkbox][checked]").isEmpty()) ?? false)
                    blocks.append(.toDo(rts, checked: checked))
                } else if ordered {
                    blocks.append(.numberedListItem(rts))
                } else {
                    blocks.append(.bulletedListItem(rts))
                }
            }
        }

        private func processTable(_ element: Element) {
            // Best-effort: emit each row as " | "-joined paragraph. Notion `table` blocks
            // require strict shape (header_row, table_row), which we defer to v2.
            guard let rows = try? element.select("tr") else { return }
            for row in rows.array() {
                let cells = (try? row.select("td, th").array()) ?? []
                let texts: [String] = cells.compactMap { try? $0.text() }
                let joined = texts.joined(separator: " | ")
                if !joined.isEmpty {
                    blocks.append(.paragraph([NotionRichText(content: joined)]))
                }
            }
        }

        private func emitImage() {
            guard let att = nextAttachment() else {
                blocks.append(.imageFailed(message: "no matching attachment"))
                return
            }
            blocks.append(.imagePlaceholder(id: UUID(), localPath: att.localURL))
        }

        // MARK: - Inline collection

        private func collectInline(_ element: Element, base: NotionRichText, strippingCheckboxes: Bool = false) -> [NotionRichText] {
            var out: [NotionRichText] = []
            for child in element.getChildNodes() {
                if strippingCheckboxes,
                   let el = child as? Element,
                   el.tagName().lowercased() == "input",
                   ((try? el.attr("type"))?.lowercased() == "checkbox") {
                    continue
                }
                collectInlineNode(child, base: base, into: &out)
            }
            return trimRichText(out)
        }

        private func collectInlineNode(_ node: Node, base: NotionRichText, into out: inout [NotionRichText]) {
            if let text = node as? TextNode {
                let s = text.text()
                if !s.isEmpty {
                    var rt = base
                    rt.content = s
                    out.append(rt)
                }
                return
            }
            guard let el = node as? Element else { return }
            let tag = el.tagName().lowercased()
            if tag == "br" {
                var rt = base
                rt.content = "\n"
                out.append(rt)
                return
            }
            if tag == "img" || tag == "object" {
                // Image inside inline run — flush the run, emit image, then continue.
                pending.append(contentsOf: out)
                out.removeAll()
                flushParagraph()
                emitImage()
                return
            }
            let merged = applyTagAnnotations(base, tag: tag, element: el)
            for child in el.getChildNodes() {
                collectInlineNode(child, base: merged, into: &out)
            }
        }

        private func appendText(_ s: String, with base: NotionRichText) {
            guard !s.isEmpty else { return }
            var rt = base
            rt.content = s
            pending.append(rt)
        }

        private func applyTagAnnotations(_ base: NotionRichText, tag: String, element: Element) -> NotionRichText {
            var rt = base
            switch tag {
            case "b", "strong": rt.bold = true
            case "i", "em": rt.italic = true
            case "u": rt.underline = true
            case "s", "strike", "del": rt.strikethrough = true
            case "code", "tt", "kbd", "samp": rt.code = true
            case "a":
                if let href = try? element.attr("href"), !href.isEmpty {
                    rt.link = URL(string: href)
                }
            default: break
            }
            return rt
        }

        // MARK: - Helpers

        private func trimRichText(_ rts: [NotionRichText]) -> [NotionRichText] {
            var merged: [NotionRichText] = []
            for rt in rts {
                if var last = merged.last, sameAnnotations(last, rt) {
                    last.content += rt.content
                    merged[merged.count - 1] = last
                } else {
                    merged.append(rt)
                }
            }
            // Trim leading/trailing whitespace-only spans
            while let first = merged.first, first.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.removeFirst()
            }
            while let last = merged.last, last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.removeLast()
            }
            return merged
        }

        private func sameAnnotations(_ a: NotionRichText, _ b: NotionRichText) -> Bool {
            return a.bold == b.bold && a.italic == b.italic && a.strikethrough == b.strikethrough
                && a.underline == b.underline && a.code == b.code && a.link == b.link
        }

        private static let blockTags: Set<String> = [
            "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
            "ul", "ol", "li", "blockquote", "pre", "hr", "table",
            "tr", "td", "th", "thead", "tbody", "section", "article"
        ]
        private static func isBlockTag(_ tag: String) -> Bool { blockTags.contains(tag) }
    }
}
