import XCTest
@testable import RightLayout

final class HebrewQwertyCollisionTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
    }

    func testHebrewQwertyCollisionPrefersEnglishForNahInAutomaticMode() async throws {
        let settings = await MainActor.run { SettingsManager.shared }
        let router = ConfidenceRouter(settings: settings)

        let token = "נאה" // "nah" typed on Hebrew-QWERTY
        let decision = await router.route(token: token, context: DetectorContext(lastLanguage: nil), mode: .automatic)

        XCTAssertEqual(decision.layoutHypothesis, .enFromHeLayout)
        XCTAssertEqual(decision.language, .english)
        XCTAssertGreaterThanOrEqual(decision.confidence, 0.70)
    }

    func testHebrewQwertyCollisionPrefersEnglishForGGInManualMode() async throws {
        let settings = await MainActor.run { SettingsManager.shared }
        let router = ConfidenceRouter(settings: settings)

        let token = "גג" // "gg" typed on Hebrew-QWERTY (also valid Hebrew word)
        let decision = await router.route(token: token, context: DetectorContext(lastLanguage: nil), mode: .manual)

        XCTAssertEqual(decision.layoutHypothesis, .enFromHeLayout)
        XCTAssertEqual(decision.language, .english)
        XCTAssertGreaterThanOrEqual(decision.confidence, 0.70)
    }

    func testCyrillicGibberishPrefersEnglishOverHebrew() async throws {
        let settings = await MainActor.run { SettingsManager.shared }
        let router = ConfidenceRouter(settings: settings)

        let token = "руддщ" // "hello" typed on RU layout
        let decision = await router.route(token: token, context: DetectorContext(lastLanguage: nil), mode: .automatic)

        XCTAssertEqual(decision.layoutHypothesis, .enFromRuLayout)
        XCTAssertEqual(decision.language, .english)
    }

    func testPureCyrillicValidRussianWordIsNotCorrectedToEnglish() async throws {
        let settings = await MainActor.run { SettingsManager.shared }
        let router = ConfidenceRouter(settings: settings)

        let token = "люблю"
        let decision = await router.route(token: token, context: DetectorContext(lastLanguage: nil), mode: .automatic)

        XCTAssertEqual(decision.layoutHypothesis, .ru)
        XCTAssertEqual(decision.language, .russian)
        XCTAssertGreaterThanOrEqual(decision.confidence, 0.70)
    }

    func testDarlingTypedInRussianLayoutPrefersEnglishOverHebrew() async throws {
        let settings = await MainActor.run { SettingsManager.shared }
        let router = ConfidenceRouter(settings: settings)

        let token = "вфкдштп" // "darling" typed on RU layout
        let decision = await router.route(token: token, context: DetectorContext(lastLanguage: .russian), mode: .automatic)

        XCTAssertEqual(decision.layoutHypothesis, .enFromRuLayout)
        XCTAssertEqual(decision.language, .english)
        XCTAssertGreaterThanOrEqual(decision.confidence, 0.70)
    }
}
