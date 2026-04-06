import XCTest
@testable import RightLayout

final class EarlyLayoutSwitchingTests: XCTestCase {
    var engine: CorrectionEngine!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        // Ensure layouts are configured for test logic (mocked or real)
        settings.activeLayouts = [
            "com.apple.keylayout.US": "en",
            "com.apple.keylayout.Russian": "ru"
        ]
        
        // Reset thresholds to defaults in case other tests changed them
        // (Assuming we can't easily reset config, but default init should be fine)
        engine = CorrectionEngine(settings: settings)
    }
    
    @MainActor
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "activeLayouts")
        SettingsManager.shared.activeLayouts = [:]
    }
    
    func testEarlySwitchTrigger() async {
        // "ghb" -> "при" (Russian)
        // High confidence trigram on Russian layout vs garbage on English
        let result = await engine.checkEarlyCorrection("ghb", bundleId: nil)
        XCTAssertEqual(result, "при", "Should detect early switch for 'ghb'")
    }
    
    func testEarlySwitchLongerWord() async {
        // "ghbdtn" -> "привет"
        let result = await engine.checkEarlyCorrection("ghbdtn", bundleId: nil)
        XCTAssertEqual(result, "привет", "Should detect early switch for 'ghbdtn'")
    }
    
    func testNoEarlySwitchForValidEnglish() async {
        // "the" -> valid English
        let result = await engine.checkEarlyCorrection("the", bundleId: nil)
        XCTAssertNil(result, "Should NOT early switch for valid English 'the'")
    }

    func testNoEarlySwitchForShortTokens() async {
        // "gh" -> to short (min 3)
        let result = await engine.checkEarlyCorrection("gh", bundleId: nil)
        XCTAssertNil(result, "Should NOT early switch for length < 3")
    }
    
    func testNoEarlySwitchForAmbiguous() async {
        // "fgh" -> pr... maybe, but "fgh" is also common trigram? 
        // actually "apk" -> valid partial word?
        // Let's rely on strict thresholds.
        // "ghb" is very strictly Russian start.
        
        // Let's test something that shouldn't switch
        // "sys" -> valid start of system
        let result = await engine.checkEarlyCorrection("sys", bundleId: nil)
        XCTAssertNil(result)
    }
}
