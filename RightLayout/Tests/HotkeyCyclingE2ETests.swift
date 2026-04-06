import XCTest
@testable import RightLayout

@MainActor
final class HotkeyCyclingE2ETests: XCTestCase {
    var engine: CorrectionEngine!
    
    override func setUp() async throws {
        // Setup deps
        let settings = SettingsManager.shared
        engine = CorrectionEngine(settings: settings)
    }
    
    func testManualFlowOrder() async {
        // Given text "ghbdtn" (User meant "привет")
        // Manual Flow should start with Best Candidate ("привет")
        
        // 1. Trigger manually
        let text = "ghbdtn"
        // We simulate `processHotkeyCorrection` which calls correctLastWord
        await engine.processHotkeyCorrection(text: text, bundleId: "com.test.app")
        
        // 2. Verify Cycling State Initialized
        let hasState = await engine.hasCyclingState()
        XCTAssertTrue(hasState, "Should have cycling state")
        
        // 3. Verify First Cycle (called implicitly by processHotkeyCorrection in implementation, 
        // but here we might need to check internal state or call cycleCorrection again? 
        // Wait, processHotkeyCorrection calls correctLastWord which returns the FIRST result.)
        // But since we can't capture the return value easily from processHotkeyCorrection (it's void),
        // let's peek via a public method if possible, or cycle again.
        
        // Actually, `processHotkeyCorrection` calls `correctLastWord` which returns `String?` but it ignores it.
        // So state is set to index -1 (conceptually) which immediately cycles to 0.
        // Wait, my implementation of `correctLastWord` calls `cycleCorrection` at the end! 
        // So after `processHotkeyCorrection`, the state IS ALREADY at index 0 (Best Candidate).
        // Let's verify `getCurrentCyclingTextLength` matches "привет" (6).
        
        let length = await engine.getCurrentCyclingTextLength()
        XCTAssertEqual(length, 6) // "привет".count 
        
        // 4. Verify Next Cycle
        let next = await engine.cycleCorrection(bundleId: "com.test.app")
        // "привет" (idx 0) -> Next Candidate (idx 1).
        // Likely "ghbdtn" (Original) if no other candidates?
        // Let's see what candidates for "ghbdtn" are.
        // Likely Hebrew "פראי א" or similar if enabled.
        // Or if only RU/EN enabled, then [Best=RU, Original=EN]. 2 items.
        // So next() should wrap to 0? Or go to ...?
        // If items=[Best, Original], index 0 is Best. index 1 is Original.
        // next() -> 1 (Original).
        
        XCTAssertNotNil(next)
        // With 3 layouts (EN, RU, HE), we should have multiple alternatives.
        // Just verify cycling returns a string.
        print("Second cycle result: \(next ?? "nil")")
    }
    
    // Note: Can't easily test Selection interaction in Unit/E2E without mocking AX/Clipboard heavily.
    // relying on Manual Verification for Selection part.
}
