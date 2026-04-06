import SwiftUI

struct UserDictionaryView: View {
    @State private var rules: [UserDictionaryRule] = []
    @State private var searchText = ""
    @State private var showAddRule = false
    @State private var selected: Set<UserDictionaryRule.ID> = []

    private let bundle = SettingsManager.shared.resourceBundle

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                TextField(text: $searchText) {
                    Text("Search rules", bundle: bundle)
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

                Spacer()

                Button {
                    showAddRule = true
                } label: {
                    Label {
                        Text("Add Rule", bundle: bundle)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.plain)
                .secondaryActionButton()

                if !rules.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await UserDictionary.shared.clearAll()
                                await loadRules()
                            }
                        } label: {
                            Label {
                                Text("Clear All Rules", bundle: bundle)
                            } icon: {
                                Image(systemName: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .menuStyle(.borderlessButton)
                    .help(Text("More actions", bundle: bundle))
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)

            Divider()

            if filteredRules.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? NSLocalizedString("No manual rules yet", bundle: bundle, comment: "") : NSLocalizedString("No matches", bundle: bundle, comment: ""),
                    systemImage: searchText.isEmpty ? "book.closed" : "magnifyingglass",
                    message: searchText.isEmpty ? NSLocalizedString("Add an explicit rule when a specific word should always stay unchanged or prefer one language.", bundle: bundle, comment: "") : nil,
                    primaryAction: searchText.isEmpty
                    ? .init(title: NSLocalizedString("Add Rule", bundle: bundle, comment: ""), systemImage: "plus", style: .primary, action: { showAddRule = true })
                    : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredRules, selection: $selected) {
                    TableColumn(NSLocalizedString("Token", bundle: bundle, comment: "")) { rule in
                        Text(rule.token)
                            .font(Theme.Typography.numericData())
                            .lineLimit(1)
                    }
                    TableColumn(NSLocalizedString("Action", bundle: bundle, comment: "")) { rule in
                        RuleActionBadge(rule: rule)
                    }
                    TableColumn(NSLocalizedString("Source", bundle: bundle, comment: "")) { rule in
                        Text(rule.source == .learned ? NSLocalizedString("Learned", bundle: bundle, comment: "") : NSLocalizedString("Manual", bundle: bundle, comment: ""))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn(NSLocalizedString("Updated", bundle: bundle, comment: "")) { rule in
                        Text(rule.updatedAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: UserDictionaryRule.ID.self) { ids in
                    if !ids.isEmpty {
                        Button(role: .destructive) {
                            for id in ids {
                                deleteRule(id)
                            }
                        } label: {
                            Label {
                                Text("Delete", bundle: bundle)
                            } icon: {
                                Image(systemName: "trash")
                            }
                        }
                    } else {
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadRules() }
        .sheet(isPresented: $showAddRule) {
            AddRuleDialog { newRule in
                Task {
                    await UserDictionary.shared.addRule(newRule)
                    await loadRules()
                }
            }
        }
    }

    private var filteredRules: [UserDictionaryRule] {
        let sorted = rules.sorted { $0.updatedAt > $1.updatedAt }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return sorted }
        return sorted.filter { $0.token.localizedCaseInsensitiveContains(q) }
    }

    private func loadRules() async {
        rules = await UserDictionary.shared.getAllRules()
    }

    private func deleteRule(_ id: UUID) {
        Task {
            await UserDictionary.shared.removeRule(id: id)
            await loadRules()
        }
    }
}

private struct RuleActionBadge: View {
    let rule: UserDictionaryRule

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(label)
                .font(Theme.Typography.label())
        }
        .foregroundStyle(color)
    }

    private var icon: String {
        switch rule.action {
        case .none: "questionmark.circle"
        case .keepAsIs: "hand.raised"
        case .preferLanguage: "scope"
        case .preferHypothesis: "wand.and.stars"
        }
    }

    private var label: String {
        let bundle = SettingsManager.shared.resourceBundle
        switch rule.action {
        case .none:
            return NSLocalizedString("Pending", bundle: bundle, comment: "")
        case .keepAsIs:
            return NSLocalizedString("Keep", bundle: bundle, comment: "")
        case .preferLanguage(let lang):
            let fmt = NSLocalizedString("Prefer %@", bundle: bundle, comment: "")
            return String(format: fmt, lang.shortName)
        case .preferHypothesis(let h):
            let fmt = NSLocalizedString("Prefer %@", bundle: bundle, comment: "")
            return String(format: fmt, h)
        }
    }

    private var color: Color {
        switch rule.action {
        case .none: return Theme.Color.textTertiary
        case .keepAsIs: return Theme.Color.success
        case .preferLanguage: return Theme.Color.accent
        case .preferHypothesis: return Theme.Color.brand
        }
    }

}
#Preview {
    UserDictionaryView()
        .frame(width: 820, height: 420)
}
