import Foundation

struct MergeSourceNote: Sendable, Equatable {
    let noteID: String
    let title: String
    let plainText: String
}

struct MergeSection: Sendable, Equatable, Codable {
    let header: String
    let bodyText: String
    let sourceNoteIDs: [String]

    enum CodingKeys: String, CodingKey {
        case header
        case bodyText = "body"
        case sourceNoteIDs = "source_note_ids"
    }
}

struct StagedImage: Sendable, Equatable {
    let sourceNoteID: String
    let sourceNoteTitle: String
    let localURL: URL
}

struct MergeDraft: Sendable, Equatable {
    let titleLine: String
    let sections: [MergeSection]
    let bodyHTML: String
    let runDirectory: URL
    let imagesEmbedded: Bool
}

struct MergeJob: Sendable {
    let noteIDs: [String]
}

enum MergeStage: Sendable, Equatable {
    case fetching(done: Int, total: Int)
    case categorizing
    case assembling
    case readyForPreview(MergeDraft)
    case writing
    case completed(noteID: String)
    case failed(message: String)
}
