import XCTest
@testable import RightLayout

/// Comprehensive edge case tests - things we might have missed
/// Written from QA perspective to find bugs
final class EdgeCaseTests: XCTestCase {
    var engine: CorrectionEngine!
    var mapper: LayoutMapper!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        engine = CorrectionEngine(settings: settings)
        mapper = LayoutMapper.shared
    }
    
    // MARK: - 1. Words with numbers
    
    func testWordWithTrailingNumbers() throws {
        // "ghbdtn2024" -> "привет2024"
        let input = "ghbdtn2024"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasSuffix("2024") ?? false, "Numbers should be preserved: \(result ?? "nil")")
    }
    
    func testWordWithLeadingNumbers() throws {
        let input = "2024ujl"  // 2024год
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("2024") ?? false, "Leading numbers should be preserved: \(result ?? "nil")")
    }
    
    func testPureNumbers() throws {
        let input = "12345"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertEqual(result, "12345", "Pure numbers should stay unchanged")
    }
    
    // MARK: - 2. Words with punctuation
    
    func testWordWithHyphen() throws {
        // "rfrjq-nj" -> "какой-то"
        let input = "rfrjq-nj"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertNotNil(result)
        // Hyphen might map to different char, but structure should be preserved
        print("Hyphenated word: '\(input)' -> '\(result ?? "nil")'")
    }
    
    func testWordWithApostrophe() throws {
        // English "don't" typed on RU layout
        let input = "вщт'е"  // don't
        let result = mapper.convert(input, fromLayout: "russianwin", toLayout: "us")
        print("Apostrophe word: '\(input)' -> '\(result ?? "nil")'")
        // Check no garbage
        if let r = result {
            XCTAssertFalse(r.contains("¬"), "Should not contain ¬")
        }
    }
    
    func testWordWithTrailingPunctuation() throws {
        let input = "ghbdtn!"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertNotNil(result)
        print("Trailing punct: '\(input)' -> '\(result ?? "nil")'")
    }
    
    func testWordInQuotes() throws {
        let input = "\"ghbdtn\""
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertNotNil(result)
        print("Quoted word: '\(input)' -> '\(result ?? "nil")'")
    }
    
    func testRussianQuotes() throws {
        // «привет» - Russian quotes
        let input = "«ghbdtn»"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Russian quotes: '\(input)' -> '\(result ?? "nil")'")
    }
    
    // MARK: - 3. Ambiguous words (look same in multiple layouts)
    
    func testAmbiguousSingleLetterA() throws {
        // 'a' exists in both EN and RU
        let input = "a"
        
        // Should not crash or produce garbage
        let toRu = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        let toEn = mapper.convert(input, fromLayout: "russianwin", toLayout: "us")
        
        print("'a' -> RU: '\(toRu ?? "nil")', 'a' -> EN: '\(toEn ?? "nil")'")
        XCTAssertNotNil(toRu)
        XCTAssertNotNil(toEn)
    }
    
    func testAmbiguousWordCoca() throws {
        // "coca" could be English word or "сосф" typed on EN layout
        let input = "coca"
        
        let toRu = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("'coca' EN->RU: '\(toRu ?? "nil")'")
    }
    
    func testCyrillicLookalikeC() throws {
        // Cyrillic 'с' (U+0441) vs Latin 'c' (U+0063)
        let cyrillicC = "с"  // U+0441
        let latinC = "c"     // U+0063
        
        XCTAssertNotEqual(cyrillicC, latinC, "Should be different characters")
        
        // Both should convert without crashing
        let _ = mapper.convert(cyrillicC, fromLayout: "russianwin", toLayout: "us")
        let _ = mapper.convert(latinC, fromLayout: "us", toLayout: "russianwin")
    }
    
    // MARK: - 4. Very short and very long words
    
    func testSingleCharacter() throws {
        for char in "qwerty" {
            let result = mapper.convert(String(char), fromLayout: "us", toLayout: "russianwin")
            XCTAssertNotNil(result, "Single char '\(char)' should convert")
            XCTAssertEqual(result?.count, 1, "Single char should produce single char")
        }
    }
    
    func testVeryLongWord() throws {
        // 50 character word
        let input = String(repeating: "ghbdtn", count: 10)  // 60 chars
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, input.count, "Length should be preserved")
    }
    
    // MARK: - 5. Case handling
    
    func testAllCaps() throws {
        let input = "GHBDTN"  // ПРИВЕТ
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertEqual(result, "ПРИВЕТ", "All caps should be preserved")
    }
    
    func testMixedCase() throws {
        let input = "GhBdTn"  // ПрИвЕт
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertEqual(result, "ПрИвЕт", "Mixed case should be preserved")
    }
    
    func testFirstLetterCap() throws {
        let input = "Ghbdtn"  // Привет
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertEqual(result, "Привет", "First letter cap should be preserved")
    }
    
    // MARK: - 6. Cycling edge cases
    
    @MainActor
    func testCyclingWithNoAlternatives() async throws {
        // Pure Russian word - no conversion possible
        let input = "привет"
        
        let corrected = await engine.correctLastWord(input)
        // Should still work (return alternatives or nil)
        print("Pure Russian cycling: \(corrected ?? "nil")")
    }
    
    @MainActor
    func testCyclingAfterTimeout() async throws {
        let input = "ghbdtn"
        
        _ = await engine.correctLastWord(input)
        
        // Simulate timeout by resetting
        await engine.resetCycling()
        
        // Should not crash
        let cycled = await engine.cycleCorrection()
        XCTAssertNil(cycled, "Should return nil after reset")
    }
    
    @MainActor
    func testCyclingWithDifferentLengthAlternatives() async throws {
        // Find a word where alternatives have different lengths
        let input = "ghbdtn"  // 6 chars
        
        _ = await engine.correctLastWord(input)
        
        var lengths: Set<Int> = []
        for _ in 0..<10 {
            if let cycled = await engine.cycleCorrection() {
                lengths.insert(cycled.count)
                print("Cycled: '\(cycled)' (len: \(cycled.count))")
            }
        }
        
        print("Different lengths seen: \(lengths)")
    }
    
    // MARK: - 7. Special characters and symbols
    
    func testEmailAddress() throws {
        let input = "user@example.com"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Email: '\(input)' -> '\(result ?? "nil")'")
        // Should not crash, @ might map to something
    }
    
    func testURLPath() throws {
        let input = "/path/to/file"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Path: '\(input)' -> '\(result ?? "nil")'")
    }
    
    func testHashtag() throws {
        let input = "#ghbdtn"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Hashtag: '\(input)' -> '\(result ?? "nil")'")
    }
    
    // MARK: - 8. Partial layout switch (mixed scripts in one word)
    
    func testMixedScriptWord() throws {
        // User started typing in EN, switched to RU mid-word
        let input = "priвет"  // Mixed Latin + Cyrillic
        
        let toRu = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        let toEn = mapper.convert(input, fromLayout: "russianwin", toLayout: "us")
        
        print("Mixed script: EN->RU: '\(toRu ?? "nil")', RU->EN: '\(toEn ?? "nil")'")
        
        // Should handle gracefully (convert what it can)
    }
    
    // MARK: - 9. Empty and whitespace-only inputs
    
    func testEmptyString() throws {
        let result = mapper.convert("", fromLayout: "us", toLayout: "russianwin")
        XCTAssertEqual(result, "", "Empty string should return empty")
    }
    
    func testWhitespaceOnly() throws {
        let input = "   \t\n  "
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        XCTAssertEqual(result, input, "Whitespace should be preserved as-is")
    }
    
    @MainActor
    func testCorrectionOfEmptyString() async throws {
        let result = await engine.correctLastWord("")
        XCTAssertNil(result, "Empty string should return nil")
    }
    
    @MainActor
    func testCorrectionOfWhitespaceOnly() async throws {
        let result = await engine.correctLastWord("   ")
        // Trimmed = empty, should return nil
        XCTAssertNil(result, "Whitespace-only should return nil")
    }
    
    // MARK: - 10. Unicode edge cases
    
    func testEmojiInText() throws {
        let input = "ghbdtn😀"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("With emoji: '\(input)' -> '\(result ?? "nil")'")
        // Emoji should be preserved
        XCTAssertTrue(result?.contains("😀") ?? false, "Emoji should be preserved")
    }
    
    func testAccentedCharacters() throws {
        let input = "café"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Accented: '\(input)' -> '\(result ?? "nil")'")
    }
    
    // MARK: - 11. Real typos and errors
    
    func testTypoInWrongLayoutWord() throws {
        // "ghbdtn" with one wrong character
        let input = "ghbdtm"  // 'm' instead of 'n'
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Typo: '\(input)' -> '\(result ?? "nil")'")
        // Should still convert (user will see the typo in Russian)
    }
    
    func testDoubledCharacter() throws {
        let input = "ghhbdtn"  // doubled 'h'
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Doubled char: '\(input)' -> '\(result ?? "nil")'")
    }
    
    // MARK: - 12. Buffer state edge cases
    
    @MainActor
    func testRapidCycling() async throws {
        let input = "ghbdtn"
        _ = await engine.correctLastWord(input)
        
        // Rapid cycling - should not crash or produce garbage
        var results: [String] = []
        for _ in 0..<20 {
            if let cycled = await engine.cycleCorrection() {
                results.append(cycled)
                // Check for garbage
                for scalar in cycled.unicodeScalars {
                    if scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                        XCTFail("Control char in rapid cycling: U+\(String(format: "%04X", scalar.value))")
                    }
                }
            }
        }
        
        // Should cycle through same alternatives
        let unique = Set(results)
        print("Rapid cycling unique results: \(unique.count)")
    }
    
    @MainActor 
    func testCyclingThenNewWord() async throws {
        // Start cycling one word
        _ = await engine.correctLastWord("ghbdtn")
        _ = await engine.cycleCorrection()
        
        // Now correct a different word - should reset state
        let newResult = await engine.correctLastWord("ntcn")
        XCTAssertNotNil(newResult)
        
        // Cycling should now be for new word
        if let cycled = await engine.cycleCorrection() {
            // Should be alternative for "ntcn", not "ghbdtn"
            print("After new word, cycled: '\(cycled)'")
        }
    }
    
    // MARK: - 13. Sentence/phrase handling
    
    func testSentenceWithPunctuation() throws {
        let input = "Ghbdtn, vbh!"  // "Привет, мир!"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Sentence: '\(input)' -> '\(result ?? "nil")'")
        
        // Check structure preserved
        XCTAssertTrue(result?.contains(",") ?? false || result?.contains("б") ?? false, 
                     "Comma or its mapping should be present")
    }
    
    func testMultipleSentences() throws {
        let input = "Ghbdtn. Rfr ltkf?"  // "Привет. Как дела?"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Multiple sentences: '\(input)' -> '\(result ?? "nil")'")
    }
}
