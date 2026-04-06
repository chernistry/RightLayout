import Foundation
import os.log

/// "Strategy A": Contextual Priors Adapter.
/// Adjusts the confidence of the correction candidate based on historic user behavior in the current app context.
actor PersonalizationEngine {
    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "Personalization")
    
    // MARK: - Dependencies
    
    private let store: PersonalizationStore
    private let adapter: OnlineAdapter
    private let riskController: RiskController // Ticket 44: Calibration Gate

    
    // MARK: - Configuration
    
    private let negativeBiasHintThreshold: Double = -0.20
    private let negativeBiasHoldThreshold: Double = -0.45
    
    // MARK: - Init
    
    init(store: PersonalizationStore = .shared, adapter: OnlineAdapter = .shared, riskController: RiskController = .shared) {
        self.store = store
        self.adapter = adapter
        self.riskController = riskController
    }
    
    // MARK: - API
    
    func demote(policy: RiskPolicy, features: PersonalFeatures, isManualIntent: Bool = false) async -> RiskPolicy {
        _ = store
        _ = adapter
        return await riskController.demote(
            policy: policy,
            contextKey: features.contextKey,
            isManual: isManualIntent
        )
    }

    func adjust(candidate: CorrectionCandidateResult, features: PersonalFeatures) async -> (CorrectionCandidateResult, RiskPolicy) {
        let basePolicy: RiskPolicy
        if candidate.confidence >= 0.78 {
            basePolicy = .autoApply
        } else if candidate.confidence >= 0.70 {
            basePolicy = .suggestHint
        } else {
            basePolicy = .holdForHotkey
        }

        let priors = await store.getPriors(for: features.appBundleIdHash)
        let priorScore = priors[candidate.language] ?? 0.0

        var adjustedPolicy = await demote(policy: basePolicy, features: features)
        if adjustedPolicy == .autoApply, priorScore <= -3.0 {
            adjustedPolicy = .suggestHint
        }

        if adjustedPolicy != basePolicy {
            logger.info(
                "\(candidate.language, privacy: .public) conf: \(candidate.confidence) policy \(basePolicy.rawValue, privacy: .public) -> \(adjustedPolicy.rawValue, privacy: .public)"
            )
        }
        return (candidate, adjustedPolicy)
    }
}

// Temporary shim for types if Models.swift usage is tricky or implicit
struct CorrectionCandidateResult: Sendable {
    let language: String
    let confidence: Double
    let originalText: String
    let correctedText: String
}
