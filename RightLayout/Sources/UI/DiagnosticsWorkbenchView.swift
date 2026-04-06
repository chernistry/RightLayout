import SwiftUI

struct DiagnosticsWorkbenchView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var navigation = SettingsNavigationState.shared
    @State private var hasAccessibilityPermission = SandboxPermissionManager.shared.checkAccessibilityPermission()

    private var availableTabs: [DiagnosticsTab] {
        settings.isAdvancedMode ? DiagnosticsTab.allCases : [.history, .insights]
    }

    private var selectedTab: DiagnosticsTab {
        availableTabs.contains(navigation.selectedDiagnosticsTab) ? navigation.selectedDiagnosticsTab : .history
    }

    private var issues: [AppStatusIssue] {
        var issues: [AppStatusIssue] = []
        if !hasAccessibilityPermission {
            issues.append(
                AppStatusIssue(
                    title: "Runtime blocked",
                    message: "Diagnostics may still show local history, but live correction is blocked without Accessibility access.",
                    severity: .critical
                )
            )
        }
        if !settings.isStatsCollectionEnabled {
            issues.append(
                AppStatusIssue(
                    title: "Statistics paused",
                    message: "Insights and some history context are limited until local statistics collection is enabled again.",
                    severity: .info
                )
            )
        }
        return issues
    }

    var body: some View {
        WorkbenchPage(
            title: "Diagnostics",
            subtitle: "Observe what the engine did, where it acted, and whether runtime conditions explain misses or surprises.",
            issues: issues,
            accessory: AnyView(
                Picker(UIStrings.text("Diagnostics tab"), selection: $navigation.selectedDiagnosticsTab) {
                    ForEach(availableTabs) { tab in
                        Text(LocalizedStringKey(tab.title), bundle: settings.resourceBundle).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: settings.isAdvancedMode ? 340 : 220)
            )
        ) {
            switch selectedTab {
            case .history:
                WorkbenchSection(title: "Correction history", detail: "Structured comparison of original text, result, policy, confidence, and app.") {
                    HistoryView(showsHeader: false)
                }
            case .insights:
                WorkbenchSection(title: "Operational insights", detail: "A concise picture of usage and reliability rather than decorative dashboard widgets.") {
                    if #available(macOS 13.0, *) {
                        InsightsView(showsHeader: false)
                    } else {
                        Text("Insights requires macOS 13 or later.", bundle: settings.resourceBundle)
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            case .decisionLog:
                WorkbenchSection(title: "Live trace", detail: "Use this when a correction fired unexpectedly or failed to fire at all.") {
                    DecisionLogView(showsHeader: false)
                }
            }
        }
        .onAppear {
            hasAccessibilityPermission = SandboxPermissionManager.shared.checkAccessibilityPermission()
            if !availableTabs.contains(navigation.selectedDiagnosticsTab) {
                navigation.selectedDiagnosticsTab = .history
            }
        }
        .onChange(of: settings.isAdvancedMode) { _ in
            if !availableTabs.contains(navigation.selectedDiagnosticsTab) {
                navigation.selectedDiagnosticsTab = .history
            }
        }
    }
}
