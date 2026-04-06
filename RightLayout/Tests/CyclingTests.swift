import XCTest
@testable import RightLayout

final class CyclingTests: XCTestCase {
    var engine: CorrectionEngine!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
        engine = CorrectionEngine(settings: settings)
    }
    
    @MainActor
    func testFirstRoundTwoStates() async throws {
        let initial = await engine.correctLastWord("ghbdtn")
        XCTAssertEqual(initial, "привет")
        
        let cycle1 = await engine.cycleCorrection()
        XCTAssertEqual(cycle1, "ghbdtn") // Undo
        
        let cycle2 = await engine.cycleCorrection()
        XCTAssertEqual(cycle2, "привет") // Redo
    }
    
    @MainActor
    func testSecondRoundThreeStates() async throws {
        // Setup: same as above
        _ = await engine.correctLastWord("ghbdtn") // -> привет
        _ = await engine.cycleCorrection() // -> ghbdtn (Undo)
        _ = await engine.cycleCorrection() // -> привет (Redo)
        
        // Next press should expand to Round 2 and show a 3rd option
        let cycle3 = await engine.cycleCorrection()
        XCTAssertNotEqual(cycle3, "ghbdtn")
        XCTAssertNotEqual(cycle3, "привет")
    }
    
    @MainActor
    func testTypingResetsCyclingRound() async throws {
        _ = await engine.correctLastWord("ghbdtn")
        await engine.resetCycling()
        
        let state = await engine.hasCyclingState()
        XCTAssertFalse(state)
    }
}
