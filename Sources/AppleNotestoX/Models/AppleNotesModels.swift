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
