import SwiftUI
import AppKit

/// Study-first hero: big counts + Launch/Refresh + "jump back in", with a quieter
/// synthesis-backlog panel. The wiki is the focal point.
struct StudyView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            hero
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(WorkspaceStyle.spacing24)
            Divider()
            backlog
                .frame(width: 320)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { state.loadStudyOnAppear() }
    }

    // MARK: hero (the wiki)
    @ViewBuilder private var hero: some View {
        VStack(alignment: .leading, spacing: WorkspaceStyle.spacing16) {
            Text("Study your wiki")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))

            if state.vaultURL == nil {
                emptyVault
            } else {
                Text("\(state.studyData?.conceptCount ?? 0)")
                    .font(.system(size: 60, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel(
                        (state.studyData?.conceptCount ?? 0) == 1
                            ? "1 concept"
                            : "\(state.studyData?.conceptCount ?? 0) concepts"
                    )

                HStack(spacing: WorkspaceStyle.spacing8) {
                    Text("\(state.studyData?.cardCount ?? 0) cards")
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(state.studyData?.edgeCount ?? 0) links")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if let gen = state.studyData?.generatedAt {
                    Text("last refreshed \(relative(gen))")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("No study data yet — hit Refresh to build it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: WorkspaceStyle.spacing8) {
                    Button {
                        state.launchWikiReview()
                    } label: {
                        Label("Launch Wiki Review", systemImage: "book.pages")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.studyData == nil)

                    Button {
                        Task { await state.refreshStudyData() }
                    } label: {
                        HStack(spacing: WorkspaceStyle.spacing4) {
                            if state.isRefreshingStudy {
                                ProgressView().controlSize(.small)
                                Text("Refreshing…")
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                        }
                    }
                    .disabled(state.isRefreshingStudy)
                }

                if let err = state.studyError {
                    HStack(alignment: .top, spacing: WorkspaceStyle.spacing4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error: \(err)")
                }

                if let top = state.studyData?.topConcepts, !top.isEmpty {
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                        WorkspaceSectionLabel("Jump back in")
                            .padding(.top, WorkspaceStyle.spacing8)
                        FlowChips(items: top)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var emptyVault: some View {
        WorkspaceEmptyState(
            systemImage: "books.vertical",
            title: "Choose your vault to begin",
            message: "Wiki Studio studies your Personal_LLM_Wiki. Pick the vault folder in the Wiki (Capture) tab."
        )
        Button("Go to Capture") { state.appMode = .capture }
            .padding(.top, WorkspaceStyle.spacing8)
    }

    // MARK: backlog (supporting)
    @ViewBuilder private var backlog: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WorkspaceStyle.spacing8) {
                WorkspaceSectionLabel("Awaiting synthesis")
                if !state.backlogItems.isEmpty {
                    WorkspaceBadge(text: "\(state.backlogItems.count)", tint: .orange)
                }
            }
            .padding(.bottom, WorkspaceStyle.spacing12)

            if state.backlogItems.isEmpty {
                Text("All caught up — nothing waiting in raw/.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                    ForEach(state.backlogItems.prefix(8)) { item in
                        HStack(spacing: WorkspaceStyle.spacing8) {
                            Text(item.date)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                            Text(item.slug)
                                .font(.callout)
                                .lineLimit(1)
                        }
                    }
                    if state.backlogItems.count > 8 {
                        Text("+ \(state.backlogItems.count - 8) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .workspaceInsetSurface()

                HStack(spacing: WorkspaceStyle.spacing8) {
                    Button("Copy opencode prompt") { state.copyBacklogPrompt() }
                    Button {
                        if let v = state.vaultURL {
                            NSWorkspace.shared.open(v.appendingPathComponent("raw/journal"))
                        }
                    } label: { Image(systemName: "folder") }
                    .help("Reveal raw/journal in Finder")
                    .accessibilityLabel("Reveal raw journal in Finder")
                }
                .controlSize(.small)
                .padding(.top, WorkspaceStyle.spacing8)
            }

            Spacer()

            Text("Synthesis stays LLM-owned — the app surfaces what's in raw/ but not yet in wiki/sources/.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .workspaceFooterSurface()
                .padding(.horizontal, -WorkspaceStyle.spacing16)
                .padding(.bottom, -WorkspaceStyle.spacing16)
        }
        .padding(WorkspaceStyle.spacing16)
    }

    private func relative(_ iso: String) -> String {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = withFrac.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "recently" }
        let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

/// Simple wrapping chip row for the "jump back in" concept titles.
/// Minimum width 170pt so multi-word concept labels stay readable at 900–1100pt window widths.
/// lineLimit(2) prevents mid-concept truncation while keeping the grid compact.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: WorkspaceStyle.spacing8, alignment: .leading)],
            alignment: .leading,
            spacing: WorkspaceStyle.spacing8
        ) {
            ForEach(items, id: \.self) { t in
                Text(t)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, WorkspaceStyle.spacing12)
                    .padding(.vertical, WorkspaceStyle.spacing8)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            }
        }
    }
}
