import Foundation
import Observation
import KeychainAccess

@Observable
@MainActor
final class AppState {
    // Token / auth
    var token: String = ""
    var workspaceName: String? = nil

    // Apple Notes hierarchy
    var hierarchy: AppleNotesHierarchy? = nil
    var selectedNoteIDs: Set<String> = []
    var expandedFolderIDs: Set<String> = []
    var archivedNoteIDs: Set<String> = []

    // Notion hierarchy (lazily loaded)
    var notionRoots: [NotionPage] = []
    var notionChildren: [String: [NotionPage]] = [:]
    var expandedNotionIDs: Set<String> = []
    var loadingNotionPageID: String? = nil
    var selectedNotionPageID: String? = nil

    // Status
    var loadingApple = false
    var loadingNotion = false
    var errorMessage: String? = nil
    var permissionDeniedSheet = false

    // Archive
    var archiveProgress: [NoteArchiveProgress] = []
    var isArchiving = false

    // Services
    let notes: AppleNotesService
    let notion: NotionService
    let images: ImagePipeline
    let log: ArchiveLog
    let coordinator: ArchiveCoordinator

    private let keychain = Keychain(service: "com.applenotestox.app")

    init() {
        let n = NotionService()
        let a = AppleNotesService()
        let l = ArchiveLog()
        let i = ImagePipeline(notion: n)
        self.notion = n
        self.notes = a
        self.log = l
        self.images = i
        self.coordinator = ArchiveCoordinator(notes: a, notion: n, images: i, log: l)
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        if let t = try? keychain.get("notion_token") {
            token = t
            await notion.setToken(t)
        }
        await refreshArchivedSet()
        await loadAppleHierarchy()
        if !token.isEmpty {
            await verifyAndLoadNotion()
        }
    }

    // MARK: - Token

    func saveToken(_ t: String) async {
        token = t
        try? keychain.set(t, key: "notion_token")
        await notion.setToken(t)
        await verifyAndLoadNotion()
    }

    func clearToken() async {
        token = ""
        try? keychain.remove("notion_token")
        await notion.setToken(nil)
        workspaceName = nil
        notionRoots = []
        notionChildren = [:]
        selectedNotionPageID = nil
    }

    // MARK: - Apple Notes

    func loadAppleHierarchy() async {
        loadingApple = true
        defer { loadingApple = false }
        do {
            hierarchy = try await notes.loadHierarchy()
        } catch let e as AppleNotesService.AppleNotesError where e == .permissionDenied {
            permissionDeniedSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Notion

    func verifyAndLoadNotion() async {
        loadingNotion = true
        defer { loadingNotion = false }
        do {
            workspaceName = try await notion.verifyToken()
            notionRoots = try await notion.searchSharedPages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleNotionExpansion(_ pageID: String) async {
        if expandedNotionIDs.contains(pageID) {
            expandedNotionIDs.remove(pageID)
            return
        }
        expandedNotionIDs.insert(pageID)
        if notionChildren[pageID] == nil {
            loadingNotionPageID = pageID
            defer { loadingNotionPageID = nil }
            do {
                notionChildren[pageID] = try await notion.childPages(of: pageID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func createNotionSubPage(parentID: String, title: String) async -> String? {
        do {
            let id = try await notion.createPage(parentID: parentID, title: title)
            // Refresh children of parent
            notionChildren[parentID] = try await notion.childPages(of: parentID)
            expandedNotionIDs.insert(parentID)
            selectedNotionPageID = id
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Archive

    func runArchive(disposition: PostArchiveDisposition) async {
        guard let parent = selectedNotionPageID, !selectedNoteIDs.isEmpty, let h = hierarchy else { return }
        let job = ArchiveJob(
            noteIDs: Array(selectedNoteIDs),
            parentPageID: parent,
            disposition: disposition
        )
        isArchiving = true
        archiveProgress = []
        let stream = coordinator.archive(job: job, hierarchy: h)
        for await snapshot in stream {
            archiveProgress = snapshot
        }
        isArchiving = false
        await refreshArchivedSet()
        // Reload Apple hierarchy if any disposition changed it.
        if disposition != .leave {
            await loadAppleHierarchy()
        }
        selectedNoteIDs.removeAll()
    }

    private func refreshArchivedSet() async {
        let entries = await log.allEntries()
        archivedNoteIDs = Set(entries.map(\.appleNoteID))
    }
}

// Equatable conformance for AppleNotesError to enable pattern match in catch.
extension AppleNotesService.AppleNotesError: Equatable {
    public static func == (lhs: AppleNotesService.AppleNotesError, rhs: AppleNotesService.AppleNotesError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied, .permissionDenied): return true
        case (.scriptFailed(let a), .scriptFailed(let b)): return a == b
        case (.parseFailed(let a), .parseFailed(let b)): return a == b
        default: return false
        }
    }
}
