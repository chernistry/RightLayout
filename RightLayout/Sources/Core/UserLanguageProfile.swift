import Foundation
import os.log

/// Outcome of a correction attempt
enum CorrectionOutcome: String, Codable {
    case accepted       // User kept the correction
    case reverted      // User undid/rejected the correction  
    case manual        // User manually triggered correction
}

/// Context for profiling decisions
struct ProfileContext: Hashable, Codable {
    let prefix: String      // First 2-3 chars of token
    let lastLanguage: Language?
    
    init(token: String, lastLanguage: Language?) {
        // Use first 3 chars as prefix (or full token if shorter)
        self.prefix = String(token.prefix(3)).lowercased()
        self.lastLanguage = lastLanguage
    }
}

/// Statistics for a specific context
struct ProfileStats: Codable {
    var accepted: Int = 0
    var reverted: Int = 0
    
    var totalAttempts: Int { accepted + reverted }
    var acceptanceRate: Double {
        guard totalAttempts > 0 else { return 0.5 }
        return Double(accepted) / Double(totalAttempts)
    }
}

private struct UserLanguageProfileStore: Codable {
    var version: Int = 3
    var stats: [ProfileContext: ProfileStats] = [:]
}

/// User-specific language profile for adaptive corrections
actor UserLanguageProfile {
    private var stats: [ProfileContext: ProfileStats] = [:]
    private let maxContexts = 1000  // LRU limit
    private let persistenceURL: URL
    private let logger = Logger.profile
    
    // Thresholds for adjustment
    private let lowAcceptanceThreshold = 0.3    // Below this, raise threshold
    private let highAcceptanceThreshold = 0.7   // Above this, allow lower threshold
    private let minSamples = 3  // Minimum attempts before adjusting
    
    init(persistenceURL: URL? = nil) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let disablePersistence = ProcessInfo.processInfo.environment["RightLayout_DISABLE_PROFILE_PERSISTENCE"] == "1"

        if let url = persistenceURL {
            self.persistenceURL = url
        } else if isTesting || disablePersistence {
            // Avoid loading/writing user state in tests (and keep tests deterministic).
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.persistenceURL = tmp.appendingPathComponent("rightlayout_user_profile_test.json")
        } else {
            // Default to Application Support
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let rightlayoutDir = appSupport.appendingPathComponent("RightLayout", isDirectory: true)
            try? FileManager.default.createDirectory(at: rightlayoutDir, withIntermediateDirectories: true)
            self.persistenceURL = rightlayoutDir.appendingPathComponent("user_profile.json")
        }

        if !(isTesting || disablePersistence) {
            self.stats = Self.loadStats(from: self.persistenceURL, logger: logger)
        }
    }
    
    /// Record a correction outcome
    func record(context: ProfileContext, outcome: CorrectionOutcome, hypothesis: LanguageHypothesis) {
        var stat = stats[context] ?? ProfileStats()
        
        switch outcome {
        case .accepted, .manual:
            stat.accepted += 1
        case .reverted:
            stat.reverted += 1
        }
        
        stats[context] = stat
        
        // Enforce LRU limit (simple: remove oldest when over limit)
        if stats.count > maxContexts {
            // Remove context with lowest total attempts
            if let minKey = stats.min(by: { $0.value.totalAttempts < $1.value.totalAttempts })?.key {
                stats.removeValue(forKey: minKey)
            }
        }
        
        logger.debug("Recorded \(outcome.rawValue, privacy: .public) for \(DecisionLogger.tokenSummary(context.prefix), privacy: .public), acceptance: \(stat.acceptanceRate)")
    }
    
    /// Adjust confidence threshold based on user history
    func adjustThreshold(for token: String, lastLanguage: Language?, baseConfidence: Double) -> Double {
        let context = ProfileContext(token: token, lastLanguage: lastLanguage)
        
        guard let stat = stats[context], stat.totalAttempts >= minSamples else {
            // Not enough data, use base threshold
            return baseConfidence
        }
        
        let rate = stat.acceptanceRate
        
        if rate < lowAcceptanceThreshold {
            // User frequently rejects this pattern - raise threshold (be more conservative)
            let adjusted = baseConfidence * 1.2
            logger.debug("Low acceptance (\(rate)) for \(DecisionLogger.tokenSummary(context.prefix), privacy: .public) - raising threshold to \(adjusted)")
            return min(1.0, adjusted)
        } else if rate > highAcceptanceThreshold {
            // User frequently accepts this pattern - lower threshold (be more aggressive)
            let adjusted = baseConfidence * 0.9
            logger.debug("High acceptance (\(rate)) for \(DecisionLogger.tokenSummary(context.prefix), privacy: .public) - lowering threshold to \(adjusted)")
            return max(0.3, adjusted)
        }
        
        // Medium acceptance - no adjustment
        return baseConfidence
    }
    
    /// Get statistics for debugging
    func getStats(for context: ProfileContext) -> ProfileStats? {
        return stats[context]
    }
    
    /// Clear all stats (for testing or user reset)
    func clearAll() {
        stats.removeAll()
        logger.info("Cleared user profile stats")
    }
    
    /// Save stats to disk
    func save() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(UserLanguageProfileStore(stats: stats))
            try data.write(to: persistenceURL)
            logger.info("Saved profile to \(self.persistenceURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to save profile: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Load stats from disk
    private static func loadStats(from persistenceURL: URL, logger: Logger) -> [ProfileContext: ProfileStats] {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
            logger.info("No existing profile file, starting fresh")
            return [:]
        }

        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(UserLanguageProfileStore.self, from: data),
               decoded.version == 3 {
                logger.info("Loaded profile with \(decoded.stats.count) contexts")
                return decoded.stats
            } else {
                try? FileManager.default.removeItem(at: persistenceURL)
            }
        } catch {
            logger.error("Failed to load profile: \(error.localizedDescription, privacy: .public)")
        }
        return [:]
    }
}
