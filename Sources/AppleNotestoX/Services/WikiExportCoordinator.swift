import Foundation

/// Orchestrates exporting selected Apple Notes into the wiki vault, streaming a
/// snapshot of per-note progress on every change (same pattern as `ArchiveCoordinator`).
/// The source notes are never modified.
actor WikiExportCoordinator {
    private let notes: AppleNotesService
    private let assembler: WikiExportAssembler
    private let videoCoordinator: VideoIngestCoordinator

    init(
        notes: AppleNotesService,
        assembler: WikiExportAssembler = WikiExportAssembler(),
        videoCoordinator: VideoIngestCoordinator = VideoIngestCoordinator()
    ) {
        self.notes = notes
        self.assembler = assembler
        self.videoCoordinator = videoCoordinator
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

                let vaultIndex = WikiVaultIndex.scan(journalDir: job.config.journalDir)

                for (idx, noteID) in job.noteIDs.enumerated() {
                    do {
                        try await self.exportOne(
                            idx: idx,
                            noteID: noteID,
                            job: job,
                            hierarchy: hierarchy,
                            vaultIndex: vaultIndex,
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
        vaultIndex: [String: [WikiVaultIndex.Entry]],
        update: @Sendable (Int, WikiExportStatus) -> Void
    ) async throws {
        let note = hierarchy.notes[noteID]
        let title = note?.name ?? "(untitled)"
        let modified = note?.modifiedAt ?? Date()

        // Dedup check against the vault's existing exports, using the
        // modified date already in `hierarchy` — no need to fetch the note's
        // content just to decide it hasn't changed since last time.
        if let noteModified = note?.modifiedAt,
           WikiVaultIndex.isUpToDate(noteID: noteID, modified: noteModified, index: vaultIndex) {
            update(idx, .skipped(reason: "Already exported and unchanged"))
            return
        }

        update(idx, .fetching)
        let content = try await notes.fetchNote(id: noteID)
        defer { AppleNotesService.cleanupTemporaryAttachments(in: content) }

        update(idx, .converting)

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

        // Optionally transcribe any video attachments into sibling transcript notes.
        if job.transcribeVideos {
            for attachment in content.attachments where VideoSupport.isVideo(url: attachment.localURL) {
                _ = try? await videoCoordinator.ingest(
                    videoURL: attachment.localURL,
                    title: "\(title) — video",
                    modified: modified,
                    config: job.config,
                    sourceApp: "apple-notes"
                )
            }
        }

        update(idx, .done(result: result))
    }
}
