import XCTest
@testable import RightLayout

final class RealisticBehaviorTests: XCTestCase {
    var engine: CorrectionEngine!
    var settings: SettingsManager!
    var eventMonitor: EventMonitor!
    var mockTime: MockTimeProvider!
    var mockEncoder: MockCharacterEncoder!
    
    // We need a mock proxy to capture events posted by EventMonitor
    // Since we can't easily mock CGEventTapProxy in pure Swift without ObjC runtime tricks or elaborate wrappers,
    // we will rely on EventMonitor's internal state (buffers) or its interaction with CorrectionEngine.
    // Ideally, EventMonitor should use an injectable "EventPoster" protocol.
    // For now, we will inspect EventMonitor's internal state where possible or mock the Engine to verify calls.
    
    @MainActor
    override func setUp() async throws {
        settings = SettingsManager.shared
        settings.isEnabled = true
        engine = CorrectionEngine(settings: settings)
        mockTime = MockTimeProvider()
        mockEncoder = MockCharacterEncoder()
        eventMonitor = EventMonitor(engine: engine, timeProvider: mockTime, charEncoder: mockEncoder)
        eventMonitor.skipPIDCheck = true
        eventMonitor.skipSecureInputCheck = true
        eventMonitor.skipEventPosting = true
    }
    
    // MARK: - Helpers
    
    private func createKeyEvent(keyCode: CGKeyCode, down: Bool) -> CGEvent {
        let source = CGEventSource(stateID: .privateState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
        return event!
    }
    
    @MainActor
    private func typeChar(_ char: Character, keyCode: CGKeyCode) async {
        // Key Down
        let down = createKeyEvent(keyCode: keyCode, down: true)
        // We can pass nil for proxy since we are not using it in our mocked flow logic heavily, 
        // OR we need to mock it better. For now, let's pass an OpaquePointer that is at least valid-ish or use nil if allowed.
        // CGEventTapProxy is OpaquePointer. 
        // Hack for testing: unsafeBitCast(0, to: CGEventTapProxy.self) if 0 is accepted, otherwise we need a real value.
        // But handleEvent expects it.
        // Let's rely on the fact that for these tests we might not trigger the replacement logic heavily requiring the proxy callback 
        // OR we accept that proxy interaction is limited.
        // Swift casting `0 as! CGEventTapProxy` fails.
        // Using `unsafeBitCast(0, to: CGEventTapProxy.self)`
         
        let mockProxy = unsafeBitCast(Int(0), to: CGEventTapProxy.self)

        _ = eventMonitor.handleEvent(proxy: mockProxy, type: .keyDown, event: down)
        
        // Advance time slightly (simulating key press duration)
        mockTime.advance(by: 0.05)
        
        // Key Up
        let up = createKeyEvent(keyCode: keyCode, down: false)
        _ = eventMonitor.handleEvent(proxy: mockProxy, type: .keyUp, event: up)
    }
    
    // MARK: - Tests
    
    @MainActor
    func testVariableSpeedTyping() async throws {
        // Fast burst: "ghb" (10ms between keys)
        // Pause: 800ms
        // Finish: "dtn" (10ms between keys)
        // Input: "ghbdtn" (-> привет)
        
        // 'g' (keyCode 5)
        await typeChar("g", keyCode: 5)
        mockTime.advance(by: 0.01)
        await typeChar("h", keyCode: 4)
        mockTime.advance(by: 0.01)
        await typeChar("b", keyCode: 11)
        
        // Pause (thinking)
        mockTime.advance(by: 0.8)
        
        await typeChar("d", keyCode: 2)
        mockTime.advance(by: 0.01)
        await typeChar("t", keyCode: 17)
        mockTime.advance(by: 0.01)
        await typeChar("n", keyCode: 45)
        
        // Space (trigger)
        mockTime.advance(by: 0.1)
        await typeChar(" ", keyCode: 49)
        
        // Wait for async processing
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify via history that "ghbdtn" was corrected to "привет"
        let history = await engine.getHistory()
        XCTAssertEqual(history.first?.original, "ghbdtn")
        XCTAssertEqual(history.first?.corrected, "привет")
    }
    
    @MainActor
    func testMidWordPause() async throws {
        // Pause > 2.0s triggers buffer clear in handleEvent
        // Type "ghb"
        await typeChar("g", keyCode: 5)
        await typeChar("h", keyCode: 4)
        await typeChar("b", keyCode: 11)
        
        // Long pause (2.5s) - exceeds buffer timeout
        mockTime.advance(by: 2.5)
        
        // Type "dtn"
        await typeChar("d", keyCode: 2)
        await typeChar("t", keyCode: 17)
        await typeChar("n", keyCode: 45)
        await typeChar(" ", keyCode: 49)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Expectation: buffer cleared after "ghb", so the timed-out token must not be
        // merged into a synthetic "ghbdtn" correction attempt. Under v3 fail-closed
        // rules the isolated fragment may remain uncorrected, so history can be empty.
        let history = await engine.getHistory()
        let lastOriginal = history.first?.original
        XCTAssertNotEqual(lastOriginal, "ghbdtn", "Timed-out input must not be merged into the prior token")
        XCTAssertTrue(lastOriginal == nil || lastOriginal == "dtn", "Only the post-timeout fragment may be considered for correction")
    }
    
    @MainActor
    func testTypoBackspaceFlow() async throws {
        // "ghbdtnn" -> Backspace -> Space
        
        await typeChar("g", keyCode: 5)
        await typeChar("h", keyCode: 4)
        await typeChar("b", keyCode: 11)
        await typeChar("d", keyCode: 2)
        await typeChar("t", keyCode: 17)
        await typeChar("n", keyCode: 45)
        await typeChar("n", keyCode: 45) // Typo
        
        mockTime.advance(by: 0.2)
        
        // Backspace (keyCode 51)
        await typeChar("\u{8}", keyCode: 51)
        
        mockTime.advance(by: 0.2)
        
        // Space
        await typeChar(" ", keyCode: 49)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Should correct "ghbdtn" -> "привет"
        let history = await engine.getHistory()
        XCTAssertEqual(history.first?.original, "ghbdtn")
        XCTAssertEqual(history.first?.corrected, "привет")
    }
    
    /*
    @MainActor
    func testTicket29Integration_CombinedFlow() async throws {
        // ... (Disabled due to AX dependency mocking issues)
    }
    */
}
