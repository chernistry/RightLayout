import Foundation

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    
    @Published var preferredLanguage: Language {
        didSet { UserDefaults.standard.set(preferredLanguage.rawValue, forKey: "preferredLanguage") }
    }
    
    @Published var excludedApps: Set<String> {
        didSet { UserDefaults.standard.set(Array(excludedApps), forKey: "excludedApps") }
    }
    
    @Published var autoSwitchLayout: Bool {
        didSet { UserDefaults.standard.set(autoSwitchLayout, forKey: "autoSwitchLayout") }
    }
    
    @Published var hotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    
    @Published var hotkeyKeyCode: UInt16 {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }

    public enum ManualTriggerMode: String, CaseIterable, Identifiable {
        case doubleTapOption

        public var id: String { rawValue }
    }

    public enum ManualTriggerOptionSide: String, CaseIterable, Identifiable {
        case left
        case right

        public var id: String { rawValue }

        public var keyCode: UInt16 {
            switch self {
            case .left:
                return 58
            case .right:
                return 61
            }
        }
    }

    @Published public var manualTriggerMode: ManualTriggerMode {
        didSet { UserDefaults.standard.set(manualTriggerMode.rawValue, forKey: "manualTriggerMode") }
    }

    @Published public var manualTriggerOptionSide: ManualTriggerOptionSide {
        didSet {
            hotkeyKeyCode = manualTriggerOptionSide.keyCode
            UserDefaults.standard.set(manualTriggerOptionSide.rawValue, forKey: "manualTriggerOptionSide")
        }
    }
    
    @Published var activeLayouts: [String: String] {
        didSet { UserDefaults.standard.set(activeLayouts, forKey: "activeLayouts") }
    }
    
    @Published var fastPathThreshold: Double {
        didSet { UserDefaults.standard.set(fastPathThreshold, forKey: "fastPathThreshold") }
    }
    
    @Published var standardPathThreshold: Double {
        didSet { UserDefaults.standard.set(standardPathThreshold, forKey: "standardPathThreshold") }
    }
    
    @Published var isLearningEnabled: Bool {
        didSet { UserDefaults.standard.set(isLearningEnabled, forKey: "isLearningEnabled") }
    }
    
    @Published var isStatsCollectionEnabled: Bool {
        didSet { UserDefaults.standard.set(isStatsCollectionEnabled, forKey: "isStatsCollectionEnabled") }
    }
    
    @Published var isStrictPrivacyMode: Bool {
        didSet { UserDefaults.standard.set(isStrictPrivacyMode, forKey: "isStrictPrivacyMode") }
    }
    
    /// Simple mode (default) vs Advanced mode for power users
    @Published var isAdvancedMode: Bool {
        didSet { UserDefaults.standard.set(isAdvancedMode, forKey: "isAdvancedMode") }
    }
    
    /// Proactive Hinting (Ticket 54)
    @Published public var proactiveHintsEnabled: Bool {
        didSet { UserDefaults.standard.set(proactiveHintsEnabled, forKey: "proactiveHintsEnabled") }
    }

    /// Transliteration Suggestions (Ticket 55) — opt-in, hint-only.
    @Published var transliterationHintsEnabled: Bool {
        didSet { UserDefaults.standard.set(transliterationHintsEnabled, forKey: "transliterationHintsEnabled") }
    }

    /// Ticket 71: CorrectionVerifierAgent — independent second-opinion validation before applying corrections.
    @Published var isVerifierEnabled: Bool {
        didSet { UserDefaults.standard.set(isVerifierEnabled, forKey: "isVerifierEnabled") }
    }

    /// Ticket 72: Foundation Model classifier for ambiguous tokens (macOS 26+).
    @Published var isFoundationModelEnabled: Bool {
        didSet { UserDefaults.standard.set(isFoundationModelEnabled, forKey: "isFoundationModelEnabled") }
    }
    
    // MARK: - Ticket 68: Behavior Presets
    
    package enum BehaviorPreset: String, CaseIterable, Identifiable {
        case conservative
        case balanced
        case aggressive
        
        package var id: String { rawValue }
        
        package var displayName: String {
            switch self {
            case .conservative: return "Safe"
            case .balanced: return "Balanced+"
            case .aggressive: return "Aggressive"
            }
        }
        
        package var description: String {
            switch self {
            case .conservative: return "Prioritizes safety. Misses more doubtful corrections instead of changing text unexpectedly."
            case .balanced: return "Auto-fixes clear layout mistakes, keeps ambiguous cases for hints or manual correction."
            case .aggressive: return "Fixes more probable layout mistakes automatically, with a slightly higher false-positive risk."
            }
        }
        
        package var thresholds: (fast: Double, standard: Double) {
            switch self {
            case .conservative: return (1.0, 1.0)  // Never auto-apply
            case .balanced: return (0.95, 0.70)     // Current defaults
            case .aggressive: return (0.85, 0.50)   // More aggressive
            }
        }
    }
    
    @Published var behaviorPreset: BehaviorPreset {
        didSet {
            UserDefaults.standard.set(behaviorPreset.rawValue, forKey: "behaviorPreset")
            applyPreset(behaviorPreset)
        }
    }
    
    /// Computed: detects if current thresholds match a preset
    var currentPreset: BehaviorPreset? {
        for preset in BehaviorPreset.allCases {
            let (fast, standard) = preset.thresholds
            if abs(fastPathThreshold - fast) < 0.01 && abs(standardPathThreshold - standard) < 0.01 {
                return preset
            }
        }
        return nil // Custom settings
    }
    
    private func applyPreset(_ preset: BehaviorPreset) {
        let (fast, standard) = preset.thresholds
        fastPathThreshold = fast
        standardPathThreshold = standard
    }
    
    // MARK: - App Language

    
    public enum AppLanguage: String, CaseIterable, Identifiable {
        case system
        case english = "en"
        case russian = "ru"
        case hebrew = "he"
        
        public var id: String { rawValue }
        
        public var displayName: String {
            switch self {
            case .system: return "System Default"
            case .english: return "English"
            case .russian: return "Русский"
            case .hebrew: return "עברית"
            }
        }
        
        public var locale: Locale? {
            switch self {
            case .system: return nil
            case .english: return Locale(identifier: "en")
            case .russian: return Locale(identifier: "ru")
            case .hebrew: return Locale(identifier: "he")
            }
        }
    }
    
    @Published public var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            updateResourceBundle()
        }
    }
    
    @Published var resourceBundle: Bundle = .module
    
    private func updateResourceBundle() {
        let localization = resolvedLocalizationCode()
        print("[SettingsManager] Updating resource bundle for language: \(appLanguage.rawValue) -> \(localization ?? "module-default")")

        if let localization,
           let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            print("[SettingsManager] Found bundle at: \(path)")
            self.resourceBundle = bundle
        } else {
            print("[SettingsManager] Could not find bundle for \(appLanguage.rawValue). Falling back to .module")
            self.resourceBundle = .module
        }
    }

    private func resolvedLocalizationCode() -> String? {
        if appLanguage != .system {
            return appLanguage.rawValue
        }

        let available = Set(Bundle.module.localizations.filter { $0 != "Base" })
        let preferredCodes = Locale.preferredLanguages.compactMap { preferred in
            let locale = Locale(identifier: preferred)
            if #available(macOS 13.0, *) {
                if let code = locale.language.languageCode?.identifier {
                    return code
                }
            }
            return preferred
                .split(separator: "-")
                .first
                .map(String.init)
        }

        for code in preferredCodes {
            if available.contains(code) {
                return code
            }
        }

        return available.contains("en") ? "en" : available.first
    }
    
    // MARK: - Update Settings
    
    @Published public var checkForUpdatesAutomatically: Bool {
        didSet { UserDefaults.standard.set(checkForUpdatesAutomatically, forKey: "checkForUpdatesAutomatically") }
    }
    
    public var lastUpdateCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheckDate") }
    }
    
    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        self.isLearningEnabled = UserDefaults.standard.object(forKey: "isLearningEnabled") as? Bool ?? true
        self.isStatsCollectionEnabled = UserDefaults.standard.object(forKey: "isStatsCollectionEnabled") as? Bool ?? true
        self.isStrictPrivacyMode = UserDefaults.standard.object(forKey: "isStrictPrivacyMode") as? Bool ?? false
        self.isAdvancedMode = UserDefaults.standard.object(forKey: "isAdvancedMode") as? Bool ?? false
        self.isStrictPrivacyMode = UserDefaults.standard.object(forKey: "isStrictPrivacyMode") as? Bool ?? false
        self.isAdvancedMode = UserDefaults.standard.object(forKey: "isAdvancedMode") as? Bool ?? false
        self.proactiveHintsEnabled = UserDefaults.standard.object(forKey: "proactiveHintsEnabled") as? Bool ?? true
        self.transliterationHintsEnabled = UserDefaults.standard.object(forKey: "transliterationHintsEnabled") as? Bool ?? false
        
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isVerifierEnabled = UserDefaults.standard.object(forKey: "isVerifierEnabled") as? Bool ?? !isTesting
        self.isFoundationModelEnabled = UserDefaults.standard.object(forKey: "isFoundationModelEnabled") as? Bool ?? true
        self.checkForUpdatesAutomatically = UserDefaults.standard.object(forKey: "checkForUpdatesAutomatically") as? Bool ?? true
        
        // Ticket 68: Behavior Preset
        let presetRaw = UserDefaults.standard.string(forKey: "behaviorPreset") ?? "balanced"
        self.behaviorPreset = BehaviorPreset(rawValue: presetRaw) ?? .balanced
        
        let appLangRaw = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        self.appLanguage = AppLanguage(rawValue: appLangRaw) ?? .system
        

        let langRaw = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"
        self.preferredLanguage = Language(rawValue: langRaw) ?? .english
        
        let apps = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
        self.excludedApps = Set(apps)
        
        self.autoSwitchLayout = UserDefaults.standard.object(forKey: "autoSwitchLayout") as? Bool ?? true
        self.hotkeyEnabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") as? Bool ?? true
        let storedHotkeyKeyCode = UInt16(UserDefaults.standard.integer(forKey: "hotkeyKeyCode") != 0 ? UserDefaults.standard.integer(forKey: "hotkeyKeyCode") : 58)
        self.hotkeyKeyCode = storedHotkeyKeyCode
        self.manualTriggerMode = ManualTriggerMode(rawValue: UserDefaults.standard.string(forKey: "manualTriggerMode") ?? ManualTriggerMode.doubleTapOption.rawValue) ?? .doubleTapOption
        let defaultOptionSide: ManualTriggerOptionSide = storedHotkeyKeyCode == 61 ? .right : .left
        self.manualTriggerOptionSide = ManualTriggerOptionSide(rawValue: UserDefaults.standard.string(forKey: "manualTriggerOptionSide") ?? defaultOptionSide.rawValue) ?? defaultOptionSide
        
        self.activeLayouts = UserDefaults.standard.object(forKey: "activeLayouts") as? [String: String] ?? [
            "en": "us",
            "ru": "russianwin",
            "he": "hebrew"
        ]
        
        self.fastPathThreshold = UserDefaults.standard.object(forKey: "fastPathThreshold") as? Double ?? 0.95
        self.standardPathThreshold = UserDefaults.standard.object(forKey: "standardPathThreshold") as? Double ?? 0.70
        
        // Auto-detect installed keyboard layouts (skip in tests; allow opt-out via env var).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
           ProcessInfo.processInfo.environment["RightLayout_DISABLE_LAYOUT_AUTODETECT"] != "1" {
            detectAndUpdateLayouts()
        }
        
        // Initialize resource bundle now that all properties are set
        self.updateResourceBundle()
    }

    /// Auto-detect keyboard layout variants from macOS
    private func detectAndUpdateLayouts() {
        let detected = InputSourceManager.shared.detectInstalledLayouts()
        var updated = false
        
        for (lang, layoutID) in detected {
            if activeLayouts[lang] != layoutID {
                activeLayouts[lang] = layoutID
                updated = true
            }
        }
        
        if updated {
            // Persist the detected layouts
            UserDefaults.standard.set(activeLayouts, forKey: "activeLayouts")
        }
    }
    
    func isExcluded(bundleId: String) -> Bool {
        return excludedApps.contains(bundleId)
    }

    public var manualTriggerOptionKeyCode: UInt16 {
        manualTriggerOptionSide.keyCode
    }

    public var manualTriggerDoubleTapWindow: TimeInterval {
        0.25
    }
    
    func toggleApp(_ bundleId: String) {
        if excludedApps.contains(bundleId) {
            excludedApps.remove(bundleId)
        } else {
            excludedApps.insert(bundleId)
        }
    }

    /// Re-runs layout auto-detection and persists the results.
    func autoDetectLayouts() {
        detectAndUpdateLayouts()
    }
}
