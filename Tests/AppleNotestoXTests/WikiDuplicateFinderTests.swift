import XCTest
@testable import AppleNotestoX

final class WikiDuplicateFinderTests: XCTestCase {
    private func entry(
        noteID: String, day: String, exported: String? = nil, title: String? = nil, filename: String
    ) -> WikiVaultIndex.Entry {
        WikiVaultIndex.Entry(
            noteID: noteID, noteModifiedDay: day, exportedDay: exported, title: title,
            markdownPath: URL(fileURLWithPath: "/vault/raw/journal/\(filename)")
        )
    }

    func test_duplicateGroups_onlyIncludesNoteIDsWithMoreThanOneEntry() {
        let index: [String: [WikiVaultIndex.Entry]] = [
            "A": [entry(noteID: "A", day: "2026-01-01", filename: "a.md")],
            "B": [
                entry(noteID: "B", day: "2026-01-01", filename: "b.md"),
                entry(noteID: "B", day: "2026-01-01", filename: "b-2.md"),
            ],
        ]

        let groups = WikiDuplicateFinder.duplicateGroups(in: index)

        XCTAssertEqual(groups.map(\.noteID), ["B"])
        XCTAssertEqual(groups[0].entries.count, 2)
    }

    func test_duplicateGroups_sortsEntriesNewestExportedFirst() {
        let index: [String: [WikiVaultIndex.Entry]] = [
            "A": [
                entry(noteID: "A", day: "2026-01-01", exported: "2026-01-01", filename: "old.md"),
                entry(noteID: "A", day: "2026-01-05", exported: "2026-01-05", filename: "new.md"),
            ]
        ]

        let groups = WikiDuplicateFinder.duplicateGroups(in: index)

        XCTAssertEqual(groups[0].entries.map(\.markdownPath.lastPathComponent), ["new.md", "old.md"])
    }

    func test_duplicateGroups_entriesWithNoExportedDaySortLast() {
        let index: [String: [WikiVaultIndex.Entry]] = [
            "A": [
                entry(noteID: "A", day: "2026-01-01", exported: nil, filename: "no-date.md"),
                entry(noteID: "A", day: "2026-01-01", exported: "2026-01-05", filename: "dated.md"),
            ]
        ]

        let groups = WikiDuplicateFinder.duplicateGroups(in: index)

        XCTAssertEqual(groups[0].entries.map(\.markdownPath.lastPathComponent), ["dated.md", "no-date.md"])
    }

    func test_duplicateGroups_sortsGroupsByDisplayTitle() {
        let index: [String: [WikiVaultIndex.Entry]] = [
            "zebra-id": [
                entry(noteID: "zebra-id", day: "2026-01-01", title: "Zebra", filename: "z1.md"),
                entry(noteID: "zebra-id", day: "2026-01-01", title: "Zebra", filename: "z2.md"),
            ],
            "apple-id": [
                entry(noteID: "apple-id", day: "2026-01-01", title: "Apple", filename: "a1.md"),
                entry(noteID: "apple-id", day: "2026-01-01", title: "Apple", filename: "a2.md"),
            ],
        ]

        let groups = WikiDuplicateFinder.duplicateGroups(in: index)

        XCTAssertEqual(groups.map(\.displayTitle), ["Apple", "Zebra"])
    }

    func test_duplicateGroups_displayTitleFallsBackToNoteID() {
        let index: [String: [WikiVaultIndex.Entry]] = [
            "note-id-only": [
                entry(noteID: "note-id-only", day: "2026-01-01", title: nil, filename: "1.md"),
                entry(noteID: "note-id-only", day: "2026-01-01", title: nil, filename: "2.md"),
            ]
        ]

        XCTAssertEqual(WikiDuplicateFinder.duplicateGroups(in: index)[0].displayTitle, "note-id-only")
    }

    func test_duplicateGroups_emptyIndex_returnsNoGroups() {
        XCTAssertEqual(WikiDuplicateFinder.duplicateGroups(in: [:]), [])
    }
}
