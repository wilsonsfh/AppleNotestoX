import SwiftUI
import Accessibility

struct SourcePane: View {
    @Environment(AppState.self) private var state
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WorkspaceStyle.spacing8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Notes")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("Choose what belongs in your knowledge base")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)
                Spacer(minLength: WorkspaceStyle.spacing8)
                if state.loadingApple {
                    HStack(spacing: WorkspaceStyle.spacing4) {
                        ProgressView().controlSize(.small)
                        Text("Reading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Reading Apple Notes")
                }
                if !state.selectedNoteIDs.isEmpty {
                    WorkspaceBadge(text: "\(state.selectedNoteIDs.count) selected")
                }
            }
            .padding(.horizontal, WorkspaceStyle.spacing16)
            .padding(.vertical, WorkspaceStyle.spacing12)

            TextField("Search notes and folders", text: $state.noteSearchQuery)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isSearchFocused)
                .disabled(state.hierarchy == nil || state.loadingApple)
                .accessibilityLabel("Search Apple Notes")
                .onExitCommand {
                    if state.noteSearchQuery.isEmpty {
                        isSearchFocused = false
                    } else {
                        state.noteSearchQuery = ""
                    }
                }
                .padding(.horizontal, WorkspaceStyle.spacing16)
                .padding(.bottom, WorkspaceStyle.spacing8)

            Divider()

            if let h = state.hierarchy {
                if let results = AppleNoteSearch.results(in: h, matching: state.noteSearchQuery) {
                    if results.isEmpty {
                        searchEmptyState
                    } else {
                        List(results) { result in
                            AppleNoteRow(note: result.note, folderPath: result.folderPath)
                        }
                        .listStyle(.sidebar)
                    }
                } else {
                    List {
                        ForEach(h.rootFolderIDs.compactMap { h.folders[$0] }, id: \.id) { folder in
                            AppleFolderRow(folder: folder, hierarchy: h, depth: 0)
                        }
                    }
                    .listStyle(.sidebar)
                }
            } else if state.loadingApple {
                VStack(spacing: WorkspaceStyle.spacing8) {
                    ProgressView()
                        .controlSize(.regular)
                        .accessibilityHidden(true)
                    Text("Reading Apple Notes")
                        .font(.title3.weight(.semibold))
                    Text("Loading your notes and folders…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(WorkspaceStyle.spacing24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Reading Apple Notes. Loading your notes and folders.")
            } else {
                WorkspaceEmptyState(
                    systemImage: "note.text",
                    title: "No Apple Notes Found",
                    message: "Apple Notes data could not be loaded. Check your Notes library and try again."
                )
            }

            Divider()
            personalWikiFooter
        }
        .onChange(of: state.noteSearchFocusRequest, initial: true) { _, request in
            guard request > 0 else { return }
            isSearchFocused = true
        }
        .onChange(of: state.loadingApple) { wasLoading, isLoading in
            guard wasLoading, !isLoading, state.hierarchy != nil else { return }
            AccessibilityNotification.Announcement("Apple Notes update finished").post()
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: WorkspaceStyle.spacing8) {
            WorkspaceEmptyState(
                systemImage: "magnifyingglass",
                title: "No Results",
                message: "No notes or folders match your search."
            )
            Button("Clear Search") {
                state.noteSearchQuery = ""
                isSearchFocused = true
            }
            .accessibilityLabel("Clear note search")
            .padding(.bottom, WorkspaceStyle.spacing16)
        }
    }

    @ViewBuilder private var personalWikiFooter: some View {
        let actionState = PersonalWikiActionState.resolve(
            selectedCount: state.selectedNoteIDs.count,
            hasVault: state.vaultURL != nil,
            isExporting: state.isExportingToWiki,
            progress: state.wikiProgress
        )

        VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
            Text("Personal Wiki")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch actionState {
            case .selectNotes:
                Text("Select notes to export")
                    .foregroundStyle(.secondary)
            case .chooseVault:
                Button {
                    if let url = pickVaultDirectory() {
                        state.chooseVault(url)
                    }
                } label: {
                    Label("Choose Personal Wiki…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isArchiving)
                .accessibilityLabel("Choose Personal Wiki folder")
            case .ready(let noteCount):
                Button {
                    state.exportDestination = .wiki
                    Task { await state.runWikiExport() }
                } label: {
                    Label(
                        "Export \(noteCount) \(noteCount == 1 ? "note" : "notes")",
                        systemImage: "arrow.up.doc"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(
                    state.exportDestination == .wiki
                        ? KeyboardShortcut(.return, modifiers: [.command])
                        : nil
                )
                .disabled(state.isArchiving)
                .accessibilityLabel("Export \(noteCount) \(noteCount == 1 ? "note" : "notes") to Personal Wiki")
            case .exporting(let done, let total):
                HStack(spacing: WorkspaceStyle.spacing8) {
                    ProgressView().controlSize(.small)
                    Text("Exporting \(done)/\(total)")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Exporting \(done) of \(total) notes to Personal Wiki")
            case .completed(let done, let failed):
                Label {
                    if failed == 0 {
                        Text("\(done) \(done == 1 ? "note" : "notes") exported to Personal Wiki")
                    } else {
                        Text("\(done) \(done == 1 ? "note" : "notes") exported, \(failed) \(failed == 1 ? "note" : "notes") failed")
                    }
                } icon: {
                    Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(failed == 0 ? Color.green : Color.orange)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .workspaceFooterSurface()
    }
}

private struct AppleFolderRow: View {
    @Environment(AppState.self) private var state
    let folder: AppleFolder
    let hierarchy: AppleNotesHierarchy
    let depth: Int

    private var allNoteIDs: [String] { hierarchy.allNoteIDs(underFolder: folder.id) }

    private enum SelectionState { case none, some, all }

    private var selectionState: SelectionState {
        let ids = allNoteIDs
        guard !ids.isEmpty else { return .none }
        let selectedCount = ids.count { state.selectedNoteIDs.contains($0) }
        if selectedCount == 0 { return .none }
        if selectedCount == ids.count { return .all }
        return .some
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { state.expandedFolderIDs.contains(folder.id) },
                set: { v in
                    if v { state.expandedFolderIDs.insert(folder.id) }
                    else { state.expandedFolderIDs.remove(folder.id) }
                }
            )
        ) {
            ForEach(folder.childFolderIDs.compactMap { hierarchy.folders[$0] }, id: \.id) { child in
                AppleFolderRow(folder: child, hierarchy: hierarchy, depth: depth + 1)
            }
            ForEach(folder.noteIDs.compactMap { hierarchy.notes[$0] }, id: \.id) { note in
                AppleNoteRow(note: note)
            }
        } label: {
            HStack(spacing: 8) {
                Button {
                    state.toggleFolderSelection(folder.id)
                } label: {
                    Image(systemName: folderCheckboxSymbol)
                        .foregroundStyle(selectionState == .none ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(allNoteIDs.isEmpty)
                .accessibilityLabel(folderAccessibilityLabel)
                .accessibilityAddTraits(selectionState == .all ? .isSelected : [])

                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                Spacer()
                let count = folder.noteIDs.count
                if count > 0 {
                    Text("\(count)").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var folderCheckboxSymbol: String {
        switch selectionState {
        case .none: return "square"
        case .some: return "minus.square.fill"
        case .all: return "checkmark.square.fill"
        }
    }

    private var folderAccessibilityLabel: String {
        switch selectionState {
        case .none: return "Select all notes in \(folder.name)"
        case .some: return "Select remaining notes in \(folder.name)"
        case .all: return "Deselect all notes in \(folder.name)"
        }
    }
}

private struct AppleNoteRow: View {
    @Environment(AppState.self) private var state
    let note: AppleNote
    var folderPath: String? = nil

    private var isSelected: Bool { state.selectedNoteIDs.contains(note.id) }
    private var isArchived: Bool { state.archivedNoteIDs.contains(note.id) }

    var body: some View {
        Button {
            state.toggleNoteSelection(note.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.name)
                        .lineLimit(1)
                    if let folderPath {
                        Text(folderPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if isArchived {
                    Label {
                        Text("Archived")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.green)
                    }
                    .lineLimit(1)
                    .help("Already archived previously")
                }
                Spacer()
                Text(relativeDate(note.modifiedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, WorkspaceStyle.spacing4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityDescription: String {
        var parts = [note.name]
        if let folderPath { parts.append(folderPath) }
        if isArchived { parts.append("already archived") }
        parts.append(isSelected ? "selected" : "not selected")
        return parts.joined(separator: ", ")
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
