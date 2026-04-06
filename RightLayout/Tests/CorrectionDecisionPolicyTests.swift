import XCTest
@testable import RightLayout

final class CorrectionDecisionPolicyTests: XCTestCase {
    private func makeEvidence(
        original: String,
        converted: String,
        confidence: Double,
        margin: Double,
        tokenKind: DecisionTokenKind = .plain,
        targetLanguage: Language = .russian
    ) -> DecisionEvidence {
        let decision = LanguageDecision(
            language: targetLanguage,
            layoutHypothesis: .ruFromEnLayout,
            confidence: confidence,
            scores: [
                .ruFromEnLayout: confidence,
                .en: max(0.0, confidence - margin)
            ]
        )

        return DecisionEvidence(
            original: original,
            decision: decision,
            confidence: confidence,
            winnerMargin: margin,
            primaryCandidate: DecisionEvidenceCandidate(hypothesis: .ruFromEnLayout, score: confidence),
            secondaryCandidate: DecisionEvidenceCandidate(hypothesis: .en, score: max(0.0, confidence - margin)),
            tokenKind: tokenKind,
            convertedText: converted,
            sourceLayout: .english,
            targetLanguage: targetLanguage,
            isCorrection: true,
            isWhitelistedShort: false
        )
    }

    func testNonAccessibilityPlainTokenAutoAppliesAtRelaxedThreshold() {
        let evidence = makeEvidence(
            original: "ghbdtn",
            converted: "привет",
            confidence: 0.89,
            margin: 0.17
        )

        let disposition = CorrectionDecisionPolicy.evaluate(
            evidence: evidence,
            environment: .nonAccessibility,
            preset: .balanced
        )

        XCTAssertEqual(disposition, .autoApply)
    }

    func testSingleLetterRemainsManualOnlyInNonAccessibility() {
        let evidence = makeEvidence(
            original: "r",
            converted: "к",
            confidence: 0.99,
            margin: 0.40,
            tokenKind: .short
        )

        let disposition = CorrectionDecisionPolicy.evaluate(
            evidence: evidence,
            environment: .nonAccessibility,
            preset: .balanced
        )

        XCTAssertEqual(disposition, .manualOnly)
    }
}
