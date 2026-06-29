import Foundation

/// Orchestrates exporting selected Apple Notes into the wiki vault, streaming a
/// snapshot of per-note progress on every change (same pattern as `ArchiveCoordinator`).
/// The source notes are never modified.
actor WikiExportCoordinator {
    private let notes: AppleNotesService
    private let assembler: WikiExportAssembler

    init(notes: AppleNotesService, assembler: WikiExportAssembler = WikiExportAssembler()) {
        self.notes = notes
        self.assembler = assembler
    }

    nonisolated func export(job: WikiExportJob, hierarchy: AppleNotesHierarchy) -> AsyncStream<[WikiExportProgress]> {
        AsyncStream { continuation in
            let task = Task {
                nonisolated(unsafe) var progresses: [WikiExportProgress] = job.noteIDs.map { id in
                    WikiExportProgress(id: id, title: hierarchy.notes[id]?.name ?? id, status: .pending)
                }

                @Sendable func snapshot() -> [WikiExportProgress] { progresses }
                @Sendable func update(_ idx: Int, _ status: WikiExportStatus) {
                    progresses[idx].status = status
                    continuation.yield(snapshot())
                }

                continuation.yield(snapshot())

                for (idx, noteID) in job.noteIDs.enumerated() {
                    do {
                        try await self.exportOne(
                            idx: idx,
                            noteID: noteID,
                            job: job,
                            hierarchy: hierarchy,
                            update: update
                        )
                    } catch {
                        update(idx, .failed(message: error.localizedDescription))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func exportOne(
        idx: Int,
        noteID: String,
        job: WikiExportJob,
        hierarchy: AppleNotesHierarchy,
        update: @Sendable (Int, WikiExportStatus) -> Void
    ) async throws {
        update(idx, .fetching)
        let content = try await notes.fetchNote(id: noteID)

        update(idx, .converting)
        let note = hierarchy.notes[noteID]
        let title = note?.name ?? "(untitled)"
        let modified = note?.modifiedAt ?? Date()

        update(idx, .savingAssets(done: 0, total: content.attachments.count))
        let result = try assembler.assemble(
            noteID: noteID,
            title: title,
            modified: modified,
            content: content,
            config: job.config,
            exported: Date()
        )

        update(idx, .writing)
        update(idx, .done(result: result))
    }
}
