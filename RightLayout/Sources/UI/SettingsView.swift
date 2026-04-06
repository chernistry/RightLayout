import AppKit
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var navigation = SettingsNavigationState.shared
    @State private var searchText = ""

    public init() {}

    private var visiblePanes: [SettingsPane] {
        SettingsPane.allCases
    }

    public var body: some View {
        NavigationSplitView {
            List(visiblePanes, selection: $navigation.selectedPane) { pane in
                Label(
                    title: { Text(LocalizedStringKey(pane.title), bundle: settings.resourceBundle) },
                    icon: { Image(systemName: pane.systemImage) }
                )
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationTitle("RightLayout")
        } detail: {
            Group {
                if !searchText.isEmpty {
                    SettingsSearchResultsView(query: searchText) { pane in
                        navigation.open(pane)
                        searchText = ""
                    }
                } else {
                    SettingsPaneView(pane: navigation.selectedPane)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.pageBackgroundPrimary)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search settings", bundle: settings.resourceBundle))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $settings.isAdvancedMode) {
                    Label {
                        Text("Advanced diagnostics", bundle: settings.resourceBundle)
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}

private struct SettingsPaneView: View {
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .overview:
            OverviewPane()
        case .general:
            GeneralPane()
        case .languages:
            LanguagesPane()
        case .hotkey:
            HotkeyPane()
        case .apps:
            AppsPane()
        case .adaptation:
            PersonalizationSettingsView(settings: SettingsManager.shared)
        case .diagnostics:
            DiagnosticsWorkbenchView()
        case .updates:
            UpdatesPane()
        case .about:
            AboutPane()
        }
    }
}

private struct OverviewPane: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var updateState = UpdateState.shared
    @ObservedObject private var history = HistoryManager.shared
    @State private var hasAccessibilityPermission = SandboxPermissionManager.shared.checkAccessibilityPermission()

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

    var body: some View {
        WorkbenchPage(
            title: "Overview",
            subtitle: "Operational status, correction posture, and the signals that matter before you trust automatic changes.",
            issues: snapshot.issues,
            accessory: AnyView(
                HStack(spacing: Theme.Spacing.sm) {
                    StatusChip(
                        title: snapshot.runtimeTitle,
                        severity: hasAccessibilityPermission ? (settings.isEnabled ? .info : .warning) : .critical
                    )
                    if updateState.isUpdateAvailable {
                        StatusChip(title: "Update", severity: .info)
                    }
                }
            )
        ) {
            HStack(spacing: Theme.Spacing.md) {
                MetricTile(label: "Runtime", value: snapshot.runtimeTitle, detail: snapshot.runtimeMessage)
                MetricTile(label: "Behavior", value: settings.behaviorPreset.displayName, detail: snapshot.behaviorSummary)
                MetricTile(label: "Coverage", value: snapshot.coverageSummary, detail: snapshot.layoutSummary.joined(separator: " · "))
            }

            WorkbenchSection(
                title: "Current setup",
                detail: "The app should feel invisible when these settings and permissions line up."
            ) {
                SummaryRow(title: "Accessibility permission", detail: "Required for live monitoring and verified corrections.") {
                    if hasAccessibilityPermission {
                        StatusChip(title: "Granted", severity: .info)
                    } else {
                        Button {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Grant access", bundle: settings.resourceBundle)
                        }
                        .buttonStyle(.plain)
                        .primaryActionButton()
                    }
                }

                Divider()

                SummaryRow(title: "Preferred language", detail: "Used as a tie-breaker when the token is ambiguous.") {
                    Text(settings.preferredLanguage.localizedDisplayName)
                        .font(Theme.Typography.bodyStrong())
                        .foregroundStyle(Theme.Color.textPrimary)
                }

                Divider()

                SummaryRow(title: "Recent correction", detail: "The latest visible outcome helps confirm the engine is actually active.") {
                    Text(snapshot.recentCorrectionDescription ?? UIStrings.text("No corrections yet"))
                        .font(Theme.Typography.mono())
                        .foregroundStyle(snapshot.recentCorrectionDescription == nil ? Theme.Color.textMeta : Theme.Color.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: 320, alignment: .trailing)
                }
            }

            WorkbenchSection(
                title: "Go deeper",
                detail: "Use diagnostics when behavior feels off, or tighten adaptation when the app should become more conservative."
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        SettingsNavigationState.shared.open(.diagnostics, diagnosticsTab: .history)
                    } label: {
                        Label {
                            Text("Open diagnostics", bundle: settings.resourceBundle)
                        } icon: {
                            Image(systemName: "waveform.path.ecg")
                        }
                    }
                    .buttonStyle(.plain)
                    .primaryActionButton()

                    Button {
                        SettingsNavigationState.shared.open(.adaptation)
                    } label: {
                        Label {
                            Text("Open adaptation", bundle: settings.resourceBundle)
                        } icon: {
                            Image(systemName: "brain")
                        }
                    }
                    .buttonStyle(.plain)
                    .secondaryActionButton()
                }
            }
        }
        .onAppear {
            hasAccessibilityPermission = SandboxPermissionManager.shared.checkAccessibilityPermission()
        }
    }
}

private struct GeneralPane: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        WorkbenchPage(
            title: "General",
            subtitle: "Choose the default behavior, language bias, and local privacy posture.",
            issues: []
        ) {
            WorkbenchSection(title: "Runtime behavior", detail: "One primary posture, one layout handoff rule, one launch decision.") {
                SettingsToggleRow(
                    title: "Enable auto-correction",
                    detail: "Automatically fix text typed in the wrong keyboard layout.",
                    isOn: $settings.isEnabled
                )

                Divider()

                SummaryRow(title: "Correction style", detail: settings.behaviorPreset.description) {
                    Picker("", selection: $settings.behaviorPreset) {
                        ForEach(SettingsManager.BehaviorPreset.allCases) { preset in
                            Text(LocalizedStringKey(preset.displayName), bundle: settings.resourceBundle).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                Divider()

                SettingsToggleRow(
                    title: "Switch system layout after fix",
                    detail: "Keeps the keyboard aligned with the language of the corrected word.",
                    isOn: $settings.autoSwitchLayout
                )

                Divider()

                SettingsToggleRow(
                    title: "Launch at login",
                    detail: "Start RightLayout with macOS so correction is available immediately.",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            LaunchAtLogin.isEnabled = newValue
                        }
                    )
                )
            }

            WorkbenchSection(title: "Language bias", detail: "Tie-breakers should be explicit so ambiguous tokens never feel random.") {
                SummaryRow(title: "Preferred language", detail: "Used only when the token is otherwise ambiguous.") {
                    Picker("", selection: $settings.preferredLanguage) {
                        Text("English", bundle: settings.resourceBundle).tag(Language.english)
                        Text("Russian", bundle: settings.resourceBundle).tag(Language.russian)
                        Text("Hebrew", bundle: settings.resourceBundle).tag(Language.hebrew)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                Divider()

                SummaryRow(title: "Interface language", detail: "Applies to the settings UI and other user-facing text only.") {
                    Picker("", selection: $settings.appLanguage) {
                        ForEach(SettingsManager.AppLanguage.allCases) { lang in
                            Text(LocalizedStringKey(lang.displayName), bundle: settings.resourceBundle).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }

            WorkbenchSection(title: "Privacy and insights", detail: "Everything remains local; these controls decide how much operational evidence you keep.") {
                SettingsToggleRow(
                    title: "Enable usage statistics",
                    detail: "Collect local statistics so diagnostics and insights have something real to show.",
                    isOn: $settings.isStatsCollectionEnabled
                )

                Divider()

                SettingsToggleRow(
                    title: "Strict privacy mode",
                    detail: "Store anonymized app identifiers instead of readable app names in local diagnostics.",
                    isOn: $settings.isStrictPrivacyMode
                )
                .disabled(!settings.isStatsCollectionEnabled)

                Divider()

                SummaryRow(title: "Reset insights data", detail: "Clears local statistics without touching correction settings.") {
                    Button(role: .destructive) {
                        Task { await StatsStore.shared.reset() }
                    } label: {
                        Text("Reset data", bundle: settings.resourceBundle)
                    }
                    .buttonStyle(.plain)
                    .secondaryActionButton()
                }
            }
        }
    }
}

private struct LanguagesPane: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var installed: [String: [InputSourceManager.InstalledLayoutVariant]] = [:]

    var body: some View {
        WorkbenchPage(
            title: "Languages",
            subtitle: "Map each working language to the exact macOS keyboard variant you actually use.",
            issues: []
        ) {
            WorkbenchSection(
                title: "Active layout variants",
                detail: "Exact layout IDs reduce false positives in variant-sensitive cases such as Russian phonetic or Hebrew QWERTY."
            ) {
                layoutPickerRow(title: "English layout", languageCode: "en", fallback: "us")
                Divider()
                layoutPickerRow(title: "Russian layout", languageCode: "ru", fallback: "russianwin")
                Divider()
                layoutPickerRow(title: "Hebrew layout", languageCode: "he", fallback: "hebrew")
            }

            WorkbenchSection(title: "System sync", detail: "Use the OS list as the source of truth when your installed variants change.") {
                SummaryRow(title: "Auto-detect from macOS", detail: "Scans installed input sources and chooses the most likely variant per language.") {
                    Button {
                        settings.autoDetectLayouts()
                        installed = InputSourceManager.shared.installedLayoutVariantsByLanguage()
                    } label: {
                        Label {
                            Text("Refresh layouts", bundle: settings.resourceBundle)
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.plain)
                    .secondaryActionButton()
                }
            }
        }
        .task {
            installed = InputSourceManager.shared.installedLayoutVariantsByLanguage()
        }
    }

    @ViewBuilder
    private func layoutPickerRow(title: String, languageCode: String, fallback: String) -> some View {
        SummaryRow(title: title, detail: "Selected variant will be used for detection and layout switching.") {
            Picker("", selection: binding(for: languageCode, fallback: fallback)) {
                if (installed[languageCode] ?? []).isEmpty {
                    Text("No matching layouts found", bundle: settings.resourceBundle).tag(binding(for: languageCode, fallback: fallback).wrappedValue)
                } else {
                    ForEach(installed[languageCode] ?? []) { option in
                        Text(option.displayName).tag(option.layoutId)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 220)
        }
    }

    private func binding(for languageCode: String, fallback: String) -> Binding<String> {
        Binding(
            get: { settings.activeLayouts[languageCode] ?? fallback },
            set: { newValue in settings.activeLayouts[languageCode] = newValue }
        )
    }
}

private struct HotkeyPane: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        WorkbenchPage(
            title: "Hotkey",
            subtitle: "Manual correction is for deliberate recovery, not constant intervention.",
            issues: []
        ) {
            WorkbenchSection(title: "Manual trigger", detail: "Double-tap one Option key to undo or cycle when automatic correction stays silent.") {
                SettingsToggleRow(
                    title: "Enable manual correction trigger",
                    detail: "Keeps double-tap Option available for last-word, selection, undo, and cycle flows.",
                    isOn: $settings.hotkeyEnabled
                )

                Divider()

                SummaryRow(title: "Double-tap Option side", detail: "Choose the Option key that should act as the manual trigger.") {
                    Picker("", selection: $settings.manualTriggerOptionSide) {
                        Text("Left Option (⌥)", bundle: settings.resourceBundle).tag(SettingsManager.ManualTriggerOptionSide.left)
                        Text("Right Option (⌥)", bundle: settings.resourceBundle).tag(SettingsManager.ManualTriggerOptionSide.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .disabled(!settings.hotkeyEnabled)
                }
            }

            WorkbenchSection(title: "When to use it", detail: "Manual correction remains the reliable fallback for blind editors and ambiguous words.") {
                Text(UIStrings.text("Tip: Select text and double-tap Option to cycle between EN, RU, and HE alternatives without changing more than the selected scope."))
                    .font(Theme.Typography.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }
}

private struct AppsPane: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showingAppPicker = false

    var body: some View {
        WorkbenchPage(
            title: "Apps",
            subtitle: "Define where RightLayout is allowed to monitor and where it should stay silent.",
            issues: []
        ) {
            WorkbenchSection(title: "Coverage policy", detail: "Keep runtime scope explicit so corrections never feel arbitrary.") {
                SettingsToggleRow(
                    title: "Enable in all apps",
                    detail: "Turn this off to maintain a small explicit exclusion list.",
                    isOn: Binding(
                        get: { settings.excludedApps.isEmpty },
                        set: { newValue in
                            if newValue {
                                settings.excludedApps.removeAll()
                            } else {
                                showingAppPicker = true
                            }
                        }
                    )
                )
            }

            WorkbenchSection(
                title: "Excluded apps",
                detail: "These apps are never monitored and never auto-corrected."
            ) {
                if settings.excludedApps.isEmpty {
                    EmptyStateView(
                        title: "No excluded apps",
                        systemImage: "checkmark.circle",
                        message: "RightLayout is currently allowed to work everywhere you type.",
                        primaryAction: .init(
                            title: "Add excluded app",
                            systemImage: "plus",
                            style: .primary,
                            action: { showingAppPicker = true }
                        )
                    )
                    .frame(height: 220)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.excludedApps).sorted(), id: \.self) { bundleId in
                            ExcludedAppRow(bundleId: bundleId) {
                                settings.toggleApp(bundleId)
                            }
                            .padding(.vertical, Theme.Spacing.sm)
                            if bundleId != Array(settings.excludedApps).sorted().last {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .controlSurface(level: 1)

                    Button {
                        showingAppPicker = true
                    } label: {
                        Label {
                            Text("Add excluded app", bundle: settings.resourceBundle)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .buttonStyle(.plain)
                    .secondaryActionButton()
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(isPresented: $showingAppPicker)
        }
    }
}

private struct ExcludedAppRow: View {
    let bundleId: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            appIcon

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(appName)
                    .font(Theme.Typography.bodyStrong())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(bundleId)
                    .font(Theme.Typography.meta())
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Label {
                    Text("Remove", bundle: SettingsManager.shared.resourceBundle)
                } icon: {
                    Image(systemName: "minus.circle")
                }
            }
            .buttonStyle(.plain)
            .secondaryActionButton()
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app")
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }
}

private struct UpdatesPane: View {
    @ObservedObject private var updateState = UpdateState.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        WorkbenchPage(
            title: "Updates",
            subtitle: "Keep the app current without turning version checks into a marketing surface.",
            issues: [],
            accessory: updateState.isUpdateAvailable ? AnyView(StatusChip(title: "Update ready", severity: .info)) : nil
        ) {
            WorkbenchSection(title: "Release checks", detail: "Version checks are local until you explicitly open the download page.") {
                UpdateCheckButton(updateState: updateState)

                Divider()

                SettingsToggleRow(
                    title: "Check automatically",
                    detail: "Periodically check GitHub Releases while the app is installed.",
                    isOn: $settings.checkForUpdatesAutomatically
                )
            }
        }
    }
}

private struct AboutPane: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        WorkbenchPage(
            title: "About",
            subtitle: "Version, support, and product boundaries in one place.",
            issues: []
        ) {
            WorkbenchSection(title: "Build", detail: "Use this when reporting bugs or confirming which release is installed.") {
                SummaryRow(title: "Version", detail: "Matches the build metadata shown in GitHub releases and the app bundle.") {
                    Text(appVersion)
                        .font(Theme.Typography.mono())
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            }

            WorkbenchSection(title: "Support and links", detail: "Operational links, not marketing pathways.") {
                Link(destination: URL(string: "https://github.com/chernistry/rightlayout")!) {
                    Text("GitHub Repository", bundle: settings.resourceBundle)
                }
                Link(destination: URL(string: "https://github.com/chernistry/rightlayout/releases")!) {
                    Text("Release Notes", bundle: settings.resourceBundle)
                }
                Link(destination: URL(string: "https://github.com/chernistry/rightlayout/issues")!) {
                    Text("Report a Bug", bundle: settings.resourceBundle)
                }
            }

            WorkbenchSection(title: "Reliability posture", detail: "The product aims for safe, local correction and fail-closed behavior when confidence is weak.") {
                Text(UIStrings.text("RightLayout corrects RU, EN, and HE layout mistakes locally on-device. It should either make a clear correction or stay out of the way."))
                    .font(Theme.Typography.body())
                    .foregroundStyle(Theme.Color.textSecondary)

                if settings.isStrictPrivacyMode {
                    StatusChip(title: "Strict privacy mode enabled", severity: .info)
                }
            }
        }
    }
}

private struct SettingsSearchResultsView: View {
    let query: String
    let onSelect: (SettingsPane) -> Void
    @ObservedObject private var settings = SettingsManager.shared

    private var matches: [SettingsPane] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return SettingsPane.allCases.filter { pane in
            pane.title.lowercased().contains(q) || pane.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        WorkbenchPage(
            title: "Search",
            subtitle: "Jump directly to the right area instead of browsing the sidebar.",
            issues: []
        ) {
            if matches.isEmpty {
                EmptyStateView(
                    title: NSLocalizedString("No matches", bundle: settings.resourceBundle, comment: ""),
                    systemImage: "magnifyingglass",
                    message: NSLocalizedString("Try a broader term such as languages, diagnostics, or adaptation.", bundle: settings.resourceBundle, comment: "")
                )
                .frame(minHeight: 260)
            } else {
                WorkbenchSection(title: "Matching sections", detail: nil) {
                    ForEach(matches) { pane in
                        Button {
                            onSelect(pane)
                        } label: {
                            HStack {
                                Label(
                                    title: { Text(LocalizedStringKey(pane.title), bundle: settings.resourceBundle) },
                                    icon: { Image(systemName: pane.systemImage) }
                                )
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Theme.Color.textMeta)
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                        .buttonStyle(.plain)
                        if pane != matches.last {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct AppPickerSheet: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Binding var isPresented: Bool

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { !settings.excludedApps.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Button {
                        if let bundleId = app.bundleIdentifier {
                            settings.toggleApp(bundleId)
                            isPresented = false
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            }

                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(app.localizedName ?? UIStrings.text("Unknown"))
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Text(app.bundleIdentifier ?? "")
                                    .font(Theme.Typography.meta())
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(Text("Add excluded app", bundle: settings.resourceBundle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel", bundle: settings.resourceBundle)
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 460)
    }
}

#Preview {
    SettingsView()
}
