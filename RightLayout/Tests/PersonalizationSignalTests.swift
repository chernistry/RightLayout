import XCTest
import Carbon
@testable import RightLayout

@MainActor
final class PersonalizationSignalTests: XCTestCase {
    var engine: CorrectionEngine!
    var settings: SettingsManager!
    var monitor: EventMonitor!
    var mockTime: MockTimeProvider!
    var mockEncoder: MockCharacterEncoder!
    
    // Mock Encoder
    class MockCharacterEncoder: CharacterEncoder {
        var nextChar: String?
        func encode(event: CGEvent) -> String? {
            // Debug print
            if let c = nextChar { print("DEBUG: MockEncoder returning '\(c)'") }
            else { print("DEBUG: MockEncoder returning nil") }
            return nextChar
        }
    }
    
    override func setUp() async throws {
        try await super.setUp()
        settings = SettingsManager.shared
        // Reset settings
        settings.isLearningEnabled = true
        settings.isEnabled = true
        settings.autoSwitchLayout = false
        
        engine = CorrectionEngine(settings: settings)
        mockTime = MockTimeProvider()
        // Use default encoder now that we fixed the secure input blocker
        monitor = EventMonitor(engine: engine, timeProvider: mockTime)
        monitor.skipPIDCheck = true
        monitor.skipSecureInputCheck = true
        monitor.skipEventPosting = true
        
        // Reset engine state
        
        // Reset engine state
        await engine.clearHistory()
        
        // Ensure clean personalization state
         let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let persDir = appSupport.appendingPathComponent("com.chernistry.rightlayout/Personalization")
        try? FileManager.default.removeItem(at: persDir)
    }
    
    override func tearDown() {
        engine = nil
        settings = nil
        monitor = nil
        mockTime = nil
        super.tearDown()
    }
    
    // MARK: - Helpers
    
    // We can pass nil as proxy since we are not testing the actual event posting 
    // but the side effects on the engine. If passing nil crashes, we utilize a dummy opaque pointer.
    private var dummyProxy: CGEventTapProxy {
        // Just use a random pointer? OpaquePointer(bitPattern: 1)!
        // Or actually, since we are in a test, maybe we don't need a real one if we don't trigger replacement logic?
        // But retype detection happens inside correction which triggers replacement.
        // Let's hope CGEventTapPostEvent is safe with bad proxy in tests or we avoid the path.
        // Actually, we can just let it fail.
        return nil as CGEventTapProxy? ?? OpaquePointer(bitPattern: 1)!
    }
    
    private func typeString(_ text: String) async {
        for char in text {
            let event = createKeyEvent(char: char)
            _ = monitor.handleEvent(proxy: dummyProxy, type: .keyDown, event: event)
            
            // If char is space, logic is async. Wait a bit.
            if char == " " {
                // Wait for async processing
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
    
    private func typeKey(code: Int) {
        // Create event with specific keycode
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true) else { return }
        _ = monitor.handleEvent(proxy: dummyProxy, type: .keyDown, event: event)
    }
    
    private func createKeyEvent(char: Character) -> CGEvent {
        // Minimal mapping for test
        let (code, _) = simpleKeyMap(char)
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
        // We need to set the string implementation for the encoder to pick it up?
        // DefaultCharacterEncoder uses event.keyboardSetUnicodeString logic or fallbacks.
        // CGEventKeyboardSetUnicodeString is deprecated but works or we can rely on how `CharacterEncoder` works.
        // `DefaultCharacterEncoder` uses `event.getUnicodeString()` wrapper.
        // We can manually set it.
        var chars = [UniChar](String(char).utf16)
        event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        return event
    }
    
    private func simpleKeyMap(_ char: Character) -> (Int, Bool) {
        // Very basic mapping
        switch char {
        case "a": return (0, false)
        case " ": return (49, false)
        default: return (1, false)
        }
    }

    // MARK: - Tests
    
    func testBackspaceBurstDetection() async throws {
         // 1. Simulate a correction
        // "ghbdtn " -> "привет "
        // We simulate this by directly calling engine to set state, or by "typing" if we trust simulation.
        // Let's interact with Engine directly to "prime" it with a tracking ID.
        // Manually report a "pending" like state or just ensure `lastCorrectionTrackingId` is set in monitor.
        // Since `lastCorrectionTrackingId` is private in Monitor, we must trigger it via typing.
        
        // We rely on `EventMonitor.processBufferContent` to update `lastCorrectionTrackingId`.
        // So we MUST simulate typing a triggered correction.
        // "ghbdtn" maps to "привет".
        // Setup:
        // Type "ghbdtn "
        // Engine should correct.
        
        // Mock time start
        mockTime.currentTime = Date()
        
        // Type correction trigger
        await typeString("ghbdtn ")
        
        // Allow async correction to finish (wait for engine warmup)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify engine state
        // We can't easily check monitor state.
        
        // 2. Perform Backspace Burst
        // Wait minor time
        mockTime.advance(by: 0.5)
        
        // Backspace 1
        typeKey(code: 51)
        
        // Backspace 2
        mockTime.advance(by: 0.1)
        typeKey(code: 51)
        
        // Backspace 3 (Ticket 55: Burst threshold requires 3)
        mockTime.advance(by: 0.1)
        typeKey(code: 51) // Burst threshold met (count=3)
        
        // Allow async reporting
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // 3. Verify Engine received signal
        let signal = await engine.lastReportedSignal
        XCTAssertNotNil(signal, "Should have reported a signal")
        XCTAssertEqual(signal?.1, .backspaceBurst)
        // Check ID matches (we can't check exact ID easily without capturing it from correctText result, but engine captured it)
        // If signal is not nil, it works.
    }
    
    func testLayoutSwitchDetection() async throws {
        // 1. Trigger correction
        mockTime.currentTime = Date()
        await typeString("ghbdtn ") 
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // 2. Post layout change notification
        mockTime.advance(by: 0.5) // Within window
        
        // We must ensure the observer was set up. It was set up in `setUp` -> `EventMonitor.init`.
        // Post notification manually.
        NotificationCenter.default.post(
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        // Wait, `DistributedNotificationCenter` is what we observe.
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        
        // Allow async reporting
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // 3. Verify Engine received signal
        let signal = await engine.lastReportedSignal
        XCTAssertNotNil(signal, "Should have reported negative feedback")
        XCTAssertEqual(signal?.1, .manualSwitch)
    }
    
    func testRetypeDetection() async throws {
        // 1. Type and Correct
        mockTime.currentTime = Date()
        await typeString("ghbdtn ") // -> "привет "
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // 2. Undo
        // Cmd+Z
        let undoEvent = CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true)!
        undoEvent.flags = .maskCommand
        _ = monitor.handleEvent(proxy: dummyProxy, type: .keyDown, event: undoEvent)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify Undo happened (engine state log or feedback)
        // But for Ticket 50 we want to verify RETYPE.
        
        // 3. Type the SAME thing again "ghbdtn "
        // This time, it should match the reverted features.
        // Note: feature hashing depends on hashing "ghbdtn".
        // And "ghbdtn" was the original text.
        
        // We need to advance time slightly so retype window is valid (< 10s)
        mockTime.advance(by: 2.0)
        
        // Reset buffers is implied by Undo? Not really, Undo logic relies on App Undo.
        // But `EventMonitor` `resetBuffer` is called on Cmd+Z? No, it just calls `engine.handleUndo()`.
        // User manually deletes or undoes text in real life.
        // Here we just type again.
        
        // Force buffer reset first to simulate "clean slate" typing?
        // Or just type.
        await typeString("ghbdtn ")
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // 4. Verify Engine reported signal
        let signal = await engine.lastReportedSignal
        XCTAssertNotNil(signal, "Should have reported retype detected as manualRevert")
        XCTAssertEqual(signal?.1, .manualRevert)
        // I need to update the code to actually REPORT it if I want to test it outcome?
        // Or I update the test to fail/pass based on log? (Can't read logs)
        
        // I should update `CorrectionEngine` to report `.manualRevert` again? or `.retypeConfirmed`?
        // Plan says: "Retype detected: ... report .manualRevert to FeedbackCollector." in the "Proposed Changes" section?
        // Plan said: "If match, report .manualRevert to FeedbackCollector."
        // My implementation MISSED THIS line in `checkForRetype`!
        // I need to fix `CorrectionEngine.swift` implementation of `checkForRetype`.
    }

    func testDeferredCascadeAppliedInEventMonitor() async throws {
        // Ticket 49: Ensure EventMonitor applies pendingCorrection/pendingOriginal by deleting
        // the previous token + separator + current token, then retyping both corrected.

        mockTime.currentTime = Date()

        // 1) Type "vs " (intended "мы ")
        await typeString("vs ")
        try await Task.sleep(nanoseconds: 150_000_000)

        // No replacement expected for the first ambiguous short token.
        XCTAssertNil(monitor.lastReplacement)

        // 2) Type "xnj " (intended "что ")
        await typeString("xnj ")
        try await Task.sleep(nanoseconds: 150_000_000)

        guard let op = monitor.lastReplacement else {
            XCTFail("Expected a replacement operation for cascade correction")
            return
        }

        XCTAssertEqual(op.insertedText, "мы что ")
        XCTAssertEqual(op.deletedCount, "vs xnj ".count)
    }
}
