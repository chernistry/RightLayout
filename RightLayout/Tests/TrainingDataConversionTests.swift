import XCTest
@testable import RightLayout

/// Tests conversion quality on training data samples
/// Ensures no control characters or garbage in output
final class TrainingDataConversionTests: XCTestCase {
    
    // Sample from training_data_combined.csv - wrong layout cases
    static let wrongLayoutSamples: [(text: String, label: String)] = [
        // ru_from_en: Russian typed on English layout
        (",jzhbyjv «Gjxёnysq Ctdthyjv", "ru_from_en"),
        ("hfcgeoty Gfgs Pyfz |url-status=live", "ru_from_en"),
        ("Ghbdtn", "ru_from_en"),  // привет
        ("Vfvf", "ru_from_en"),    // мама
        
        // en_from_ru: English typed on Russian layout  
        ("бетшеен сшитцхинг жжХалл тиме трансфер", "en_from_ru"),
        ("Ифзешые кщду", "en_from_ru"),
        ("пройецтиле", "en_from_ru"),
        ("руддщ", "en_from_ru"),   // hello
        ("цщкв", "en_from_ru"),    // word
        
        // he_from_en: Hebrew typed on English layout
        ("BXLQV mYRIM HFSIkVLVGI IDI", "he_from_en"),
        ("LnXITVT FEVLVT HAHBH", "he_from_en"),
        
        // ru_from_he: Russian typed on Hebrew layout
        ("|דארשמןבט פםלרטא", "ru_from_he"),
    ]
    
    // Common English words that should NOT produce garbage when cycling
    static let commonEnglishWords = [
        "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
        "her", "was", "one", "our", "out", "day", "get", "has", "him", "his",
        "how", "its", "may", "new", "now", "old", "see", "two", "way", "who",
        "boy", "did", "own", "say", "she", "too", "use", "probably", "hello",
        "world", "computer", "keyboard", "language", "system", "application"
    ]
    
    // Common Russian words
    static let commonRussianWords = [
        "привет", "мир", "компьютер", "клавиатура", "язык", "система",
        "программа", "работа", "время", "человек", "день", "год"
    ]
    
    func testNoControlCharactersInConversions() throws {
        let mapper = LayoutMapper.shared
        
        for (text, label) in Self.wrongLayoutSamples {
            // Determine conversion direction
            let (from, to) = conversionDirection(for: label)
            
            // Get all variants
            let variants = mapper.convertAllVariants(text, from: from, to: to)
            
            for (layout, result) in variants {
                // Check for control characters
                for scalar in result.unicodeScalars {
                    if scalar.value < 0x20 || scalar.value == 0x7F {
                        XCTFail("Control char U+\(String(format: "%04X", scalar.value)) in conversion of '\(text)' (\(label)) via \(layout)")
                    }
                }
                
                // Check for ¬ character (common bug)
                if result.contains("¬") {
                    XCTFail("'¬' character in conversion of '\(text)' (\(label)) via \(layout): '\(result)'")
                }
            }
        }
    }
    
    @MainActor
    func testCyclingNoGarbage() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        let engine = CorrectionEngine(settings: settings)
        
        // Test English words - cycling should never produce garbage
        for word in Self.commonEnglishWords {
            await engine.resetCycling()
            
            _ = await engine.correctLastWord(word)
            
            // Cycle through all alternatives
            for _ in 0..<6 {
                if let cycled = await engine.cycleCorrection() {
                    // Check for control characters
                    for scalar in cycled.unicodeScalars {
                        if scalar.value < 0x20 || scalar.value == 0x7F {
                            XCTFail("Control char in cycling '\(word)': U+\(String(format: "%04X", scalar.value)) in '\(cycled)'")
                        }
                    }
                    // Check for ¬
                    if cycled.contains("¬") {
                        XCTFail("'¬' in cycling '\(word)': '\(cycled)'")
                    }
                }
            }
        }
    }
    
    @MainActor 
    func testRussianWordsCycling() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        let engine = CorrectionEngine(settings: settings)
        
        for word in Self.commonRussianWords {
            await engine.resetCycling()
            
            _ = await engine.correctLastWord(word)
            
            for _ in 0..<6 {
                if let cycled = await engine.cycleCorrection() {
                    for scalar in cycled.unicodeScalars {
                        if scalar.value < 0x20 || scalar.value == 0x7F {
                            XCTFail("Control char in cycling '\(word)': U+\(String(format: "%04X", scalar.value))")
                        }
                    }
                    if cycled.contains("¬") {
                        XCTFail("'¬' in cycling '\(word)': '\(cycled)'")
                    }
                }
            }
        }
    }
    
    func testWrongLayoutConversionQuality() throws {
        let mapper = LayoutMapper.shared
        
        // Test specific known conversions
        let knownConversions: [(input: String, from: Language, to: Language, expected: String)] = [
            ("ghbdtn", .english, .russian, "привет"),
            ("руддщ", .russian, .english, "hello"),
            ("ntcn", .english, .russian, "тест"),
            ("Vfvf", .english, .russian, "Мама"),
        ]
        
        for (input, from, to, expected) in knownConversions {
            if let result = mapper.convertBest(input, from: from, to: to, activeLayouts: nil) {
                XCTAssertEqual(result, expected, "'\(input)' should convert to '\(expected)', got '\(result)'")
            } else {
                XCTFail("Failed to convert '\(input)' from \(from) to \(to)")
            }
        }
    }
    
    private func conversionDirection(for label: String) -> (from: Language, to: Language) {
        switch label {
        case "ru_from_en": return (.english, .russian)
        case "en_from_ru": return (.russian, .english)
        case "he_from_en": return (.english, .hebrew)
        case "he_from_ru": return (.russian, .hebrew)
        case "ru_from_he": return (.hebrew, .russian)
        case "en_from_he": return (.hebrew, .english)
        default: return (.english, .russian)
        }
    }
}
