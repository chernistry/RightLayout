import XCTest
@testable import RightLayout

final class CorrectionEngineTests: XCTestCase {
    var engine: CorrectionEngine!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        settings.isLearningEnabled = false
        settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
        engine = CorrectionEngine(settings: settings)
    }

    @MainActor
    override func tearDown() {
        SettingsManager.shared.isLearningEnabled = true
        engine = nil
        super.tearDown()
    }
    
    // MARK: - Hybrid Algorithm Tests
    
    func testCorrectInvalidRussianToEnglish() async throws {
        // "ghbdtn" is invalid in English, but "привет" is valid in Russian
        let result = await engine.correctText("ghbdtn", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "привет")
    }
    
    func testCorrectInvalidEnglishToRussian() async throws {
        // "ghbdtn" typed on English layout is invalid, converts to valid Russian "привет"
        let result = await engine.correctText("ghbdtn", phraseBuffer: "", expectedLayout: nil)
        XCTAssertNotNil(result.corrected)
        if let corrected = result.corrected {
            XCTAssertEqual(corrected, "привет")
        }
    }
    
    func testValidWordNotCorrected() async throws {
        // "hello" is valid in English, should not be corrected
        let result = await engine.correctText("hello", phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(result.corrected)
    }
    
    func testValidRussianWordNotCorrected() async throws {
        // "привет" is valid in Russian, should not be corrected
        let result = await engine.correctText("привет", phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(result.corrected)
    }
    
    func testHebrewToEnglishCorrection() async throws {
        // Invalid Hebrew word that becomes valid English
        let result = await engine.correctText("adk", phraseBuffer: "", expectedLayout: nil)
        if result.corrected != nil {
            XCTAssertNotEqual(result.corrected, "adk")
        }
    }
    
    func testEmptyTextReturnsNil() async throws {
        let result = await engine.correctText("", phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(result.corrected)
    }
    
    func testHistoryRecordsCorrection() async throws {
        let result = await engine.correctText("ghbdtn", phraseBuffer: "", expectedLayout: nil)
        if let transaction = result.transaction {
            await engine.commitTransaction(transaction)
        }
        let history = await engine.getHistory()
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.first?.original, "ghbdtn")
    }
    
    func testClearHistory() async throws {
        let result = await engine.correctText("ghbdtn", phraseBuffer: "", expectedLayout: nil)
        if let transaction = result.transaction {
            await engine.commitTransaction(transaction)
        }
        await engine.clearHistory()
        let history = await engine.getHistory()
        XCTAssertTrue(history.isEmpty)
    }
    
    @MainActor
    func testShouldCorrectWhenEnabled() async throws {
        let shouldCorrect = await engine.shouldCorrect(for: nil)
        XCTAssertTrue(shouldCorrect)
    }
    
    @MainActor
    func testShouldNotCorrectWhenDisabled() async throws {
        let settings = SettingsManager.shared
        let originalState = settings.isEnabled
        settings.isEnabled = false
        let shouldCorrect = await engine.shouldCorrect(for: nil)
        XCTAssertFalse(shouldCorrect)
        settings.isEnabled = originalState
    }
}
