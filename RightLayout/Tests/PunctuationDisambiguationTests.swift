import XCTest
@testable import RightLayout

final class PunctuationDisambiguationTests: XCTestCase {
    var engine: CorrectionEngine!
    var settings: SettingsManager!

    override func setUp() async throws {
        let settings = await SettingsManager.shared
        self.settings = settings
        engine = CorrectionEngine(settings: settings)

        await MainActor.run {
            settings.isEnabled = true
            settings.activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]
            settings.isLearningEnabled = false
            // Keep thresholds permissive for deterministic unit tests.
            settings.standardPathThreshold = 0.4
        }
    }

    override func tearDown() async throws {
        engine = nil
        settings = nil
    }

    func testPunctuationAsSeparatorIsPreserved() async throws {
        let result = await engine.correctText("ghbdtn.rfr", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "привет.как")
    }

    func testPunctuationAsMappedLettersIsConverted() async throws {
        let result = await engine.correctText("epyf.n", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "узнают")
    }

    func testSemicolonAndDotAsMappedLettersIsConverted() async throws {
        let result = await engine.correctText("cj;fktyb.", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "сожалению")
    }

    func testPhraseKSozhaleniyuCorrectsPendingPrepositionAndWord() async throws {
        await MainActor.run {
            settings.standardPathThreshold = 0.65
        }

        let first = await engine.correctText("r", phraseBuffer: "", expectedLayout: nil)
        XCTAssertNil(first.corrected)
        XCTAssertNil(first.pendingCorrection)

        let second = await engine.correctText("cj;fktyb.", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(second.corrected, "сожалению")
        XCTAssertNil(second.pendingCorrection)
        XCTAssertNil(second.pendingOriginal)

        // Single-letter/preposition auto is intentionally disabled in the
        // reliability-first baseline; the manual path still needs to remain
        // available and precise.
        let manualPreposition = await engine.correctLastWord("r")
        XCTAssertEqual(manualPreposition, "к")

        let manualWord = await engine.correctLastWord("cj;fktyb.")
        XCTAssertEqual(manualWord, "сожалению")
    }

    func testLeadingCommaCanBeMappedLetter() async throws {
        let result = await engine.correctText(",tp", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "без")
    }

    func testManualSelectionUsesSmartSegmentation() async throws {
        // Hotkey correction path uses smart per-segment correction before whole-text fallbacks.
        let corrected = await engine.correctLastWord("ghbdtn.rfr ltkf")
        XCTAssertEqual(corrected, "привет.как дела")
    }

    func testVsConvertedInRussianSentenceContext() async throws {
        _ = await engine.correctText("vtyz", phraseBuffer: "", expectedLayout: nil) // "меня"
        _ = await engine.correctText("tcnm", phraseBuffer: "", expectedLayout: nil) // "есть"
        let result = await engine.correctText("vs", phraseBuffer: "", expectedLayout: nil) // "мы"
        XCTAssertNil(result.corrected)
        XCTAssertNotEqual(result.action, .applied)

        let manual = await engine.correctLastWord("vs")
        XCTAssertEqual(manual, "мы")
    }

    func testLtkfConvertsToDela() async throws {
        let result = await engine.correctText("ltkf", phraseBuffer: "", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "дела")
    }

    func testRouterConfidenceForLtkfManual() async throws {
        let router = ConfidenceRouter(settings: settings)
        let ctx = DetectorContext(lastLanguage: nil)
        let manual = await router.route(token: "ltkf", context: ctx, mode: .manual)
        XCTAssertEqual(manual.layoutHypothesis, .ruFromEnLayout)
        XCTAssertGreaterThanOrEqual(manual.confidence, 0.25)
    }
}
