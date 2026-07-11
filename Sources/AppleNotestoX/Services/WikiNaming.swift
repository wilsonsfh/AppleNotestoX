import Foundation
import Darwin

@_silgen_name("flock")
private func systemFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Naming, exclusive file publication, and provenance helpers for wiki exports.
enum WikiNaming {
    struct CreatedFile: Sendable {
        let url: URL
        fileprivate let identity: FileIdentity
    }

    fileprivate struct FileIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    /// Kebab-cases a note title for use in filenames: lowercased, non-alphanumerics
    /// collapsed to single hyphens, trimmed. Falls back to `"note"` when empty.
    static func slug(from title: String) -> String {
        let lower = title.lowercased()
        let mapped = lower.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let collapsed = String(mapped)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: "-")
        return collapsed.isEmpty ? "note" : collapsed
    }

    /// `YYYY-MM-DD` in a stable (UTC, POSIX) calendar so output is deterministic.
    static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// `YYYY-MM-DD-<slug>.md`
    static func markdownFilename(date: Date, slug: String) -> String {
        "\(isoDay(date))-\(slug).md"
    }

    /// `<slug>-NN.<ext>` with `NN` zero-padded to two digits and a lowercased extension.
    static func assetFilename(slug: String, index: Int, ext: String) -> String {
        let nn = String(format: "%02d", index)
        let cleaned = ext.lowercased()
        let safeExt = cleaned.isEmpty ? "dat" : cleaned
        return "\(slug)-\(nn).\(safeExt)"
    }

    /// Returns `name` if unused, otherwise appends `-2`, `-3`, … before the extension.
    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        let collisionKeys = Set(existing.map(collisionKey))
        guard collisionKeys.contains(collisionKey(name)) else { return name }
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            if !collisionKeys.contains(collisionKey(candidate)) { return candidate }
            i += 1
        }
    }

    /// Publishes complete data without replacing an existing filesystem entry.
    static func publish(data: Data, preferredName: String, in directory: URL) throws -> URL {
        try publishTracked(data: data, preferredName: preferredName, in: directory).url
    }

    static func publishTracked(data: Data, preferredName: String, in directory: URL) throws -> CreatedFile {
        let staging = directory.appendingPathComponent(".applenotestox-\(UUID().uuidString).tmp")
        try data.write(to: staging, options: .atomic)
        defer { try? FileManager.default.removeItem(at: staging) }
        return try publish(stagedFile: staging, preferredName: preferredName, in: directory)
    }

    /// Copies a complete file and publishes it without replacing an existing entry.
    static func copy(source: URL, preferredName: String, to directory: URL) throws -> URL {
        try copyTracked(source: source, preferredName: preferredName, to: directory).url
    }

    static func copyTracked(source: URL, preferredName: String, to directory: URL) throws -> CreatedFile {
        let staging = directory.appendingPathComponent(".applenotestox-\(UUID().uuidString).tmp")
        try FileManager.default.copyItem(at: source, to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        return try publish(stagedFile: staging, preferredName: preferredName, in: directory)
    }

    static func removeIfIdentityMatches(_ createdFile: CreatedFile) {
        try? withExclusiveDirectoryAccess(createdFile.url.deletingLastPathComponent()) {
            guard (try? fileIdentity(at: createdFile.url)) == createdFile.identity else { return }
            try FileManager.default.removeItem(at: createdFile.url)
        }
    }

    private static func publish(stagedFile: URL, preferredName: String, in directory: URL) throws -> CreatedFile {
        let identity = try fileIdentity(at: stagedFile)
        return try withExclusiveDirectoryAccess(directory) {
            var existing = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
            var candidate = uniqueName(preferredName, existing: existing)
            while true {
                let destination = directory.appendingPathComponent(candidate)
                do {
                    try FileManager.default.linkItem(at: stagedFile, to: destination)
                    return CreatedFile(url: destination, identity: identity)
                } catch where isDestinationExists(error) {
                    existing.insert(candidate)
                    existing.formUnion(try FileManager.default.contentsOfDirectory(atPath: directory.path))
                    candidate = uniqueName(preferredName, existing: existing)
                }
            }
        }
    }

    private static func fileIdentity(at url: URL) throws -> FileIdentity {
        var info = Darwin.stat()
        let status = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.lstat($0, &info) } ?? -1
        }
        guard status == 0 else { throw posixError(path: url.path) }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private static func collisionKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func withExclusiveDirectoryAccess<T>(_ directory: URL, _ body: () throws -> T) throws -> T {
        let descriptor = directory.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY) } ?? -1
        }
        guard descriptor >= 0 else { throw posixError(path: directory.path) }
        defer { Darwin.close(descriptor) }
        guard systemFlock(descriptor, LOCK_EX) == 0 else { throw posixError(path: directory.path) }
        defer { _ = systemFlock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func isDestinationExists(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EEXIST) { return true }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileWriteFileExists.rawValue { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isDestinationExists(underlying)
        }
        return false
    }

    private static func posixError(path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSFilePathErrorKey: path]
        )
    }

    /// Emits a YAML double-quoted scalar, escaping characters that could alter
    /// frontmatter structure or scalar meaning.
    static func yamlScalar(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: escaped += "\\\""
            case 0x5C: escaped += "\\\\"
            case 0x0A: escaped += "\\n"
            case 0x0D: escaped += "\\r"
            case 0x09: escaped += "\\t"
            case 0x00...0x1F, 0x7F...0x9F:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    /// Provenance frontmatter block (YAML + an immutability banner) written at the
    /// top of every exported note, satisfying the vault's "raw/ is immutable +
    /// origin-marked" rule. Ends with a trailing blank line.
    static func frontmatter(noteID: String, title: String, modified: Date, exported: Date) -> String {
        """
        ---
        origin: \(yamlScalar("user-stated"))
        source_type: \(yamlScalar("journal"))
        source_app: \(yamlScalar("apple-notes"))
        apple_note_id: \(yamlScalar(noteID))
        title: \(yamlScalar(title))
        note_modified: \(yamlScalar(isoDay(modified)))
        exported: \(yamlScalar(isoDay(exported)))
        ---
        > Provenance: exported from Apple Notes and converted to normalized Markdown. Immutable — synthesize into
        > wiki/, don't edit here.

        """
    }
}
