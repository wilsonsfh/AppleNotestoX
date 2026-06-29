import Foundation

struct NotionPage: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let parentID: String?
    var hasChildren: Bool
}

struct NotionRichText: Sendable, Equatable {
    var content: String
    var bold: Bool = false
    var italic: Bool = false
    var strikethrough: Bool = false
    var underline: Bool = false
    var code: Bool = false
    var link: URL? = nil
}

enum NotionBlock: Sendable, Equatable {
    case paragraph([NotionRichText])
    case heading1([NotionRichText])
    case heading2([NotionRichText])
    case heading3([NotionRichText])
    case bulletedListItem([NotionRichText])
    case numberedListItem([NotionRichText])
    case toDo([NotionRichText], checked: Bool)
    case quote([NotionRichText])
    case code([NotionRichText], language: String)
    case divider
    case imagePlaceholder(id: UUID, localPath: URL)
    case imageUploaded(fileUploadID: String)
    case imageFailed(message: String)
}
