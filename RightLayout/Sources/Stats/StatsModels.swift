import Foundation

/// Represents a single statistical event in the system.
/// Privacy-safe: No raw text is included.
public enum StatsEvent: Sendable, Codable {
    /// Automatic correction applied
    case autoFixed(appBundleId: String?, from: Language, to: Language)
    
    /// User manually undid a correction (Cmnd+Z)
    case undo(appBundleId: String?)
    
    /// User explicitly selected a conversion via hotkey
    case manualHotkey(appBundleId: String?, from: Language, to: Language)
    
    /// User cycled through alternatives
    case cycledSelection
    
    /// Correction was skipped because user was typing Code or URL
    case skippedForSecureIntent(intent: String) // "code" or "url"
    
    /// Secure Input (password field) was active
    case secureInputPaused
}

/// A daily bucket for counting events
public struct StatsDayBucket: Codable, Sendable {
    public let date: Date // Normalized to start of day
    public var totalFixes: Int = 0
    public var autoFixes: Int = 0
    public var manualFixes: Int = 0
    public var undos: Int = 0
    public var savedSeconds: Double = 0.0
    
    /// Aggregate counters for languages pairs (e.g. "en_ru" -> 5)
    public var languagePairs: [String: Int] = [:]
    
    public init(date: Date) {
        self.date = date
    }
}

/// The persistent state of the statistics system.
public struct StatsState: Codable, Sendable {
    /// Schema version for future migrations
    public var version: Int = 1
    
    /// Historical data (past 180 days)
    public var history: [StatsDayBucket] = []
    
    /// All-time aggregates
    public var allTimeFixes: Int = 0
    public var allTimeUndos: Int = 0
    public var allTimeSavedSeconds: Double = 0.0
    
    /// Per-app statistics (bundleId -> count)
    /// If strict privacy is enabled, keys are hashes
    public var topApps: [String: Int] = [:]
    
    /// Unlocked achievements IDs
    public var unlockedBadges: Set<String> = []
    
    public init() {}
}

public struct Achievement: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let iconName: String
    public let condition: @Sendable (StatsState) -> Bool
}
