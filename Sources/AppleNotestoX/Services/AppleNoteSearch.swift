import Foundation

struct AppleNoteSearchResult: Identifiable, Equatable {
    let note: AppleNote
    let folderPath: String

    var id: String { note.id }
}

enum AppleNoteSearch {
    static func results(in hierarchy: AppleNotesHierarchy, matching rawQuery: String) -> [AppleNoteSearchResult]? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        return hierarchy.notes.values.compactMap { note in
            let path = folderPath(for: note.folderID, in: hierarchy)
            guard matches(note.name, query) || matches(path, query) else { return nil }
            return AppleNoteSearchResult(note: note, folderPath: path)
        }.sorted {
            if $0.note.modifiedAt != $1.note.modifiedAt {
                return $0.note.modifiedAt > $1.note.modifiedAt
            }
            let titleOrder = $0.note.name.localizedCaseInsensitiveCompare($1.note.name)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return $0.note.id < $1.note.id
        }
    }

    private static func matches(_ value: String, _ query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func folderPath(for folderID: String, in hierarchy: AppleNotesHierarchy) -> String {
        var names: [String] = []
        var currentID: String? = folderID
        var visited: Set<String> = []
        while let id = currentID, visited.insert(id).inserted, let folder = hierarchy.folders[id] {
            names.append(folder.name)
            currentID = folder.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}
