import Foundation

struct AppleFolder: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let accountName: String
    let parentID: String?
    var childFolderIDs: [String]
    var noteIDs: [String]
}

struct AppleNote: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let folderID: String
    let modifiedAt: Date
}

struct AppleNotesHierarchy: Sendable {
    let folders: [String: AppleFolder]
    let notes: [String: AppleNote]
    let rootFolderIDs: [String]

    /// All note IDs contained in the given folder and, recursively, its
    /// subfolders. Cycle-safe (guards against a folder graph that loops)
    /// and de-duplicates repeated note/child references.
    func allNoteIDs(underFolder folderID: String) -> [String] {
        var seenFolders: Set<String> = []
        var seenNotes: Set<String> = []
        var result: [String] = []

        func visit(_ id: String) {
            guard seenFolders.insert(id).inserted, let folder = folders[id] else { return }
            for noteID in folder.noteIDs where seenNotes.insert(noteID).inserted {
                result.append(noteID)
            }
            for childID in folder.childFolderIDs {
                visit(childID)
            }
        }

        visit(folderID)
        return result
    }
}

struct AppleNoteContent: Sendable {
    let html: String
    let attachments: [AppleNoteAttachment]
}

struct AppleNoteAttachment: Sendable {
    let id: String
    let filename: String
    let localURL: URL
}
