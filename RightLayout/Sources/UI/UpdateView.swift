import SwiftUI

struct UpdateAvailableView: View {
    let release: GitHubRelease
    let onDownload: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Theme.Color.accent)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(UIStrings.text("Update available"))
                        .font(Theme.Typography.heading())
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(UIStrings.format("Version %@ is ready to download from GitHub Releases.", release.version))
                        .font(Theme.Typography.body())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            if let body = release.body, !body.isEmpty {
                WorkbenchSection(title: "Release notes", detail: "Shown exactly as published for this release.") {
                    ScrollView {
                        Text(body)
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(action: onDownload) {
                    Label(UIStrings.text("Download update"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.plain)
                .primaryActionButton()

                Button(action: onDismiss) {
                    Text(UIStrings.text("Later"))
                }
                .buttonStyle(.plain)
                .secondaryActionButton()
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
        .background(Theme.Color.pageBackgroundPrimary)
    }
}

struct UpdateCheckButton: View {
    @ObservedObject var updateState: UpdateState
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Button {
                    errorMessage = nil
                    Task {
                        await updateState.checkForUpdate()
                        if case .error(let error) = updateState.lastResult {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    if updateState.isChecking {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text(UIStrings.text("Checking…"))
                        }
                    } else {
                        Label(UIStrings.text("Check for updates"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .secondaryActionButton()
                .disabled(updateState.isChecking)

                Spacer()

                statusView
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.meta())
                    .foregroundStyle(Theme.Color.warning)
            }

            if let lastCheck = updateState.lastCheckDate ?? SettingsManager.shared.lastUpdateCheckDate {
                Text(UIStrings.format("Last checked %@", lastCheck.formatted(.relative(presentation: .named))))
                    .font(Theme.Typography.meta())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updateState.lastResult {
        case .upToDate:
            StatusChip(title: "Up to date", severity: .info)
        case .updateAvailable(let release):
            StatusChip(title: UIStrings.format("v%@ ready", release.version), severity: .info)
        case .error:
            StatusChip(title: "Check failed", severity: .warning)
        case nil:
            EmptyView()
        }
    }
}

struct UpdateAvailableButton: View {
    let version: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(UIStrings.format("Update available (v%@)", version), systemImage: "arrow.down.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .secondaryActionButton()
    }
}
