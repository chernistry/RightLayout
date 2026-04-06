import XCTest
@testable import RightLayout

final class UserDictionaryTests: XCTestCase {
    var dictionary: UserDictionary!
    var tempURL: URL!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".json")
        dictionary = UserDictionary(storageURL: tempURL)
    }

    override func tearDown() async throws {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testAddAndLookup() async {
        let rule = UserDictionaryRule(
            token: "TestToken",
            matchMode: .exact,
            scope: .global,
            action: .keepAsIs,
            source: .manual
        )

        await dictionary.addRule(rule)

        let found = await dictionary.lookup("testtoken")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.token, "TestToken")
        XCTAssertEqual(found?.source, .manual)
    }

    func testAutoRejectDoesNotCreateLearnedRule() async {
        await dictionary.recordAutoReject(token: "UndoMe")
        let rule = await dictionary.lookup("UndoMe")
        XCTAssertNil(rule, "Conservative mode should not auto-create keepAsIs rules from undo signals")
    }

    func testManualApplyDoesNotCreateLearnedRule() async {
        await dictionary.recordManualApply(token: "ApplyMe", hypothesis: "enFromRuLayout")
        let rule = await dictionary.lookup("ApplyMe")
        XCTAssertNil(rule, "Conservative mode should not auto-create preferred hypotheses from manual cycles")
    }

    func testOverrideDoesNotDeleteManualRule() async {
        let rule = UserDictionaryRule(
            token: "ManualToken",
            action: .preferHypothesis("ruFromEnLayout"),
            source: .manual
        )
        await dictionary.addRule(rule)

        await dictionary.recordOverride(token: "ManualToken")

        let found = await dictionary.lookup("ManualToken")
        XCTAssertNotNil(found)
        if case .preferHypothesis(let hyp) = found?.action {
            XCTAssertEqual(hyp, "ruFromEnLayout")
        } else {
            XCTFail("Manual rule should remain intact")
        }
    }

    func testPersistenceRoundTripForManualRule() async {
        let rule = UserDictionaryRule(
            token: "Persist",
            action: .keepAsIs,
            source: .manual
        )
        await dictionary.addRule(rule)

        let reloaded = UserDictionary(storageURL: tempURL)
        let found = await reloaded.lookup("persist")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.source, .manual)
        XCTAssertEqual(found?.action, .keepAsIs)
    }
}
