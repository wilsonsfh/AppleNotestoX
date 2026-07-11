import SwiftUI

enum WorkspaceStyle {
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let cornerRadius: CGFloat = 10
}

struct WorkspaceSectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct WorkspaceBadge: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, WorkspaceStyle.spacing8)
            .padding(.vertical, WorkspaceStyle.spacing4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct WorkspaceEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: WorkspaceStyle.spacing8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WorkspaceStyle.spacing24)
    }
}

private struct WorkspaceInsetSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(WorkspaceStyle.spacing16)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            }
    }
}

private struct WorkspaceFooterSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(WorkspaceStyle.spacing12)
            .background(.regularMaterial)
    }
}

extension View {
    func workspaceInsetSurface() -> some View { modifier(WorkspaceInsetSurface()) }
    func workspaceFooterSurface() -> some View { modifier(WorkspaceFooterSurface()) }
}
