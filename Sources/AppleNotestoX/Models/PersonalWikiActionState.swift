import Foundation

enum PersonalWikiActionState: Equatable {
    case selectNotes
    case chooseVault(noteCount: Int)
    case ready(noteCount: Int)
    case exporting(done: Int, total: Int)
    case completed(done: Int, failed: Int)

    static func resolve(
        selectedCount: Int,
        hasVault: Bool,
        isExporting: Bool,
        progress: [WikiExportProgress]
    ) -> Self {
        let done = progress.filter { if case .done = $0.status { true } else { false } }.count
        let failed = progress.filter { if case .failed = $0.status { true } else { false } }.count

        if isExporting {
            return .exporting(done: done, total: max(selectedCount, progress.count))
        }
        if !progress.isEmpty, done + failed == progress.count {
            return .completed(done: done, failed: failed)
        }
        guard selectedCount > 0 else { return .selectNotes }
        guard hasVault else { return .chooseVault(noteCount: selectedCount) }
        return .ready(noteCount: selectedCount)
    }
}
