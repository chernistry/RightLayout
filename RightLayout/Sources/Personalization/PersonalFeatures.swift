import Foundation

/// Represents privacy-safe, non-reversible features used for personalization.
/// No raw text is ever stored here.
package struct PersonalFeatures: Codable, Sendable {
    // MARK: - Context Features
    
    /// Salted hash of the active application's bundle identifier.
    let appBundleIdHash: Int
    
    /// Hierarchical Context Key
    let contextKey: ContextKey
    
    /// Hour of the day (0-23).
    let hourOfDay: Int
    
    let isWeekend: Bool
    
    /// Hashed features of the text (n-grams, shape, etc.)
    let ngramHashes: [UInt16]
    
    /// 0=short, 1=medium, 2=long
    let lengthCategory: Int
    
    /// Optional biometric signals (typing cadence)
    let bioFeatures: BioFeatures?
}

/// Hierarchical Context Keys for SOTA Personalization
package struct ContextKey: Hashable, Codable, Sendable {
    package let global: Int      // Hash(0) - baseline bias
    package let app: Int         // Hash(bundleId)
    package let appIntent: Int   // Hash(bundleId + intent)
    package let appTime: Int     // Hash(bundleId + timeBucket)
}

/// SOTA Keystroke Dynamics Features (Ticket 40)
package struct BioFeatures: Codable, Sendable {
    /// Approximate words per minute in the current session.
    package let wpm: Double
    
    /// Variance of flight times (time between key press and release of previous key).
    /// Low variance = steady rhythm (confident). High variance = hesitation (uncertainty).
    package let flightTimeVar: Double
    
    /// Ratio of backspaces to total keystrokes in the recent buffer.
    /// High ratio = struggle/correction.
    package let backspaceRatio: Double
}
