import XCTest
@testable import RightLayout

final class LanguageEnsembleTests: XCTestCase {
    var ensemble: LanguageEnsemble!
    private let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
    
    override func setUp() {
        super.setUp()
        ensemble = LanguageEnsemble(wordValidator: MockWordValidator(validWords: [
            .english: ["hello", "world", "ok", "som"],
            .russian: ["привет", "нет", "да", "мир"],
            .hebrew: ["שלום", "מה", "כן", "לא"]
        ]))
    }
    
    override func tearDown() {
        ensemble = nil
        super.tearDown()
    }
    
    func testBasicClassification() async {
        let context = EnsembleContext(activeLayouts: activeLayouts)
        
        // English
        let resEn = await ensemble.classify("hello", context: context)
        XCTAssertEqual(resEn.language, .english)
        XCTAssertEqual(resEn.layoutHypothesis, .en)
        
        // Russian
        _ = await ensemble.classify("ghbdtn", context: context) // "עינגאמ" (nonsense but mapped)
        // Wait, "ghbdtn" maps to "עינגאמ" in Hebrew?
        // Let's use a real Hebrew example: "shalom" -> "דhשךם" (approx)
        // Or "akuo" -> "שלום"
        
        let result2 = await ensemble.classify("akuo", context: context) // "שלום"
        XCTAssertEqual(result2.language, .hebrew)
        XCTAssertEqual(result2.layoutHypothesis, .heFromEnLayout)
    }
    
    func testLayoutCorrectionRussian() async {
        let context = EnsembleContext(activeLayouts: activeLayouts)
        // "ghbdtn" is "привет" typed on English layout
        let result = await ensemble.classify("ghbdtn", context: context) // "привет"
        
        XCTAssertEqual(result.language, .russian)
        XCTAssertEqual(result.layoutHypothesis, .ruFromEnLayout)
        XCTAssertGreaterThan(result.confidence, 0.55)
    }
    
    func testLayoutCorrectionHebrew() async {
        let context = EnsembleContext(activeLayouts: activeLayouts)
        // "akuo" is "שלום" typed on English layout
        let result = await ensemble.classify("akuo", context: context)
        
        XCTAssertEqual(result.language, .hebrew)
        XCTAssertEqual(result.layoutHypothesis, .heFromEnLayout)
    }
    
    func testContextBias() async {
        // Ambiguous token "is" (could be English 'is' or part of something else)
        // Actually "is" is too short (2 chars), let's use "chat" (EN) vs "сhat" (if it were RU, but unlikely)
        // Better example: "net" (EN) vs "нет" (RU - 'ytn' on EN layout)
        
        // "ytn" -> "нет" (RU)
        // "ytn" -> "ytn" (EN - nonsense)
        
        // Without context, should prefer RU because "нет" is a valid word and "ytn" is not
        let noContext = await ensemble.classify("ytn", context: EnsembleContext(activeLayouts: activeLayouts))
        XCTAssertEqual(noContext.language, .russian)
        
        // With English context, might still prefer RU if the word is very strong, 
        // but let's try a case where context flips it.
        // "som" -> "som" (EN - partial) vs "ыом" (RU - nonsense)
        
        let res = await ensemble.classify("som", context: EnsembleContext(lastLanguage: .english, activeLayouts: activeLayouts))
        XCTAssertEqual(res.language, .english)
    }
    
    func testShortTokenFallback() async {
        let context = EnsembleContext(lastLanguage: .russian)
        // 1 char token - should fallback to context
        let result = await ensemble.classify("a", context: context)
        
        XCTAssertEqual(result.language, .russian)
        XCTAssertEqual(result.confidence, 0.5)
    }
    
    func testMixedText() async {
        // "hello мир"
        // Should detect as English or Russian depending on dominance
        // "hello" (5) + " " (1) + "мир" (3) = 9 chars. 5 Latin, 3 Cyrillic.
        // Likely English.
        
        let result = await ensemble.classify("hello мир", context: EnsembleContext(activeLayouts: activeLayouts))
        XCTAssertEqual(result.language, .english)
    }
}
