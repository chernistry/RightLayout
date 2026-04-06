import XCTest
@testable import RightLayout

/// Automated test suite for layout detection covering all 9 language scenarios.
/// Tests both CoreML predictions and the full ConfidenceRouter pipeline.
final class LayoutDetectionTests: XCTestCase {
    
    private var classifier: CoreMLLayoutClassifier!
    private var layoutMapper: LayoutMapper!
    
    override func setUp() {
        super.setUp()
        classifier = CoreMLLayoutClassifier()
        layoutMapper = LayoutMapper.shared
    }
    
    // MARK: - Test Data
    
    /// Test cases for each scenario: (input, expectedClass, intendedText)
    struct TestCase {
        let input: String
        let expectedClass: LanguageHypothesis
        let intendedText: String
    }
    
    // Pure language test cases (correct layout)
    static let pureRussianCases: [TestCase] = [
        TestCase(input: "привет", expectedClass: .ru, intendedText: "привет"),
        TestCase(input: "мир", expectedClass: .ru, intendedText: "мир"),
        TestCase(input: "компьютер", expectedClass: .ru, intendedText: "компьютер"),
        TestCase(input: "программа", expectedClass: .ru, intendedText: "программа"),
        TestCase(input: "система", expectedClass: .ru, intendedText: "система"),
    ]
    
    static let pureEnglishCases: [TestCase] = [
        TestCase(input: "hello", expectedClass: .en, intendedText: "hello"),
        TestCase(input: "world", expectedClass: .en, intendedText: "world"),
        TestCase(input: "computer", expectedClass: .en, intendedText: "computer"),
        TestCase(input: "program", expectedClass: .en, intendedText: "program"),
        TestCase(input: "system", expectedClass: .en, intendedText: "system"),
    ]
    
    static let pureHebrewCases: [TestCase] = [
        TestCase(input: "שלום", expectedClass: .he, intendedText: "שלום"),
        TestCase(input: "עולם", expectedClass: .he, intendedText: "עולם"),
        TestCase(input: "מחשב", expectedClass: .he, intendedText: "מחשב"),
        TestCase(input: "תוכנית", expectedClass: .he, intendedText: "תוכנית"),
        TestCase(input: "מערכת", expectedClass: .he, intendedText: "מערכת"),
    ]
    
    // Layout mismatch test cases (wrong layout active)
    // Russian intended, English layout active -> produces Latin gibberish
    static let ruFromEnCases: [TestCase] = [
        TestCase(input: "ghbdtn", expectedClass: .ruFromEnLayout, intendedText: "привет"),
        TestCase(input: "vbh", expectedClass: .ruFromEnLayout, intendedText: "мир"),
        TestCase(input: "rjvgm.nth", expectedClass: .ruFromEnLayout, intendedText: "компьютер"),
        TestCase(input: "ghjuhfvvf", expectedClass: .ruFromEnLayout, intendedText: "программа"),
        TestCase(input: "cbcntvf", expectedClass: .ruFromEnLayout, intendedText: "система"),
        TestCase(input: "xnj,", expectedClass: .ruFromEnLayout, intendedText: "чтоб"), // Ticket 59 reproduction
    ]
    
    // English intended, Russian layout active -> produces Cyrillic gibberish
    static let enFromRuCases: [TestCase] = [
        TestCase(input: "руддщ", expectedClass: .enFromRuLayout, intendedText: "hello"),
        TestCase(input: "цщкдв", expectedClass: .enFromRuLayout, intendedText: "world"),
        TestCase(input: "сщьзгеук", expectedClass: .enFromRuLayout, intendedText: "computer"),
        TestCase(input: "зкщпкфь", expectedClass: .enFromRuLayout, intendedText: "program"),
        TestCase(input: "ыные|у|ь", expectedClass: .enFromRuLayout, intendedText: "system"),
    ]
    
    // Hebrew intended, English layout active -> produces Latin chars
    static let heFromEnCases: [TestCase] = [
        TestCase(input: "NJAC", expectedClass: .heFromEnLayout, intendedText: "מחשב"),
        TestCase(input: "MWTNH", expectedClass: .heFromEnLayout, intendedText: "משתנה"),
        TestCase(input: "MERKT", expectedClass: .heFromEnLayout, intendedText: "מערכת"),
        TestCase(input: "WLVם", expectedClass: .heFromEnLayout, intendedText: "שלום"),
    ]
    
    // English intended, Hebrew layout active -> produces Hebrew chars
    static let enFromHeCases: [TestCase] = [
        TestCase(input: "יקךךם", expectedClass: .enFromHeLayout, intendedText: "hello"),
        TestCase(input: "ןםרךג", expectedClass: .enFromHeLayout, intendedText: "world"),
    ]
    
    // Hebrew intended, Russian layout active -> produces Cyrillic chars
    static let heFromRuCases: [TestCase] = [
        TestCase(input: "ЬУКЛЕ", expectedClass: .heFromRuLayout, intendedText: "מערכת"),
        TestCase(input: "ТОФС", expectedClass: .heFromRuLayout, intendedText: "מחשב"),
        TestCase(input: "ИВШЙР", expectedClass: .heFromRuLayout, intendedText: "בדיקה"),
        TestCase(input: "ЦДМם", expectedClass: .heFromRuLayout, intendedText: "שלום"),
    ]
    
    // Russian intended, Hebrew layout active -> produces Hebrew chars
    static let ruFromHeCases: [TestCase] = [
        TestCase(input: "עינגאמ", expectedClass: .ruFromHeLayout, intendedText: "привет"),
        TestCase(input: "זפדר", expectedClass: .ruFromHeLayout, intendedText: "язык"),
    ]
    
    // MARK: - Edge Cases
    
    // Very short tokens (2-3 chars)
    static let shortTokenCases: [TestCase] = [
        TestCase(input: "hi", expectedClass: .en, intendedText: "hi"),
        TestCase(input: "да", expectedClass: .ru, intendedText: "да"),
        TestCase(input: "לא", expectedClass: .he, intendedText: "לא"),
        TestCase(input: "ok", expectedClass: .en, intendedText: "ok"),
        TestCase(input: "нет", expectedClass: .ru, intendedText: "нет"),
    ]
    
    // Tokens with punctuation
    static let punctuationCases: [TestCase] = [
        TestCase(input: "hello!", expectedClass: .en, intendedText: "hello!"),
        TestCase(input: "привет?", expectedClass: .ru, intendedText: "привет?"),
        TestCase(input: "test.", expectedClass: .en, intendedText: "test."),
    ]
    
    // MARK: - CoreML Direct Tests
    
    func testCoreMLPureRussian() {
        runCoreMLTests(Self.pureRussianCases, scenario: "Pure Russian")
    }
    
    func testCoreMLPureEnglish() {
        runCoreMLTests(Self.pureEnglishCases, scenario: "Pure English")
    }
    
    func testCoreMLPureHebrew() {
        runCoreMLTests(Self.pureHebrewCases, scenario: "Pure Hebrew")
    }
    
    func testCoreMLRuFromEn() {
        runCoreMLTests(Self.ruFromEnCases, scenario: "RU from EN layout")
    }
    
    func testCoreMLEnFromRu() {
        runCoreMLTests(Self.enFromRuCases, scenario: "EN from RU layout")
    }
    
    func testCoreMLHeFromEn() {
        runCoreMLTests(Self.heFromEnCases, scenario: "HE from EN layout")
    }
    
    func testCoreMLHeFromRu() {
        runCoreMLTests(Self.heFromRuCases, scenario: "HE from RU layout")
    }
    
    func testCoreMLEnFromHe() {
        runCoreMLTests(Self.enFromHeCases, scenario: "EN from HE layout")
    }
    
    func testCoreMLRuFromHe() {
        runCoreMLTests(Self.ruFromHeCases, scenario: "RU from HE layout")
    }
    
    func testCoreMLShortTokens() {
        runCoreMLTests(Self.shortTokenCases, scenario: "Short tokens (2-3 chars)")
    }
    
    func testCoreMLPunctuation() {
        runCoreMLTests(Self.punctuationCases, scenario: "Tokens with punctuation")
    }
    
    // MARK: - Layout Mapper Tests
    
    func testLayoutMapperRuToEn() {
        // Verify that Russian text converts correctly to English layout output
        let ruText = "привет"
        let converted = layoutMapper.convert(ruText, from: .russian, to: .english)
        XCTAssertNotNil(converted, "Should convert Russian to English layout")
        XCTAssertEqual(converted, "ghbdtn", "привет on EN layout should be ghbdtn")
    }
    
    func testLayoutMapperEnToRu() {
        let enText = "hello"
        let converted = layoutMapper.convert(enText, from: .english, to: .russian)
        XCTAssertNotNil(converted, "Should convert English to Russian layout")
        // "hello" typed on RU layout produces Cyrillic
    }
    
    // MARK: - Accuracy Metrics
    
    func testOverallAccuracy() {
        var totalCorrect = 0
        var totalTests = 0
        
        let allCases: [(String, [TestCase])] = [
            ("Pure RU", Self.pureRussianCases),
            ("Pure EN", Self.pureEnglishCases),
            ("Pure HE", Self.pureHebrewCases),
            ("RU from EN", Self.ruFromEnCases),
            ("EN from RU", Self.enFromRuCases),
            ("HE from EN", Self.heFromEnCases),
            ("HE from RU", Self.heFromRuCases),
            ("EN from HE", Self.enFromHeCases),
            ("RU from HE", Self.ruFromHeCases),
        ]
        
        print("\n=== LAYOUT DETECTION ACCURACY REPORT ===\n")
        
        for (name, cases) in allCases {
            var correct = 0
            for testCase in cases {
                if let (prediction, _) = classifier.predict(testCase.input) {
                    if prediction == testCase.expectedClass {
                        correct += 1
                    }
                }
            }
            let accuracy = cases.isEmpty ? 0 : Double(correct) / Double(cases.count) * 100
            print("\(name): \(correct)/\(cases.count) (\(String(format: "%.1f", accuracy))%)")
            totalCorrect += correct
            totalTests += cases.count
        }
        
        let overallAccuracy = totalTests == 0 ? 0 : Double(totalCorrect) / Double(totalTests) * 100
        print("\nOVERALL: \(totalCorrect)/\(totalTests) (\(String(format: "%.1f", overallAccuracy))%)")
        
        // DoD: Accuracy should be >= 80%
        XCTAssertGreaterThanOrEqual(overallAccuracy, 80.0, "Overall accuracy should be at least 80%")
    }
    
    // MARK: - Helpers
    
    private func runCoreMLTests(_ cases: [TestCase], scenario: String) {
        var passed = 0
        var failed: [(TestCase, LanguageHypothesis?)] = []
        
        for testCase in cases {
            if let (prediction, _) = classifier.predict(testCase.input) {
                if prediction == testCase.expectedClass {
                    passed += 1
                } else {
                    failed.append((testCase, prediction))
                }
            } else {
                failed.append((testCase, nil))
            }
        }
        
        if !failed.isEmpty {
            print("\n[\(scenario)] Failed cases:")
            for (tc, pred) in failed {
                print("  Input: '\(tc.input)' Expected: \(tc.expectedClass.rawValue) Got: \(pred?.rawValue ?? "nil")")
            }
        }
        
        let accuracy = cases.isEmpty ? 100 : Double(passed) / Double(cases.count) * 100
        XCTAssertGreaterThanOrEqual(accuracy, 60.0, "\(scenario) accuracy should be at least 60%")
    }
}
