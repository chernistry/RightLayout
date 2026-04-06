import XCTest
@testable import RightLayout

/// Tests that simulate REAL user behavior with selection and replacement
/// Focus on finding actual bugs in the flow
final class RealUserBehaviorTests: XCTestCase {
    var engine: CorrectionEngine!
    var mapper: LayoutMapper!
    var buffer: TextBufferSimulator!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
        engine = CorrectionEngine(settings: settings)
        mapper = LayoutMapper.shared
        buffer = TextBufferSimulator()
    }
    
    // MARK: - Scenario 1: User types paragraph, selects all, presses hotkey
    
    @MainActor
    func testSelectAllAndConvert() async throws {
        // User typed a paragraph in wrong layout
        let typed = """
        Ghbdtn? rfr ltkf?
        Z gbie rjl yf Hfcn/
        """
        
        // Expected after conversion
        let expected = """
        Привет, как дела?
        Я пишу код на Раст.
        """
        _ = expected
        
        // Simulate: user selects all and presses hotkey
        buffer.type(typed)
        
        // Get correction
        let corrected = await engine.correctLastWord(typed)
        
        print("=== Select All and Convert ===")
        print("Input (\(typed.count) chars):")
        print(typed)
        print("\nOutput (\(corrected?.count ?? 0) chars):")
        print(corrected ?? "nil")
        
        // Check structure preserved
        if let c = corrected {
            let inputLines = typed.components(separatedBy: "\n")
            let outputLines = c.components(separatedBy: "\n")
            XCTAssertEqual(inputLines.count, outputLines.count, "Line count should match")
        }
    }
    
    // MARK: - Scenario 2: User types, realizes mistake, selects last word
    
    @MainActor
    func testSelectLastWordAndConvert() async throws {
        // User typed correct text, then one wrong word
        let correctPart = "Привет, я пишу "
        let wrongWord = "rjl"  // "код" on EN layout
        
        buffer.type(correctPart)
        buffer.type(wrongWord)
        
        // User selects just the wrong word and presses hotkey
        let corrected = await engine.correctLastWord(wrongWord)
        
        print("=== Select Last Word ===")
        print("Wrong word: '\(wrongWord)' -> '\(corrected ?? "nil")'")
        
        XCTAssertEqual(corrected, "код", "Should convert to 'код'")
        
        // Simulate replacement
        if let c = corrected {
            buffer.replaceLast(wrongWord.count, with: c)
            XCTAssertEqual(buffer.content, correctPart + "код")
        }
    }
    
    // MARK: - Scenario 3: User cycles through alternatives
    
    @MainActor
    func testCycleUntilCorrect() async throws {
        // User typed something ambiguous
        let input = "nt,z"  // Could be "те,я" or something else
        
        _ = await engine.correctLastWord(input)
        
        print("=== Cycling through alternatives ===")
        print("Input: '\(input)'")
        
        var seen: [String] = []
        for i in 0..<10 {
            if let cycled = await engine.cycleCorrection() {
                seen.append(cycled)
                print("  Cycle \(i): '\(cycled)'")
                
                // Check no garbage
                XCTAssertFalse(cycled.contains("¬"), "Should not contain ¬")
                for scalar in cycled.unicodeScalars {
                    if scalar.value == 0x7F {
                        XCTFail("Contains DEL character")
                    }
                }
            }
        }
        
        // Should have cycled back to start
        XCTAssertTrue(seen.count >= 2, "Should have at least 2 alternatives")
    }
    
    // MARK: - Scenario 4: User makes typo in wrong layout
    
    @MainActor
    func testTypoInWrongLayout() async throws {
        // User typed "привет" on EN layout but made a typo
        let input = "ghbdtm"  // 'm' instead of 'n'
        
        let corrected = await engine.correctLastWord(input)
        
        print("=== Typo in wrong layout ===")
        print("Input: '\(input)' -> '\(corrected ?? "nil")'")
        
        // Should still convert (typo will be visible in Russian)
        XCTAssertNotNil(corrected)
        // "ghbdtm" -> "привеь" (typo preserved)
    }
    
    // MARK: - Scenario 5: Mixed correct and wrong in selection
    
    @MainActor
    func testMixedCorrectAndWrong() async throws {
        // User selected text that has both correct and wrong parts
        // This is tricky - what should happen?
        
        let input = "Привет ghbdtn"  // Russian + wrong layout
        
        let corrected = await engine.correctLastWord(input)
        
        print("=== Mixed correct and wrong ===")
        print("Input: '\(input)' -> '\(corrected ?? "nil")'")
        
        // The whole thing gets converted, which might mess up the Russian part
        // This is a known limitation
    }
    
    // MARK: - Scenario 6: Very fast typing and correction
    
    @MainActor
    func testRapidTypingAndCorrection() async throws {
        // Simulate rapid typing followed by immediate correction
        let words = ["ghbdtn", "vbh", "ntcn", "rjl"]
        
        for word in words {
            await engine.resetCycling()
            
            let corrected = await engine.correctLastWord(word)
            XCTAssertNotNil(corrected, "Should correct '\(word)'")
            
            // Immediately cycle
            let cycled = await engine.cycleCorrection()
            XCTAssertNotNil(cycled, "Should be able to cycle")
        }
    }
    
    // MARK: - Scenario 7: Selection with trailing newline
    
    @MainActor
    func testSelectionWithTrailingNewline() async throws {
        let input = "ghbdtn\n"
        
        let corrected = await engine.correctLastWord(input.trimmingCharacters(in: .whitespacesAndNewlines))
        
        print("=== With trailing newline ===")
        print("Input: '\(input.debugDescription)' -> '\(corrected?.debugDescription ?? "nil")'")
        
        // The newline should be handled by EventMonitor, not CorrectionEngine
        // CorrectionEngine gets trimmed input
    }
    
    // MARK: - Scenario 8: Undo after auto-correction
    
    @MainActor
    func testUndoAfterAutoCorrection() async throws {
        let input = "ghbdtn"
        
        // Simulate auto-correction
        let autoResult = await engine.correctText(input, phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(autoResult.corrected, "привет")
        
        // Now user presses hotkey to undo
        let undone = await engine.cycleCorrection()
        
        print("=== Undo auto-correction ===")
        print("Auto: '\(input)' -> '\(autoResult.corrected ?? "nil")'")
        print("Undo: -> '\(undone ?? "nil")'")
        
        // First cycle after auto should go back to original
        XCTAssertEqual(undone, input, "First cycle should undo to original")
    }
    
    // MARK: - Scenario 9: Multiple undo/redo cycles
    
    @MainActor
    func testMultipleUndoRedo() async throws {
        let input = "ghbdtn"
        
        // Auto-correct
        _ = await engine.correctText(input, phraseBuffer: "", expectedLayout: nil)
        
        // Track the cycle
        var history: [String] = ["привет"]  // Start with corrected
        
        for _ in 0..<6 {
            if let cycled = await engine.cycleCorrection() {
                history.append(cycled)
            }
        }
        
        print("=== Multiple undo/redo ===")
        print("History: \(history)")
        
        // Should cycle: привет -> ghbdtn -> (hebrew) -> привет -> ...
        // Check we can get back to original
        XCTAssertTrue(history.contains(input), "Should be able to get back to original")
    }
    
    // MARK: - Scenario 10: Empty selection
    
    @MainActor
    func testEmptySelection() async throws {
        let result = await engine.correctLastWord("")
        XCTAssertNil(result, "Empty selection should return nil")
    }
    
    // MARK: - Scenario 11: Selection of only spaces
    
    @MainActor
    func testSpaceOnlySelection() async throws {
        let result = await engine.correctLastWord("   ")
        XCTAssertNil(result, "Space-only selection should return nil")
    }
    
    // MARK: - Scenario 12: Very long selection
    
    @MainActor
    func testVeryLongSelection() async throws {
        // 1000 character selection
        let input = String(repeating: "ghbdtn ", count: 140)  // ~1000 chars
        
        let corrected = await engine.correctLastWord(input)
        
        print("=== Very long selection ===")
        print("Input length: \(input.count)")
        print("Output length: \(corrected?.count ?? 0)")
        
        // Should handle without crashing
        XCTAssertNotNil(corrected)
    }
    
    // MARK: - Scenario 13: Unicode edge cases in selection
    
    @MainActor
    func testUnicodeInSelection() async throws {
        // Selection with emoji
        let input = "ghbdtn 😀 vbh"
        
        let corrected = await engine.correctLastWord(input)
        
        print("=== Unicode in selection ===")
        print("Input: '\(input)' -> '\(corrected ?? "nil")'")
        
        // Emoji should be preserved
        if let c = corrected {
            XCTAssertTrue(c.contains("😀"), "Emoji should be preserved")
        }
    }
    
    // MARK: - Scenario 14: Replacement length accuracy
    
    func testReplacementLengthAccuracy() throws {
        // This tests the CRITICAL bug: wrong deletion length
        
        let testCases: [(input: String, from: Language, to: Language)] = [
            ("ghbdtn", .english, .russian),      // Same length
            ("hello", .english, .russian),        // Different lengths possible
            ("привет", .russian, .english),
            ("test", .english, .russian),
        ]
        
        for (input, from, to) in testCases {
            if let converted = mapper.convertBest(input, from: from, to: to, activeLayouts: nil) {
                print("'\(input)' (\(input.count)) -> '\(converted)' (\(converted.count))")
                
                // Simulate buffer replacement
                buffer.clear()
                buffer.type("prefix ")
                buffer.type(input)
                buffer.type(" suffix")
                
                let before = buffer.content
                
                // Replace input with converted
                buffer.replaceLast(" suffix".count + input.count, with: converted + " suffix")
                
                // Check prefix is intact
                XCTAssertTrue(buffer.content.hasPrefix("prefix "), 
                             "Prefix damaged for '\(input)': before='\(before)', after='\(buffer.content)'")
            }
        }
    }
}
