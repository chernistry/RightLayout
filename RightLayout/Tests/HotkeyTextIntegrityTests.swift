import XCTest
@testable import RightLayout

/// Synthetic E2E tests for hotkey undo/cycle and forced layout switch.
/// Validates text integrity: no extra deletions, no control characters, correct replacement lengths.
final class HotkeyTextIntegrityTests: XCTestCase {
    var engine: CorrectionEngine!
    var buffer: TextBufferSimulator!
    var inputSwitcher: MockInputSourceSwitcher!
    private var originalLearningEnabled: Bool = true
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        originalLearningEnabled = settings.isLearningEnabled
        settings.isLearningEnabled = false // Deterministic: avoid RiskController suppressing auto-corrections.
        settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
        engine = CorrectionEngine(settings: settings)
        buffer = TextBufferSimulator()
        inputSwitcher = MockInputSourceSwitcher()
    }
    
    override func tearDown() async throws {
        await engine.resetCycling()
        buffer.clear()
        inputSwitcher.reset()
        await MainActor.run {
            SettingsManager.shared.isLearningEnabled = originalLearningEnabled
        }
    }
    
    // MARK: - Helper Methods
    
    /// Simulate typing text and triggering word-boundary correction
    private func simulateTypingWithCorrection(_ text: String) async -> (original: String, corrected: String?) {
        buffer.type(text)
        let result = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
        
        if let corrected = result.corrected {
            // Simulate the replacement operation
            buffer.replaceLast(text.count, with: corrected)
        }
        
        return (text, result.corrected)
    }
    
    /// Simulate hotkey press for manual correction (word mode)
    private func simulateHotkeyWordCorrection(_ text: String) async -> String? {
        return await engine.correctLastWord(text)
    }
    
    /// Simulate cycling through alternatives
    private func simulateCycle() async -> String? {
        return await engine.cycleCorrection()
    }
    
    /// Assert buffer contains no control characters
    private func assertNoControlCharacters(file: StaticString = #file, line: UInt = #line) {
        let controlChars = buffer.findControlCharacters()
        XCTAssertTrue(
            controlChars.isEmpty,
            "Buffer contains control characters: \(controlChars.map { String(format: "0x%02X", $0.value) })",
            file: file,
            line: line
        )
    }
    
    // MARK: - A) Word Mode Hotkey Tests
    
    func testWordModeCorrection_RussianFromEnglish() async throws {
        // "ghbdtn" typed on EN layout should become "привет" (Russian)
        let text = "ghbdtn"
        buffer.type(text)
        
        let corrected = await simulateHotkeyWordCorrection(text)
        XCTAssertNotNil(corrected, "Should produce correction for ghbdtn")
        
        if let corrected = corrected {
            buffer.replaceLast(text.count, with: corrected)
            XCTAssertEqual(corrected, "привет", "Should convert to Russian 'привет'")
            XCTAssertEqual(buffer.content, "привет")
            assertNoControlCharacters()
        }
    }
    
    func testWordModeCorrection_EnglishFromRussian() async throws {
        // "руддщ" typed on RU layout should become "hello" (English)
        let text = "руддщ"
        buffer.type(text)
        
        let corrected = await simulateHotkeyWordCorrection(text)
        XCTAssertNotNil(corrected, "Should produce correction for руддщ")
        
        if let corrected = corrected {
            buffer.replaceLast(text.count, with: corrected)
            XCTAssertEqual(corrected, "hello", "Should convert to English 'hello'")
            XCTAssertEqual(buffer.content, "hello")
            assertNoControlCharacters()
        }
    }
    
    func testWordModeCorrection_HebrewFromEnglish() async throws {
        // "akuo" typed on EN layout should become Hebrew (if valid)
        let text = "akuo"
        buffer.type(text)
        
        let corrected = await simulateHotkeyWordCorrection(text)
        // Hebrew conversion may or may not produce valid word
        if let corrected = corrected {
            buffer.replaceLast(text.count, with: corrected)
            assertNoControlCharacters()
        }
    }
    
    func testWordModeCorrection_ValidWordNotChanged() async throws {
        // "hello" is valid English - should still offer alternatives but not auto-correct
        let text = "hello"
        buffer.type(text)
        
        // Manual correction should still work (offers alternatives)
        let corrected = await simulateHotkeyWordCorrection(text)
        
        // Even if correction is offered, buffer should not contain control chars
        if let corrected = corrected {
            buffer.replaceLast(text.count, with: corrected)
        }
        assertNoControlCharacters()
    }
    
    // MARK: - B) Cycling Tests
    
    func testCycling_UndoAfterAutoCorrection() async throws {
        // Simulate auto-correction, then hotkey should UNDO first
        let text = "ghbdtn"
        buffer.type(text)
        
        // Auto-correct
        let result = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "привет")
        buffer.replaceLast(text.count, with: result.corrected!)
        XCTAssertEqual(buffer.content, "привет")
        
        // First hotkey press should UNDO (go back to original)
        let cycled1 = await simulateCycle()
        XCTAssertNotNil(cycled1)
        if let cycled1 = cycled1 {
            buffer.replaceLast("привет".count, with: cycled1)
            XCTAssertEqual(cycled1, text, "First cycle should undo to original")
            XCTAssertEqual(buffer.content, text)
        }
        
        assertNoControlCharacters()
    }
    
    func testCycling_MultiplePresses() async throws {
        let text = "ghbdtn"
        buffer.type(text)
        
        // Start manual correction
        let corrected = await simulateHotkeyWordCorrection(text)
        XCTAssertNotNil(corrected)
        buffer.replaceLast(text.count, with: corrected!)
        let afterFirst = buffer.content
        
        // Cycle through alternatives
        var previousContent = afterFirst
        var seenContents: Set<String> = [afterFirst]
        
        for _ in 0..<5 {
            let cycled = await simulateCycle()
            if let cycled = cycled {
                buffer.replaceLast(previousContent.count, with: cycled)
                previousContent = cycled
                seenContents.insert(cycled)
                
                // Verify no control characters after each cycle
                assertNoControlCharacters()
            } else {
                break
            }
        }
        
        // Should have seen at least 2 different values (original + corrected)
        XCTAssertGreaterThanOrEqual(seenContents.count, 2, "Should cycle through at least 2 alternatives")
    }
    
    func testCycling_ReturnsToOriginal() async throws {
        let text = "ghbdtn"
        buffer.type(text)
        
        // Manual correction
        let corrected = await simulateHotkeyWordCorrection(text)
        XCTAssertNotNil(corrected)
        buffer.replaceLast(text.count, with: corrected!)
        
        // Keep cycling until we see the original again
        var foundOriginal = false
        var currentText = corrected!
        
        for _ in 0..<10 {
            let cycled = await simulateCycle()
            if let cycled = cycled {
                buffer.replaceLast(currentText.count, with: cycled)
                currentText = cycled
                
                if cycled == text {
                    foundOriginal = true
                    break
                }
            } else {
                break
            }
        }
        
        XCTAssertTrue(foundOriginal, "Cycling should eventually return to original text")
        assertNoControlCharacters()
    }
    
    // MARK: - C) Phrase Mode Tests
    
    func testPhraseMode_OnlyWrongSegmentReplaced() async throws {
        // Simulate: "ok " + wrong-layout-word
        // Only the wrong part should be replaced
        
        let correctPart = "ok "
        let wrongPart = "ghbdtn"  // Should become "привет"
        
        buffer.type(correctPart)
        buffer.type(wrongPart)
        
        // Correct only the wrong part
        let corrected = await simulateHotkeyWordCorrection(wrongPart)
        XCTAssertNotNil(corrected)
        
        if let corrected = corrected {
            // Replace only the wrong part length
            buffer.replaceLast(wrongPart.count, with: corrected)
            
            // "ok " should remain intact
            XCTAssertTrue(buffer.content.hasPrefix(correctPart), 
                         "Correct prefix 'ok ' should remain intact. Got: \(buffer.content)")
            assertNoControlCharacters()
        }
    }
    
    func testPhraseMode_MixedCorrectAndWrong() async throws {
        // "hello ghbdtn world" - only middle word is wrong
        let prefix = "hello "
        let wrongWord = "ghbdtn"
        let suffix = " world"
        
        buffer.type(prefix)
        buffer.type(wrongWord)
        buffer.type(suffix)
        
        // Full content before correction
        let fullBefore = buffer.content
        XCTAssertEqual(fullBefore, "hello ghbdtn world")
        
        // In real app, phrase mode would identify and correct only the wrong segment
        // Here we test that correcting the wrong word doesn't corrupt surrounding text
        
        // Simulate correcting just the wrong word (as if selected)
        let corrected = await simulateHotkeyWordCorrection(wrongWord)
        
        if let corrected = corrected {
            // This simulates what SHOULD happen: only wrongWord.count chars deleted
            // In the middle of the buffer, but our simulator only handles end-of-buffer
            // So we verify the correction itself is valid
            XCTAssertEqual(corrected, "привет")
            assertNoControlCharacters()
        }
    }
    
    // MARK: - D) Input Source Switching Tests
    
    func testInputSourceSwitch_CalledAfterManualCorrection() async throws {
        let text = "ghbdtn"
        
        // Perform manual correction
        let corrected = await engine.correctLastWord(text)
        XCTAssertNotNil(corrected)
        
        // Get target language from engine
        let targetLang = await engine.getLastCorrectionTargetLanguage()
        XCTAssertNotNil(targetLang, "Should have target language after correction")
        XCTAssertEqual(targetLang, .russian, "Target should be Russian for ghbdtn→привет")
    }
    
    func testInputSourceSwitch_NotCalledWhenNoCorrection() async throws {
        // Valid English word - no correction needed
        let text = "hello"
        
        // Auto-correct should return nil
        let result = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(result.corrected, "Valid word should not be corrected")
        
        // No target language should be set
        let targetLang = await engine.getLastCorrectionTargetLanguage()
        // After no correction, cycling state should be nil
        let hasCycling = await engine.hasCyclingState()
        if !hasCycling {
            XCTAssertNil(targetLang, "No target language when no correction")
        }
    }
    
    // MARK: - E) Control Character Guardrail Tests
    
    func testNoControlCharacters_AfterCorrection() async throws {
        let testCases = ["ghbdtn", "руддщ", "ntcn", "ызщку"]
        
        for text in testCases {
            buffer.clear()
            buffer.type(text)
            
            let corrected = await simulateHotkeyWordCorrection(text)
            if let corrected = corrected {
                buffer.replaceLast(text.count, with: corrected)
                
                let controlChars = buffer.findControlCharacters()
                XCTAssertTrue(
                    controlChars.isEmpty,
                    "Control characters found after correcting '\(text)': \(controlChars.map { String(format: "0x%02X", $0.value) })"
                )
            }
        }
    }
    
    func testNoControlCharacters_AfterCycling() async throws {
        let text = "ghbdtn"
        buffer.type(text)
        
        _ = await simulateHotkeyWordCorrection(text)
        
        // Cycle multiple times
        for _ in 0..<5 {
            let cycled = await simulateCycle()
            if let cycled = cycled {
                // Check the cycled text itself for control characters
                for scalar in cycled.unicodeScalars {
                    if scalar.value <= 0x1F || scalar.value == 0x7F {
                        if scalar != "\n" && scalar != "\r" && scalar != "\t" {
                            XCTFail("Control character 0x\(String(format: "%02X", scalar.value)) found in cycled text: \(cycled)")
                        }
                    }
                }
            }
        }
    }
    
    func testNoDELCharacter_InOutput() async throws {
        // Specifically test for DEL (0x7F) which was reported in bugs
        let testCases = ["ghbdtn", "руддщ", "ntcn"]
        
        for text in testCases {
            let corrected = await simulateHotkeyWordCorrection(text)
            if let corrected = corrected {
                let hasDEL = corrected.unicodeScalars.contains { $0.value == 0x7F }
                XCTAssertFalse(hasDEL, "DEL character (0x7F) found in correction of '\(text)': \(corrected)")
            }
            
            // Also check cycling
            for _ in 0..<3 {
                let cycled = await simulateCycle()
                if let cycled = cycled {
                    let hasDEL = cycled.unicodeScalars.contains { $0.value == 0x7F }
                    XCTAssertFalse(hasDEL, "DEL character (0x7F) found in cycled text: \(cycled)")
                }
            }
            
            await engine.resetCycling()
        }
    }
    
    // MARK: - F) Regression Tests
    
    func testRegression_DeletesTooMuch() async throws {
        // Regression: deletion length exceeds intended segment
        let prefix = "correctly typed "
        let wrongWord = "ghbdtn"
        
        buffer.type(prefix)
        buffer.type(wrongWord)
        
        let fullBefore = buffer.content
        XCTAssertEqual(fullBefore, "correctly typed ghbdtn")
        
        // Correct only the wrong word
        let corrected = await simulateHotkeyWordCorrection(wrongWord)
        XCTAssertNotNil(corrected)
        
        if let corrected = corrected {
            // Verify we only delete wrongWord.count characters
            let op = buffer.replaceLast(wrongWord.count, with: corrected)
            
            XCTAssertEqual(op.deletedCount, wrongWord.count, 
                          "Should delete exactly \(wrongWord.count) chars, not more")
            XCTAssertTrue(buffer.content.hasPrefix(prefix),
                         "Prefix should remain intact. Got: \(buffer.content)")
        }
    }
    
    func testRegression_TrailingSpaceHandling() async throws {
        // Regression: trailing space causes double-count
        let wordWithSpace = "ghbdtn "
        let wordWithoutSpace = "ghbdtn"
        
        buffer.type(wordWithSpace)
        
        // Correction should handle trailing space correctly
        let result = await engine.correctText(wordWithoutSpace, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNotNil(result.corrected)
        
        if let corrected = result.corrected {
            // When replacing, we need to account for the space
            // The word is 6 chars, space is 1, total 7
            // But correction is for the word only (6 chars)
            
            // Simulate what EventMonitor does: delete word + space, insert corrected + space
            buffer.replaceLast(wordWithSpace.count, with: corrected + " ")
            
            XCTAssertEqual(buffer.content, "привет ", "Should have corrected word + space")
            assertNoControlCharacters()
        }
    }
    
    func testRegression_CyclingLengthMismatch() async throws {
        // Regression: cycling uses wrong length for replacement
        let text = "ghbdtn"
        buffer.type(text)
        
        // First correction
        let corrected1 = await simulateHotkeyWordCorrection(text)
        XCTAssertNotNil(corrected1)
        buffer.replaceLast(text.count, with: corrected1!)
        
        var currentLength = corrected1!.count
        
        // Cycle and verify lengths match
        for _ in 0..<5 {
            let cycled = await simulateCycle()
            if let cycled = cycled {
                // The length we delete should match what we previously inserted
                let op = buffer.replaceLast(currentLength, with: cycled)
                
                XCTAssertEqual(op.deletedCount, currentLength,
                              "Deleted count should match previous text length")
                
                currentLength = cycled.count
                assertNoControlCharacters()
            } else {
                break
            }
        }
    }
}

// MARK: - Deterministic Test Fixtures

extension HotkeyTextIntegrityTests {
    /// Fixed test cases for reproducibility (seeded)
    static let deterministicTestCases: [(input: String, expectedLang: Language, expectedOutput: String?)] = [
        ("ghbdtn", .russian, "привет"),
        ("руддщ", .english, "hello"),
        ("ntcn", .russian, "тест"),
        ("ызщку", .english, "spore"),  // Actually maps to "spore" not "score"
        ("hello", .english, nil),  // Valid, no correction
        ("привет", .russian, nil), // Valid, no correction
    ]
    
    func testDeterministicCases() async throws {
        for (input, expectedLang, expectedOutput) in Self.deterministicTestCases {
            buffer.clear()
            await engine.resetCycling()
            
            let result = await engine.correctText(input, phraseBuffer: "", expectedLayout: nil)
            
            if let expectedOutput = expectedOutput {
                XCTAssertEqual(result.corrected, expectedOutput,
                              "Input '\(input)' should correct to '\(expectedOutput)'")
            } else {
                XCTAssertNil(result.corrected,
                            "Input '\(input)' should not be corrected (valid \(expectedLang.rawValue))")
            }
            
            // Verify no control characters in any output
            if let corrected = result.corrected {
                let hasControl = corrected.unicodeScalars.contains { scalar in 
                    let v = scalar.value
                    return (v <= 0x1F || v == 0x7F) && scalar != "\n" && scalar != "\r" && scalar != "\t"
                }
                XCTAssertFalse(hasControl, "Control character in correction of '\(input)'")
            }
        }
    }
}
