import Foundation

/// Cross-note content-similarity check — separate from and complementary to
/// `apple_note_id`-based dedup. Two notes with different IDs can still be
/// near-duplicates (a note manually duplicated in Apple Notes, or content
/// pasted into a second note); this flags those by comparing word shingles.
enum WikiContentSimilarity {
    /// Similarity at/above this fraction is treated as a likely duplicate.
    static let defaultThreshold = 0.8

    /// Jaccard similarity of 3-word shingle sets, case-insensitive.
    /// Two empty (or blank) strings are treated as dissimilar — there's no
    /// content to meaningfully compare, so it's not a useful match.
    static func jaccardSimilarity(_ a: String, _ b: String, shingleSize: Int = 3) -> Double {
        jaccardSimilarity(shingles(of: a, size: shingleSize), shingles(of: b, size: shingleSize))
    }

    /// Jaccard similarity of two precomputed shingle sets, so callers
    /// comparing many notes pairwise shingle each note only once.
    static func jaccardSimilarity(_ shinglesA: Set<[String]>, _ shinglesB: Set<[String]>) -> Double {
        guard !shinglesA.isEmpty, !shinglesB.isEmpty else { return 0.0 }

        let intersection = shinglesA.intersection(shinglesB).count
        let union = shinglesA.union(shinglesB).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    static func shingles(of text: String, size: Int = 3) -> Set<[String]> {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return [] }
        guard words.count >= size else { return [words] }

        var result = Set<[String]>()
        for i in 0...(words.count - size) {
            result.insert(Array(words[i..<(i + size)]))
        }
        return result
    }
}
