import XCTest
@testable import RightLayout

@MainActor
final class LogicFixesTests: XCTestCase {
    var engine: CorrectionEngine!

    override func setUp() async throws {
        let settings = SettingsManager.shared
        engine = CorrectionEngine(settings: settings)
    }

    func testCommaHandlingForIzbiratel() async {
        // "bp,bhfntkm" -> "избиратель" in RU-PC.
        // The comma ',' in EN maps to 'б' in RU-PC if mapped.
        // Previously, the comma caused a split.
        // The fix allows whole-word dictionary match to override the split.
        
        let text = "bp,bhfntkm"
        
        // Mock RiskController to force auto-apply so we get .applied
        await RiskController.shared.forcePolicy(.autoApply)
        
        // Use empty phrase buffer and no expected layout
        let result = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
        
        // Check if action is applied
        // result.action is CorrectionAction enum (applied, hint, none)
        XCTAssertEqual(result.action, .applied, "Should have applied correction")
        XCTAssertEqual(result.corrected, "избиратель", "Should convert full word including comma")
    }
}
