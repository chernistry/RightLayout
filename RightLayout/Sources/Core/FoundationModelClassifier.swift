#if canImport(FoundationModels)
import Foundation
import FoundationModels
import os.log

/// Classifier using Apple's on-device Foundation Models (macOS 26+)
/// as an alternative/supplement to CoreMLLayoutClassifier.
///
/// Uses structured generation via @Generable to produce typed predictions
/// matching the same 9-class label set as the CoreML model.
///
/// Ticket 72: Apple Foundation Models Integration
@available(macOS 26, *)
public final class FoundationModelClassifier: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "FoundationModel")

    // MARK: - Structured Output

    /// Layout hypothesis as a @Generable enum — Foundation Models constrain output to these cases.
    @Generable
    enum PredictedHypothesis {
        case ru
        case en
        case he
        case ru_from_en
        case he_from_en
        case en_from_ru
        case en_from_he
        case he_from_ru
        case ru_from_he
    }

    @Generable(description: "Layout detection prediction for a text token")
    struct LayoutPrediction {
        var hypothesis: PredictedHypothesis

        @Guide(description: "Confidence score from 0.0 to 1.0", .range(0.0...1.0))
        var confidence: Double
    }

    // MARK: - Mapping

    private static let hypothesisMapping: [PredictedHypothesis: LanguageHypothesis] = [
        .ru: .ru, .en: .en, .he: .he,
        .ru_from_en: .ruFromEnLayout, .he_from_en: .heFromEnLayout,
        .en_from_ru: .enFromRuLayout, .en_from_he: .enFromHeLayout,
        .he_from_ru: .heFromRuLayout, .ru_from_he: .ruFromHeLayout
    ]

    // MARK: - State

    private let systemPrompt: String = """
    You are a keyboard layout mismatch detector for a multilingual text correction app.
    The user types in three languages: English, Russian, and Hebrew.
    Sometimes users accidentally type in the wrong keyboard layout — for example, \
    typing Russian words while the English keyboard is active produces gibberish like "ghbdtn" \
    instead of "привет".

    Given a text token and its keyboard context, determine:
    1. Which language/layout the text actually belongs to.
    2. Whether it was typed on the wrong keyboard layout.

    Be precise. Short tokens (1-3 chars) are inherently ambiguous — express lower confidence.
    """

    private var isAvailable: Bool = false

    private var session: LanguageModelSession?

    // MARK: - Init

    public init() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            isAvailable = true
            self.session = LanguageModelSession(model: .default) { [systemPrompt] in
                systemPrompt
            }
            logger.info("✅ Foundation Models available")
        case .unavailable(let reason):
            isAvailable = false
            logger.info("⚠️ Foundation Models unavailable: \(String(describing: reason))")
        }
    }

    // MARK: - Availability

    /// Whether the Foundation Model is ready for inference.
    public var modelAvailable: Bool { isAvailable && session != nil }

    // MARK: - Prediction

    /// Predicts the layout/language for the given text using Foundation Models.
    /// - Parameters:
    ///   - text: The token to classify
    ///   - context: Optional phrase buffer for context
    /// - Returns: Tuple of (Hypothesis, Confidence) or nil if prediction fails/unavailable.
    public func predict(_ text: String, context: String = "") async -> (LanguageHypothesis, Double)? {
        guard let session = self.session, isAvailable else { return nil }

        let prompt: String
        if context.isEmpty {
            prompt = "Classify this token: \"\(text)\""
        } else {
            prompt = "Classify this token: \"\(text)\" (context: \"\(context)\")"
        }

        do {
            let response = try await session.respond(
                to: prompt,
                generating: LayoutPrediction.self
            )

            let prediction = response.content

            guard let hypothesis = Self.hypothesisMapping[prediction.hypothesis] else {
                logger.warning("⚠️ Foundation Model returned unmapped hypothesis")
                return nil
            }

            let confidence = min(max(prediction.confidence, 0.0), 1.0)
            logger.info("🤖 FM prediction: \(hypothesis.rawValue) (conf: \(String(format: "%.2f", confidence)))")
            return (hypothesis, confidence)

        } catch {
            logger.error("❌ Foundation Model error: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
