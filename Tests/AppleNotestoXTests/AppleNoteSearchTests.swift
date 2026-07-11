import XCTest
@testable import AppleNotestoX

final class AppleNoteSearchTests: XCTestCase {
    private let cafePlan = AppleNote(
        id: "cafe-plan",
        name: "Cafe Plan",
        folderID: "ideas",
        modifiedAt: Date(timeIntervalSince1970: 200)
    )
    private let resume = AppleNote(
        id: "resume",
        name: "Résumé",
        folderID: "ideas",
        modifiedAt: Date(timeIntervalSince1970: 100)
    )
    private let weeklyReview = AppleNote(
        id: "weekly-review",
        name: "Weekly Review",
        folderID: "personal",
        modifiedAt: Date(timeIntervalSince1970: 100)
    )

    private var hierarchy: AppleNotesHierarchy {
        AppleNotesHierarchy(
            folders: [
                "personal": AppleFolder(
                    id: "personal",
                    name: "Personal",
                    accountName: "iCloud",
                    parentID: nil,
                    childFolderIDs: ["ideas", "ideas"],
                    noteIDs: ["weekly-review"]
                ),
                "ideas": AppleFolder(
                    id: "ideas",
                    name: "Ideas",
                    accountName: "iCloud",
                    parentID: "personal",
                    childFolderIDs: [],
                    noteIDs: ["cafe-plan", "resume", "cafe-plan"]
                ),
            ],
            notes: [
                cafePlan.id: cafePlan,
                resume.id: resume,
                weeklyReview.id: weeklyReview,
            ],
            rootFolderIDs: ["personal"]
        )
    }

    func testEmptyQueryReturnsNilForHierarchyMode() {
        XCTAssertNil(AppleNoteSearch.results(in: hierarchy, matching: " \n "))
    }

    func testMatchesTitlesAndReturnsFolderPaths() {
        let results = AppleNoteSearch.results(in: hierarchy, matching: "cafe")

        XCTAssertEqual(results?.map(\.note.id), ["cafe-plan"])
        XCTAssertEqual(results?.first?.folderPath, "Personal / Ideas")
    }

    func testMatchesDiacriticsInTitles() {
        XCTAssertEqual(
            AppleNoteSearch.results(in: hierarchy, matching: "resume")?.map(\.note.id),
            ["resume"]
        )
    }

    func testMatchesAncestorFoldersWithoutDuplicateNotes() {
        let results = AppleNoteSearch.results(in: hierarchy, matching: "personal")

        XCTAssertEqual(results?.map(\.note.id), ["cafe-plan", "resume", "weekly-review"])
        XCTAssertEqual(Set(results?.map(\.note.id) ?? []).count, 3)
    }

    func testOrdersByModifiedDateThenTitle() {
        XCTAssertEqual(
            AppleNoteSearch.results(in: hierarchy, matching: "personal")?.map(\.note.name),
            ["Cafe Plan", "Résumé", "Weekly Review"]
        )
    }

    func testOrdersEqualDatesAndCaseInsensitiveTitlesByNoteIDAscending() {
        let modifiedAt = Date(timeIntervalSince1970: 300)
        let notes = [
            AppleNote(id: "note-z", name: "Same Title", folderID: "personal", modifiedAt: modifiedAt),
            AppleNote(id: "note-a", name: "same title", folderID: "personal", modifiedAt: modifiedAt),
        ]
        let equalHierarchy = AppleNotesHierarchy(
            folders: [
                "personal": AppleFolder(
                    id: "personal",
                    name: "Personal",
                    accountName: "iCloud",
                    parentID: nil,
                    childFolderIDs: [],
                    noteIDs: notes.map(\.id)
                )
            ],
            notes: Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) }),
            rootFolderIDs: ["personal"]
        )

        XCTAssertEqual(
            AppleNoteSearch.results(in: equalHierarchy, matching: "same title")?.map(\.note.id),
            ["note-a", "note-z"]
        )
    }
}
