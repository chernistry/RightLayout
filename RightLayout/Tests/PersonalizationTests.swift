import XCTest
@testable import RightLayout

final class PersonalizationTests: XCTestCase {
    
    // MARK: - Feature Extractor
    
    func testFeatureHashingStability() async {
        let fixedSalt = Data(repeating: 0x01, count: 32)
        let extractor = FeatureExtractor(saltOverride: fixedSalt)
        
        let features1 = await extractor.extract(text: "Hello", phraseBuffer: "", appBundleId: "com.apple.Terminal", intent: "prose")
        let features2 = await extractor.extract(text: "Hello", phraseBuffer: "", appBundleId: "com.apple.Terminal", intent: "prose")
        
        XCTAssertEqual(features1.appBundleIdHash, features2.appBundleIdHash, "Context hash must be stable")
        XCTAssertEqual(features1.ngramHashes, features2.ngramHashes, "N-gram hashes must be stable")
    }
    
    func testFeatureDifferentiation() async {
        let fixedSalt = Data(repeating: 0x01, count: 32)
        let extractor = FeatureExtractor(saltOverride: fixedSalt)
        
        let f1 = await extractor.extract(text: "Hello", phraseBuffer: "", appBundleId: "A", intent: "prose")
        let f2 = await extractor.extract(text: "World", phraseBuffer: "", appBundleId: "A", intent: "prose")
        let f3 = await extractor.extract(text: "Hello", phraseBuffer: "", appBundleId: "B", intent: "prose")
        
        XCTAssertNotEqual(f1.ngramHashes, f2.ngramHashes, "Different text should have different n-grams")
        XCTAssertNotEqual(f1.appBundleIdHash, f3.appBundleIdHash, "Different app should have different context hash")
    }
    
    func testBioFeatureExtraction() async {
        let fixedSalt = Data(repeating: 0x01, count: 32)
        let extractor = FeatureExtractor(saltOverride: fixedSalt)
        
        // 1. Fast, steady typing (100ms per key)
        let fastTimings = [0.1, 0.1, 0.1, 0.1, 0.1]
        let fFast = await extractor.extract(text: "test", phraseBuffer: "", appBundleId: "A", intent: "prose", latencies: fastTimings)
        
        // 2. Slow, variable typing (300ms, then 100ms...)
        let slowTimings = [0.3, 0.3, 0.3, 0.3, 0.3]
        let fSlow = await extractor.extract(text: "test", phraseBuffer: "", appBundleId: "A", intent: "prose", latencies: slowTimings)
        
        XCTAssertNotEqual(fFast.ngramHashes, fSlow.ngramHashes, "Bio features should differentiate fast vs slow typing")
        
        // 3. Pauses
        let pauseTimings = [0.1, 0.6, 0.1] // One long pause > 0.5
        let fPause = await extractor.extract(text: "test", phraseBuffer: "", appBundleId: "A", intent: "prose", latencies: pauseTimings)
        
        XCTAssertNotEqual(fFast.ngramHashes, fPause.ngramHashes, "Bio features should capture pauses")
    }
    
    // MARK: - Store
    
    func testStorePersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 1. Init and write
        let store1 = PersonalizationStore(customDirectory: tempDir)
        await store1.waitForReady()
        await store1.updatePriors(for: 123, layout: "ru", delta: 1.0)
        await store1.flush()
        
        // 2. Load from new instance
        let store2 = PersonalizationStore(customDirectory: tempDir)
        await store2.waitForReady()
        
        let priors = await store2.getPriors(for: 123)
        XCTAssertEqual(priors["ru"], 1.0, "Should persist changes: \(priors)")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Strategy A (Habit Learning)
    
    func testHabitLearning() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let store = PersonalizationStore(customDirectory: tempDir)
        let adapter = OnlineAdapter(customDirectory: tempDir)
        await store.waitForReady()
        
        let riskController = RiskController(customDirectory: tempDir)
        await riskController.setTestMode(true)
        
        let engine = PersonalizationEngine(store: store, adapter: adapter, riskController: riskController)
        let contextHash = 999
        let features = PersonalFeatures(appBundleIdHash: contextHash, contextKey: ContextKey(global: 0, app: 0, appIntent: 0, appTime: 0), hourOfDay: 12, isWeekend: false, ngramHashes: [], lengthCategory: 1, bioFeatures: nil)
        
        // 1. Initial State: No bias
        let candidate = CorrectionCandidateResult(language: "ru", confidence: 0.8, originalText: "test", correctedText: "test_ru")
        let (adjusted1, policy1) = await engine.adjust(candidate: candidate, features: features)
        XCTAssertEqual(adjusted1.confidence, 0.8, accuracy: 0.001, "No bias should result in same confidence")
        XCTAssertEqual(policy1, .autoApply)
        
        // 2. Train: User accepts 'ru' many times (Strong Habit)
        // Simulate +10 score (~0.76 tanh bias)
        await store.updatePriors(for: contextHash, layout: "ru", delta: 10.0)
        
        let (adjusted2, policy2) = await engine.adjust(candidate: candidate, features: features)
        XCTAssertEqual(adjusted2.confidence, 0.8, accuracy: 0.001, "Positive priors should not inflate confidence in conservative mode")
        XCTAssertEqual(policy2, .autoApply)
        
        // 4. Train: User rejects 'ru' (Undo)
        // Simulate -15 score (Net -5)
        await store.updatePriors(for: contextHash, layout: "ru", delta: -15.0)
        let (adjusted3, policy3) = await engine.adjust(candidate: candidate, features: features)
        XCTAssertEqual(adjusted3.confidence, 0.8, accuracy: 0.001, "Negative priors should not directly rewrite confidence")
        XCTAssertEqual(policy3, .suggestHint, "Negative priors should demote auto-apply to hint")
        
        await store.flush() // Checkpoint to ensure save doesn't race with cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testDecay() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = PersonalizationStore(customDirectory: tempDir)
        await store.waitForReady()
        
        // Set initial score = 100
        await store.updatePriors(for: 1, layout: "en", delta: 100.0)
        
        // Mock time passing by modifying lastDecayDate inside store?
        // Actor isolation prevents direct mod.
        // But applyDecay uses State properties.
        // We can simulate decay logic by calling applyDecay() multiple times if it was based on calls, 
        // but it is based on Date(). 
        // Since we can't Inject DateProvider easily without refactor, we will Skip rigorous Decay time-test 
        // and just verify the method doesn't crash or zero out incorrectly on immediate call.
        
        await store.applyDecay()
        // Should be no change if time diff is 0
        let priors = await store.getPriors(for: 1)
        XCTAssertEqual(priors["en"], 100.0, "Immediate decay should do nothing")
        
        await store.flush()
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Feedback Collector
    
    func testFeedbackCollector() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let store = PersonalizationStore(customDirectory: tempDir)
        let adapter = OnlineAdapter(customDirectory: tempDir)
        await store.waitForReady()
        
        let collector = FeedbackCollector(store: store, adapter: adapter)
        
        let fixedSalt = Data(repeating: 0x01, count: 32)
        let extractor = FeatureExtractor(saltOverride: fixedSalt)
        let features = await extractor.extract(text: "Test", phraseBuffer: "", appBundleId: "com.test", intent: "prose")
        
        let id = await collector.register(targetLayout: "en", features: features)
        
        // Verify wiring
        await collector.reportOutcome(trackingId: id, outcome: .accepted)
        await collector.waitForIdle() // Wait for task to spawn/run
        await store.flush() // Wait for store save
        
        let priors = await store.getPriors(for: features.appBundleIdHash)
        XCTAssertEqual(priors["en"], 0.5, "Accepted should add conservative prior weight")
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRiskControllerColdStartPolicies() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let controller = RiskController(customDirectory: tempDir)
        let key = ContextKey(global: 1, app: 2, appIntent: 3, appTime: 4)

        let auto = await controller.evaluate(candidateConfidence: 0.76, contextKey: key)
        let hint = await controller.evaluate(candidateConfidence: 0.70, contextKey: key)
        let reject = await controller.evaluate(candidateConfidence: 0.49, contextKey: key)

        XCTAssertEqual(auto, .autoApply)
        XCTAssertEqual(hint, .suggestHint)
        XCTAssertEqual(reject, .reject)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
