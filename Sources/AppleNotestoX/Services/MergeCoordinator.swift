import Foundation

/// Orchestrates fetching selected notes, categorizing them via Groq, staging
/// attachments, and assembling one merged HTML document — mirrors the
/// progress-streaming pattern of `WikiExportCoordinator`/`ArchiveCoordinator`.
/// Source notes are never modified or deleted.
actor MergeCoordinator {
    private let notes: AppleNotesService
    private let groq: GroqService

    init(notes: AppleNotesService, groq: GroqService) {
        self.notes = notes
        self.groq = groq
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
        var sourceNotes: [MergeSourceNote] = []
        var done = 0
        let total = job.noteIDs.count
        continuation.yield(.fetching(done: done, total: total))

        for noteID in job.noteIDs {
            let content = try await notes.fetchNote(id: noteID)
            AppleNotesService.cleanupTemporaryAttachments(in: content)

            let title = hierarchy.notes[noteID]?.name ?? "(untitled)"
            let plainText = PlainTextExtractor.extract(html: content.html)
            sourceNotes.append(MergeSourceNote(noteID: noteID, title: title, plainText: plainText))

            done += 1
            continuation.yield(.fetching(done: done, total: total))
        }

        continuation.yield(.categorizing)
        // Large selections are split into request-sized batches so no single
        // categorization call is big enough to risk timing out; each later
        // batch is nudged to reuse earlier batches' headers so the merged
        // result doesn't end up with near-duplicate sections.
        let noteBatches = MergeBatching.batches(for: sourceNotes)
        var batchResults: [[MergeSection]] = []
        var headersSoFar: [String] = []
        for batch in noteBatches {
            let batchSections = try await groq.categorize(notes: batch, existingHeaders: headersSoFar)
            batchResults.append(batchSections)
            for section in batchSections
            where !headersSoFar.contains(where: { $0.caseInsensitiveCompare(section.header) == .orderedSame }) {
                headersSoFar.append(section.header)
            }
        }
        let sections = MergeBatching.mergeBatchResults(batchResults)

        continuation.yield(.assembling)
        let titleLine = MergeAssembler.titleLine()
        let sourceNoteTitles = Dictionary(uniqueKeysWithValues: sourceNotes.map { ($0.noteID, $0.title) })
        let bodyHTML = MergeAssembler.assembleHTML(
            sections: sections,
            titleLine: titleLine,
            sourceNoteTitles: sourceNoteTitles
        )

        return MergeDraft(titleLine: titleLine, sections: sections, bodyHTML: bodyHTML)
    }

    func write(draft: MergeDraft) async throws -> String {
        try await notes.createNote(bodyHTML: draft.bodyHTML)
    }
}
