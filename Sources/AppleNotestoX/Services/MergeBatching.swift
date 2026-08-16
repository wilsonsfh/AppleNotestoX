import Foundation

/// Splits a large note selection into LLM-request-sized batches, and merges
/// each batch's independently-categorized sections back into one list. Pure
/// logic, no I/O — `MergeCoordinator` drives the actual `GroqService` calls
/// between `batches(for:)` and `mergeBatchResults(_:)`.
enum MergeBatching {
    /// Notes' combined plain-text length that keeps a single categorization
    /// request comfortably fast against a rate-limited/shared LLM gateway.
    static let maxCharactersPerBatch = 20_000
    /// Hard cap on notes per batch, independent of character budget, so a
    /// pile of very short notes doesn't inflate one request's JSON overhead.
    static let maxNotesPerBatch = 20

    /// Groups notes into batches under the character/count budget above. A
    /// single note whose own plain text exceeds the budget still gets its
    /// own batch rather than being dropped or split.
    static func batches(for notes: [MergeSourceNote]) -> [[MergeSourceNote]] {
        var result: [[MergeSourceNote]] = []
        var current: [MergeSourceNote] = []
        var currentChars = 0

        for note in notes {
            let noteChars = note.plainText.count
            if !current.isEmpty,
               currentChars + noteChars > maxCharactersPerBatch || current.count >= maxNotesPerBatch {
                result.append(current)
                current = []
                currentChars = 0
            }
            current.append(note)
            currentChars += noteChars
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Combines each batch's sections into one list, merging sections whose
    /// headers match (case/whitespace-insensitive) across batches so the
    /// same topic doesn't produce duplicate headers just because its notes
    /// landed in different batches.
    static func mergeBatchResults(_ batchSections: [[MergeSection]]) -> [MergeSection] {
        var merged: [MergeSection] = []
        var indexByNormalizedHeader: [String: Int] = [:]

        for sections in batchSections {
            for section in sections {
                let key = section.header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let idx = indexByNormalizedHeader[key] {
                    let existing = merged[idx]
                    let newIDs = section.sourceNoteIDs.filter { !existing.sourceNoteIDs.contains($0) }
                    merged[idx] = MergeSection(
                        header: existing.header,
                        bodyText: existing.bodyText + "\n\n" + section.bodyText,
                        sourceNoteIDs: existing.sourceNoteIDs + newIDs
                    )
                } else {
                    indexByNormalizedHeader[key] = merged.count
                    merged.append(section)
                }
            }
        }
        return merged
    }
}
