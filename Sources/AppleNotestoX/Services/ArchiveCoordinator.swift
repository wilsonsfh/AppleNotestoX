import Foundation

actor ArchiveCoordinator {
    private let notes: AppleNotesService
    private let notion: NotionService
    private let images: ImagePipeline
    private let log: ArchiveLog
    private let archivedFolderName: String

    init(
        notes: AppleNotesService,
        notion: NotionService,
        images: ImagePipeline,
        log: ArchiveLog,
        archivedFolderName: String = "Archived"
    ) {
        self.notes = notes
        self.notion = notion
        self.images = images
        self.log = log
        self.archivedFolderName = archivedFolderName
    }

    /// Runs an archive job. Streams a snapshot of all per-note progress on every change.
    /// The stream ends when the batch finishes (success or partial failure).
    nonisolated func archive(job: ArchiveJob, hierarchy: AppleNotesHierarchy) -> AsyncStream<[NoteArchiveProgress]> {
        AsyncStream { continuation in
            let task = Task {
                nonisolated(unsafe) var progresses: [NoteArchiveProgress] = job.noteIDs.map { id in
                    let title = hierarchy.notes[id]?.name ?? id
                    return NoteArchiveProgress(id: id, title: title, status: .pending)
                }

                @Sendable func snapshot() -> [NoteArchiveProgress] { progresses }
                @Sendable func update(_ idx: Int, _ status: NoteArchiveStatus) {
                    progresses[idx].status = status
                    continuation.yield(snapshot())
                }

                continuation.yield(snapshot())

                for (idx, noteID) in job.noteIDs.enumerated() {
                    do {
                        try await self.archiveOne(
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

    private func archiveOne(
        idx: Int,
        noteID: String,
        job: ArchiveJob,
        hierarchy: AppleNotesHierarchy,
        update: @Sendable (Int, NoteArchiveStatus) -> Void
    ) async throws {
        update(idx, .fetching)
        let content = try await notes.fetchNote(id: noteID)
        defer { AppleNotesService.cleanupTemporaryAttachments(in: content) }

        update(idx, .converting)
        var blocks = NoteConverter.convert(html: content.html, attachments: content.attachments)

        let placeholderIndices: [Int] = blocks.indices.filter {
            if case .imagePlaceholder = blocks[$0] { return true } else { return false }
        }
        if !placeholderIndices.isEmpty {
            update(idx, .uploadingImages(done: 0, total: placeholderIndices.count))
            var done = 0
            for blockIdx in placeholderIndices {
                if case .imagePlaceholder(_, let path) = blocks[blockIdx] {
                    do {
                        let id = try await images.uploadResized(localURL: path)
                        blocks[blockIdx] = .imageUploaded(fileUploadID: id)
                    } catch {
                        blocks[blockIdx] = .imageFailed(message: error.localizedDescription)
                    }
                }
                done += 1
                update(idx, .uploadingImages(done: done, total: placeholderIndices.count))
            }
        }

        let title = hierarchy.notes[noteID]?.name ?? "(untitled)"
        let newPageID = try await notion.createPage(parentID: job.parentPageID, title: title)

        update(idx, .writingBlocks)
        try await notion.appendBlocks(blocks, to: newPageID)

        update(idx, .dispositioning)
        switch job.disposition {
        case .leave:
            break
        case .moveToArchivedFolder:
            if let note = hierarchy.notes[noteID],
               let folder = hierarchy.folders[note.folderID] {
                try await notes.moveNote(id: noteID, toFolderNamed: archivedFolderName, in: folder.accountName)
            }
        case .delete:
            try await notes.deleteNote(id: noteID)
        }

        await log.record(noteID: noteID, notionPageID: newPageID)
        update(idx, .done(notionPageID: newPageID))
    }
}
