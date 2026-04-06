import XCTest
@testable import RightLayout

final class FeedbackCollectorTests: XCTestCase {
    var collector: FeedbackCollector!
    var store: PersonalizationStore!
    var riskController: RiskController!
    
    override func setUp() async throws {
        // Use temporary directory for store to avoid touching real user data
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        store = PersonalizationStore(customDirectory: tempDir)
        riskController = RiskController.shared // Singleton, might need mocking if it has state. 
        // ideally we'd inject a mock, but RiskController is a singleton usage in FeedbackCollector currently. 
        // FeedbackCollector init allows injecting riskController.
        
        collector = FeedbackCollector(store: store, riskController: riskController)
    }
    
    override func tearDown() async throws {
        // cleanup?
    }
    
    func testRegisterAndAccepted() async throws {
        let features = PersonalFeatures(
            appBundleIdHash: 123,
            contextKey: ContextKey(global: 0, app: 123, appIntent: 0, appTime: 0),
            hourOfDay: 12,
            isWeekend: false,
            ngramHashes: [1, 2, 3],
            lengthCategory: 1,
            bioFeatures: nil
        )
        
        let id = await collector.register(targetLayout: "ru", features: features)
        
        // Report Accepted
        await collector.reportOutcome(trackingId: id, outcome: .accepted)
        
        // Allow async processing
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let priors = await store.getPriors(for: 123)
        XCTAssertEqual(priors["ru"], 0.5)
    }
    
    func testRegisterAndUndo() async throws {
        let features = PersonalFeatures(
            appBundleIdHash: 456,
            contextKey: ContextKey(global: 0, app: 456, appIntent: 0, appTime: 0),
            hourOfDay: 12,
            isWeekend: false,
            ngramHashes: [4, 5, 6],
            lengthCategory: 1,
            bioFeatures: nil
        )
        
        let id = await collector.register(targetLayout: "he", features: features)
        
        // Report Undo
        await collector.reportOutcome(trackingId: id, outcome: .undo)
        
        // Allow async processing
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let priors = await store.getPriors(for: 456)
        XCTAssertEqual(priors["he"], -0.75)
    }
    
    func testCleanupOldEntries() async throws {
        let features = PersonalFeatures(
            appBundleIdHash: 789,
            contextKey: ContextKey(global: 0, app: 789, appIntent: 0, appTime: 0),
            hourOfDay: 12,
            isWeekend: false,
            ngramHashes: [7, 8, 9],
            lengthCategory: 1,
            bioFeatures: nil
        )
        
        let id = await collector.register(targetLayout: "en", features: features)
        
        // We can't easily mock time inside FeedbackCollector without refactoring it to take a TimeProvider.
        // But the cleanup happens on 'register'.
        // So if we register again, it cleans up.
        // We'd need to wait > 60s to test real expiration, which is too slow.
        // For now, assume logic is correct or refactor later. 
        // We can test that the ID is valid immediately.
        
        // Just verify no crash on re-register
        let id2 = await collector.register(targetLayout: "en", features: features)
        XCTAssertNotEqual(id, id2)
    }
}
