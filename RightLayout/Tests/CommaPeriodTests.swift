import XCTest
@testable import RightLayout

final class CommaPeriodTests: XCTestCase {
    
    // MARK: - LayoutMapper Tests
    
    func testLayoutMapper_JComma_To_OB() {
        let mapper = LayoutMapper.shared
        // Mock active layouts: standard Mac setup
        let activeLayouts = ["com.apple.keylayout.US": "ABC", "com.apple.keylayout.Russian": "Russian"]
        
        // Step 1: Verify raw conversion (Mac layout)
        // j -> о
        // , -> ? (Mac Russian)
        // Expected: "о?" (standard Mac mapping)
        let macConversion = mapper.convert("j,", from: .english, to: .russian)
        // Note: convert() might default to "о?" or similar. Check exact output.
        print("Raw Mac conversion: \(macConversion ?? "nil")")
        
        // Step 2: Verify PC layout variant (Ensemble)
        // LayoutMapper.convertAllVariants should find "об" via RussianWin
        let variants = mapper.convertAllVariants("j,", from: .english, to: .russian, activeLayouts: activeLayouts)
        print("All converted variants: \(variants)")
        
        let hasOb = variants.contains { $0.result == "об" }
        XCTAssertTrue(hasOb, "convertAllVariants MUST produce 'об' via RussianWin or similar layout")
    }

    func testLayoutMapper_KPointCommaKPoint_To_Love() {
        let mapper = LayoutMapper.shared
        // "k.,k." -> "люблю"
        let result = mapper.convertBest("k.,k.", from: .english, to: .russian, activeLayouts: nil)
        XCTAssertEqual(result, "люблю")
    }

    // MARK: - CorrectionEngine Tests
    
    func testCorrectionEngine_SmartCorrect_JComma() async {
        let settings = await MainActor.run { 
            let s = SettingsManager.shared 
            s.isVerifierEnabled = false
            return s
        }
        let engine = CorrectionEngine(settings: settings)
        
        let config = LanguageDataConfig.shared
        let hasOb = config.lexiconContains("об", language: .russian)
        XCTAssertTrue(hasOb, "Lexicon MUST contain 'об'")
        
        let input = "j,"
        let result = await engine.correctText(input, phraseBuffer: "", expectedLayout: nil)

        // Reliability-first baseline: very short punctuated tokens are ambiguous
        // enough that the engine must not auto-rewrite them.
        XCTAssertNil(result.corrected)
        XCTAssertNotEqual(result.action, .applied)

        // The manual hotkey path must still surface the intended correction.
        let manual = await engine.correctLastWord(input)
        XCTAssertEqual(manual, "об")
    }

    func testCorrectionEngine_SmartCorrect_Love() async {
        let settings = await MainActor.run { 
            let s = SettingsManager.shared 
            s.isVerifierEnabled = false
            return s
        }
        let engine = CorrectionEngine(settings: settings)
        
        let input = "k.,k."
        let result = await engine.correctText(input, phraseBuffer: "", expectedLayout: nil)
        
        XCTAssertEqual(result.corrected, "люблю", "Must correct 'k.,k.' to 'люблю'")
        XCTAssertEqual(result.action, .applied)
    }
}
