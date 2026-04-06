import AppKit
import SwiftUI

public struct MenuBarView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var history = HistoryManager.shared
    @ObservedObject private var updateState = UpdateState.shared
    @ObservedObject private var navigation = SettingsNavigationState.shared
    @Environment(\.openWindow) private var openWindow

    @State private var suggestedLanguage: String? = nil
    @State private var transliterationHint: TransliterationHint? = nil
    @State private var hasAccessibilityPermission = SandboxPermissionManager.shared.checkAccessibilityPermission()

    private struct TransliterationHint: Equatable {
        let id: String
        let text: String
        let language: String
    }

    public init() {}

    private var snapshot: AppStatusSnapshot {
        AppStatusSnapshot.build(
            from: AppStatusSnapshot.Source(
                settings: settings,
                updateState: updateState,
                history: history,
                hasAccessibilityPermission: hasAccessibilityPermission
            )
        )
    }

    public var body: some View {
        Group {
            Text("RightLayout")
                .font(.headline)

            Text(UIStrings.format("%@ · %@", snapshot.runtimeTitle, UIStrings.text(settings.behaviorPreset.displayName)))
                .foregroundStyle(.secondary)

            if !snapshot.issues.isEmpty {
                ForEach(snapshot.issues.prefix(2)) { issue in
                    Text(issue.title)
                        .foregroundStyle(issue.severity == .critical ? .red : .secondary)
                }
            }

            Divider()

            Button {
                settings.isEnabled.toggle()
            } label: {
                Label(
                    settings.isEnabled ? UIStrings.text("Pause RightLayout") : UIStrings.text("Resume RightLayout"),
                    systemImage: settings.isEnabled ? "pause.circle" : "play.circle"
                )
            }

            if !hasAccessibilityPermission {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(UIStrings.text("Grant Accessibility Permission…"), systemImage: "lock.open")
                }
            }

            if updateState.isUpdateAvailable, let version = updateState.latestVersion {
                Button {
                    updateState.openDownloadURL()
                } label: {
                    Label(UIStrings.format("Download v%@", version), systemImage: "arrow.down.circle")
                }
            }

            Divider()

            Menu {
                Toggle(isOn: $settings.autoSwitchLayout) {
                    Text("Switch layout after fix", bundle: settings.resourceBundle)
                }

                Toggle(isOn: $settings.hotkeyEnabled) {
                    Text("Manual correction hotkey", bundle: settings.resourceBundle)
                }

                Toggle(isOn: $settings.isLearningEnabled) {
                    Text("Conservative adaptation", bundle: settings.resourceBundle)
                }

                Divider()

                Picker(UIStrings.text("Correction style"), selection: $settings.behaviorPreset) {
                    ForEach(SettingsManager.BehaviorPreset.allCases) { preset in
                        Text(LocalizedStringKey(preset.displayName), bundle: settings.resourceBundle).tag(preset)
                    }
                }

                Picker(UIStrings.text("Preferred language"), selection: $settings.preferredLanguage) {
                    Text("English", bundle: settings.resourceBundle).tag(Language.english)
                    Text("Russian", bundle: settings.resourceBundle).tag(Language.russian)
                    Text("Hebrew", bundle: settings.resourceBundle).tag(Language.hebrew)
                }
            } label: {
                Label(UIStrings.text("Quick Controls"), systemImage: "slider.horizontal.3")
            }

            if let suggestion = suggestedLanguage {
                Button {
                    applySuggestedLanguage(suggestion)
                    suggestedLanguage = nil
                } label: {
                    Label(UIStrings.format("Switch to %@", suggestion.uppercased()), systemImage: "sparkles")
                }
            }

            if let hint = transliterationHint {
                Button {
                    NotificationCenter.default.post(
                        name: Notification.Name("ApplyTransliterationHint"),
                        object: nil,
                        userInfo: ["id": hint.id]
                    )
                    transliterationHint = nil
                } label: {
                    Label(UIStrings.format("Apply suggestion: %@", hint.text), systemImage: "lightbulb")
                }
            }

            Divider()

            Menu {
                if history.records.isEmpty {
                    Text("No corrections yet", bundle: settings.resourceBundle)
                } else {
                    ForEach(history.records.prefix(8)) { record in
                        Button {
                            Clipboard.copy(record.corrected)
                        } label: {
                            Text("\(record.original) → \(record.corrected)")
                                .lineLimit(1)
                        }
                    }
                }
            } label: {
                Label(UIStrings.text("Recent Corrections"), systemImage: "clock.arrow.circlepath")
            }

            Button {
                openSettings(at: .overview)
            } label: {
                Label(UIStrings.text("Open Control Center…"), systemImage: "rectangle.grid.2x2")
            }

            Button {
                openSettings(at: .diagnostics, diagnosticsTab: .history)
            } label: {
                Label(UIStrings.text("Open Diagnostics…"), systemImage: "waveform.path.ecg")
            }

            Divider()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label(UIStrings.text("Quit RightLayout"), systemImage: "power")
            }
        }
        .onAppear {
            hasAccessibilityPermission = SandboxPermissionManager.shared.checkAccessibilityPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProactiveLayoutHint"))) { notification in
            if let lang = notification.userInfo?["language"] as? String, !lang.isEmpty {
                suggestedLanguage = lang
            } else {
                suggestedLanguage = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TransliterationHint"))) { notification in
            guard let userInfo = notification.userInfo,
                  let id = userInfo["id"] as? String,
                  let text = userInfo["text"] as? String,
                  let language = userInfo["language"] as? String,
                  !text.isEmpty else {
                transliterationHint = nil
                return
            }
            transliterationHint = TransliterationHint(id: id, text: text, language: language)
        }
    }

    private func openSettings(at pane: SettingsPane, diagnosticsTab: DiagnosticsTab? = nil) {
        navigation.open(pane, diagnosticsTab: diagnosticsTab)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    private func applySuggestedLanguage(_ suggestion: String) {
        guard let lang = Language(rawValue: suggestion.lowercased()) else { return }
        let activeLayouts = settings.activeLayouts
        if let preferredLayout = activeLayouts[lang.rawValue],
           InputSourceManager.shared.switchToLayoutVariant(preferredLayout) {
            return
        }
        InputSourceManager.shared.switchTo(language: lang)
    }
}

#Preview {
    MenuBarView()
        .padding()
}
