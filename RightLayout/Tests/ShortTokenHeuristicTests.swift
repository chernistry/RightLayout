import XCTest
@testable import RightLayout

final class ShortTokenHeuristicTests: XCTestCase {
    func testEnsemblePrefersHebrewFromEnglishForMH() async throws {
        let validator = MockWordValidator(validWords: [
            .english: ["hi", "ok", "yes"],
            .russian: ["да", "нет"],
            .hebrew: ["מה", "לא", "כן"]
        ])

        let ensemble = LanguageEnsemble(wordValidator: validator)
        let context = EnsembleContext(
            lastLanguage: nil,
            activeLayouts: ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
        )

        let decision = await ensemble.classify("mh", context: context)
        XCTAssertEqual(decision.layoutHypothesis, .heFromEnLayout)
        XCTAssertGreaterThan(decision.confidence, 0.7)
    }
    // MARK: - Ticket 47: Single-letter safety
    
    @MainActor
    func testSingleCyrillicLetterSafety() async throws {
        // "я" is a valid Russian word (manual/pronoun "I"). 
        // It should NEVER be auto-corrected to "z" (English), even if "z" is frequent.
        
        let settings = SettingsManager.shared

        
        let router = ConfidenceRouter(settings: settings)
        let token = "я"
        let context = DetectorContext(lastLanguage: .russian)
        
        let decision = await router.route(token: token, context: context, mode: .automatic)
        
        // Should keep as Russian
        XCTAssertEqual(decision.language, Language.russian)
        // Should basically be a "Keep" decision
        XCTAssertEqual(decision.layoutHypothesis, LanguageHypothesis.ru)
    }

    @MainActor
    func testSingleLatinLetterSafety() async throws {
        // "z" maps to "я" on RU layout.
        // Even though "я" is a word, valid 1-letter Latin should NOT be aggressively auto-corrected
        // in isolation, because 1-letter variables (x, y, z) are common.
        
        let settings = SettingsManager.shared

        
        let router = ConfidenceRouter(settings: settings)
        let token = "z"
        
        // Even if previous context was Russian
        let context = DetectorContext(lastLanguage: .russian)
        
        let decision = await router.route(token: token, context: context, mode: .automatic)
        
        // Should NOT auto-correct to Russian "я"
        // It should remain English "z" (or at least not return a correction hypothesis)
        XCTAssertEqual(decision.language, Language.english)
        XCTAssertEqual(decision.layoutHypothesis, LanguageHypothesis.en)
    }
}
