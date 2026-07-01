import Foundation

actor AppleNotesService {
    enum AppleNotesError: Error, LocalizedError {
        case scriptFailed(String)
        case parseFailed(String)
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .scriptFailed(let m): return "AppleScript failed: \(m)"
            case .parseFailed(let m): return "Could not parse AppleScript output: \(m)"
            case .permissionDenied:
                return "Apple Notes automation permission denied. Grant in System Settings → Privacy & Security → Automation → AppleNotestoX → Notes."
            }
        }
    }

    func loadHierarchy() async throws -> AppleNotesHierarchy {
        let raw = try await runScript(Self.listScript)
        return try Self.parseHierarchy(raw)
    }

    func fetchNote(id: String) async throws -> AppleNoteContent {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleNotestoX-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let raw = try await runScript(Self.fetchScript, args: [id, tmpDir.path])
        return try Self.parseNoteContent(raw)
    }

    func moveNote(id: String, toFolderNamed folderName: String, in accountName: String) async throws {
        _ = try await runScript(Self.moveScript, args: [id, folderName, accountName])
    }

    func deleteNote(id: String) async throws {
        _ = try await runScript(Self.deleteScript, args: [id])
    }

    // MARK: - Process

    private func runScript(_ source: String, args: [String] = []) async throws -> String {
        var procArgs = ["-e", source]
        if !args.isEmpty {
            procArgs.append("--")
            procArgs.append(contentsOf: args)
        }
        let result = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: procArgs
        )
        if result.status != 0 {
            let err = result.stderr
            if err.contains("(-1743)") || err.contains("Not authorized") || err.contains("not allowed") || err.contains("isn't allowed") {
                throw AppleNotesError.permissionDenied
            }
            throw AppleNotesError.scriptFailed(err.isEmpty ? result.stdout : err)
        }
        return result.stdout
    }

    // MARK: - Parsers

    private static let noteDateCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    /// Fast parser for the local-time `"yyyy-MM-dd'T'HH:mm:ss"` timestamps emitted by
    /// `listScript`. Avoids per-note `DateFormatter`/ICU parsing, which dominated CPU
    /// while reading large Notes libraries. Returns nil for structurally invalid input.
    static func parseNoteDate(_ s: String) -> Date? {
        let halves = s.split(separator: "T", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let d = halves[0].split(separator: "-", omittingEmptySubsequences: false)
        let t = halves[1].split(separator: ":", omittingEmptySubsequences: false)
        guard d.count == 3, t.count == 3,
              let year = Int(d[0]), let month = Int(d[1]), let day = Int(d[2]),
              let hour = Int(t[0]), let minute = Int(t[1]), let second = Int(t[2])
        else { return nil }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return noteDateCalendar.date(from: c)
    }

    static func parseHierarchy(_ raw: String) throws -> AppleNotesHierarchy {
        var folders: [String: AppleFolder] = [:]
        var notes: [String: AppleNote] = [:]
        var rootIDs: [String] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let kind = parts.first else { continue }
            if kind == "F", parts.count >= 5 {
                let id = parts[1], name = parts[2], account = parts[3]
                let parent = parts[4].isEmpty ? nil : parts[4]
                folders[id] = AppleFolder(
                    id: id, name: name, accountName: account,
                    parentID: parent, childFolderIDs: [], noteIDs: []
                )
                if parent == nil { rootIDs.append(id) }
            } else if kind == "N", parts.count >= 5 {
                let id = parts[1], name = parts[2], folderID = parts[3]
                let date = Self.parseNoteDate(parts[4]) ?? Date.distantPast
                notes[id] = AppleNote(id: id, name: name, folderID: folderID, modifiedAt: date)
                folders[folderID]?.noteIDs.append(id)
            }
        }
        for (id, folder) in folders {
            if let parent = folder.parentID, folders[parent] != nil {
                folders[parent]!.childFolderIDs.append(id)
            }
        }
        return AppleNotesHierarchy(folders: folders, notes: notes, rootFolderIDs: rootIDs)
    }

    static func parseNoteContent(_ raw: String) throws -> AppleNoteContent {
        let startMarker = "{{NOTESTOX-BODY-START}}"
        let endMarker = "{{NOTESTOX-BODY-END}}"
        guard let bodyStart = raw.range(of: startMarker),
              let bodyEnd = raw.range(of: endMarker) else {
            throw AppleNotesError.parseFailed("missing body markers")
        }
        var html = String(raw[bodyStart.upperBound..<bodyEnd.lowerBound])
        if html.first == "\n" { html.removeFirst() }
        if html.last == "\n" { html.removeLast() }

        var attachments: [AppleNoteAttachment] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, parts[0] == "ATT" else { continue }
            let id = parts[1]
            let path = parts[2]
            let url = URL(fileURLWithPath: path)
            attachments.append(AppleNoteAttachment(id: id, filename: url.lastPathComponent, localURL: url))
        }
        return AppleNoteContent(html: html, attachments: attachments)
    }

    // MARK: - AppleScript sources

    private static let listScript = #"""
    on isoDate(d)
        set y to year of d as string
        set mn to text -2 thru -1 of ("0" & ((month of d) as integer))
        set dd to text -2 thru -1 of ("0" & (day of d))
        set hh to text -2 thru -1 of ("0" & (hours of d))
        set mm to text -2 thru -1 of ("0" & (minutes of d))
        set ss to text -2 thru -1 of ("0" & (seconds of d))
        return y & "-" & mn & "-" & dd & "T" & hh & ":" & mm & ":" & ss
    end isoDate

    set output to ""
    tell application "Notes"
        repeat with acct in accounts
            set acctName to name of acct as string
            repeat with f in folders of acct
                set fID to id of f as string
                set fName to name of f as string
                set parentID to ""
                try
                    set parentObj to container of f
                    if class of parentObj is folder then
                        set parentID to id of parentObj as string
                    end if
                end try
                set output to output & "F" & tab & fID & tab & fName & tab & acctName & tab & parentID & linefeed
                repeat with n in notes of f
                    set nID to id of n as string
                    set nName to name of n as string
                    set nMod to my isoDate(modification date of n)
                    set output to output & "N" & tab & nID & tab & nName & tab & fID & tab & nMod & linefeed
                end repeat
            end repeat
        end repeat
    end tell
    return output
    """#

    private static let fetchScript = #"""
    on run argv
        set noteID to item 1 of argv
        set outDir to item 2 of argv
        set output to ""
        tell application "Notes"
            set theNote to note id noteID
            set i to 0
            repeat with att in attachments of theNote
                set i to i + 1
                set attID to id of att as string
                set attName to ""
                try
                    set attName to name of att as string
                end try
                if attName is "" then set attName to "attachment-" & (i as string) & ".dat"
                set savePath to outDir & "/" & (i as string) & "-" & attName
                try
                    save att in (POSIX file savePath)
                    set output to output & "ATT" & tab & attID & tab & savePath & linefeed
                on error errMsg
                    set output to output & "ATTERR" & tab & attID & tab & errMsg & linefeed
                end try
            end repeat
            set theBody to body of theNote
        end tell
        set output to output & "{{NOTESTOX-BODY-START}}" & linefeed & theBody & linefeed & "{{NOTESTOX-BODY-END}}" & linefeed
        return output
    end run
    """#

    private static let moveScript = #"""
    on run argv
        set noteID to item 1 of argv
        set folderName to item 2 of argv
        set acctName to item 3 of argv
        tell application "Notes"
            set theNote to note id noteID
            set existing to (folders of account acctName whose name is folderName)
            if (count of existing) is 0 then
                tell account acctName to make new folder with properties {name:folderName}
                set existing to (folders of account acctName whose name is folderName)
            end if
            move theNote to item 1 of existing
        end tell
        return "OK"
    end run
    """#

    private static let deleteScript = #"""
    on run argv
        set noteID to item 1 of argv
        tell application "Notes"
            delete (note id noteID)
        end tell
        return "OK"
    end run
    """#
}
