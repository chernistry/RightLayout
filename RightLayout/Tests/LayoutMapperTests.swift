import XCTest
@testable import RightLayout

final class LayoutMapperTests: XCTestCase {
    
    func testRussianToEnglish() {
        let result = LayoutMapper.shared.convert("ghbdtn", from: .english, to: .russian)
        XCTAssertEqual(result, "привет")
    }
    
    func testEnglishToRussian() {
        let result = LayoutMapper.shared.convert("привет", from: .russian, to: .english)
        XCTAssertEqual(result, "ghbdtn")
    }
    
    func testHebrewToEnglish() {
        let result = LayoutMapper.shared.convert("שלום", from: .hebrew, to: .english)
        XCTAssertNotNil(result)
    }
    
    func testEnglishToHebrew() {
        let input = "adk"
        let result = LayoutMapper.shared.convert(input, from: .english, to: .hebrew)
        XCTAssertNotNil(result)
    }

    func testEnglishToHebrewQwertySofits() {
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
        let result = LayoutMapper.shared.convert("wloM", from: .english, to: .hebrew, activeLayouts: activeLayouts)
        XCTAssertEqual(result, "שלום")
    }

    func testEnglishToHebrewQwertyShortMH() {
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
        let result = LayoutMapper.shared.convert("mh", from: .english, to: .hebrew, activeLayouts: activeLayouts)
        XCTAssertEqual(result, "מה")
    }
    
    func testSameLanguage() {
        let result = LayoutMapper.shared.convert("hello", from: .english, to: .english)
        XCTAssertEqual(result, "hello")
    }
    
    func testMixedCase() {
        let result = LayoutMapper.shared.convert("Ghbdtn", from: .english, to: .russian)
        XCTAssertEqual(result, "Привет")
    }

    func testPunctuationRoundTripRussianEnglish() {
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
        let original = "(what) ok, no!"
        guard let typedOnRu = LayoutMapper.shared.convert(original, from: .english, to: .russian, activeLayouts: activeLayouts),
              let backToEn = LayoutMapper.shared.convert(typedOnRu, from: .russian, to: .english, activeLayouts: activeLayouts) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(backToEn, original)
    }

    func testPunctuationRussianToEnglishMappings() {
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
        XCTAssertEqual(LayoutMapper.shared.convert("б", from: .russian, to: .english, activeLayouts: activeLayouts), ",")
        XCTAssertEqual(LayoutMapper.shared.convert("ю", from: .russian, to: .english, activeLayouts: activeLayouts), ".")
        XCTAssertEqual(LayoutMapper.shared.convert(")", from: .russian, to: .english, activeLayouts: activeLayouts), ")")
        XCTAssertEqual(LayoutMapper.shared.convert("(", from: .russian, to: .english, activeLayouts: activeLayouts), "(")
        XCTAssertEqual(LayoutMapper.shared.convert("сщщдбдуае", from: .russian, to: .english, activeLayouts: activeLayouts), "cool,left")
        XCTAssertEqual(LayoutMapper.shared.convertBest("сщщдбдуае", from: .russian, to: .english, activeLayouts: activeLayouts), "cool,left")
    }
    
    func testRussianToHebrew() {
        // RU→HE via composition (RU→EN→HE)
        let result = LayoutMapper.shared.convert("привет", from: .russian, to: .hebrew)
        XCTAssertNotNil(result)
        // Verify it's different from original
        XCTAssertNotEqual(result, "привет")
    }
    
    func testHebrewToRussian() {
        // HE→RU via composition (HE→EN→RU)
        let result = LayoutMapper.shared.convert("שלום", from: .hebrew, to: .russian)
        XCTAssertNotNil(result)
        // Verify it's different from original
        XCTAssertNotEqual(result, "שלום")
    }
    
    func testRussianHebrewRoundTrip() {
        // Test reversibility: RU→HE→RU should preserve structure
        let original = "привет"
        guard let toHebrew = LayoutMapper.shared.convert(original, from: .russian, to: .hebrew),
              let backToRussian = LayoutMapper.shared.convert(toHebrew, from: .hebrew, to: .russian) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(backToRussian, original)
    }
    
    func testHebrewRussianRoundTrip() {
        // Test reversibility: HE→RU→HE should preserve structure
        let original = "שלום"
        guard let toRussian = LayoutMapper.shared.convert(original, from: .hebrew, to: .russian),
              let backToHebrew = LayoutMapper.shared.convert(toRussian, from: .russian, to: .hebrew) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(backToHebrew, original)
    }
    
    func testAllLanguagePairs() {
        // Verify all 6 conversion pairs work
        let testText = "test"
        
        // RU↔EN (direct)
        XCTAssertNotNil(LayoutMapper.shared.convert(testText, from: .russian, to: .english))
        XCTAssertNotNil(LayoutMapper.shared.convert(testText, from: .english, to: .russian))
        
        // HE↔EN (direct)
        XCTAssertNotNil(LayoutMapper.shared.convert(testText, from: .hebrew, to: .english))
        XCTAssertNotNil(LayoutMapper.shared.convert(testText, from: .english, to: .hebrew))
        
        // RU↔HE (composition)
        XCTAssertNotNil(LayoutMapper.shared.convert(testText, from: .russian, to: .hebrew))
        XCTAssertNotNil(LayoutMapper.shared.convert(testText, from: .hebrew, to: .russian))
    }
}
