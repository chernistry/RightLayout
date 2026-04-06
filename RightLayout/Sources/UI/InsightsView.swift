import SwiftUI

@available(macOS 13.0, *)
struct InsightsView: View {
    @StateObject private var vm = InsightsViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    private let bundle = SettingsManager.shared.resourceBundle

    private let showsHeader: Bool

    init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if showsHeader {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Insights", bundle: bundle)
                        .font(Theme.Typography.heading())
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Local correction volume, reliability, and which apps consume the most fixes.", bundle: bundle)
                        .font(Theme.Typography.body())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            if !settings.isStatsCollectionEnabled {
                IssueBanner(
                    issue: AppStatusIssue(
                        title: "Statistics paused",
                        message: "Insights stay empty until local statistics collection is enabled again.",
                        severity: .info
                    )
                )
            }

            HStack(spacing: Theme.Spacing.md) {
                MetricTile(label: "Corrections", value: "\(vm.state.allTimeFixes)", detail: "All-time local fixes")
                MetricTile(label: "Time saved", value: vm.formattedTimeSaved, detail: "Estimated from correction events")
                MetricTile(label: "Reliability", value: vm.accuracyString, detail: "Approximate accept rate")
            }

            WorkbenchSection(title: "Last 7 days", detail: "A short horizon is usually more informative than a dashboard full of widgets.") {
                if vm.last7Days.isEmpty {
                    EmptyStateView(
                        title: "No recent activity",
                        systemImage: "calendar",
                        message: "Use RightLayout for a few days and the recent activity table will fill in automatically."
                    )
                    .frame(height: 220)
                } else {
                    VStack(spacing: 0) {
                        ForEach(vm.last7Days, id: \.date) { bucket in
                            HStack {
                                Text(bucket.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(Theme.Typography.meta())
                                    .foregroundStyle(Theme.Color.textSecondary)
                                    .frame(width: 88, alignment: .leading)
                                Text(UIStrings.format("%d fixes", bucket.totalFixes))
                                    .font(Theme.Typography.mono())
                                    .foregroundStyle(Theme.Color.textPrimary)
                                    .frame(width: 90, alignment: .leading)
                                Text(UIStrings.format("%d undos", bucket.undos))
                                    .font(Theme.Typography.mono())
                                    .foregroundStyle(Theme.Color.textSecondary)
                                    .frame(width: 90, alignment: .leading)
                                Text(formatSavedTime(bucket.savedSeconds))
                                    .font(Theme.Typography.mono())
                                    .foregroundStyle(Theme.Color.textSecondary)
                                Spacer()
                            }
                            .padding(.vertical, Theme.Spacing.sm)

                            if bucket.date != vm.last7Days.last?.date {
                                Divider()
                            }
                        }
                    }
                }
            }

            WorkbenchSection(title: "Top apps", detail: "Where the engine is doing the most work right now.") {
                if vm.topApps.isEmpty {
                    EmptyStateView(
                        title: "No app-level data yet",
                        systemImage: "app.badge",
                        message: "App-level insights appear after a few correction events."
                    )
                    .frame(height: 200)
                } else {
                    VStack(spacing: 0) {
                        ForEach(vm.topApps.prefix(5), id: \.key) { app, count in
                            HStack {
                                Text(appDisplayName(app))
                                    .font(Theme.Typography.bodyStrong())
                                    .foregroundStyle(Theme.Color.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(count)")
                                    .font(Theme.Typography.mono())
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                            .padding(.vertical, Theme.Spacing.sm)

                            if app != vm.topApps.prefix(5).last?.key {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .onAppear { vm.load() }
    }

    private func appDisplayName(_ bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        if bundleId.count == 12 && bundleId.allSatisfy(\.isHexDigit) {
            return UIStrings.format("App (%@…)", String(bundleId.prefix(4)))
        }
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }

    private func formatSavedTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return UIStrings.format("%ds saved", Int(seconds))
        }
        if seconds < 3600 {
            return UIStrings.format("%dm saved", Int(seconds / 60))
        }
        return UIStrings.format("%.1fh saved", seconds / 3600)
    }
}

@MainActor
class InsightsViewModel: ObservableObject {
    @Published var state = StatsState()

    var last7Days: [StatsDayBucket] {
        state.history.sorted(by: { $0.date < $1.date }).suffix(7).map { $0 }
    }

    var topApps: [(key: String, value: Int)] {
        state.topApps.sorted(by: { $0.value > $1.value }).prefix(5).map { ($0.key, $0.value) }
    }

    var formattedTimeSaved: String {
        let seconds = state.allTimeSavedSeconds
        if seconds < 60 { return UIStrings.format("%ds", Int(seconds)) }
        if seconds < 3600 { return UIStrings.format("%dm", Int(seconds / 60)) }
        return UIStrings.format("%.1fh", seconds / 3600)
    }

    var accuracyString: String {
        let total = Double(state.allTimeFixes)
        guard total > 0 else { return "—" }
        let rate = 1.0 - (Double(state.allTimeUndos) / total)
        return String(format: "%.0f%%", rate * 100)
    }

    func load() {
        Task {
            let insights = await StatsStore.shared.getInsights()
            self.state = insights
        }
    }
}
