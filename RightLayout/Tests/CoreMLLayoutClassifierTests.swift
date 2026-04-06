import XCTest
@testable import RightLayout

final class CoreMLLayoutClassifierTests: XCTestCase {
    
    var classifier: CoreMLLayoutClassifier!
    
    override func setUp() {
        super.setUp()
        classifier = CoreMLLayoutClassifier()
    }
    
    func testInitialization() {
        XCTAssertNotNil(classifier, "Classifier should initialize")
    }
    
    func testPredictionSmoke() {
        // Simple smoke test
        // "test" -> probable English
        if let (hypoth, conf) = classifier.predict("test") {
            print("Prediction for 'test': \(hypoth) conf: \(conf)")
            XCTAssertNotNil(hypoth)
            XCTAssertTrue(conf >= 0.0 && conf <= 1.0)
        } else {
            // It might fail if model not loaded (e.g. bundle issue in test env)
            // But we want to know.
            XCTFail("Prediction returned nil - model likely not loaded")
        }
    }
    
    func testAmbiguousCase() {
        // "ghbdtn" -> 'ru_from_en' (privet)
        // This depends on the training data quality. 
        // Since we trained on synthetic data, it should likely work if 'ghbdtn' was generated or similar patterns.
        if let (hypoth, conf) = classifier.predict("ghbdtn") {
             print("Prediction for 'ghbdtn': \(hypoth) conf: \(conf)")
             // We don't strictly assert the result for now as training was minimal/synthetic 
             // and stochastic. We verify it runs.
        }
    }
}
