import Foundation

package enum DecisionTokenKind: String, Sendable {
    case plain
    case short
    case punctuated
    case mixed
    case technical
}

package enum EditingEnvironment: Sendable {
    case accessibility
    case nonAccessibility
    case secureReadBlind
}

package enum CorrectionDisposition: Sendable {
    case autoApply
    case hint
    case manualOnly
    case reject
}

package struct DecisionEvidenceCandidate: Sendable {
    package let hypothesis: LanguageHypothesis
    package let score: Double
}

package struct DecisionEvidence: Sendable {
    package let original: String
    package let decision: LanguageDecision
    package let confidence: Double
    package let winnerMargin: Double
    package let primaryCandidate: DecisionEvidenceCandidate
    package let secondaryCandidate: DecisionEvidenceCandidate?
    package let tokenKind: DecisionTokenKind
    package let convertedText: String
    package let sourceLayout: Language?
    package let targetLanguage: Language
    package let isCorrection: Bool
    package let isWhitelistedShort: Bool
}

private struct PolicyThresholds {
    let axAuto: Double
    let axMargin: Double
    let axShortAuto: Double
    let axShortMargin: Double
    let axHint: Double
    let nonAXAuto: Double
    let nonAXMargin: Double
    let nonAXHint: Double
    let whitelistAuto: Double
    let whitelistHint: Double

    static func forPreset(_ preset: SettingsManager.BehaviorPreset) -> PolicyThresholds {
        let base = PolicyThresholds(
            axAuto: 0.78,
            axMargin: 0.12,
            axShortAuto: 0.90,
            axShortMargin: 0.16,
            axHint: 0.70,
            nonAXAuto: 0.88,
            nonAXMargin: 0.16,
            nonAXHint: 0.74,
            whitelistAuto: 0.90,
            whitelistHint: 0.65
        )

        switch preset {
        case .conservative:
            return PolicyThresholds(
                axAuto: min(1.0, base.axAuto + 0.06),
                axMargin: base.axMargin + 0.02,
                axShortAuto: min(1.0, base.axShortAuto + 0.06),
                axShortMargin: base.axShortMargin + 0.02,
                axHint: min(1.0, base.axHint + 0.04),
                nonAXAuto: min(1.0, max(0.82, base.nonAXAuto + 0.06)),
                nonAXMargin: base.nonAXMargin + 0.02,
                nonAXHint: min(1.0, base.nonAXHint + 0.04),
                whitelistAuto: min(1.0, base.whitelistAuto + 0.06),
                whitelistHint: min(1.0, base.whitelistHint + 0.04)
            )
        case .balanced:
            return base
        case .aggressive:
            return PolicyThresholds(
                axAuto: max(0.0, base.axAuto - 0.06),
                axMargin: max(0.08, base.axMargin - 0.02),
                axShortAuto: max(0.0, base.axShortAuto - 0.06),
                axShortMargin: max(0.14, base.axShortMargin - 0.02),
                axHint: max(0.0, base.axHint - 0.05),
                nonAXAuto: max(0.82, base.nonAXAuto - 0.06),
                nonAXMargin: max(0.16, base.nonAXMargin - 0.02),
                nonAXHint: max(0.0, base.nonAXHint - 0.05),
                whitelistAuto: max(0.0, base.whitelistAuto - 0.06),
                whitelistHint: max(0.0, base.whitelistHint - 0.05)
            )
        }
    }
}

package enum CorrectionDecisionPolicy {
    package static func evaluate(
        evidence: DecisionEvidence,
        environment: EditingEnvironment,
        preset: SettingsManager.BehaviorPreset
    ) -> CorrectionDisposition {
        let thresholds = PolicyThresholds.forPreset(preset)

        guard evidence.isCorrection else {
            return .reject
        }

        guard evidence.convertedText != evidence.original else {
            return .reject
        }

        let letterCount = evidence.original.filter(\.isLetter).count
        if letterCount <= 1 {
            return .manualOnly
        }

        switch evidence.tokenKind {
        case .technical, .mixed:
            return .reject
        case .punctuated:
            if environment == .accessibility,
               letterCount >= 2,
               evidence.convertedText.allSatisfy({ $0.isLetter || $0.isWhitespace || $0 == "«" || $0 == "»" || $0 == "\"" || $0 == "'" }),
               evidence.confidence >= thresholds.axAuto,
               evidence.winnerMargin >= thresholds.axMargin {
                return .autoApply
            }
            return evaluateAmbiguous(
                confidence: evidence.confidence,
                environment: environment,
                thresholds: thresholds
            )
        case .short:
            if evidence.isWhitelistedShort {
                if environment == .accessibility,
                   letterCount >= 2,
                   evidence.confidence >= thresholds.whitelistAuto,
                   evidence.winnerMargin >= thresholds.axShortMargin {
                    return .autoApply
                }
                if evidence.confidence >= thresholds.whitelistHint {
                    return .hint
                }
                return .manualOnly
            }

            switch environment {
            case .accessibility:
                if letterCount >= 3,
                   evidence.confidence >= thresholds.axShortAuto,
                   evidence.winnerMargin >= thresholds.axShortMargin {
                    return .autoApply
                }
                if evidence.confidence >= thresholds.axHint {
                    return .hint
                }
                return .manualOnly
            case .nonAccessibility:
                if evidence.confidence >= thresholds.nonAXHint {
                    return .hint
                }
                return .manualOnly
            case .secureReadBlind:
                return .manualOnly
            }
        case .plain:
            switch environment {
            case .accessibility:
                guard letterCount >= 4, letterCount <= 18 else {
                    return .manualOnly
                }
                if evidence.confidence >= thresholds.axAuto && evidence.winnerMargin >= thresholds.axMargin {
                    return .autoApply
                }
                if evidence.confidence >= thresholds.axHint {
                    return .hint
                }
                return .manualOnly
            case .nonAccessibility:
                guard letterCount >= 5, letterCount <= 18 else {
                    return .manualOnly
                }
                if evidence.confidence >= thresholds.nonAXAuto && evidence.winnerMargin >= thresholds.nonAXMargin {
                    return .autoApply
                }
                if evidence.confidence >= thresholds.nonAXHint {
                    return .hint
                }
                return .manualOnly
            case .secureReadBlind:
                return .manualOnly
            }
        }
    }

    private static func evaluateAmbiguous(
        confidence: Double,
        environment: EditingEnvironment,
        thresholds: PolicyThresholds
    ) -> CorrectionDisposition {
        switch environment {
        case .accessibility:
            return confidence >= thresholds.axHint ? .hint : .manualOnly
        case .nonAccessibility:
            return confidence >= thresholds.nonAXHint ? .hint : .manualOnly
        case .secureReadBlind:
            return .manualOnly
        }
    }
}
