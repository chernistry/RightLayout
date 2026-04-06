import Foundation
import os.log

/// A "second opinion" agent that independently validates proposed corrections
/// before they are applied, catching high-confidence false positives.
///
/// Ticket 71: CorrectionVerifierAgent
actor CorrectionVerifierAgent {

    private let logger = Logger.engine

    // MARK: - Types

    struct VerifierContext: Sendable {
        let sentenceDominantLanguage: Language?
        let sentenceWordCount: Int
    }

    struct VerifiedDecision: Sendable {
        let shouldApply: Bool
        let adjustedConfidence: Double
        let reason: String
    }

    // MARK: - Scoring (self-contained, no CorrectionEngine dependency)

    private lazy var unigramModels: [Language: WordFrequencyModel] = {
        var out: [Language: WordFrequencyModel] = [:]
        if let ru = try? WordFrequencyModel.loadLanguage("ru") { out[.russian] = ru }
        if let en = try? WordFrequencyModel.loadLanguage("en") { out[.english] = en }
        if let he = try? WordFrequencyModel.loadLanguage("he") { out[.hebrew] = he }
        return out
    }()

    private let builtinValidator = BuiltinWordValidator()

    private func wordScore(_ word: String, language: Language) -> Double {
        let trimmed = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }
        let unigram = unigramModels[language]?.score(trimmed) ?? 0.0
        let builtin = builtinValidator.confidence(for: trimmed, language: language)
        return max(unigram, builtin)
    }

    private func textScore(_ text: String, language: Language) -> Double {
        let words = text
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0.0 }
        let total = words.reduce(0.0) { $0 + wordScore($1, language: language) }
        return total / Double(words.count)
    }

    // MARK: - Language Helpers

    private func languages(for hypothesis: LanguageHypothesis) -> (source: Language, target: Language)? {
        switch hypothesis {
        case .ruFromEnLayout: return (.english, .russian)
        case .heFromEnLayout: return (.english, .hebrew)
        case .enFromRuLayout: return (.russian, .english)
        case .heFromRuLayout: return (.russian, .hebrew)
        case .enFromHeLayout: return (.hebrew, .english)
        case .ruFromHeLayout: return (.hebrew, .russian)
        case .ru, .en, .he: return nil
        }
    }

    // MARK: - Verification

    /// Validate a proposed correction before it is applied.
    ///
    /// Returns a `VerifiedDecision` indicating whether the correction should proceed,
    /// with a potentially adjusted confidence and a reason string for logging.
    func verify(
        original: String,
        proposed: String,
        hypothesis: LanguageHypothesis,
        baseConfidence: Double,
        context: VerifierContext,
        activeLayouts: [String: String]
    ) -> VerifiedDecision {
        guard let (source, target) = languages(for: hypothesis) else {
            // Not a cross-layout hypothesis (e.g., .ru, .en, .he) — nothing to verify
            return VerifiedDecision(shouldApply: true, adjustedConfidence: baseConfidence, reason: "no_cross_layout")
        }

        let config = ThresholdsConfig.shared.correction
        var confidence = baseConfidence
        var reasons: [String] = []

        // 1. Round-trip consistency: reverse-map proposed → should produce original
        let roundTrip = LayoutMapper.shared.convertBest(proposed, from: target, to: source, activeLayouts: activeLayouts)
        if roundTrip != original {
            confidence -= config.verifierRoundTripPenalty
            reasons.append("round_trip_fail(\(roundTrip ?? "nil")≠\(original))")
        }

        // 2. Source quality: if original is a real word in source language, suspicious
        let sourceScore = textScore(original, language: source)
        if sourceScore >= config.verifierSourceQualityMax {
            confidence -= (sourceScore - config.verifierSourceQualityMax + 0.05)
            reasons.append("source_real_word(\(String(format: "%.2f", sourceScore)))")
        }

        // 3. Target quality: if proposed is gibberish in target language, reject
        let targetScore = textScore(proposed, language: target)
        if targetScore < config.verifierTargetQualityMin {
            logger.info("🔍 Verifier REJECT: target quality too low (\(targetScore) < \(config.verifierTargetQualityMin))")
            return VerifiedDecision(shouldApply: false, adjustedConfidence: 0.0, reason: "target_gibberish(\(String(format: "%.2f", targetScore)))")
        }

        // 4. Context cross-check: sentence language mismatch
        if let dominant = context.sentenceDominantLanguage,
           context.sentenceWordCount >= 2,
           dominant != target {
            confidence -= config.verifierContextPenalty
            reasons.append("context_mismatch(\(dominant.rawValue)≠\(target.rawValue))")
        }

        let shouldApply = confidence > 0.0
        let reason = reasons.isEmpty ? "pass" : reasons.joined(separator: ",")

        if !reasons.isEmpty {
            logger.info("🔍 Verifier: \(reason) → conf \(String(format: "%.2f", baseConfidence))→\(String(format: "%.2f", confidence))")
        }

        return VerifiedDecision(shouldApply: shouldApply, adjustedConfidence: confidence, reason: reason)
    }
}
