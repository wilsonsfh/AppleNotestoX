import XCTest
@testable import AppleNotestoX

final class MergeBatchingTests: XCTestCase {
    private func note(_ id: String, chars: Int) -> MergeSourceNote {
        MergeSourceNote(noteID: id, title: id, plainText: String(repeating: "x", count: chars))
    }

    func test_batches_singleSmallBatch_whenUnderBudget() {
        let notes = [note("A", chars: 10), note("B", chars: 10), note("C", chars: 10)]

        let batches = MergeBatching.batches(for: notes)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].map(\.noteID), ["A", "B", "C"])
    }

    func test_batches_splitsOnCharacterBudget() {
        let notes = [
            note("A", chars: MergeBatching.maxCharactersPerBatch - 100),
            note("B", chars: 200),
        ]

        let batches = MergeBatching.batches(for: notes)

        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0].map(\.noteID), ["A"])
        XCTAssertEqual(batches[1].map(\.noteID), ["B"])
    }

    func test_batches_splitsOnNoteCountEvenWhenCharactersAreTiny() {
        let notes = (0..<(MergeBatching.maxNotesPerBatch + 5)).map { note("n\($0)", chars: 1) }

        let batches = MergeBatching.batches(for: notes)

        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0].count, MergeBatching.maxNotesPerBatch)
        XCTAssertEqual(batches[1].count, 5)
    }

    func test_batches_oversizedSingleNoteGetsItsOwnBatch() {
        let notes = [note("huge", chars: MergeBatching.maxCharactersPerBatch * 2), note("small", chars: 10)]

        let batches = MergeBatching.batches(for: notes)

        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0].map(\.noteID), ["huge"])
        XCTAssertEqual(batches[1].map(\.noteID), ["small"])
    }

    func test_batches_emptyInput_returnsNoBatches() {
        XCTAssertEqual(MergeBatching.batches(for: []), [])
    }

    func test_mergeBatchResults_combinesMatchingHeadersCaseAndWhitespaceInsensitively() {
        let batch1 = [MergeSection(header: "Work", bodyText: "First half", sourceNoteIDs: ["A"])]
        let batch2 = [MergeSection(header: "  work  ", bodyText: "Second half", sourceNoteIDs: ["B"])]

        let merged = MergeBatching.mergeBatchResults([batch1, batch2])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].header, "Work")
        XCTAssertEqual(merged[0].bodyText, "First half\n\nSecond half")
        XCTAssertEqual(merged[0].sourceNoteIDs, ["A", "B"])
    }

    func test_mergeBatchResults_keepsDistinctHeadersSeparate() {
        let batch1 = [MergeSection(header: "Work", bodyText: "W", sourceNoteIDs: ["A"])]
        let batch2 = [MergeSection(header: "Health", bodyText: "H", sourceNoteIDs: ["B"])]

        let merged = MergeBatching.mergeBatchResults([batch1, batch2])

        XCTAssertEqual(merged.map(\.header), ["Work", "Health"])
    }

    func test_mergeBatchResults_dedupesSourceNoteIDsOnMerge() {
        let batch1 = [MergeSection(header: "Work", bodyText: "W1", sourceNoteIDs: ["A", "B"])]
        let batch2 = [MergeSection(header: "Work", bodyText: "W2", sourceNoteIDs: ["B", "C"])]

        let merged = MergeBatching.mergeBatchResults([batch1, batch2])

        XCTAssertEqual(merged[0].sourceNoteIDs, ["A", "B", "C"])
    }

    func test_mergeBatchResults_emptyInput_returnsEmpty() {
        XCTAssertEqual(MergeBatching.mergeBatchResults([]), [])
    }
}
