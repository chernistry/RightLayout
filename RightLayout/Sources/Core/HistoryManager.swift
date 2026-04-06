import Foundation
import SwiftUI

/// Shared history storage accessible from UI
@MainActor
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published var records: [HistoryRecord] = []
    
    /// Policy describing how a correction was applied
    enum CorrectionPolicy: String, Sendable {
        case autoApplied = "Auto-Applied"
        case manual = "Manual"
        case hint = "Hint"
        case contextBoost = "Context Boost"
    }

    struct HistoryRecord: Identifiable {
        let id = UUID()
        let original: String
        let corrected: String
        let fromLang: Language
        let toLang: Language
        let timestamp: Date

        // Ticket 69: Transparency metadata
        let confidence: Double?
        let appName: String?
        let policy: CorrectionPolicy?
    }
    
    func add(
        original: String,
        corrected: String,
        from: Language,
        to: Language,
        confidence: Double? = nil,
        appName: String? = nil,
        policy: CorrectionPolicy? = nil
    ) {
        let record = HistoryRecord(
            original: original,
            corrected: corrected,
            fromLang: from,
            toLang: to,
            timestamp: Date(),
            confidence: confidence,
            appName: appName,
            policy: policy
        )
        records.insert(record, at: 0)
        if records.count > 50 {
            records.removeLast()
        }
    }
    
    func clear() {
        records.removeAll()
    }
}
