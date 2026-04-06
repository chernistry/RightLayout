import SwiftUI

public struct HistoryView: View {
    @StateObject private var historyManager = HistoryManager.shared
    @State private var searchText = ""
    @State private var selected: Set<HistoryManager.HistoryRecord.ID> = []

    private let bundle = SettingsManager.shared.resourceBundle
    private let showsHeader: Bool

    public init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if showsHeader {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("History", bundle: bundle)
                        .font(Theme.Typography.heading())
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(UIStrings.format("%d recorded corrections", historyManager.records.count))
                        .font(Theme.Typography.meta())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                TextField(text: $searchText) {
                    Text("Search corrections", bundle: bundle)
                }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Spacer()

                Button {
                    copyCorrectedSelection()
                } label: {
                    Label(UIStrings.text("Copy result"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .secondaryActionButton()
                .disabled(selected.isEmpty)

                Button(role: .destructive) {
                    historyManager.clear()
                    selected.removeAll()
                } label: {
                    Label(UIStrings.text("Clear history"), systemImage: "trash")
                }
                .buttonStyle(.plain)
                .secondaryActionButton()
                .disabled(historyManager.records.isEmpty)
            }

            if historyManager.records.isEmpty {
                EmptyStateView(
                    title: NSLocalizedString("No corrections yet", bundle: bundle, comment: ""),
                    systemImage: "clock.arrow.circlepath",
                    message: NSLocalizedString("History becomes useful once RightLayout has corrected a few words locally.", bundle: bundle, comment: "")
                )
                .frame(minHeight: 260)
            } else if filteredRecords.isEmpty {
                EmptyStateView(
                    title: NSLocalizedString("No matches", bundle: bundle, comment: ""),
                    systemImage: "magnifyingglass",
                    message: NSLocalizedString("Try searching by original word, corrected word, or language.", bundle: bundle, comment: "")
                )
                .frame(minHeight: 260)
            } else {
                Table(filteredRecords, selection: $selected) {
                    TableColumn(NSLocalizedString("Time", bundle: bundle, comment: "")) { record in
                        Text(record.timestamp, style: .time)
                            .font(Theme.Typography.mono())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .width(min: 72, ideal: 80, max: 90)

                    TableColumn(NSLocalizedString("Route", bundle: bundle, comment: "")) { record in
                        Text("\(record.fromLang.shortName) → \(record.toLang.shortName)")
                            .font(Theme.Typography.meta())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .width(min: 84, ideal: 92, max: 100)

                    TableColumn(NSLocalizedString("Original", bundle: bundle, comment: "")) { record in
                        Text(record.original)
                            .font(Theme.Typography.mono())
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }

                    TableColumn(NSLocalizedString("Corrected", bundle: bundle, comment: "")) { record in
                        Text(record.corrected)
                            .font(Theme.Typography.mono())
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                    }

                    TableColumn(NSLocalizedString("Confidence", bundle: bundle, comment: "")) { record in
                        Text(confidenceText(record.confidence))
                            .font(Theme.Typography.mono())
                            .foregroundStyle(confidenceColor(record.confidence))
                    }
                    .width(min: 92, ideal: 100, max: 110)

                    TableColumn(NSLocalizedString("Policy", bundle: bundle, comment: "")) { record in
                        Text(record.policy?.rawValue ?? "—")
                            .font(Theme.Typography.meta())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .width(min: 100, ideal: 120, max: 130)

                    TableColumn(NSLocalizedString("App", bundle: bundle, comment: "")) { record in
                        Text(record.appName ?? "—")
                            .font(Theme.Typography.meta())
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 160, max: 220)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
            }
        }
    }

    private var filteredRecords: [HistoryManager.HistoryRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return historyManager.records }
        return historyManager.records.filter { record in
            record.original.localizedCaseInsensitiveContains(q) ||
                record.corrected.localizedCaseInsensitiveContains(q) ||
                record.fromLang.localizedDisplayName.localizedCaseInsensitiveContains(q) ||
                record.toLang.localizedDisplayName.localizedCaseInsensitiveContains(q) ||
                (record.appName?.localizedCaseInsensitiveContains(q) ?? false) ||
                (record.policy?.rawValue.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private func copyCorrectedSelection() {
        let joined = historyManager.records
            .filter { selected.contains($0.id) }
            .map(\.corrected)
            .joined(separator: "\n")
        guard !joined.isEmpty else { return }
        Clipboard.copy(joined)
    }

    private func confidenceText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    private func confidenceColor(_ value: Double?) -> Color {
        guard let value else { return Theme.Color.textMeta }
        if value >= 0.9 { return Theme.Color.success }
        if value >= 0.7 { return Theme.Color.accent }
        return Theme.Color.warning
    }
}

#Preview {
    HistoryView()
        .padding()
}
