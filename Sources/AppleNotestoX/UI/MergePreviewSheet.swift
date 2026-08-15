import SwiftUI

struct MergePreviewSheet: View {
    @Environment(AppState.self) private var state
    /// Cached so the sheet keeps rendering the draft while `mergeStage` is
    /// `.writing` (that stage carries no draft of its own).
    @State private var shownDraft: MergeDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing4) {
                        Text("Confirm Merge")
                            .font(.title2.weight(.semibold))
                        if let draft = draft {
                            Text("\(draft.sections.count) section\(draft.sections.count == 1 ? "" : "s") \u{2192} \(draft.titleLine)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, WorkspaceStyle.spacing16)
                    .padding(.top, WorkspaceStyle.spacing16)
                    .padding(.bottom, WorkspaceStyle.spacing12)

                    Divider()

                    if let draft = draft {
                        LazyVStack(alignment: .leading, spacing: WorkspaceStyle.spacing12) {
                            ForEach(Array(draft.sections.enumerated()), id: \.offset) { _, section in
                                VStack(alignment: .leading, spacing: WorkspaceStyle.spacing4) {
                                    Text(section.header)
                                        .font(.headline)
                                    Text(section.bodyText)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Text("From \(section.sourceNoteIDs.count) note\(section.sourceNoteIDs.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, WorkspaceStyle.spacing16)
                            }
                        }
                        .padding(.vertical, WorkspaceStyle.spacing12)
                    } else {
                        Text("No draft ready.")
                            .foregroundStyle(.secondary)
                            .padding(WorkspaceStyle.spacing16)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    // `cancelMerge` clears `showMergePreview`, which dismisses
                    // the sheet — no explicit `dismiss()` needed.
                    Task { await state.cancelMerge() }
                }
                .keyboardShortcut(.escape)
                .disabled(isWriting)
                Button {
                    Task { await state.confirmMerge() }
                } label: {
                    Text(isWriting ? "Creating\u{2026}" : "Create in Apple Notes")
                }
                .keyboardShortcut(.return)
                .disabled(draft == nil || isWriting)
                .buttonStyle(.borderedProminent)
            }
            .workspaceFooterSurface()
        }
        .frame(width: 520, height: 480)
        .onAppear { shownDraft = pendingDraft }
        .onChange(of: pendingDraft) { _, new in
            if let new { shownDraft = new }
        }
    }

    private var pendingDraft: MergeDraft? {
        if case .readyForPreview(let d) = state.mergeStage { return d }
        return nil
    }

    private var draft: MergeDraft? { shownDraft }

    private var isWriting: Bool {
        if case .writing = state.mergeStage { return true }
        return false
    }
}
