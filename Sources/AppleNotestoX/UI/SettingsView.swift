import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var reviewDraft: String = UserDefaults.standard.string(forKey: RepoPaths.reviewFolderOverrideKey) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, WorkspaceStyle.spacing16)
                .padding(.top, WorkspaceStyle.spacing16)
                .padding(.bottom, WorkspaceStyle.spacing8)
                .accessibilityAddTraits(.isHeader)

            Form {
                Section {
                    Text("Create an integration at notion.so/profile/integrations. The secret stays in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Integration token") {
                        SecureField("secret_...", text: $draft)
                            .onAppear { draft = state.token }
                    }
                    if let workspaceName = state.workspaceName {
                        Label("Connected to \(workspaceName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Notion")
                }

                Section {
                    Text("macOS controls permission to read Notes through Automation settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Privacy & Security") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } header: {
                    Text("Apple Notes")
                }

                Section {
                    Text("Leave the advanced folder blank to use the bundled review app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Review folder") {
                        HStack {
                            TextField("~/Projects/AppleNotestoX/review", text: $reviewDraft)
                                .onChange(of: reviewDraft) { _, value in
                                    UserDefaults.standard.set(
                                        value.trimmingCharacters(in: .whitespacesAndNewlines),
                                        forKey: RepoPaths.reviewFolderOverrideKey
                                    )
                                }
                            Button("Choose\u{2026}") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                if panel.runModal() == .OK, let url = panel.url { reviewDraft = url.path }
                            }
                        }
                    }
                } header: {
                    Text("Review")
                }
            }
            .formStyle(.grouped)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Clear token", role: .destructive) {
                    Task {
                        await state.clearToken()
                        draft = ""
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    Task {
                        await state.saveToken(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, WorkspaceStyle.spacing16)
            .padding(.vertical, WorkspaceStyle.spacing12)
            .background(.regularMaterial)
        }
        .frame(width: 520, height: 440)
    }
}

struct PermissionDeniedSheet: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: WorkspaceStyle.spacing16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
                .padding(.top, WorkspaceStyle.spacing8)

            Text("Apple Notes permission required")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("AppleNotestoX needs permission to read your Apple Notes via AppleScript. Grant it in System Settings \u{2192} Privacy & Security \u{2192} Automation, then retry.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: WorkspaceStyle.spacing8) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Retry") {
                    Task {
                        state.permissionDeniedSheet = false
                        await state.loadAppleHierarchy()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, WorkspaceStyle.spacing8)
        }
        .padding(WorkspaceStyle.spacing24)
        .frame(width: 460)
    }
}
