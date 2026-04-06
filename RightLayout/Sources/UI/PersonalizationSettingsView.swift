import SwiftUI

struct PersonalizationSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @State private var stats: (contexts: Int, events: Int) = (0, 0)
    @State private var showingResetAlert = false

    var body: some View {
        WorkbenchPage(
            title: "Adaptation",
            subtitle: "Keep learning conservative, visible, and reversible. This area is for demotion and explicit rules, not hidden cleverness.",
            issues: []
        ) {
            WorkbenchSection(title: "Adaptive behavior", detail: "These settings should only make the engine safer, never more aggressive.") {
                SettingsToggleRow(
                    title: "Enable conservative adaptation",
                    detail: "Locally remembers risky contexts and demotes future auto-corrections instead of promoting them.",
                    isOn: $settings.isLearningEnabled
                )

                Divider()

                SettingsToggleRow(
                    title: "Enable transliteration suggestions",
                    detail: "Shows a bounded hint for transliterated Latin input, but never auto-applies it.",
                    isOn: $settings.transliterationHintsEnabled
                )
            }

            WorkbenchSection(title: "State and reset", detail: "Adaptation should be auditable and easy to clear when behavior drifts.") {
                HStack(spacing: Theme.Spacing.md) {
                    MetricTile(label: "Active contexts", value: "\(stats.contexts)")
                    MetricTile(label: "Learning events", value: "\(stats.events)")
                    MetricTile(label: "Safety model", value: "Calibrated", detail: settings.isLearningEnabled ? "Demotion only" : "Disabled")
                }

                SummaryRow(title: "Reset personalization", detail: "Deletes local adaptive state and online adapter state. Manual rules remain separate below.") {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Text("Reset adaptation", bundle: settings.resourceBundle)
                    }
                    .buttonStyle(.plain)
                    .secondaryActionButton()
                    .disabled(stats.contexts == 0 && stats.events == 0)
                }
            }

            WorkbenchSection(title: "Manual rules", detail: "Explicit dictionary rules are the only durable way to force behavior for specific words or phrases.") {
                UserDictionaryView()
                    .frame(minHeight: 320)
            }
        }
        .task {
            await refreshStats()
        }
        .alert(Text("Reset personalization?", bundle: settings.resourceBundle), isPresented: $showingResetAlert) {
            Button(role: .cancel) { } label: {
                Text("Cancel", bundle: settings.resourceBundle)
            }
            Button(role: .destructive) {
                Task {
                    await PersonalizationStore.shared.reset()
                    await OnlineAdapter.shared.reset()
                    await refreshStats()
                }
            } label: {
                Text("Reset", bundle: settings.resourceBundle)
            }
        } message: {
            Text("This clears local learned habits and conservative adaptation data. Manual dictionary rules remain managed separately.", bundle: settings.resourceBundle)
        }
    }

    private func refreshStats() async {
        stats = await PersonalizationStore.shared.getStats()
    }
}
