import SwiftUI
import AppKit
import Accessibility
import UniformTypeIdentifiers

@MainActor
func pickVaultDirectory() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url : nil
}

struct DestinationPane: View {
    @Environment(AppState.self) private var state
    @State private var showCreatePage = false
    @State private var newPageTitle = ""

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                WorkspaceSectionLabel("Send to")
                Picker("Destination", selection: $state.exportDestination) {
                    Label("Recategorise Apple Notes", systemImage: "square.stack.3d.up")
                        .tag(AppState.ExportDestination.mergeToNote)
                    Label("Personal Wiki", systemImage: "books.vertical")
                        .tag(AppState.ExportDestination.wiki)
                    Label("Notion", systemImage: "square.grid.2x2")
                        .tag(AppState.ExportDestination.notion)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, WorkspaceStyle.spacing16)
            .padding(.vertical, WorkspaceStyle.spacing12)

            switch state.exportDestination {
            case .notion: notionPane
            case .wiki: wikiPane
            case .mergeToNote: mergePane
            }
        }
        .sheet(isPresented: $showCreatePage) {
            CreatePageSheet(
                title: $newPageTitle,
                onCancel: { showCreatePage = false },
                onConfirm: {
                    let parentID = state.selectedNotionPageID
                    let title = newPageTitle
                    showCreatePage = false
                    Task {
                        if let parent = parentID, !title.isEmpty {
                            _ = await state.createNotionSubPage(parentID: parent, title: title)
                        }
                    }
                }
            )
        }
    }

    // MARK: - Notion

    @ViewBuilder private var notionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WorkspaceStyle.spacing8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notion")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let ws = state.workspaceName {
                        Text(ws)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: WorkspaceStyle.spacing8)
                if state.loadingNotion {
                    HStack(spacing: WorkspaceStyle.spacing4) {
                        ProgressView().controlSize(.small)
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading Notion")
                }
                if state.selectedNotionPageID != nil {
                    Button {
                        showCreatePage = true
                        newPageTitle = ""
                    } label: {
                        Label("New page", systemImage: "plus.square")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, WorkspaceStyle.spacing16)
            .padding(.vertical, WorkspaceStyle.spacing12)

            Divider()

            if state.token.isEmpty {
                WorkspaceEmptyState(
                    systemImage: "key.horizontal",
                    title: "No Integration Token",
                    message: "Add your Notion integration token in Settings."
                )
            } else if state.loadingNotion && state.notionRoots.isEmpty {
                VStack(spacing: WorkspaceStyle.spacing8) {
                    ProgressView()
                        .controlSize(.regular)
                        .accessibilityHidden(true)
                    Text("Loading Notion")
                        .font(.title3.weight(.semibold))
                    Text("Fetching your pages…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(WorkspaceStyle.spacing24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading Notion. Fetching your pages.")
            } else if !state.loadingNotion && state.workspaceName == nil && !state.token.isEmpty {
                WorkspaceEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Workspace Unavailable",
                    message: "Notion could not be reached. Check your integration token in Settings and reload."
                )
            } else if state.notionRoots.isEmpty {
                WorkspaceEmptyState(
                    systemImage: "square.grid.2x2",
                    title: "No Pages Shared",
                    message: "No pages shared with this integration yet.\nIn Notion: open a page → Connect to integration → select your integration."
                )
            } else {
                List {
                    ForEach(state.notionRoots) { root in
                        NotionPageRow(page: root)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: state.loadingNotion) { wasLoading, isLoading in
            guard wasLoading, !isLoading, !state.token.isEmpty else { return }
            AccessibilityNotification.Announcement("Notion update finished").post()
        }
    }

    // MARK: - Wiki

    @ViewBuilder private var wikiPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceStyle.spacing12) {
                VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                    WorkspaceSectionLabel("Personal Wiki")
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                        let vaultPath = state.vaultURL?.path ?? "No vault chosen"
                        Text(vaultPath)
                            .font(.callout)
                            .foregroundStyle(state.vaultURL == nil ? Color.secondary : Color.primary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(vaultPath)
                            .accessibilityLabel(state.vaultURL == nil ? "No vault chosen" : "Vault path: \(vaultPath)")
                        Button("Choose vault…") {
                            if let url = pickVaultDirectory() {
                                state.chooseVault(url)
                            }
                        }
                        Text("Notes land in raw/journal; screenshots and media land in raw/assets.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .workspaceInsetSurface()
                }

                VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                    WorkspaceSectionLabel("Transcription")
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                        Toggle("Transcribe video attachments", isOn: Binding(
                            get: { state.transcribeNoteVideos },
                            set: { state.transcribeNoteVideos = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        Button("Import video…") { chooseVideo() }
                            .disabled(state.vaultURL == nil || state.isArchiving)
                        Text("Transcribes on-device (Apple Speech) + extracts keyframes into a transcript note.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .workspaceInsetSurface()
                }
            }
            .padding(.horizontal, WorkspaceStyle.spacing16)
            .padding(.vertical, WorkspaceStyle.spacing12)
        }
    }

    // MARK: - Merge to Note

    @ViewBuilder private var mergePane: some View {
        @Bindable var state = state
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceStyle.spacing12) {
                VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                    WorkspaceSectionLabel("Recategorise Apple Notes")
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                        Text("\(state.selectedNoteIDs.count) note\(state.selectedNoteIDs.count == 1 ? "" : "s") selected")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if state.activeLLMAPIKey.isEmpty {
                            WorkspaceEmptyState(
                                systemImage: "key.horizontal",
                                title: "No \(state.llmProvider.displayName) API Key",
                                message: "Add your \(state.llmProvider.displayName) API key in Settings."
                            )
                        } else {
                            Button {
                                Task { await state.startMergePreview() }
                            } label: {
                                Text(state.isMerging ? "Categorizing\u{2026}" : "Preview & Merge\u{2026}")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.isMerging || state.selectedNoteIDs.isEmpty)
                        }
                        if case .completed = state.mergeStage {
                            Label("Merged note created in Apple Notes", systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                        Text("Writes one new note into Apple Notes with LLM-chosen sections. Originals are left untouched.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .workspaceInsetSurface()
                }
            }
            .padding(.horizontal, WorkspaceStyle.spacing16)
            .padding(.vertical, WorkspaceStyle.spacing12)
        }
        .sheet(isPresented: $state.showMergePreview) {
            // Only a real user dismissal (swipe/Esc while the draft is still
            // pending) should discard the draft — `confirmMerge` closes the
            // sheet itself once the stage has moved past `.readyForPreview`.
            if case .readyForPreview = state.mergeStage {
                Task { await state.cancelMerge() }
            }
        } content: {
            MergePreviewSheet()
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await state.importVideo(url: url) }
        }
    }
}

private struct NotionPageRow: View {
    @Environment(AppState.self) private var state
    let page: NotionPage
    @FocusState private var isFocused: Bool

    private var isSelected: Bool { state.selectedNotionPageID == page.id }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { state.expandedNotionIDs.contains(page.id) },
                set: { v in
                    Task {
                        if v && !state.expandedNotionIDs.contains(page.id) {
                            await state.toggleNotionExpansion(page.id)
                        } else if !v {
                            await state.toggleNotionExpansion(page.id)
                        }
                    }
                }
            )
        ) {
            if let kids = state.notionChildren[page.id] {
                ForEach(kids) { child in
                    NotionPageRow(page: child)
                }
                if kids.isEmpty {
                    Text("(no sub-pages)").font(.caption).foregroundStyle(.tertiary)
                }
            } else if state.loadingNotionPageID == page.id {
                HStack { ProgressView().controlSize(.small); Text("loading…").font(.caption).foregroundStyle(.tertiary) }
            }
        } label: {
            HStack {
                Image(systemName: "doc.text.fill").foregroundStyle(.secondary)
                Text(page.title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, WorkspaceStyle.spacing4)
            .contentShape(Rectangle())
            .onTapGesture { state.selectedNotionPageID = page.id }
            .onKeyPress(.return) {
                state.selectedNotionPageID = page.id
                return .handled
            }
            .onKeyPress(.space) {
                state.selectedNotionPageID = page.id
                return .handled
            }
            .focusable()
            .focused($isFocused)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(page.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

private struct CreatePageSheet: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create new Notion sub-page").font(.headline)
            TextField("Page title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.escape)
                Button("Create", action: onConfirm)
                    .keyboardShortcut(.return)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
