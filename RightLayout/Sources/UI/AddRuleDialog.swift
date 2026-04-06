import SwiftUI

struct AddRuleDialog: View {
    @Environment(\.dismiss) var dismiss
    var onAdd: (UserDictionaryRule) -> Void
    
    @State private var token: String = ""
    @State private var matchMode: MatchMode = .exact
    @State private var actionType: ActionType = .keepAsIs
    @State private var selectedLanguage: Language = .english
    
    enum ActionType: String, CaseIterable, Identifiable {
        case keepAsIs = "Keep As-Is"
        case preferLanguage = "Prefer Language"
        
        var id: String { rawValue }
    }
    
    private let bundle = SettingsManager.shared.resourceBundle

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Add Dictionary Rule", bundle: bundle)
                .font(Theme.Typography.sectionTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word or Phrase", bundle: bundle).font(Theme.Typography.label()).foregroundStyle(Theme.Color.textSecondary)
                    TextField("", text: $token)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Match Mode", bundle: bundle).font(Theme.Typography.label()).foregroundStyle(Theme.Color.textSecondary)
                    Picker("", selection: $matchMode) {
                        Text("Exact Case", bundle: bundle).tag(MatchMode.exact)
                        Text("Case Insensitive", bundle: bundle).tag(MatchMode.caseInsensitive)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action", bundle: bundle).font(Theme.Typography.label()).foregroundStyle(Theme.Color.textSecondary)
                    Picker("", selection: $actionType) {
                        ForEach(ActionType.allCases) { type in
                            Text(NSLocalizedString(type.rawValue, bundle: bundle, comment: "")).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                
                if actionType == .preferLanguage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Language", bundle: bundle).font(Theme.Typography.label()).foregroundStyle(Theme.Color.textSecondary)
                        Picker("", selection: $selectedLanguage) {
                            Text("🇺🇸 English", bundle: bundle).tag(Language.english)
                            Text("🇷🇺 Russian", bundle: bundle).tag(Language.russian)
                            Text("🇮🇱 Hebrew", bundle: bundle).tag(Language.hebrew)
                        }
                        .labelsHidden()
                    }
                }
                
                Text(descriptionForAction)
                    .font(Theme.Typography.label())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(height: 30, alignment: .topLeading)
            }
            .padding()
            
            HStack {
                Button(role: .cancel) { dismiss() } label: {
                    Text("Cancel", bundle: bundle)
                }
                .secondaryActionButton()
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: {
                    let ruleAction: RuleAction
                    switch actionType {
                    case .keepAsIs: ruleAction = .keepAsIs
                    case .preferLanguage: ruleAction = .preferLanguage(selectedLanguage)
                    }
                    
                    let rule = UserDictionaryRule(
                        id: UUID(),
                        token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                        matchMode: matchMode,
                        scope: .global,
                        action: ruleAction,
                        source: .manual,
                        evidence: RuleEvidence(),
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    onAdd(rule)
                    dismiss()
                }) {
                    Text("Add Rule", bundle: bundle)
                }
                .primaryActionButton()
                .disabled(token.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350)
        .padding(.top, Theme.Spacing.sm)
        .background(Theme.Color.pageBackgroundPrimary)
    }
    
    var descriptionForAction: String {
        switch actionType {
        case .keepAsIs: 
            return NSLocalizedString("Never auto-correct this word.", bundle: bundle, comment: "")
        case .preferLanguage: 
            let fmt = NSLocalizedString("If ambiguous (e.g. mixed characters), treat as %@.", bundle: bundle, comment: "")
            return String(format: fmt, selectedLanguage.localizedDisplayName)
        }
    }
}
