import Foundation

enum PostArchiveDisposition: String, Sendable, CaseIterable, Identifiable {
    case leave
    case moveToArchivedFolder
    case delete
    var id: String { rawValue }

    var label: String {
        switch self {
        case .leave: return "Leave original in Apple Notes"
        case .moveToArchivedFolder: return "Move original to 'Archived' folder"
        case .delete: return "Delete original"
        }
    }
}

struct ArchiveJob: Sendable {
    /// Notes to archive. Each note becomes a new Notion sub-page under `parentPageID`,
    /// titled with the Apple Notes name.
    let noteIDs: [String]
    let parentPageID: String
    let disposition: PostArchiveDisposition
}

enum NoteArchiveStatus: Sendable, Equatable {
    case pending
    case fetching
    case converting
    case uploadingImages(done: Int, total: Int)
    case writingBlocks
    case dispositioning
    case done(notionPageID: String)
    case failed(message: String)
}

struct NoteArchiveProgress: Sendable, Identifiable {
    let id: String
    let title: String
    var status: NoteArchiveStatus
}
