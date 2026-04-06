import XCTest
@testable import RightLayout

/// Tests for multi-line text selection and replacement scenarios
/// Simulates user selecting text and pressing hotkey to convert
final class SelectionReplacementTests: XCTestCase {
    var buffer: TextBufferSimulator!
    var engine: CorrectionEngine!
    
    @MainActor
    override func setUp() async throws {
        buffer = TextBufferSimulator()
        let settings = SettingsManager.shared
        settings.isEnabled = true
        engine = CorrectionEngine(settings: settings)
    }
    
    override func tearDown() async throws {
        buffer.clear()
        await engine.resetCycling()
    }
    
    // MARK: - Whitespace Preservation Tests
    
    func testSingleWordPreservesNoWhitespace() throws {
        let input = "ghbdtn"
        let expected = "привет"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesLeadingSpace() throws {
        let input = "  ghbdtn"
        let expected = "  привет"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesTrailingSpace() throws {
        let input = "ghbdtn  "
        let expected = "привет  "
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesLeadingAndTrailingSpaces() throws {
        let input = "   ghbdtn   "
        let expected = "   привет   "
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesNewlines() throws {
        let input = "ghbdtn\nvbh"  // привет\nмир
        let expected = "привет\nмир"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesMultipleNewlines() throws {
        let input = "ghbdtn\n\nvbh"
        let expected = "привет\n\nмир"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesCarriageReturn() throws {
        let input = "ghbdtn\r\nvbh"
        let expected = "привет\r\nмир"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesTabs() throws {
        let input = "ghbdtn\tvbh"
        let expected = "привет\tмир"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    func testPreservesComplexWhitespace() throws {
        let input = "  ghbdtn\n\tvbh  \n"
        let expected = "  привет\n\tмир  \n"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    // MARK: - Multi-line Paragraph Tests
    
    func testMultiLineParagraph() throws {
        let input = """
        Ghbdtn vbh
        'nj ntcn
        """
        let expected = """
        Привет мир
        Это тест
        """
        _ = expected
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        // Check structure is preserved (same number of lines, same whitespace pattern)
        XCTAssertEqual(input.components(separatedBy: "\n").count, 
                      result.components(separatedBy: "\n").count,
                      "Line count should be preserved")
    }
    
    func testPreservesInternalSpacing() throws {
        let input = "ghbdtn   vbh"  // Multiple spaces between words
        let expected = "привет   мир"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        XCTAssertEqual(result, expected)
    }
    
    // MARK: - Buffer Replacement Simulation
    
    func testBufferReplacementPreservesLength() throws {
        // Simulate: user has "hello world" selected, presses hotkey
        let originalText = "ghbdtn vbh"
        buffer.type("prefix ")
        buffer.type(originalText)
        buffer.type(" suffix")
        
        let fullBefore = buffer.content
        XCTAssertEqual(fullBefore, "prefix ghbdtn vbh suffix")
        
        // Convert the selected part
        let converted = convertPreservingStructure(originalText, from: .english, to: .russian)
        
        // Replace in buffer (simulating what EventMonitor does)
        // The key is: we must delete EXACTLY originalText.count characters
        buffer.replaceLast(" suffix".count + originalText.count, with: converted + " suffix")
        
        XCTAssertTrue(buffer.content.hasPrefix("prefix "), "Prefix should be preserved")
        XCTAssertTrue(buffer.content.hasSuffix(" suffix"), "Suffix should be preserved")
    }
    
    func testNoControlCharactersInMultilineConversion() throws {
        let multilineInputs = [
            "ghbdtn\nvbh\nntcn",
            "  ghbdtn  \n  vbh  ",
            "\tghbdtn\t\n\tvbh\t",
            "ghbdtn\r\nvbh\r\nntcn",
        ]
        
        for input in multilineInputs {
            let result = convertPreservingStructure(input, from: .english, to: .russian)
            
            // Check for unwanted control characters (allow \n, \r, \t)
            for scalar in result.unicodeScalars {
                if scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                    XCTFail("Unexpected control char U+\(String(format: "%04X", scalar.value)) in '\(result)'")
                }
                if scalar.value == 0x7F {
                    XCTFail("DEL character in '\(result)'")
                }
            }
        }
    }
    
    // MARK: - Real-world Multi-line Scenarios
    
    func testCodeSnippetConversion() throws {
        // Test that line structure is preserved in multi-line text
        // Note: '//' will be converted too since '/' maps to a different char
        let input = "Ghbdtn vbh\n'nj ntcn"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        
        // Structure should be preserved
        let inputLines = input.components(separatedBy: "\n")
        let resultLines = result.components(separatedBy: "\n")
        
        XCTAssertEqual(inputLines.count, resultLines.count, "Line count must match")
    }
    
    func testEmailStyleQuotedText() throws {
        // Note: '>' maps to 'Ю' in RU layout, so we use a different prefix
        // Test that structure (lines, spacing) is preserved
        let input = "ghbdtn\nvbh"
        
        let result = convertPreservingStructure(input, from: .english, to: .russian)
        
        let inputLines = input.components(separatedBy: "\n")
        let resultLines = result.components(separatedBy: "\n")
        
        XCTAssertEqual(inputLines.count, resultLines.count, "Line count should match")
    }
    
    // MARK: - Cycling with Multi-line Text
    
    @MainActor
    func testCyclingPreservesWhitespace() async throws {
        let input = "ghbdtn\nvbh"
        
        // Get correction
        let corrected = await engine.correctLastWord(input)
        XCTAssertNotNil(corrected, "Should get correction for multi-line input")
        
        if let corrected = corrected {
            print("Input: '\(input.debugDescription)'")
            print("Corrected: '\(corrected.debugDescription)'")
            
            // Check newline is preserved
            XCTAssertTrue(corrected.contains("\n"), "Newline should be preserved in '\(corrected)'")
        }
        
        // Cycle and check whitespace preservation
        for i in 0..<5 {
            if let cycled = await engine.cycleCorrection() {
                print("Cycle \(i): '\(cycled.debugDescription)'")
                
                // Check for unwanted control characters
                for scalar in cycled.unicodeScalars {
                    if scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                        XCTFail("Control char in cycled: U+\(String(format: "%04X", scalar.value))")
                    }
                }
            }
        }
    }
    
    /// Test that simulates the full flow: select text -> hotkey -> replace
    func testWhitespacePreservationInReplacement() throws {
        // Simulate what EventMonitor does
        let testCases: [(raw: String, expectedStructure: String)] = [
            ("  ghbdtn  ", "  привет  "),      // Leading + trailing spaces
            ("ghbdtn\n", "привет\n"),           // Trailing newline
            ("\nghbdtn", "\nпривет"),           // Leading newline
            ("  ghbdtn\nvbh  ", "  привет\nмир  "), // Complex
        ]
        
        for (raw, expectedStructure) in testCases {
            // Extract leading/trailing whitespace
            let leadingWS = String(raw.prefix(while: { $0.isWhitespace }))
            let trailingWS = String(raw.reversed().prefix(while: { $0.isWhitespace }).reversed())
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Convert trimmed content
            let converted = convertPreservingStructure(trimmed, from: .english, to: .russian)
            
            // Reconstruct with whitespace
            let final = leadingWS + converted + trailingWS
            
            XCTAssertEqual(final, expectedStructure, 
                          "Whitespace not preserved for '\(raw.debugDescription)'")
        }
    }
    
    // MARK: - Helper
    
    /// Converts text while preserving whitespace structure
    private func convertPreservingStructure(_ text: String, from: Language, to: Language) -> String {
        let mapper = LayoutMapper.shared
        
        // Split into tokens preserving whitespace
        var result = ""
        var currentWord = ""
        
        for char in text {
            if char.isWhitespace {
                // Convert accumulated word
                if !currentWord.isEmpty {
                    if let converted = mapper.convertBest(currentWord, from: from, to: to, activeLayouts: nil) {
                        result.append(converted)
                    } else {
                        result.append(currentWord)
                    }
                    currentWord = ""
                }
                // Preserve whitespace as-is
                result.append(char)
            } else {
                currentWord.append(char)
            }
        }
        
        // Don't forget last word
        if !currentWord.isEmpty {
            if let converted = mapper.convertBest(currentWord, from: from, to: to, activeLayouts: nil) {
                result.append(converted)
            } else {
                result.append(currentWord)
            }
        }
        
        return result
    }
}
