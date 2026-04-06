import XCTest
@testable import RightLayout

/// Integration tests for CorrectionEngine + EventMonitor logic
/// Replaces unstable E2EGitHubIssuesTests
@MainActor
final class CorrectionEngineIntegrationTests: XCTestCase {
    var engine: CorrectionEngine!
    var settings: SettingsManager!
    var monitor: EventMonitor!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        self.settings = SettingsManager.shared
        self.settings.isEnabled = true
        self.settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
        engine = CorrectionEngine(settings: settings)
        // Ticket 44: Clean state
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let persDir = appSupport.appendingPathComponent("com.chernistry.rightlayout/Personalization")
        try? FileManager.default.removeItem(at: persDir)
        
        settings.isLearningEnabled = false
        monitor = EventMonitor(engine: engine)
        
        // Reset engine state
        await engine.resetSentence()
        
        // Setup reasonable thresholds for testing
        // (Assuming default thresholds are fine, but might need tweaking if test env differs)
    }
    
    override func tearDown() {
        settings.isLearningEnabled = true
        engine = nil
        settings = nil
        monitor = nil
        super.tearDown()
    }
    
    // Helper to simulate typing a sequence of words and checking the final output
    // Returns the sequence of (Word, CorrectionResult)
    @MainActor
    private func simulateTyping(_ words: [String]) async -> [String] {
        var results: [String] = []
        
        for word in words {
            let parts = monitor.splitBufferContent(word)
            let token = parts.token
            
            if token.isEmpty {
                results.append(word) // Punctuation only
                continue
            }
            
            let res = await engine.correctText(token, phraseBuffer: "", expectedLayout: nil)
            
            // Check for pending correction (retroactive fix)
            if let _ = res.pendingCorrection, let _ = res.pendingOriginal {
                // Fix previous word in results if strictly strictly sequential
                // But for simplicity test verifies explicit expectations
            }
            
            results.append(res.corrected ?? token)
        }
        return results
    }
    
    // MARK: - Issue #2: Single-letter prepositions
    
    func testIssue2_PrepositionE() async {
        // "e vtyz" -> "e меня" automatically; the single-letter preposition stays manual-only.
        
        // 1. Type "e"
        _ = await engine.correctText("e", phraseBuffer: "", expectedLayout: nil)
        // "e" might not be corrected immediately (ambiguous)
        
        // 2. Type "vtyz" (меня)
        let res2 = await engine.correctText("vtyz", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(res2.corrected, "меня")
        
        // 3. Retroactive single-letter correction is disabled by default.
        XCTAssertNil(res2.pendingOriginal)
        XCTAssertNil(res2.pendingCorrection)
    }
    
    func testIssue2_PrepositionR() async {
        // "r cj;fktyb." -> "r сожалению" automatically; the preposition stays manual-only.
        
        _ = await engine.correctText("r", phraseBuffer: "", expectedLayout: nil)
        let res2 = await engine.correctText("cj;fktyb.", phraseBuffer: "", expectedLayout: nil) // "сожалению"
        
        XCTAssertEqual(res2.corrected, "сожалению")
        XCTAssertNil(res2.pendingOriginal)
        XCTAssertNil(res2.pendingCorrection)
    }
    
    // MARK: - Issue #3: Punctuation Boundaries (Monitor Logic)
    
    @MainActor
    func testIssue3_Splitting() {
        // Verify that EventMonitor splits these buffers correctly
        
        _ = monitor.splitBufferContent("ghbdtn?rfr") // "привет?как"
        // Should split at '?' ?
        // Current implementation tries to find "word boundary".
        // Note: splitBufferContent usually takes the buffer accumulated SO FAR.
        // It separates leading/trailing punctuation.
        // If buffer is "ghbdtn?rfr", splitBufferContent main logic might treat it as one token if ? is not delimiter?
        // Let's verify standard regex behavior.
        
        // Actually EventMonitor logic is:
        // .split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: { isDelimiter($0) })
        // Check `isDelimiterLikeCharacter`.
        
        // Let's rely on logic verification:
        // "ghbdtn?" -> token="ghbdtn", trailing="?"
        let s1 = monitor.splitBufferContent("ghbdtn?")
        XCTAssertEqual(s1.token, "ghbdtn")
        XCTAssertEqual(s1.trailing, "?")
        
        // ".rfr" -> leading=".", token="rfr"
        let s2 = monitor.splitBufferContent(".rfr")
        XCTAssertEqual(s2.leading, ".")
        XCTAssertEqual(s2.token, "rfr")
    }
    
    // MARK: - Issue #6: Technical Text Protection
    
    func testIssue6_UnixPath() async {
        let path = "/tmp/example/file.swift"
        // This is sent as one token if typed fast, or constructed char by char.
        // Engine receives the token.
        let res = await engine.correctText(path, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(res.corrected, "Unix path should NOT be corrected")
    }
    
    func testIssue6_UUID() async {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let res = await engine.correctText(uuid, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(res.corrected, "UUID should NOT be corrected")
    }
    
    func testIssue6_Version() async {
        let ver = "v1.2.3"
        let res = await engine.correctText(ver, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(res.corrected, "Version string should NOT be corrected")
    }
    
    // MARK: - Issue #7: Numbers
    
    func testIssue7_Time() async {
        let time = "15:00"
        let res = await engine.correctText(time, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(res.corrected)
    }
    
    func testIssue7_Date() async {
        let date = "25.12.2024"
        let res = await engine.correctText(date, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(res.corrected)
    }
    
    // MARK: - Issue #8: Metadata/Emoji
    
    func testIssue8_Emoji() async {
        let text = "🙂"
        let res = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(res.corrected)
    }
    
    @MainActor
    func testIssue8_Guillemets() async {
        // "«ghbdtn»"
        // Monitor separates quotes?
        // If passed as token:
        let token = "«ghbdtn»"
        // Router should handle it.
        // But `splitBufferContent` usually strips quotes as delimiters?
        // Let's check splitting
        let parts = monitor.splitBufferContent("«ghbdtn»")
        // If quotes are delimiters:
        if !parts.leading.isEmpty {
            // It was split.
            // Then we correct the inner token "ghbdtn"
            let res = await engine.correctText(parts.token, phraseBuffer: "", expectedLayout: nil)
            XCTAssertEqual(res.corrected, "привет")
        } else {
            // Passed as one token
            let res = await engine.correctText(token, phraseBuffer: "", expectedLayout: nil)
            XCTAssertEqual(res.corrected, "«привет»")
        }
    }
}
