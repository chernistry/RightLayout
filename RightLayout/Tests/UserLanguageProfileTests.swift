import XCTest
@testable import RightLayout

final class UserLanguageProfileTests: XCTestCase {
    var profile: UserLanguageProfile!
    var tempURL: URL!
    
    override func setUp() async throws {
        // Use temporary file for testing
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        profile = UserLanguageProfile(persistenceURL: tempURL)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        profile = nil
    }
    
    func testInitialThresholdNoAdjustment() async {
        // Without any data, should return base confidence unchanged
        let adjusted = await profile.adjustThreshold(
            for: "test",
            lastLanguage: .english,
            baseConfidence: 0.6
        )
        XCTAssertEqual(adjusted, 0.6, accuracy: 0.001)
    }
    
    func testLowAcceptanceRaisesThreshold() async {
        let context = ProfileContext(token: "tes", lastLanguage: .english)
        
        // Record mostly rejections (25% acceptance rate)
        await profile.record(context: context, outcome: .reverted, hypothesis: .ru)
        await profile.record(context: context, outcome: .reverted, hypothesis: .ru)
        await profile.record(context: context, outcome: .reverted, hypothesis: .ru)
        await profile.record(context: context, outcome: .accepted, hypothesis: .ru)
        
        // Should raise threshold due to low acceptance
        let adjusted = await profile.adjustThreshold(
            for: "test",
            lastLanguage: .english,
            baseConfidence: 0.6
        )
        XCTAssertGreaterThan(adjusted, 0.6)
        XCTAssertLessThanOrEqual(adjusted, 0.72) // 0.6 * 1.2 = 0.72
    }
    
    func testHighAcceptanceLowersThreshold() async {
        let context = ProfileContext(token: "goo", lastLanguage: .russian)
        
        // Record mostly acceptances (80% acceptance rate)
        await profile.record(context: context, outcome: .accepted, hypothesis: .ruFromEnLayout)
        await profile.record(context: context, outcome: .accepted, hypothesis: .ruFromEnLayout)
        await profile.record(context: context, outcome: .accepted, hypothesis: .ruFromEnLayout)
        await profile.record(context: context, outcome: .accepted, hypothesis: .ruFromEnLayout)
        await profile.record(context: context, outcome: .reverted, hypothesis: .ruFromEnLayout)
        
        // Should lower threshold due to high acceptance
        let adjusted = await profile.adjustThreshold(
            for: "good",
            lastLanguage: .russian,
            baseConfidence: 0.7
        )
        XCTAssertLessThan(adjusted, 0.7)
        XCTAssertGreaterThanOrEqual(adjusted, 0.3) // Floor at 0.3
    }
    
    func testMediumAcceptanceNoChange() async {
        let context = ProfileContext(token: "mid", lastLanguage: nil)
        
        // Record 50-50 split (50% acceptance)
        await profile.record(context: context, outcome: .accepted, hypothesis: .en)
        await profile.record(context: context, outcome: .accepted, hypothesis: .en)
        await profile.record(context: context, outcome: .reverted, hypothesis: .en)
        await profile.record(context: context, outcome: .reverted, hypothesis: .en)
        
        // Should not adjust (medium acceptance 30-70%)
        let adjusted = await profile.adjustThreshold(
            for: "middle",
            lastLanguage: nil,
            baseConfidence: 0.65
        )
        XCTAssertEqual(adjusted, 0.65, accuracy: 0.001)
    }
    
    func testMinSamplesRequired() async {
        let context = ProfileContext(token: "few", lastLanguage: .hebrew)
        
        // Record only 2 samples (below minSamples = 3)
        await profile.record(context: context, outcome: .reverted, hypothesis: .he)
        await profile.record(context: context, outcome: .reverted, hypothesis: .he)
        
        // Should not adjust due to insufficient samples
        let adjusted = await profile.adjustThreshold(
            for: "few",
            lastLanguage: .hebrew,
            baseConfidence: 0.6
        )
        XCTAssertEqual(adjusted, 0.6, accuracy: 0.001)
    }
    
    func testManualCountsAsAccepted() async {
        let context = ProfileContext(token: "man", lastLanguage: .english)
        
        // Manual corrections should count as acceptance
        await profile.record(context: context, outcome: .manual, hypothesis: .ruFromEnLayout)
        await profile.record(context: context, outcome: .manual, hypothesis: .ruFromEnLayout)
        await profile.record(context: context, outcome: .manual, hypothesis: .ruFromEnLayout)
        
        let stats = await profile.getStats(for: context)
        XCTAssertEqual(stats?.accepted, 3)
        XCTAssertEqual(stats?.reverted, 0)
    }
    
    func testClearAll() async {
        let context = ProfileContext(token: "clr", lastLanguage: nil)
        
        await profile.record(context: context, outcome: .accepted, hypothesis: .en)
        await profile.record(context: context, outcome: .accepted, hypothesis: .en)
        
        // Verify data exists
        var stats = await profile.getStats(for: context)
        XCTAssertNotNil(stats)
        
        // Clear and verify
        await profile.clearAll()
        stats = await profile.getStats(for: context)
        XCTAssertNil(stats)
    }
    
    func testPersistenceRoundtrip() async throws {
        let context = ProfileContext(token: "per", lastLanguage: .russian)
        
        // Record some data
        await profile.record(context: context, outcome: .accepted, hypothesis: .ru)
        await profile.record(context: context, outcome: .accepted, hypothesis: .ru)
        await profile.record(context: context, outcome: .reverted, hypothesis: .ru)
        
        // Save
        await profile.save()
        
        // Create new profile instance loading from same file
        let loadedProfile = UserLanguageProfile(persistenceURL: tempURL)
        
        // Give it time to load
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Verify loaded data matches
        let loadedStats = await loadedProfile.getStats(for: context)
        XCTAssertEqual(loadedStats?.accepted, 2)
        XCTAssertEqual(loadedStats?.reverted, 1)
    }
    
    func testProfileContext() {
        // Test that ProfileContext uses first 3 chars
        let ctx1 = ProfileContext(token: "hello", lastLanguage: .english)
        XCTAssertEqual(ctx1.prefix, "hel")
        
        let ctx2 = ProfileContext(token: "ab", lastLanguage: .russian)
        XCTAssertEqual(ctx2.prefix, "ab")
        
        // Test case insensitivity
        let ctx3 = ProfileContext(token: "HeLLo", lastLanguage: .english)
        XCTAssertEqual(ctx3.prefix, "hel")
        
        // Same prefix + lang should equal
        XCTAssertEqual(ctx1, ctx3)
    }
}
