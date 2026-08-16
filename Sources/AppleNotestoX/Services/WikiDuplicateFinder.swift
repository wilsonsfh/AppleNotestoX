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
}
