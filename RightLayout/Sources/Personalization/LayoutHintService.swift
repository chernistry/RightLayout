import Foundation
import AppKit

/// Service that predicts the likely language for an app context
/// and provides proactive hints ("Suggested: RU").
package actor LayoutHintService {
    
    package static let shared = LayoutHintService()
    
    private let riskController: RiskController
    private let personalizationStore: PersonalizationStore
    private let featureExtractor: FeatureExtractor
    
    init(
        riskController: RiskController = .shared,
        personalizationStore: PersonalizationStore = .shared,
        featureExtractor: FeatureExtractor = FeatureExtractor() // New instance is fine as long as salt is shared
    ) {
        self.riskController = riskController
        self.personalizationStore = personalizationStore
        self.featureExtractor = featureExtractor
    }
    
    /// Returns a suggested layout language if confidence is high enough.
    package func suggestLayout(for bundleId: String) async -> Language? {
        // 1. Extract context features (ignoring text/intent for now, just App-based)
        // We use "prose" intent as default for hints
        let features = await featureExtractor.extract(text: "", phraseBuffer: "", appBundleId: bundleId, intent: "prose")
        
        // 2. Check Priors for this app
        let priors = await personalizationStore.getPriors(for: features.appBundleIdHash)
        
        // Find language with highest positive prior
        // (A positive prior means the model learned to boost this language)
        guard let best = priors.max(by: { $0.value < $1.value }), best.value > 0.5 else {
            return nil
        }
        
        let candidateLang = best.key
        
        // 3. Risk Gate: Check if we are calibrated enough to SUGGEST
        // We simulate a "high confidence" candidate to see if RiskController allows a Hint
        let policy = await riskController.evaluate(
            candidateConfidence: 0.8, 
            contextKey: features.contextKey
        )
        
        // If policy allows Auto or Hint, we return the suggestion
        if policy == .autoApply || policy == .suggestHint {
            // Map "ru" string to Language enum
            return Language(rawValue: candidateLang)
        }
        
        return nil
    }
}
