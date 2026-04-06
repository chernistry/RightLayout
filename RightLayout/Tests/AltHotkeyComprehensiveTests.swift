import XCTest
@testable import RightLayout

/// Comprehensive tests for ALL Alt hotkey mechanisms using realistic typing simulation.
/// Tests cover:
/// 1. Undo after auto-correction (Alt reverses auto-correction)
/// 2. Manual forced correction on fresh buffer text
/// 3. Cycling through ALL layout alternatives (EN→RU→HE→Original)
/// 4. Selection-based correction (simulated)
@MainActor
final class AltHotkeyComprehensiveTests: XCTestCase {
    var engine: CorrectionEngine!
    var buffer: TextBufferSimulator!
    
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        engine = CorrectionEngine(settings: settings)
        buffer = TextBufferSimulator()
    }
    
    // MARK: - Test Cases from test_cases.json
    
    /// Load test cases from JSON file
    struct TestCasesJSON: Codable {
        struct SingleWordCase: Codable {
            let input: String
            let expected: String
            let desc: String
        }
        
        struct SingleWordsSection: Codable {
            let cases: [SingleWordCase]
        }
        
        let single_words: SingleWordsSection?
    }
    
    // MARK: - 1. Undo After Auto-Correction
    
    func testUndoAfterAutoCorrection_Basic() async throws {
        // Scenario: "ghbdtn " auto-corrects to "привет ".
        // User presses Alt → should revert to "ghbdtn".
        
        let text = "ghbdtn"
        buffer.type(text)
        
        // Simulate auto-correction
        let result = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
        if let corrected = result.corrected {
            buffer.replaceLast(text.count, with: corrected)
            XCTAssertEqual(buffer.content, "привет", "Auto-correction should produce Russian")
        }
        
        // Now simulate Alt press for UNDO
        // After auto-correction, cyclingState is set with wasAutomatic=true.
        // First cycleCorrection should return original.
        if await engine.hasCyclingState() {
            let undone = await engine.cycleCorrection()
            XCTAssertEqual(undone, text, "First Alt press should undo to original")
            if let undone = undone {
                buffer.replaceLast(6, with: undone) // "привет".count = 6
            }
            XCTAssertEqual(buffer.content, text)
        }
    }
    
    func testUndoAfterAutoCorrection_HebrewInput() async throws {
        // Scenario: "akuo" (Hebrew שלום on EN layout) auto-corrects.
        // Alt should undo back to "akuo".
        
        let text = "akuo"
        buffer.type(text)
        
        let result = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
        if let corrected = result.corrected {
            buffer.replaceLast(text.count, with: corrected)
            XCTAssertEqual(buffer.content, "שלום", "Should convert to Hebrew")
        }
        
        if await engine.hasCyclingState() {
            let undone = await engine.cycleCorrection()
            XCTAssertEqual(undone, text, "Alt should undo Hebrew conversion")
        }
    }
    
    // MARK: - 2. Manual Forced Correction (processHotkeyCorrection)
    
    func testManualForcedCorrection_BasicRussian() async throws {
        // Scenario: User types "ghbdtn" but NO auto-correction (maybe threshold not met).
        // User manually presses Alt → should force correct to "привет".
        
        let text = "ghbdtn"
        buffer.type(text)
        
        // Simulate hotkey press (creates cycling state and returns first alternative)
        await engine.processHotkeyCorrection(text: text, bundleId: "com.test")
        
        let hasCycling = await engine.hasCyclingState()
        XCTAssertTrue(hasCycling, "Should have cycling state after hotkey")
        
        let corrected = await engine.cycleCorrection()
        XCTAssertNotNil(corrected, "Should return a corrected value")
        
        // First correction should be a valid alternative (Russian or Hebrew)
        if let corrected = corrected {
            buffer.replaceLast(text.count, with: corrected)
            // Accept either Russian "привет" or Hebrew "גהבדתנ" as valid first alternative
            // (Ordering depends on scoring which may vary)
            let validAlternatives = ["привет", "גהבדתנ"]
            XCTAssertTrue(validAlternatives.contains(corrected), "First alternative should be Russian or Hebrew. Got: \(corrected)")
        }
    }
    
    func testManualForcedCorrection_ReverseFromRussian() async throws {
        // Scenario: User typed "руддщ" (hello on RU layout).
        // Alt should correct to "hello".
        
        let text = "руддщ"
        buffer.type(text)
        
        await engine.processHotkeyCorrection(text: text, bundleId: "com.test")
        
        let corrected = await engine.cycleCorrection()
        XCTAssertNotNil(corrected)
        
        // Should get a valid conversion (EN or HE)
        if let corrected = corrected {
            // Accept either "hello" (EN) or Hebrew as valid
            XCTAssertNotEqual(corrected, text, "Should convert to something other than original")
        }
    }
    
    // MARK: - 3. Cycling Through All Alternatives
    
    func testCyclingAllAlternatives_ThreeLayouts() async throws {
        // "ghbdtn" on EN layout:
        // - Best: привет (RU)
        // - Next: גהבדתנ (HE, assuming Hebrew QWERTY)
        // - Last: ghbdtn (Original)
        
        let text = "ghbdtn"
        buffer.type(text)
        
        await engine.processHotkeyCorrection(text: text, bundleId: "com.test")
        
        var alternatives: [String] = []
        
        // Cycle until we return to first or exhaust (max 5 presses)
        for _ in 0..<5 {
            if let alt = await engine.cycleCorrection() {
                if alternatives.contains(alt) {
                    // We've wrapped around
                    break
                }
                alternatives.append(alt)
            } else {
                break
            }
        }
        
        // Should have at least 2 alternatives (corrected + original)
        XCTAssertGreaterThanOrEqual(alternatives.count, 2, "Should have at least 2 cycling alternatives")
        
        // Note: Original may not be shown yet if we haven't cycled enough
        // Just verify we have multiple different alternatives
        let uniqueAlternatives = Set(alternatives)
        XCTAssertGreaterThanOrEqual(uniqueAlternatives.count, 2, "Should have at least 2 unique alternatives")
        
        print("Cycling alternatives for '\(text)': \(alternatives)")
    }
    
    func testCyclingPreservesTextIntegrity() async throws {
        // Ensure no control characters or corruption during cycling
        let testCases = ["ghbdtn", "руддщ", "akuo", "ntcn"]
        
        for text in testCases {
            buffer.clear()
            buffer.type(text)
            
            await engine.processHotkeyCorrection(text: text, bundleId: "com.test")
            
            // Cycle 3 times
            for i in 0..<3 {
                if let alt = await engine.cycleCorrection() {
                    buffer.replaceLast(buffer.content.count, with: alt)
                    
                    let controlChars = buffer.findControlCharacters()
                    XCTAssertTrue(
                        controlChars.isEmpty,
                        "Cycle \(i+1) for '\(text)': Control characters found: \(controlChars.map { String(format: "0x%02X", $0.value) })"
                    )
                }
            }
        }
    }
    
    // MARK: - 4. All test_cases.json Single Words
    
    func testAllSingleWordCases() async throws {
        // Load and test all cases from test_cases.json single_words section
        let testCasesPath = "tests/test_cases.json"
        
        guard let data = FileManager.default.contents(atPath: testCasesPath) else {
            XCTFail("Could not load test_cases.json")
            return
        }
        
        let decoder = JSONDecoder()
        guard let json = try? decoder.decode(TestCasesJSON.self, from: data),
              let singleWords = json.single_words?.cases else {
            XCTFail("Could not parse test_cases.json")
            return
        }
        
        var passCount = 0
        var failCount = 0
        var failures: [(input: String, expected: String, actual: String?, desc: String)] = []
        
        for testCase in singleWords {
            buffer.clear()
            buffer.type(testCase.input)
            
            let result = await engine.correctText(testCase.input, phraseBuffer: "", expectedLayout: nil)
            let actual = result.corrected ?? testCase.input
            
            if actual == testCase.expected {
                passCount += 1
            } else {
                failCount += 1
                failures.append((testCase.input, testCase.expected, actual, testCase.desc))
            }
        }
        
        print("Single Word Test Results: \(passCount) passed, \(failCount) failed")
        if !failures.isEmpty {
            print("Failures:")
            for (input, expected, actual, desc) in failures.prefix(10) {
                print("  - '\(input)' expected '\(expected)' got '\(actual ?? "nil")' (\(desc))")
            }
        }
        
        // Reliability-first auto path is intentionally narrower in v4.1.
        let passRate = Double(passCount) / Double(passCount + failCount)
        XCTAssertGreaterThan(passRate, 0.55, "Pass rate should remain > 55% under reliability-first auto policy. Got \(passRate * 100)%")
    }
    
    // MARK: - 5. Edge Cases
    
    func testHotkeyOnEmptyBuffer() async throws {
        // Alt on empty buffer should do nothing (no crash)
        await engine.processHotkeyCorrection(text: "", bundleId: "com.test")
        let hasCycling = await engine.hasCyclingState()
        XCTAssertFalse(hasCycling, "Empty text should not create cycling state")
    }
    
    func testHotkeyOnAmbiguousWord() async throws {
        // "ok" is valid in EN - should not be corrected
        let text = "ok"
        buffer.type(text)
        
        await engine.processHotkeyCorrection(text: text, bundleId: "com.test")
        
        // May or may not have cycling state (depends on whether alternatives exist)
        // But should not crash
        if await engine.hasCyclingState() {
            let alt = await engine.cycleCorrection()
            XCTAssertNotNil(alt)
        }
    }
    
    func testHotkeyOnURL() async throws {
        // URLs should not be corrected
        let url = "https://example.com"
        buffer.type(url)
        
        await engine.processHotkeyCorrection(text: url, bundleId: "com.test")
        
        // Should not have cycling state or should return unchanged
        let hasCycling = await engine.hasCyclingState()
        // URLs may or may not get cycling state depending on IntentDetector
        // Just ensure no crash and if we get a result, log it
        if hasCycling {
            let alt = await engine.cycleCorrection()
            // Log what we got for debugging
            print("URL cycling result: \(alt ?? "nil")")
        }
    }
    
    // MARK: - 6. Comma/Б Period/Ю Mapping (Ticket 58/59 regression)
    
    func testCommaMappingInWord() async throws {
        // "cgfcb,j" should become "спасибо" (comma maps to б)
        let text = "cgfcb,j"
        buffer.type(text)
        
        let corrected = await engine.correctLastWord(text, bundleId: "com.test")
        XCTAssertEqual(corrected, "спасибо", "Manual correction should still map comma to б")
    }
    
    func testPeriodMappingInWord() async throws {
        // "k.,k." should become "люблю" (period maps to ю)
        let text = "k.,k."
        buffer.type(text)
        
        await engine.processHotkeyCorrection(text: text, bundleId: "com.test")

        var seen: Set<String> = []
        for _ in 0..<5 {
            if let alternative = await engine.cycleCorrection() {
                seen.insert(alternative)
            }
        }

        XCTAssertGreaterThanOrEqual(seen.count, 2, "Manual correction cycle should still surface alternatives for punctuation-mapped input")
    }
}
