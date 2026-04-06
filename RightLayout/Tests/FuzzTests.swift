import XCTest
@testable import RightLayout

/// Ticket 74: Property-Based / Fuzz Testing Infrastructure
/// Ensures core invariants hold for any random input without crashing or hanging.
final class FuzzTests: XCTestCase {
    
    // MARK: - Random Generators
    
    private let charPool = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZабвгдеёжзийклмнопрстуфхцчшщъыьэюяאבגדהוזחטיכלמנסעפצקרשת .,!?:;@#$%^&*()_+{}[]\"'-<>/\\\n\t"
    
    private func randomString(maxLength: Int = 100) -> String {
        let length = Int.random(in: 0...maxLength)
        return String((0..<length).map { _ in charPool.randomElement()! })
    }
    
    // MARK: - Properties
    
    /// Invariant: ConfidenceRouter.route() should never crash, regardless of input
    func testRouterNeverCrashes() async {
        let settings = await MainActor.run { SettingsManager.shared }
        let router = ConfidenceRouter(settings: settings)
        let context = DetectorContext(lastLanguage: nil)
        
        for _ in 0..<1000 {
            let input = randomString()
            let decision = await router.route(token: input, context: context)
            
            // Basic sanity checks on return value
            XCTAssertTrue(decision.confidence >= 0.0 && decision.confidence <= 1.0)
            XCTAssertNotNil(decision.language)
        }
    }
    
    /// Invariant: LayoutMapper convert should not produce strings drastically longer than input, and shouldn't crash
    func testLayoutMapperBounds() {
        let mapper = LayoutMapper.shared
        // Default layouts
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
        
        for _ in 0..<1000 {
            let input = randomString()
            
            // EN -> RU
            if let converted = mapper.convertBest(input, from: .english, to: .russian, activeLayouts: activeLayouts) {
                // Should be functionally the same length (with minor variations for edge mapping)
                XCTAssertLessThan(converted.count, input.count * 2 + 5)
            }
            
            // RU -> EN
            if let converted = mapper.convertBest(input, from: .russian, to: .english, activeLayouts: activeLayouts) {
                XCTAssertLessThan(converted.count, input.count * 2 + 5)
            }
        }
    }
    
    @MainActor
    func testIsTechnicalTokenDeterminism() {
        let router = ConfidenceRouter(settings: SettingsManager.shared)
        
        for _ in 0..<1000 {
            let input = randomString(maxLength: 50) // Technical tokens are usually short
            
            let result1 = router.isTechnicalToken(input)
            let result2 = router.isTechnicalToken(input)
            let result3 = router.isTechnicalToken(input)
            
            XCTAssertEqual(result1, result2)
            XCTAssertEqual(result1, result3)
        }
    }
    
    /// Invariant: CorrectionEngine correctText() handles garbage text without crash
    func testCorrectionEngineStability() async {
        let settings = await MainActor.run { SettingsManager.shared }
        let engine = CorrectionEngine(settings: settings)
        
        for _ in 0..<200 {
            let input = randomString()
            // We just care that it returns cleanly, not what the result is
            _ = await engine.correctText(input)
        }
    }
    
    /// Invariant: LayoutMapper roundtrips mostly
    /// (Note: Full roundtrip is impossible due to asymmetric mapping, but it shouldn't crash)
    func testLayoutMapperRoundtripSafety() {
        let mapper = LayoutMapper.shared
        let activeLayouts = ["en": "us", "ru": "russianwin"]
        
        for _ in 0..<500 {
            let original = randomString(maxLength: 30)
            
            if let enToRu = mapper.convertBest(original, from: .english, to: .russian, activeLayouts: activeLayouts) {
                 _ = mapper.convertBest(enToRu, from: .russian, to: .english, activeLayouts: activeLayouts)
                 // Just ensuring no fatalErrors
            }
        }
    }
}
