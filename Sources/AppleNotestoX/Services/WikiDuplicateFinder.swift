import Foundation

/// Groups a scanned wiki vault's journal entries by note, surfacing the
/// notes that have more than one exported file — the leftovers from before
/// `WikiExportCoordinator` started deduping, or from manual re-imports.
enum WikiDuplicateFinder {
    struct Group: Sendable, Equatable, Identifiable {
        var id: String { noteID }
        let noteID: String
        /// Newest-exported first — the entry a caller should default to
        /// keeping, with the rest pre-selected for removal.
        let entries: [WikiVaultIndex.Entry]

        var displayTitle: String { entries.first?.title ?? noteID }
    }

    /// Note IDs with more than one entry in `index`, each group's own
    /// entries sorted newest-exported first (entries with no `exportedDay`
    /// sort last, since there's nothing to prefer them by).
    static func duplicateGroups(in index: [String: [WikiVaultIndex.Entry]]) -> [Group] {
        index
            .compactMap { noteID, entries -> Group? in
                guard entries.count > 1 else { return nil }
                let sorted = entries.sorted { lhs, rhs in
                    switch (lhs.exportedDay, rhs.exportedDay) {
                    case let (l?, r?): return l > r
                    case (nil, nil): return false
                    case (nil, _): return false
                    case (_, nil): return true
                    }
                }
                return Group(noteID: noteID, entries: sorted)
            }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    /// A pair of entries with different `apple_note_id`s whose content is
    /// similar enough to be a likely duplicate — e.g. a note manually
    /// duplicated in Apple Notes, or content pasted into a second note.
    /// Same-ID entries are excluded; `duplicateGroups` already covers those.
    struct PossibleDuplicatePair: Sendable, Equatable, Identifiable {
        var id: String { entryA.markdownPath.path + "|" + entryB.markdownPath.path }
        let entryA: WikiVaultIndex.Entry
        let entryB: WikiVaultIndex.Entry
        let similarity: Double
    }

    /// Every cross-note pair whose content-similarity meets `threshold`,
    /// sorted by similarity descending. `O(n^2)` in the number of entries —
    /// fine at personal-wiki scale.
    static func possibleDuplicatePairs(
        in index: [String: [WikiVaultIndex.Entry]],
        threshold: Double = WikiContentSimilarity.defaultThreshold
    ) -> [PossibleDuplicatePair] {
        let entries = index.flatMap { $0.value }
        guard entries.count > 1 else { return [] }

        let shingleSets = entries.map { WikiContentSimilarity.shingles(of: $0.content) }
        var pairs: [PossibleDuplicatePair] = []
        for i in 0..<(entries.count - 1) {
            for j in (i + 1)..<entries.count {
                let a = entries[i]
                let b = entries[j]
                guard a.noteID != b.noteID else { continue }
                let similarity = WikiContentSimilarity.jaccardSimilarity(shingleSets[i], shingleSets[j])
                guard similarity >= threshold else { continue }
                pairs.append(PossibleDuplicatePair(entryA: a, entryB: b, similarity: similarity))
            }
        }
        return pairs.sorted { $0.similarity > $1.similarity }
    }
}
