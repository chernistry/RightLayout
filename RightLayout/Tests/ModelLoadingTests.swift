import XCTest
@testable import RightLayout

final class ModelLoadingTests: XCTestCase {
    
    func testLoadRussianModel() throws {
        let model = try NgramLanguageModel.loadLanguage("ru")
        // Check some known trigrams from our sample corpus
        // "при" from "привет" should be present
        let score = model.lookup("п", "р", "и")
        XCTAssertGreaterThan(score, -10.0, "Should find 'при' in Russian model")
    }
    
    func testLoadEnglishModel() throws {
        let model = try NgramLanguageModel.loadLanguage("en")
        // "hel" from "hello" should be present
        let score = model.lookup("h", "e", "l")
        XCTAssertGreaterThan(score, -10.0, "Should find 'hel' in English model")
    }
    
    func testLoadHebrewModel() throws {
        let model = try NgramLanguageModel.loadLanguage("he")
        // "שלו" from "שלום" should be present
        let score = model.lookup("ש", "ל", "ו")
        XCTAssertGreaterThan(score, -10.0, "Should find 'שלו' in Hebrew model")
    }
    
    func testLoadNonExistentModel() {
        XCTAssertThrowsError(try NgramLanguageModel.loadLanguage("xx")) { error in
            guard let modelError = error as? ModelError else {
                XCTFail("Expected ModelError")
                return
            }
            if case .resourceNotFound(let lang) = modelError {
                XCTAssertEqual(lang, "xx")
            } else {
                XCTFail("Expected resourceNotFound error")
            }
        }
    }
    

}
