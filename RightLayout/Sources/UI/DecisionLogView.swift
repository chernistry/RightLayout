import SwiftUI

struct DecisionLogView: View {
    @StateObject private var logStore = DecisionLogStore.shared
    private let bundle = SettingsManager.shared.resourceBundle
    private let showsHeader: Bool

    init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if showsHeader {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Decision Log", bundle: bundle)
                        .font(Theme.Typography.heading())
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Live trace of apply, hint, and skip decisions for debugging behavior that feels wrong in the field.", bundle: bundle)
                        .font(Theme.Typography.body())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                StatusChip(title: logStore.isPaused ? "Paused" : "Live", severity: logStore.isPaused ? .warning : .info)
                Spacer()

                Button {
                    copyEntries()
                } label: {
                    Label(UIStrings.text("Copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .secondaryActionButton()
                .disabled(logStore.entries.isEmpty)

                Button {
                    logStore.isPaused.toggle()
                } label: {
                    Label(UIStrings.text(logStore.isPaused ? "Resume" : "Pause"), systemImage: logStore.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.plain)
                .secondaryActionButton()

                Button(role: .destructive) {
                    logStore.clear()
                } label: {
                    Label(UIStrings.text("Clear"), systemImage: "trash")
                }
                .buttonStyle(.plain)
                .secondaryActionButton()
                .disabled(logStore.entries.isEmpty)
            }

            if logStore.entries.isEmpty {
                EmptyStateView(
                    title: "Waiting for decisions",
                    systemImage: "text.viewfinder",
                    message: "Once RightLayout evaluates words, the live trace will appear here with action, confidence, app, and hypothesis."
                )
                .frame(minHeight: 260)
            } else {
                ScrollViewReader { proxy in
                    List(logStore.entries) { entry in
                        DecisionEntryRow(entry: entry)
                            .id(entry.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .onChange(of: logStore.entries.count) { _ in
                        if let last = logStore.entries.last, !logStore.isPaused {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .frame(minHeight: 280)
            }
        }
    }

    private func copyEntries() {
        let text = logStore.entries.map { entry in
            let confidence = entry.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
            return "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(displayAction(for: entry.action)) \(entry.token) conf=\(confidence) app=\(entry.appName ?? "—") hyp=\(entry.hypothesis ?? "—")"
        }.joined(separator: "\n")
        Clipboard.copy(text)
    }

    private func displayAction(for action: String) -> String {
        switch action {
        case "Applied":
            return UIStrings.text("Applied")
        case "Hint":
            return UIStrings.text("Hint")
        case "Skipped":
            return UIStrings.text("Skipped")
        default:
            return action
        }
    }
}

private struct DecisionEntryRow: View {
    let entry: DecisionLogStore.LogEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(entry.timestamp, style: .time)
                .font(Theme.Typography.mono())
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 76, alignment: .leading)

            Text(displayAction.uppercased())
                .font(Theme.Typography.meta())
                .foregroundStyle(actionColor)
                .frame(width: 72, alignment: .leading)

            Text(entry.token)
                .font(Theme.Typography.mono())
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(minWidth: 100, alignment: .leading)

            Text(entry.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                .font(Theme.Typography.mono())
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 64, alignment: .leading)

            Text(entry.appName ?? "—")
                .font(Theme.Typography.meta())
                .foregroundStyle(Theme.Color.textSecondary)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)

            Text(entry.hypothesis ?? "—")
                .font(Theme.Typography.mono())
                .foregroundStyle(Theme.Color.textMeta)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var actionColor: Color {
        switch entry.action {
        case "Applied":
            Theme.Color.success
        case "Hint":
            Theme.Color.accent
        case "Skipped":
            Theme.Color.warning
        default:
            Theme.Color.textSecondary
        }
    }

    private var displayAction: String {
        switch entry.action {
        case "Applied":
            return UIStrings.text("Applied")
        case "Hint":
            return UIStrings.text("Hint")
        case "Skipped":
            return UIStrings.text("Skipped")
        default:
            return entry.action
        }
    }
}

@MainActor
final class DecisionLogStore: ObservableObject {
    static let shared = DecisionLogStore()

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let token: String
        let confidence: Double?
        let appName: String?
        let action: String
        let hypothesis: String?
    }

    @Published var entries: [LogEntry] = []
    @Published var isPaused: Bool = false

    private let maxEntries = 500

    func log(
        token: String,
        confidence: Double?,
        appName: String?,
        action: String,
        hypothesis: String? = nil
    ) {
        guard !isPaused else { return }
        let entry = LogEntry(
            timestamp: Date(),
            token: token,
            confidence: confidence,
            appName: appName,
            action: action,
            hypothesis: hypothesis
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

#Preview {
    DecisionLogView()
        .padding()
}
