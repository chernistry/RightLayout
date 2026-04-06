import XCTest
@testable import RightLayout

final class KTConversionTests: XCTestCase {
    func testKTToLo() {
        let activeLayouts = ["en": "us", "ru": "russian", "he": "hebrew"]
        let result = LayoutMapper.shared.convert("kt", from: .english, to: .hebrew, activeLayouts: activeLayouts)
        print("kt -> \(result ?? "nil")")
        XCTAssertEqual(result, "לא")
        
        // Also test convertAllVariants
        let variants = LayoutMapper.shared.convertAllVariants("kt", from: .english, to: .hebrew, activeLayouts: activeLayouts)
        print("Variants: \(variants)")
        
        // Check if לא is in hebrewCommonShortWords
        let heWords = LanguageDataConfig.shared.hebrewCommonShortWords
        print("hebrewCommonShortWords: \(heWords)")
        print("לא in heWords: \(heWords.contains("לא"))")
    }
}
