import XCTest
@testable import RightLayout

@MainActor
final class SelectionReplacementIntegrationTests: XCTestCase {
    
    override func setUp() async throws {
        SelectionReplacementService.shared.setSkipEventPosting(true)
    }
    
    override func tearDown() async throws {
        SelectionReplacementService.shared.setTestBundleId(nil)
    }
    
    func testShortTextUsesEventsStrategy() async throws {
        let service = SelectionReplacementService.shared
        service.setTestBundleId("com.apple.TextEdit")
        
        try await service.replace(original: "short", replacement: "corrected", proxy: nil)
        
        let strategy = service.lastStrategy
        let replacement = service.lastReplacement
        
        XCTAssertEqual(strategy, .events)
        XCTAssertEqual(replacement?.original, "short")
        XCTAssertEqual(replacement?.replacement, "corrected")
    }
    
    func testLongTextUsesEventReplayStrategyForImplicitReplacement() async throws {
        let service = SelectionReplacementService.shared
        service.setTestBundleId("com.apple.TextEdit")
        
        // > 10 chars
        let longOriginal = "LongerThanTenChars"
        try await service.replace(original: longOriginal, replacement: "CorrectedLongText", proxy: nil)
        
        let strategy = service.lastStrategy
        let replacement = service.lastReplacement
        
        XCTAssertEqual(strategy, .events)
        XCTAssertEqual(replacement?.original, longOriginal)
    }
    
    func testVSCodeDoesNotForceClipboardForImplicitReplacement() async throws {
        let service = SelectionReplacementService.shared
        service.setTestBundleId("com.microsoft.VSCode")
        
        let result = try await service.replace(original: "short", replacement: "corrected", proxy: nil)
        
        let strategy = service.lastStrategy
        
        XCTAssertEqual(strategy, .events, "Implicit replacement should stay on replay, not clipboard")
        XCTAssertEqual(result.commitKind, .blindCommit)
    }
    
    func testIntelliJDoesNotForceClipboardForImplicitReplacement() async throws {
        let service = SelectionReplacementService.shared
        service.setTestBundleId("com.jetbrains.intellij")
        
        let result = try await service.replace(original: "code", replacement: "fixed", proxy: nil)
        
        let strategy = service.lastStrategy
        
        XCTAssertEqual(strategy, .events)
        XCTAssertEqual(result.commitKind, .blindCommit)
    }
}
