import Foundation

/// Orchestrates fetching selected notes, categorizing them via Groq, staging
/// attachments, and assembling one merged HTML document — mirrors the
/// progress-streaming pattern of `WikiExportCoordinator`/`ArchiveCoordinator`.
/// Source notes are never modified or deleted.
actor MergeCoordinator {
    private let notes: AppleNotesService
    private let groq: GroqService
    private let assets: TriageAssetStore
    private let embedImagesSupported: Bool

    init(
        notes: AppleNotesService,
        groq: GroqService,
        assets: TriageAssetStore = TriageAssetStore(),
        embedImagesSupported: Bool = MergeFeatureFlags.embedImagesSupported
    ) {
        self.notes = notes
        self.groq = groq
        self.assets = assets
        self.embedImagesSupported = embedImagesSupported
    }

    nonisolated func run(job: MergeJob, hierarchy: AppleNotesHierarchy) -> AsyncStream<MergeStage> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let draft = try await self.buildDraft(job: job, hierarchy: hierarchy, continuation: continuation)
                    continuation.yield(.readyForPreview(draft))
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildDraft(
        job: MergeJob,
        hierarchy: AppleNotesHierarchy,
        continuation: AsyncStream<MergeStage>.Continuation
    ) async throws -> MergeDraft {
        let runDirectory = try await assets.makeRunDirectory()
        var succeeded = false
        defer {
            // On failure no draft was ever returned, so nothing references this
            // run directory — clean it up unconditionally. The "keep it around
            // when embeds are unsupported" rule from the spec applies only to
            // the success path, handled by `write(draft:)` below.
            if !succeeded {
                Task { await assets.deleteRunDirectory(runDirectory) }
            }
        }

        var sourceNotes: [MergeSourceNote] = []
        var stagedImages: [String: [StagedImage]] = [:]
        var done = 0
        let total = job.noteIDs.count
        continuation.yield(.fetching(done: done, total: total))

        for noteID in job.noteIDs {
            let content = try await notes.fetchNote(id: noteID)
            defer { AppleNotesService.cleanupTemporaryAttachments(in: content) }

            let title = hierarchy.notes[noteID]?.name ?? "(untitled)"
            let plainText = PlainTextExtractor.extract(html: content.html)
            sourceNotes.append(MergeSourceNote(noteID: noteID, title: title, plainText: plainText))

            var images: [StagedImage] = []
            for attachment in content.attachments {
                let staged = try await assets.stage(
                    fileAt: attachment.localURL,
                    filename: TriageAssetStore.sanitizedPathComponent(noteID)
                        + "-"
                        + TriageAssetStore.sanitizedPathComponent(attachment.filename),
                    into: runDirectory
                )
                images.append(StagedImage(sourceNoteID: noteID, sourceNoteTitle: title, localURL: staged))
            }
            if !images.isEmpty { stagedImages[noteID] = images }

            done += 1
            continuation.yield(.fetching(done: done, total: total))
        }

        continuation.yield(.categorizing)
        let sections = try await groq.categorize(notes: sourceNotes)

        continuation.yield(.assembling)
        let titleLine = MergeAssembler.titleLine()
        let bodyHTML = MergeAssembler.assembleHTML(
            sections: sections,
            titleLine: titleLine,
            stagedImages: stagedImages,
            embedImages: embedImagesSupported,
            runDirectory: runDirectory
        )

        succeeded = true
        return MergeDraft(
            titleLine: titleLine,
            sections: sections,
            bodyHTML: bodyHTML,
            runDirectory: runDirectory,
            imagesEmbedded: embedImagesSupported
        )
    }

    func write(draft: MergeDraft) async throws -> String {
        let noteID: String
        do {
            noteID = try await notes.createNote(bodyHTML: draft.bodyHTML)
        } catch {
            // Nothing references the staged files once the write fails, so
            // clean up rather than leaking the run directory — same rule as
            // `buildDraft`'s failure path.
            await assets.deleteRunDirectory(draft.runDirectory)
            throw error
        }
        // When images were embedded inline, the staged copies are no longer
        // needed once the note exists. When embedding was unsupported, the
        // merged note's text only references these files by path — they are
        // the only copy, so they must survive the write. See spec "Risk:
        // Image Embedding" fallback.
        if draft.imagesEmbedded {
            await assets.deleteRunDirectory(draft.runDirectory)
        }
        return noteID
    }

    func discard(draft: MergeDraft) async {
        await assets.deleteRunDirectory(draft.runDirectory)
    }
}
