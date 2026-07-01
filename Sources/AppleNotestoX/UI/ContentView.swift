import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var showPreview = false

    var body: some View {
        @Bindable var state = state

        Group {
            switch state.appMode {
            case .study: StudyView()
            case .capture: captureSplit
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Mode", selection: $state.appMode) {
                    Text("Study").tag(AppState.AppMode.study)
                    Text("Capture").tag(AppState.AppMode.capture)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .principal) {
                if state.isArchiving {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(progressLabel)
                    }
                } else if hasProgress {
                    Text(summaryLabel).foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await state.loadAppleHierarchy(); await state.verifyAndLoadNotion() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload both panes")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }

                if state.appMode == .capture {
                    if isWiki {
                        Button("Export to wiki") { Task { await state.runWikiExport() } }
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(state.selectedNoteIDs.isEmpty || state.vaultURL == nil || state.isArchiving)
                    } else {
                        Button("Archive…") { showPreview = true }
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(state.selectedNoteIDs.isEmpty || state.selectedNotionPageID == nil || state.isArchiving)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPreview) { PreviewSheet() }
        .sheet(isPresented: $state.permissionDeniedSheet) { PermissionDeniedSheet() }
        .alert("Error", isPresented: .constant(state.errorMessage != nil)) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var captureSplit: some View {
        NavigationSplitView {
            SourcePane()
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            DestinationPane()
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
    }

    // MARK: - Progress helpers (destination-aware)

    private var isWiki: Bool { state.exportDestination == .wiki }

    private var progressTotal: Int {
        isWiki ? state.wikiProgress.count : state.archiveProgress.count
    }

    private var progressDone: Int {
        if isWiki {
            return state.wikiProgress.filter { if case .done = $0.status { return true } else { return false } }.count
        }
        return state.archiveProgress.filter { if case .done = $0.status { return true } else { return false } }.count
    }

    private var progressFailed: Int {
        if isWiki {
            return state.wikiProgress.filter { if case .failed = $0.status { return true } else { return false } }.count
        }
        return state.archiveProgress.filter { if case .failed = $0.status { return true } else { return false } }.count
    }

    private var hasProgress: Bool {
        isWiki ? !state.wikiProgress.isEmpty : !state.archiveProgress.isEmpty
    }

    private var progressLabel: String {
        let verb = isWiki ? "Exporting" : "Archiving"
        let total = max(progressTotal, 1)
        return "\(verb) \(min(progressDone + 1, total))/\(progressTotal)"
    }

    private var summaryLabel: String {
        let verb = isWiki ? "Exported" : "Archived"
        if progressFailed == 0 { return "✓ \(verb) \(progressDone)/\(progressTotal)" }
        return "\(verb) \(progressDone)/\(progressTotal) — \(progressFailed) failed"
    }
}
