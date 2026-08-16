import Foundation

/// Extracts the asset filenames a wiki journal entry's markdown body
/// references, so deleting a duplicate `.md` file can also clean up the
/// image/attachment copies that only that file pointed to — matching the
/// two link shapes `WikiExportAssembler.inlineMarkdown` writes: Obsidian
/// embeds for images (`![[name]]`) and plain links for everything else
/// (`[label](raw/assets/name)`).
enum WikiDuplicateAssets {
    static func referencedAssetFilenames(in markdown: String, assetsSubpath: String) -> Set<String> {
        var names = Set(matches(of: #"!\[\[([^\]]+)\]\]"#, in: markdown))
        let escapedSubpath = NSRegularExpression.escapedPattern(for: assetsSubpath)
        names.formUnion(matches(of: "\\(\(escapedSubpath)/([^)]+)\\)", in: markdown))
        return names
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
    }
}
