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
                .padding(24)
            Divider()
            backlog
                .frame(width: 300)
                .padding(20)
        }
        .task { state.loadStudyOnAppear() }
    }

    // MARK: hero (the wiki)
    @ViewBuilder private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("STUDY YOUR WIKI").font(.caption).fontWeight(.bold)
                .foregroundStyle(.tertiary).kerning(1)

            if state.vaultURL == nil {
                emptyVault
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(state.studyData?.conceptCount ?? 0)")
                        .font(.system(size: 52, weight: .bold)).monospacedDigit()
                    Text("concepts · \(state.studyData?.cardCount ?? 0) cards")
                        .foregroundStyle(.secondary)
                }
                if let gen = state.studyData?.generatedAt {
                    Text("last refreshed \(relative(gen)) · \(state.studyData?.edgeCount ?? 0) links")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("No study data yet — hit Refresh to build it.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await state.refreshStudyData() }
                    } label: {
                        if state.isRefreshingStudy { ProgressView().controlSize(.small) }
                        else { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                    .disabled(state.isRefreshingStudy)

                    Button {
                        state.launchWikiReview()
                    } label: { Label("Launch Wiki Review", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.studyData == nil)
                }

                if let err = state.studyError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let top = state.studyData?.topConcepts, !top.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("JUMP BACK IN").font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.tertiary).kerning(1).padding(.top, 6)
                        FlowChips(items: top)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var emptyVault: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose your vault to begin").font(.title3).bold()
            Text("Wiki Studio studies your Personal_LLM_Wiki. Pick the vault folder in the Wiki (Capture) tab.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Go to Capture") { state.appMode = .capture }
        }
    }

    // MARK: backlog (supporting)
    @ViewBuilder private var backlog: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Awaiting synthesis").font(.headline)
                if !state.backlogItems.isEmpty {
                    Text("\(state.backlogItems.count)").font(.caption).fontWeight(.bold)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            if state.backlogItems.isEmpty {
                Text("All caught up — nothing waiting in raw/.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(state.backlogItems.prefix(8)) { item in
                    HStack(spacing: 8) {
                        Text(item.date).font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                        Text(item.slug).font(.callout).lineLimit(1)
                    }
                }
                if state.backlogItems.count > 8 {
                    Text("+ \(state.backlogItems.count - 8) more").font(.caption).foregroundStyle(.tertiary)
                }
                HStack {
                    Button("Copy opencode prompt") { state.copyBacklogPrompt() }
                    Button {
                        if let v = state.vaultURL {
                            NSWorkspace.shared.open(v.appendingPathComponent("raw/journal"))
                        }
                    } label: { Image(systemName: "folder") }
                    .help("Reveal raw/journal in Finder")
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            Spacer()
            Text("Synthesis stays LLM-owned — the app surfaces what's in raw/ but not yet in wiki/sources/.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
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
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { t in
                Text(t).font(.callout).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}
