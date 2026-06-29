import Foundation

actor ArchiveLog {
    struct Entry: Codable, Sendable {
        let appleNoteID: String
        let archivedAt: Date
        let notionPageID: String
    }

    private var entries: [String: Entry] = [:]
    private let url: URL

    init() {
        let dir = (try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("AppleNotestoX") ??
            FileManager.default.temporaryDirectory.appendingPathComponent("AppleNotestoX")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("archive_log.json")
    }

    func loadFromDisk() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let arr = try? dec.decode([Entry].self, from: data) {
            entries = Dictionary(uniqueKeysWithValues: arr.map { ($0.appleNoteID, $0) })
        }
    }

    func record(noteID: String, notionPageID: String) {
        entries[noteID] = Entry(appleNoteID: noteID, archivedAt: Date(), notionPageID: notionPageID)
        saveToDisk()
    }

    func isArchived(noteID: String) -> Bool {
        entries[noteID] != nil
    }

    func entry(for noteID: String) -> Entry? {
        entries[noteID]
    }

    func allEntries() -> [Entry] {
        Array(entries.values)
    }


    private func saveToDisk() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(Array(entries.values)) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
