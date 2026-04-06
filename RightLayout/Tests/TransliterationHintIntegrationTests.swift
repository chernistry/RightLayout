import XCTest
@testable import RightLayout

final class TransliterationHintIntegrationTests: XCTestCase {
    private var engine: CorrectionEngine!
    private var settings: SettingsManager!
    private var eventMonitor: EventMonitor!
    private var mockTime: MockTimeProvider!
    private var mockEncoder: MockCharacterEncoder!

    private var originalTransliterationEnabled: Bool = false

    @MainActor
    override func setUp() async throws {
        settings = SettingsManager.shared
        originalTransliterationEnabled = settings.transliterationHintsEnabled
        settings.transliterationHintsEnabled = true
        settings.isEnabled = true

        engine = CorrectionEngine(settings: settings)
        mockTime = MockTimeProvider()
        mockEncoder = MockCharacterEncoder()

        // Minimal mapping for "privet " typing.
        mockEncoder.mapping[35] = "p"
        mockEncoder.mapping[15] = "r"
        mockEncoder.mapping[34] = "i"
        mockEncoder.mapping[9] = "v"
        mockEncoder.mapping[14] = "e"
        mockEncoder.mapping[17] = "t"
        mockEncoder.mapping[49] = " "

        eventMonitor = EventMonitor(engine: engine, timeProvider: mockTime, charEncoder: mockEncoder)
        eventMonitor.skipPIDCheck = true
        eventMonitor.skipSecureInputCheck = true
        eventMonitor.skipEventPosting = true
    }

    @MainActor
    override func tearDown() async throws {
        SettingsManager.shared.transliterationHintsEnabled = originalTransliterationEnabled
        eventMonitor = nil
    }

    @MainActor
    func testTransliterationHintPostedAndApplied() async throws {
        let hintExpectation = expectation(description: "Transliteration hint posted")
        var hintId: String?

        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("TransliterationHint"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let id = userInfo["id"] as? String,
                  let text = userInfo["text"] as? String else {
                return
            }
            guard text == "привет" else { return }
            hintId = id
            hintExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let proxy = unsafeBitCast(Int(0), to: CGEventTapProxy.self)

        func sendKeyDown(_ code: CGKeyCode) {
            let source = CGEventSource(stateID: .privateState)
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)!
            _ = eventMonitor.handleEvent(proxy: proxy, type: .keyDown, event: event)
        }

        // Type "privet "
        sendKeyDown(35)
        sendKeyDown(15)
        sendKeyDown(34)
        sendKeyDown(9)
        sendKeyDown(14)
        sendKeyDown(17)
        sendKeyDown(49)

        await fulfillment(of: [hintExpectation], timeout: 2.0)
        guard let id = hintId else {
            XCTFail("Missing hint id")
            return
        }

        NotificationCenter.default.post(
            name: Notification.Name("ApplyTransliterationHint"),
            object: nil,
            userInfo: ["id": id]
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(eventMonitor.lastReplacement?.deletedCount, "privet ".count)
        XCTAssertEqual(eventMonitor.lastReplacement?.insertedText, "привет ")
    }
}

