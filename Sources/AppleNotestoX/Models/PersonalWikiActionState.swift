import Foundation

enum PersonalWikiActionState: Equatable {
    case selectNotes
    case chooseVault(noteCount: Int)
    case ready(noteCount: Int)
    case exporting(done: Int, total: Int)
    case completed(done: Int, failed: Int, skipped: Int)

    static func resolve(
        selectedCount: Int,
        hasVault: Bool,
        isExporting: Bool,
        progress: [WikiExportProgress]
    ) -> Self {
        let done = progress.filter { if case .done = $0.status { true } else { false } }.count
        let failed = progress.filter { if case .failed = $0.status { true } else { false } }.count
        let skipped = progress.filter { if case .skipped = $0.status { true } else { false } }.count
        let settled = done + failed + skipped

        if isExporting {
            // Skipped notes resolve instantly, so fold them into the visible
            // progress count same as successes; failures deliberately don't
            // count here (matches this counter's original done-only meaning).
            return .exporting(done: done + skipped, total: max(selectedCount, progress.count))
        }
        if !progress.isEmpty, settled == progress.count {
            return .completed(done: done, failed: failed, skipped: skipped)
        }
        guard selectedCount > 0 else { return .selectNotes }
        guard hasVault else { return .chooseVault(noteCount: selectedCount) }
        return .ready(noteCount: selectedCount)
    }
}
