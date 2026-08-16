import XCTest
@testable import AppleNotestoX

final class AppleNotesHierarchyTests: XCTestCase {
    private func note(_ id: String, folderID: String) -> AppleNote {
        AppleNote(id: id, name: id, folderID: folderID, modifiedAt: Date(timeIntervalSince1970: 0))
    }

    func test_allNoteIDs_collectsNotesFromSubfoldersRecursively() {
        let hierarchy = AppleNotesHierarchy(
            folders: [
                "personal": AppleFolder(
                    id: "personal", name: "Personal", accountName: "iCloud", parentID: nil,
                    childFolderIDs: ["ideas"], noteIDs: ["weekly-review"]
                ),
                "ideas": AppleFolder(
                    id: "ideas", name: "Ideas", accountName: "iCloud", parentID: "personal",
                    childFolderIDs: ["archive"], noteIDs: ["cafe-plan", "resume"]
                ),
                "archive": AppleFolder(
                    id: "archive", name: "Archive", accountName: "iCloud", parentID: "ideas",
                    childFolderIDs: [], noteIDs: ["old-idea"]
                ),
            ],
            notes: [:],
            rootFolderIDs: ["personal"]
        )

        let ids = hierarchy.allNoteIDs(underFolder: "personal")

        XCTAssertEqual(Set(ids), ["weekly-review", "cafe-plan", "resume", "old-idea"])
    }

    func test_allNoteIDs_deduplicatesRepeatedNoteAndChildReferences() {
        let hierarchy = AppleNotesHierarchy(
            folders: [
                "personal": AppleFolder(
                    id: "personal", name: "Personal", accountName: "iCloud", parentID: nil,
                    childFolderIDs: ["ideas", "ideas"], noteIDs: ["weekly-review"]
                ),
                "ideas": AppleFolder(
                    id: "ideas", name: "Ideas", accountName: "iCloud", parentID: "personal",
                    childFolderIDs: [], noteIDs: ["cafe-plan", "cafe-plan"]
                ),
            ],
            notes: [:],
            rootFolderIDs: ["personal"]
        )

        let ids = hierarchy.allNoteIDs(underFolder: "personal")

        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids), ["weekly-review", "cafe-plan"])
    }

    func test_allNoteIDs_guardsAgainstFolderCycle() {
        let hierarchy = AppleNotesHierarchy(
            folders: [
                "a": AppleFolder(
                    id: "a", name: "A", accountName: "iCloud", parentID: nil,
                    childFolderIDs: ["b"], noteIDs: ["note-a"]
                ),
                "b": AppleFolder(
                    id: "b", name: "B", accountName: "iCloud", parentID: "a",
                    childFolderIDs: ["a"], noteIDs: ["note-b"]
                ),
            ],
            notes: [:],
            rootFolderIDs: ["a"]
        )

        let ids = hierarchy.allNoteIDs(underFolder: "a")

        XCTAssertEqual(Set(ids), ["note-a", "note-b"])
    }

    func test_allNoteIDs_unknownFolderReturnsEmpty() {
        let hierarchy = AppleNotesHierarchy(folders: [:], notes: [:], rootFolderIDs: [])

        XCTAssertEqual(hierarchy.allNoteIDs(underFolder: "missing"), [])
    }
}
