import XCTest
@testable import RightLayout

final class DeferredCorrectionTests: XCTestCase {
    
    actor TestHost {
        let engine: CorrectionEngine
        
        init(settings: SettingsManager) {
            self.engine = CorrectionEngine(settings: settings)
        }
        
        func correct(_ text: String, expectedLayout: Language? = nil) async -> CorrectionEngine.CorrectionResult {
            return await engine.correctText(text, phraseBuffer: "", expectedLayout: expectedLayout)
        }
    }
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        settings.isLearningEnabled = false
        settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
        SettingsManager.shared.autoSwitchLayout = false // Avoid actual switching in tests
        
        // Setup unigram models if needed (mocked or loaded)
        // For tests, we might rely on the engine loading them or mocks. 
        // Assuming engine loads them or uses built-in lexicon. 
        // "ye" is valid EN. "ну" is valid RU.
        // "xnj" -> "что".
    }

    override func tearDown() async throws {
        await MainActor.run {
            SettingsManager.shared.isLearningEnabled = true
        }
    }
    
    func testDeferredCorrection_YeChto() async {
        let host = TestHost(settings: await MainActor.run { SettingsManager.shared })
        
        // 1. User types "vs" (intended "мы")
        // "vs" is valid English abbreviation "versus". 
        // Without deferred logic, this should NOT correct.
        let result1 = await host.correct("vs")
        XCTAssertNil(result1.corrected, "First word 'vs' should NOT be corrected immediately as it is valid EN")
        
        // 2. User types "xnj" (intended "что")
        // Short strong token may still auto-correct, but retroactive cascade stays disabled.
        let result2 = await host.correct("xnj")

        XCTAssertEqual(result2.corrected, "что", "Strong short token should still auto-correct in AX mode")
        XCTAssertNil(result2.pendingCorrection, "Retroactive auto-cascade is disabled by default")
        XCTAssertNil(result2.pendingOriginal)
    }
    
    func testDeferredCorrection_StartOfSentence() async {
        let host = TestHost(settings: await MainActor.run { SettingsManager.shared })
        
        // 1. User types "z" (intended "я")
        // "z" is valid English (letter). 
        // Should be kept as "z" initially due to single-letter safety.
        let result1 = await host.correct("z")
        XCTAssertNil(result1.corrected, "First word 'z' should NOT be corrected immediately")
        
        // 2. User types "ghbdtn" (intended "привет")
        // Strong fast-lane word should correct, but must not retroactively mutate the prior single-letter token.
        let result2 = await host.correct("ghbdtn")

        XCTAssertEqual(result2.corrected, "привет")
        XCTAssertNil(result2.pendingCorrection, "Single-letter cascade is disabled by default")
        XCTAssertNil(result2.pendingOriginal)
    }
    
    func testNoRegression_YeOlde() async {
        let host = TestHost(settings: await MainActor.run { SettingsManager.shared })
        
        // 1. "vs" (ambiguous)
        let result1 = await host.correct("vs")
        XCTAssertNil(result1.corrected)
        
        // 2. "olde" (valid English, or at least not Russian)
        let result2 = await host.correct("olde")
        
        XCTAssertNil(result2.corrected, "Second word 'olde' is valid/unknown, should not force Russian")
        XCTAssertNil(result2.pendingCorrection, "Should NOT cascade correct 'vs' when next word is English")
    }
}
