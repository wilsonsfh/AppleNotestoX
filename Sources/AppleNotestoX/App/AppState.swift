import Foundation
import Observation
import AppKit
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
    var noteSearchQuery = ""
    var noteSearchFocusRequest = 0

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

    // Wiki export
    enum ExportDestination: String, Sendable { case notion, wiki, mergeToNote }
    var exportDestination: ExportDestination = .mergeToNote
    var vaultURL: URL? = nil
    var wikiProgress: [WikiExportProgress] = []
    var videoProgress: [WikiExportProgress] = []
    var isExportingToWiki = false
    var transcribeNoteVideos = false

    // Merge to Note
    enum LLMProvider: String, Sendable, CaseIterable, Identifiable {
        case groq, glm
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .groq: return "Groq"
            case .glm: return "GLM (tbtk.asia)"
            }
        }
    }
    var llmProvider: LLMProvider = .groq
    var groqAPIKey: String = ""
    var glmAPIKey: String = ""
    var mergeStage: MergeStage? = nil
    var isMerging = false
    /// The API key for whichever LLM provider is currently selected — what
    /// `startMergePreview()` actually needs present before it will run.
    var activeLLMAPIKey: String {
        switch llmProvider {
        case .groq: return groqAPIKey
        case .glm: return glmAPIKey
        }
    }
    /// Drives the merge preview sheet explicitly, so the sheet's own dismissal
    /// can't be confused with a user cancel when `mergeStage` moves on.
    var showMergePreview = false

    var canStartWikiExport: Bool { !isArchiving && !isExportingToWiki }

    // Personal Wiki duplicate cleanup
    var duplicateGroups: [WikiDuplicateFinder.Group] = []
    var isScanningDuplicates = false
    var duplicateScanError: String? = nil
    /// Files currently checked for removal, by markdown path. Populated with
    /// every entry except each group's newest (kept) one right after a scan.
    var selectedDuplicatePaths: Set<URL> = []
    var isDeletingDuplicates = false

    // Study + synthesis (Wiki Studio pass 1)
    enum AppMode: String, Sendable { case study, capture, duplicates }
    var appMode: AppMode = .study
    var studyData: StudyData? = nil
    var isRefreshingStudy = false
    var studyError: String? = nil
    var backlogItems: [BacklogItem] = []

    // Services
    let notes: AppleNotesService
    let notion: NotionService
    let images: ImagePipeline
    let log: ArchiveLog
    let coordinator: ArchiveCoordinator
    let wikiCoordinator: WikiExportCoordinator
    let videoCoordinator: VideoIngestCoordinator
    let groq: GroqService
    let mergeCoordinator: MergeCoordinator
    let vaultMaintenance: WikiVaultMaintenance

    private let keychain = Keychain(service: "com.applenotestox.app")
    private let vaultBookmarkKey = "wiki_vault_bookmark"
    private let llmProviderDefaultsKey = "llm_provider"
    private static let groqBaseURL = URL(string: "https://api.groq.com/openai/v1/")!
    private static let groqModel = "llama-3.3-70b-versatile"
    private static let glmBaseURL = URL(string: "https://tbtk.asia/v1/")!
    private static let glmModel = "glm-5.2"

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
        self.wikiCoordinator = WikiExportCoordinator(notes: a)
        self.videoCoordinator = VideoIngestCoordinator()
        let g = GroqService()
        self.groq = g
        self.mergeCoordinator = MergeCoordinator(notes: a, groq: g)
        self.vaultMaintenance = WikiVaultMaintenance()
        restoreVaultBookmark()
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        if let t = try? keychain.get("notion_token") {
            token = t
            await notion.setToken(t)
        }
        if let g = try? keychain.get("groq_api_key") {
            groqAPIKey = g
        }
        if let m = try? keychain.get("glm_api_key") {
            glmAPIKey = m
        }
        if let p = UserDefaults.standard.string(forKey: llmProviderDefaultsKey),
           let provider = LLMProvider(rawValue: p) {
            llmProvider = provider
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

    func saveGroqKey(_ key: String) async {
        groqAPIKey = key
        try? keychain.set(key, key: "groq_api_key")
    }

    func saveGLMKey(_ key: String) async {
        glmAPIKey = key
        try? keychain.set(key, key: "glm_api_key")
    }

    func setLLMProvider(_ provider: LLMProvider) {
        llmProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: llmProviderDefaultsKey)
    }

    // MARK: - Apple Notes

    func requestNoteSearch() {
        appMode = .capture
        noteSearchFocusRequest &+= 1
    }

    func toggleNoteSelection(_ noteID: String) {
        guard !isArchiving else { return }
        if !wikiProgress.isEmpty { wikiProgress = [] }
        if selectedNoteIDs.remove(noteID) == nil { selectedNoteIDs.insert(noteID) }
    }

    /// Selects every note in this folder and its subfolders if any are
    /// currently unselected; deselects all of them only when the whole
    /// subtree is already fully selected.
    func toggleFolderSelection(_ folderID: String) {
        guard !isArchiving, let hierarchy else { return }
        let ids = hierarchy.allNoteIDs(underFolder: folderID)
        guard !ids.isEmpty else { return }
        if !wikiProgress.isEmpty { wikiProgress = [] }
        if ids.allSatisfy(selectedNoteIDs.contains) {
            selectedNoteIDs.subtract(ids)
        } else {
            selectedNoteIDs.formUnion(ids)
        }
    }

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

    // MARK: - Wiki export

    /// Records the chosen vault directory and persists a (security-scoped if possible)
    /// bookmark so it survives relaunches.
    func chooseVault(_ url: URL) {
        vaultURL = url
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: vaultBookmarkKey)
        } else if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: vaultBookmarkKey)
        }
    }

    func restoreVaultBookmark() {
        guard let data = UserDefaults.standard.data(forKey: vaultBookmarkKey) else { return }
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            vaultURL = url
        } else if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
            vaultURL = url
        }
    }

    func runWikiExport() async {
        guard canStartWikiExport,
              let vault = vaultURL,
              !selectedNoteIDs.isEmpty,
              let h = hierarchy else { return }

        isArchiving = true
        isExportingToWiki = true
        defer {
            isArchiving = false
            isExportingToWiki = false
        }
        videoProgress = []

        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }

        let job = WikiExportJob(
            noteIDs: Array(selectedNoteIDs),
            config: WikiVaultConfig(vaultURL: vault),
            transcribeVideos: transcribeNoteVideos
        )
        wikiProgress = []
        let stream = wikiCoordinator.export(job: job, hierarchy: h)
        for await snapshot in stream {
            wikiProgress = snapshot
        }
        selectedNoteIDs.removeAll()
    }

    /// Transcribes a user-chosen video file directly into the vault as a transcript note.
    func importVideo(url: URL) async {
        guard !isArchiving, let vault = vaultURL else { return }
        isArchiving = true
        defer { isArchiving = false }

        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }

        let id = url.path
        videoProgress = [WikiExportProgress(id: id, title: url.lastPathComponent, status: .converting)]
        do {
            let result = try await videoCoordinator.ingest(
                videoURL: url,
                title: nil,
                modified: Date(),
                config: WikiVaultConfig(vaultURL: vault),
                sourceApp: "imported-file"
            )
            videoProgress = [WikiExportProgress(id: id, title: url.lastPathComponent, status: .done(result: result))]
        } catch {
            videoProgress = [WikiExportProgress(id: id, title: url.lastPathComponent, status: .failed(message: error.localizedDescription))]
        }
    }

    // MARK: - Merge to Note

    func startMergePreview() async {
        guard !selectedNoteIDs.isEmpty, !activeLLMAPIKey.isEmpty, let h = hierarchy, !isMerging else { return }
        isMerging = true
        mergeStage = nil
        showMergePreview = false
        switch llmProvider {
        case .groq:
            await groq.configure(baseURL: Self.groqBaseURL, model: Self.groqModel)
            await groq.setAPIKey(groqAPIKey)
        case .glm:
            await groq.configure(baseURL: Self.glmBaseURL, model: Self.glmModel)
            await groq.setAPIKey(glmAPIKey)
        }
        let job = MergeJob(noteIDs: Array(selectedNoteIDs))
        let stream = mergeCoordinator.run(job: job, hierarchy: h)
        for await stage in stream {
            mergeStage = stage
            if case .readyForPreview = stage {
                showMergePreview = true
            }
            if case .failed(let message) = stage {
                errorMessage = message
            }
        }
        isMerging = false
    }

    func confirmMerge() async {
        guard case .readyForPreview(let draft) = mergeStage else { return }
        mergeStage = .writing
        do {
            let noteID = try await mergeCoordinator.write(draft: draft)
            mergeStage = .completed(noteID: noteID)
            showMergePreview = false
            selectedNoteIDs.removeAll()
            await loadAppleHierarchy()
        } catch {
            errorMessage = error.localizedDescription
            mergeStage = .failed(message: error.localizedDescription)
            showMergePreview = false
        }
    }

    func cancelMerge() async {
        showMergePreview = false
        if case .readyForPreview(let draft) = mergeStage {
            await mergeCoordinator.discard(draft: draft)
        }
        mergeStage = nil
    }

    // MARK: - Personal Wiki duplicate cleanup

    func scanForDuplicates() async {
        guard let vault = vaultURL, !isScanningDuplicates else { return }
        isScanningDuplicates = true
        duplicateScanError = nil
        defer { isScanningDuplicates = false }
        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }

        let groups = await vaultMaintenance.findDuplicates(config: WikiVaultConfig(vaultURL: vault))
        duplicateGroups = groups
        // Default to keeping each group's newest export and marking the
        // rest for removal — the user reviews/adjusts before confirming.
        selectedDuplicatePaths = Set(groups.flatMap { $0.entries.dropFirst().map(\.markdownPath) })
    }

    func toggleDuplicateSelection(_ path: URL) {
        if selectedDuplicatePaths.remove(path) == nil {
            selectedDuplicatePaths.insert(path)
        }
    }

    func deleteSelectedDuplicates() async {
        guard let vault = vaultURL, !selectedDuplicatePaths.isEmpty, !isDeletingDuplicates else { return }
        isDeletingDuplicates = true
        defer { isDeletingDuplicates = false }
        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }

        let config = WikiVaultConfig(vaultURL: vault)
        let entriesByPath = Dictionary(
            uniqueKeysWithValues: duplicateGroups.flatMap { $0.entries }.map { ($0.markdownPath, $0) }
        )
        for path in selectedDuplicatePaths {
            guard let entry = entriesByPath[path] else { continue }
            do {
                try await vaultMaintenance.delete(entry: entry, config: config)
            } catch {
                duplicateScanError = error.localizedDescription
            }
        }
        await scanForDuplicates()
    }

    // MARK: - Study + backlog

    /// Cheap load on first show: read any existing snapshot + scan the backlog.
    func loadStudyOnAppear() {
        if studyData == nil { studyData = StudyDataService.loadExisting() }
        loadBacklog()
    }

    func refreshStudyData() async {
        guard let vault = vaultURL else { studyError = "Choose your vault first."; return }
        isRefreshingStudy = true
        studyError = nil
        defer { isRefreshingStudy = false }
        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }
        do {
            studyData = try await StudyDataService.refresh(vaultURL: vault)
            loadBacklog()
        } catch {
            studyError = error.localizedDescription
        }
    }

    func launchWikiReview() {
        NSWorkspace.shared.open(RepoPaths.indexHTML())
    }

    func loadBacklog() {
        guard let vault = vaultURL else { backlogItems = []; return }
        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }
        backlogItems = SynthesisBacklog.scan(vaultURL: vault)
    }

    func copyBacklogPrompt() {
        let prompt = SynthesisBacklog.opencodePrompt(backlogItems)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
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
