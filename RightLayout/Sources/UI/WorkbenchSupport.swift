import AppKit
import SwiftUI

enum UIStrings {
    static var bundle: Bundle {
        MainActor.assumeIsolated { SettingsManager.shared.resourceBundle }
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case overview
    case general
    case languages
    case hotkey
    case apps
    case adaptation
    case diagnostics
    case updates
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .general: "General"
        case .languages: "Languages"
        case .hotkey: "Hotkey"
        case .apps: "Apps"
        case .adaptation: "Adaptation"
        case .diagnostics: "Diagnostics"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .general: "gearshape"
        case .languages: "globe"
        case .hotkey: "keyboard"
        case .apps: "app.badge"
        case .adaptation: "brain"
        case .diagnostics: "waveform.path.ecg"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

enum DiagnosticsTab: String, CaseIterable, Identifiable {
    case history
    case insights
    case decisionLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .insights: "Insights"
        case .decisionLog: "Decision Log"
        }
    }
}

@MainActor
final class SettingsNavigationState: ObservableObject {
    static let shared = SettingsNavigationState()

    @Published var selectedPane: SettingsPane = .overview
    @Published var selectedDiagnosticsTab: DiagnosticsTab = .history

    func open(_ pane: SettingsPane, diagnosticsTab: DiagnosticsTab? = nil) {
        selectedPane = pane
        if let diagnosticsTab {
            selectedDiagnosticsTab = diagnosticsTab
        }
    }
}

struct AppStatusIssue: Identifiable, Hashable {
    enum Severity: Hashable {
        case info
        case warning
        case critical
    }

    let id = UUID()
    let title: String
    let message: String
    let severity: Severity
}

struct AppStatusSnapshot {
    struct Source {
        let isEnabled: Bool
        let hasAccessibilityPermission: Bool
        let updateAvailableVersion: String?
        let isStatsCollectionEnabled: Bool
        let isStrictPrivacyMode: Bool
        let behaviorPresetTitle: String
        let preferredLanguageTitle: String
        let activeLayouts: [String: String]
        let excludedAppsCount: Int
        let recentCorrectionDescription: String?
    }

    let runtimeTitle: String
    let runtimeMessage: String
    let behaviorSummary: String
    let coverageSummary: String
    let layoutSummary: [String]
    let recentCorrectionDescription: String?
    let issues: [AppStatusIssue]

    static func build(from source: Source) -> AppStatusSnapshot {
        var issues: [AppStatusIssue] = []

        if !source.hasAccessibilityPermission {
            issues.append(
                AppStatusIssue(
                    title: UIStrings.text("Accessibility required"),
                    message: UIStrings.text("Text correction is blocked until Accessibility access is granted in System Settings."),
                    severity: .critical
                )
            )
        }

        if !source.isEnabled {
            issues.append(
                AppStatusIssue(
                    title: UIStrings.text("Runtime paused"),
                    message: UIStrings.text("RightLayout is installed but currently not correcting text."),
                    severity: .warning
                )
            )
        }

        if let updateVersion = source.updateAvailableVersion {
            issues.append(
                AppStatusIssue(
                    title: UIStrings.text("Update available"),
                    message: UIStrings.format("Version %@ is ready to download.", updateVersion),
                    severity: .info
                )
            )
        }

        if !source.isStatsCollectionEnabled {
            issues.append(
                AppStatusIssue(
                    title: UIStrings.text("Insights paused"),
                    message: UIStrings.text("Diagnostics history is local only and currently turned off."),
                    severity: .info
                )
            )
        }

        let runtimeTitle: String
        let runtimeMessage: String
        if !source.hasAccessibilityPermission {
            runtimeTitle = UIStrings.text("Blocked")
            runtimeMessage = UIStrings.text("Grant Accessibility permission to enable live correction.")
        } else if !source.isEnabled {
            runtimeTitle = UIStrings.text("Paused")
            runtimeMessage = UIStrings.text("Runtime is healthy but automatic correction is paused.")
        } else {
            runtimeTitle = UIStrings.text("Ready")
            runtimeMessage = UIStrings.text("Monitoring keyboard input and correcting supported text fields.")
        }

        let coverageSummary: String = if source.excludedAppsCount == 0 {
            UIStrings.text("All apps")
        } else {
            UIStrings.format("%d excluded apps", source.excludedAppsCount)
        }

        let layoutSummary = source.activeLayouts
            .sorted { $0.key < $1.key }
            .map { "\($0.key.uppercased()): \($0.value)" }

        return AppStatusSnapshot(
            runtimeTitle: runtimeTitle,
            runtimeMessage: runtimeMessage,
            behaviorSummary: UIStrings.format("%@ · preferred %@", UIStrings.text(source.behaviorPresetTitle), source.preferredLanguageTitle),
            coverageSummary: coverageSummary,
            layoutSummary: layoutSummary,
            recentCorrectionDescription: source.recentCorrectionDescription,
            issues: issues
        )
    }
}

@MainActor
extension AppStatusSnapshot.Source {
    init(
        settings: SettingsManager = .shared,
        updateState: UpdateState = .shared,
        history: HistoryManager = .shared,
        hasAccessibilityPermission: Bool
    ) {
        let recentCorrectionDescription = history.records.first.map { record in
            "\(record.original) → \(record.corrected)"
        }

        self.init(
            isEnabled: settings.isEnabled,
            hasAccessibilityPermission: hasAccessibilityPermission,
            updateAvailableVersion: updateState.latestVersion,
            isStatsCollectionEnabled: settings.isStatsCollectionEnabled,
            isStrictPrivacyMode: settings.isStrictPrivacyMode,
            behaviorPresetTitle: settings.behaviorPreset.displayName,
            preferredLanguageTitle: settings.preferredLanguage.shortName,
            activeLayouts: settings.activeLayouts,
            excludedAppsCount: settings.excludedApps.count,
            recentCorrectionDescription: recentCorrectionDescription
        )
    }
}

@MainActor
extension Language {
    var localizedDisplayName: String {
        let bundle = SettingsManager.shared.resourceBundle
        switch self {
        case .english:
            return NSLocalizedString("English", bundle: bundle, comment: "")
        case .russian:
            return NSLocalizedString("Russian", bundle: bundle, comment: "")
        case .hebrew:
            return NSLocalizedString("Hebrew", bundle: bundle, comment: "")
        }
    }

    var shortName: String {
        switch self {
        case .english: "EN"
        case .russian: "RU"
        case .hebrew: "HE"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇺🇸"
        case .russian: "🇷🇺"
        case .hebrew: "🇮🇱"
        }
    }
}

struct WorkbenchPage<Content: View>: View {
    let title: String
    let subtitle: String
    let issues: [AppStatusIssue]
    let accessory: AnyView?
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String,
        issues: [AppStatusIssue] = [],
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.issues = issues
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(UIStrings.text(title))
                            .font(Theme.Typography.pageTitle())
                            .foregroundStyle(Theme.Color.textPrimary)

                        Text(UIStrings.text(subtitle))
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if let accessory {
                        accessory
                    }
                }

                if !issues.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(issues) { issue in
                            IssueBanner(issue: issue)
                        }
                    }
                }

                content
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .background(Theme.Color.pageBackgroundPrimary)
    }
}

struct WorkbenchSection<Content: View>: View {
    let title: String
    let detail: String?
    let accessory: AnyView?
    @ViewBuilder var content: Content

    init(
        title: String,
        detail: String? = nil,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(UIStrings.text(title))
                        .font(Theme.Typography.sectionTitle())
                        .foregroundStyle(Theme.Color.textPrimary)
                    if let detail, !detail.isEmpty {
                        Text(UIStrings.text(detail))
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }

                Spacer()

                if let accessory {
                    accessory
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                content
            }
        }
        .padding(Theme.Spacing.lg)
        .controlSurface(level: 0)
    }
}

struct StatusChip: View {
    let title: String
    let severity: AppStatusIssue.Severity

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(UIStrings.text(title))
                .font(Theme.Typography.meta())
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private var color: SwiftUI.Color {
        switch severity {
        case .info: Theme.Color.accent
        case .warning: Theme.Color.warning
        case .critical: Theme.Color.error
        }
    }
}

struct IssueBanner: View {
    let issue: AppStatusIssue

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(UIStrings.text(issue.title))
                    .font(Theme.Typography.label())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(UIStrings.text(issue.message))
                    .font(Theme.Typography.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }

    private var color: SwiftUI.Color {
        switch issue.severity {
        case .info: Theme.Color.accent
        case .warning: Theme.Color.warning
        case .critical: Theme.Color.error
        }
    }

    private var symbolName: String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String?

    init(label: String, value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(UIStrings.text(label))
                .font(Theme.Typography.meta())
                .foregroundStyle(Theme.Color.textSecondary)
            Text(value)
                .font(Theme.Typography.heading())
                .foregroundStyle(Theme.Color.textPrimary)
                .monospacedDigit()
            if let detail, !detail.isEmpty {
                Text(UIStrings.text(detail))
                    .font(Theme.Typography.meta())
                    .foregroundStyle(Theme.Color.textMeta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .controlSurface(level: 1)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(UIStrings.text(title))
                    .font(Theme.Typography.bodyStrong())
                    .foregroundStyle(Theme.Color.textPrimary)
                if let detail, !detail.isEmpty {
                    Text(UIStrings.text(detail))
                        .font(Theme.Typography.meta())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct SummaryRow<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var accessory: Accessory

    init(title: String, detail: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(UIStrings.text(title))
                    .font(Theme.Typography.bodyStrong())
                    .foregroundStyle(Theme.Color.textPrimary)
                if let detail, !detail.isEmpty {
                    Text(UIStrings.text(detail))
                        .font(Theme.Typography.meta())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer()
            accessory
        }
    }
}
