import XCTest
@testable import RightLayout

/// Tests for punctuation mapping correctness
/// These test ACTUAL bugs found in edge case testing
final class PunctuationMappingTests: XCTestCase {
    var mapper: LayoutMapper!
    
    override func setUp() {
        mapper = LayoutMapper.shared
    }
    
    // MARK: - Known bugs from edge case testing
    
    func testApostropheMapping() throws {
        // Real scenario: user types "don't" on Russian layout
        // Keys pressed: D O N Quote T
        // Russian output: в щ т э е = "вщтэе"
        
        let input = "вщтэе"  // "don't" typed on RU layout (э is on Quote key)
        let result = mapper.convert(input, fromLayout: "russianwin", toLayout: "us")
        
        print("'don't' on RU layout: '\(input)' -> '\(result ?? "nil")'")
        
        // Should convert to "don't" 
        XCTAssertEqual(result, "don't", "Should convert to don't")
    }
    
    func testApostropheAltMapping() throws {
        // Edge case: if someone actually typed Alt+O on Russian layout (produces ')
        // This is unusual but should not crash
        
        let input = "вщт'е"  // With actual apostrophe (Alt+O on RU)
        let result = mapper.convert(input, fromLayout: "russianwin", toLayout: "us")
        
        print("With Alt+O apostrophe: '\(input)' -> '\(result ?? "nil")'")
        
        // The ' was typed via Alt+O, which maps to ø in US
        // This is technically correct but unusual
    }
    
    func testPeriodMapping() throws {
        // Bug: 'Ghbdtn.' -> 'Приветю' (period became ю)
        // This suggests . on US maps to ю on RU, which is CORRECT for layout conversion
        // But when converting RU->EN, we need the reverse
        
        let period = "."
        let enToRu = mapper.convert(period, fromLayout: "us", toLayout: "russianwin")
        let ruToEn = mapper.convert("ю", fromLayout: "russianwin", toLayout: "us")
        
        print("Period EN->RU: '.' -> '\(enToRu ?? "nil")'")
        print("ю RU->EN: 'ю' -> '\(ruToEn ?? "nil")'")
        
        // This is actually CORRECT behavior for layout mapping!
        // The key that produces '.' in US produces 'ю' in Russian
    }
    
    func testQuestionMarkMapping() throws {
        // Bug: '?' -> ',' 
        let question = "?"
        let enToRu = mapper.convert(question, fromLayout: "us", toLayout: "russianwin")
        
        print("Question EN->RU: '?' -> '\(enToRu ?? "nil")'")
        
        // In Russian layout, Shift+7 = ?
        // In US layout, Shift+/ = ?
        // These are different keys!
    }
    
    func testRussianQuotesMapping() throws {
        // Bug: '«»' -> '\|'
        let leftQuote = "«"
        let rightQuote = "»"
        
        // These are special Russian characters, might not have direct mapping
        let leftToEn = mapper.convert(leftQuote, fromLayout: "russianwin", toLayout: "us")
        let rightToEn = mapper.convert(rightQuote, fromLayout: "russianwin", toLayout: "us")
        
        print("« RU->EN: '\(leftToEn ?? "nil")'")
        print("» RU->EN: '\(rightToEn ?? "nil")'")
    }
    
    // MARK: - Punctuation round-trip tests
    
    func testCommonPunctuationRoundTrip() throws {
        // These punctuation marks should ideally round-trip
        // But due to layout differences, they might not
        
        let punctuation = [".", ",", "!", "?", ":", ";", "-", "(", ")", "[", "]"]
        
        print("\n=== Punctuation Round-Trip Test ===")
        for p in punctuation {
            let enToRu = mapper.convert(p, fromLayout: "us", toLayout: "russianwin")
            let backToEn = enToRu.flatMap { mapper.convert($0, fromLayout: "russianwin", toLayout: "us") }
            
            let roundTrips = (backToEn == p)
            print("\(p) -> \(enToRu ?? "nil") -> \(backToEn ?? "nil") \(roundTrips ? "✓" : "✗")")
        }
    }
    
    // MARK: - Real-world sentence tests
    
    func testSentencePreservesPunctuation() throws {
        // When user types Russian sentence on EN layout, punctuation should make sense
        
        // "Привет, мир!" typed on EN layout
        let input = "Ghbdtn, vbh!"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        
        print("Sentence: '\(input)' -> '\(result ?? "nil")'")
        
        // The comma and exclamation should be in reasonable positions
        // Even if they map to different characters
        XCTAssertNotNil(result)
        
        // Check no garbage control characters
        if let r = result {
            for scalar in r.unicodeScalars {
                XCTAssertFalse(scalar.value < 0x20 && scalar != "\n" && scalar != "\t",
                              "Control char found: U+\(String(format: "%04X", scalar.value))")
            }
        }
    }
    
    // MARK: - The REAL issue: punctuation in wrong-layout detection
    
    func testWrongLayoutWithPunctuation() throws {
        // The REAL scenario: user types "привет, мир" but on EN layout
        // They get "ghbdtn, vbh" - note the comma is ALREADY correct!
        // Because comma is in same position on both layouts
        
        // So when we convert back, comma should stay comma
        let input = "ghbdtn, vbh"  // Comma typed on EN layout
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        
        print("With EN comma: '\(input)' -> '\(result ?? "nil")'")
        
        // The comma key on US produces 'б' on Russian layout
        // So "ghbdtn, vbh" -> "приветб мир" - the comma becomes б!
        // This is CORRECT layout mapping behavior
    }
    
    func testPunctuationOnSameKey() throws {
        // Some punctuation is on the same key in both layouts
        // These should round-trip correctly
        
        // Space is always space
        XCTAssertEqual(mapper.convert(" ", fromLayout: "us", toLayout: "russianwin"), " ")
        
        // Numbers are same
        for n in "0123456789" {
            let result = mapper.convert(String(n), fromLayout: "us", toLayout: "russianwin")
            XCTAssertEqual(result, String(n), "Number \(n) should stay same")
        }
    }
    
    // MARK: - What punctuation SHOULD we preserve?
    
    func testIdentifyPreservablePunctuation() throws {
        // Find which punctuation maps to itself
        let allPunct = "!@#$%^&*()_+-=[]{}|;':\",./<>?`~"
        
        print("\n=== Punctuation that maps to itself ===")
        var preservable: [Character] = []
        var changes: [(from: Character, to: String)] = []
        
        for p in allPunct {
            let result = mapper.convert(String(p), fromLayout: "us", toLayout: "russianwin")
            if result == String(p) {
                preservable.append(p)
            } else if let r = result {
                changes.append((p, r))
            }
        }
        
        print("Preservable: \(preservable)")
        print("Changes:")
        for (from, to) in changes {
            print("  '\(from)' -> '\(to)'")
        }
    }
    // MARK: - Ticket 46: Backtick (ё) mapping
    
    func testYoBacktickMapping() throws {
        // User reports: "to`" typed on EN layout should be "ещё" on RU layout
        // Currently it might be "ещ`" because ` is preserved
        
        // "to`" -> "ещё"
        // t -> е
        // o -> щ
        // ` -> ё
        let input = "to`" 
        let result = mapper.convertBest(input, from: .english, to: .russian)
        
        print("Ticket 46 'to`': '\(input)' -> '\(result ?? "nil")'")
        XCTAssertEqual(result, "ещё", "Backtick should map to ё when appropriate")
    }
    
    func testTildeMapping() throws {
        // Shift+` is ~ on US layout
        // Shift+ё is Ё on RU layout
        // So "~" should map to "Ё"
        
        let input = "TO~" // T -> Е, O -> Щ, ~ -> Ё
        let result = mapper.convertBest(input, from: .english, to: .russian)
        
        print("Ticket 46 'TO~': '\(input)' -> '\(result ?? "nil")'")
        XCTAssertEqual(result, "ЕЩЁ", "Tilde should map to Ё when appropriate")
    }
    
    func testInvariantPunctuation() throws {
        // Verify that purely invariant punctuation is still preserved
        
        // "(" shifts to "(" or something similar?
        // On US: Shift+9 = (
        // On RU: Shift+9 = (
        // So ( -> (
        
        let input = "Test (123)"
        let result = mapper.convertBest(input, from: .english, to: .russian)
        // T->Е, e->у, s->ы, t->е, (->(, 1->1, 2->2, 3->3, )->)
        // "Еуые (123)"
        
        XCTAssertEqual(result, "Еуые (123)")
    }

    // MARK: - Ticket 58: Hyphen and Colon bugs
    
    func testHyphenMapping() throws {
        // Bug 1: Hyphen mismatch. "-" converts to "|" or backslash.
        // User reports: "-" -> "|"
        
        // Test US -> RU
        // US Minus (Key 27) produces "-".
        // RU Minus (Key 27) produces "-".
        // They should map 1:1.
        
        let hyphen = "-"
        let enToRu = mapper.convert(hyphen, fromLayout: "us", toLayout: "russianwin")
        print("Hyphen EN->RU: '-' -> '\(enToRu ?? "nil")'")
        XCTAssertEqual(enToRu, "-", "Hyphen should map to hyphen")
        
        // Test RU -> EN
        let ruToEn = mapper.convert(hyphen, fromLayout: "russianwin", toLayout: "us")
        print("Hyphen RU->EN: '-' -> '\(ruToEn ?? "nil")'")
        XCTAssertEqual(ruToEn, "-", "Hyphen should map to hyphen")
    }
    
    func testColonInRussianMapping() throws {
        // Bug 2: Colon mismatch.
        // In Russian PC layout, ':' is Shift+6.
        // In US layout, Shift+6 is '^'.
        // User reports: ":" converts to "K" or "M".
        
        let colon = ":"
        
        let ruToEn = mapper.convert(colon, fromLayout: "russianwin", toLayout: "us")
        print("Colon RU->EN: ':' -> '\(ruToEn ?? "nil")'")
        
        // Ensure it is NOT 'K' or 'M'.
        XCTAssertNotEqual(ruToEn, "K")
        XCTAssertNotEqual(ruToEn, "M")
    }
    
    func testColonInRussianMacMapping() throws {
        // Bug 2: Colon mismatch (Mac Standard Russian).
        let colon = ":"
        
        // Test with "russian" layout (Mac standard)
        let ruToEn = mapper.convert(colon, fromLayout: "russian", toLayout: "us")
        print("Colon RU(Mac)->EN: ':' -> '\(ruToEn ?? "nil")'")
        
        // Ensure it is NOT 'K' or 'M'.
        XCTAssertNotEqual(ruToEn, "K")
        XCTAssertNotEqual(ruToEn, "M")
    }
    
    // MARK: - Ticket 59: Comma Preservation Bug
    
    func testCommaToRussianMapping() throws {
        // User reports: "xnj," -> "что,"
        // Expected: "xnj," -> "чтоб"
        // Cause: standard English comma (key 43) maps to standard Russian comma (Shift+6)?? 
        // NO. Key 43 in US is ",". Key 43 in Russian is "б".
        // The SYSTEM presumably sees "," and keeps it, instead of mapping Key 43 -> б.
        
        let input = "xnj,"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        
        print("Ticket 59 'xnj,': '\(input)' -> '\(result ?? "nil")'")
        
        XCTAssertEqual(result, "чтоб", "Should map comma key to 'б' in Russian")
    }
    
    func testYCharMapping() throws {
        // Ticket 59: 'y' -> 'y'?
        // US 'y' (key 16) -> RU 'н' (key 16).
        let input = "y"
        let result = mapper.convert(input, fromLayout: "us", toLayout: "russianwin")
        print("Ticket 59 'y': '\(input)' -> '\(result ?? "nil")'")
        XCTAssertEqual(result, "н", "y should map to н")
    }

    func testHyphenRussianMacMapping() throws {
        let hyphen = "-"
        let ruToEn = mapper.convert(hyphen, fromLayout: "russian", toLayout: "us")
        print("Hyphen RU(Mac)->EN: '-' -> '\(ruToEn ?? "nil")'")
        XCTAssertEqual(ruToEn, "-")
    }
}
