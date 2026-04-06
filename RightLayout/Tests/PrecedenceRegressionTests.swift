import XCTest
@testable import RightLayout

final class PrecedenceRegressionTests: XCTestCase {
    
    // Helper to load model from absolute path avoiding Bundle issues in test
    func loadModel(_ lang: String) throws -> NgramLanguageModel {
        let path = "Resources/LanguageModels/\(lang)_trigrams.json"
        let url = URL(fileURLWithPath: path)
        return try NgramLanguageModel.loadFrom(jsonURL: url)
    }

    func testReproduceUserIssue() async throws {
        print("\n--- REPRODUCTION TEST START ---")
        
        // Setup mock layouts
        let activeLayouts = [
            "com.apple.keylayout.US": "en",
            "com.apple.keylayout.Russian": "ru",
            "com.apple.keylayout.Hebrew": "he"
        ]
        
        let mapper = LayoutMapper.shared
        
        // Scenario 1: User says input is "כנח" (Hebrew)
        let heInput = "כנח"
        print("Input: '\(heInput)' (he)")
        
        if let en = mapper.convertBest(heInput, from: .hebrew, to: .english, activeLayouts: activeLayouts) {
            let model = try loadModel("en")
            let score = model.normalizedScore(en)
            print("  -> EN: '\(en)' (Score: \(String(format: "%.4f", score)))")
        }
        
        if let ru = mapper.convertBest(heInput, from: .hebrew, to: .russian, activeLayouts: activeLayouts) {
            let model = try loadModel("ru")
            let score = model.normalizedScore(ru)
            print("  -> RU: '\(ru)' (Score: \(String(format: "%.4f", score)))")
        }
        
        // Scenario 2: User says this converts to "tbh" (English)
        // Let's verify if "tbh" is the output from Scenario 1.
        
        let enInput = "tbh"
        print("\nCheck 'tbh' (en):")
        let enModel = try loadModel("en")
        print("  Score(tbh|en): \(String(format: "%.4f", enModel.normalizedScore(enInput)))")
        
        if let ru = mapper.convertBest(enInput, from: .english, to: .russian, activeLayouts: activeLayouts) {
            let model = try loadModel("ru")
            let score = model.normalizedScore(ru)
            print("  -> RU: '\(ru)' (Score: \(String(format: "%.4f", score)))")
        }
        
        if let he = mapper.convertBest(enInput, from: .english, to: .hebrew, activeLayouts: activeLayouts) {
            let model = try loadModel("he")
            let score = model.normalizedScore(he)
            print("  -> HE: '\(he)' (Score: \(String(format: "%.4f", score)))")
        }
        
        // Scenario 3: User intended "что" (Russian)
        let ruTarget = "что"
        print("\nReverse engineering 'что' (ru):")
        if let enSrc = mapper.convertBest(ruTarget, from: .russian, to: .english, activeLayouts: activeLayouts) {
            print("  <- EN Source: '\(enSrc)'")
        }
        if let heSrc = mapper.convertBest(ruTarget, from: .russian, to: .hebrew, activeLayouts: activeLayouts) {
            print("  <- HE Source: '\(heSrc)'")
        }
        
        print("--- REPRODUCTION TEST END ---\n")
    }

    @MainActor
    func testPrecedenceIssue() async throws {
        // Test that 'he' input routes to 'ru' even if 'en' is plausible-ish
        let settings = SettingsManager.shared
        settings.activeLayouts = [
            "com.apple.keylayout.US": "en",
            "com.apple.keylayout.Russian": "ru",
            "com.apple.keylayout.Hebrew": "he"
        ]
        
        // We need to bypass Bundle loading for Models if running in test bundle?
        // Ah, ConfidenceRouter uses internal init.
        // And ConfidenceRouter loads models internally.
        // WE KNOW ConfidenceRouter loads models correctly in EarlyLayoutSwitchingTests!
        // So standard init is fine.
        
        let router = ConfidenceRouter(settings: settings)
        
        let heInput = "כנח" // Maps to "что" (RU) and "fbj" (EN)
        
        // Mock context
        let context = DetectorContext(lastLanguage: nil)
        
        // Route (Automatic mode)
        let decision = await router.route(token: heInput, context: context, mode: .automatic)
        
        print("Decision language: \(decision.language)")
        print("Decision confidence: \(decision.confidence)")
        print("Decision layout: \(decision.layoutHypothesis.rawValue)")
        
        // Assert we picked RUSSIAN, not English
        XCTAssertEqual(decision.language, Language.russian, "Should pick Russian for 'כנח' -> 'что', avoiding greedy English correction")
    }
}
