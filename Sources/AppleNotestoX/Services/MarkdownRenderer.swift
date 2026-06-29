import Foundation

/// Renders the neutral `[NotionBlock]` document model (produced by `NoteConverter`)
/// into Markdown for the LLM-wiki destination. Pure: no I/O.
///
/// Spacing rule: consecutive list items (bulleted / numbered / to-do) stay tight
/// (single newline) so they render as one list; every other adjacent pair of
/// blocks is separated by a blank line so paragraphs don't merge.
enum MarkdownRenderer {

    struct Output: Equatable {
        var markdown: String = ""
        var warnings: [String] = []
    }

    /// - Parameter inlineAsset: returns the full inline markdown for an image
    ///   placeholder id (e.g. `"![[glints-01.png]]"` or `"[doc.pdf](raw/assets/doc.pdf)"`),
    ///   or `nil` to emit a visible "missing image" warning callout.
    static func render(_ blocks: [NotionBlock], inlineAsset: (UUID) -> String?) -> Output {
        var out = Output()
        var chunks: [(text: String, isList: Bool)] = []
        var missingIndex = 0

        for block in blocks {
            switch block {
            case .heading1(let r): chunks.append(("# " + inline(r), false))
            case .heading2(let r): chunks.append(("## " + inline(r), false))
            case .heading3(let r): chunks.append(("### " + inline(r), false))
            case .paragraph(let r): chunks.append((inline(r), false))
            case .bulletedListItem(let r): chunks.append(("- " + inline(r), true))
            case .numberedListItem(let r): chunks.append(("1. " + inline(r), true))
            case .toDo(let r, let checked): chunks.append(((checked ? "- [x] " : "- [ ] ") + inline(r), true))
            case .quote(let r): chunks.append(("> " + inline(r), false))
            case .code(let r, let lang): chunks.append(("```\(lang)\n\(plain(r))\n```", false))
            case .divider: chunks.append(("---", false))
            case .imagePlaceholder(let id, _):
                if let snippet = inlineAsset(id) {
                    chunks.append((snippet, false))
                } else {
                    missingIndex += 1
                    chunks.append(("> [!warning] missing image #\(missingIndex)", false))
                    out.warnings.append("missing asset for placeholder #\(missingIndex)")
                }
            case .imageUploaded:
                chunks.append(("> [!warning] unexpected uploaded-image block (Notion-only)", false))
                out.warnings.append("unexpected imageUploaded block")
            case .imageFailed(let msg):
                chunks.append(("> [!warning] image failed: \(msg)", false))
                out.warnings.append("image failed: \(msg)")
            }
        }

        var md = ""
        for (i, chunk) in chunks.enumerated() {
            if i > 0 {
                let prev = chunks[i - 1]
                md += (prev.isList && chunk.isList) ? "\n" : "\n\n"
            }
            md += chunk.text
        }
        if !md.isEmpty { md += "\n" }
        out.markdown = md
        return out
    }

    // MARK: - Inline

    private static func plain(_ rts: [NotionRichText]) -> String {
        rts.map(\.content).joined()
    }

    private static func inline(_ rts: [NotionRichText]) -> String {
        rts.map { rt -> String in
            var s = rt.content
            if s.isEmpty { return s }
            if rt.code { s = "`\(s)`" }
            if rt.bold { s = "**\(s)**" }
            if rt.italic { s = "*\(s)*" }
            if rt.strikethrough { s = "~~\(s)~~" }
            if let link = rt.link { s = "[\(s)](\(link.absoluteString))" }
            return s
        }.joined()
    }
}
