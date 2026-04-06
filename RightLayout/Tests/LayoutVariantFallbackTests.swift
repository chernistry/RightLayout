import XCTest
@testable import RightLayout

/// Regression tests for layout-variant fallback conversions (RU/HE).
/// These validate that RightLayout can recover text typed in a *different* RU/HE layout variant
/// than the one currently configured/detected in `activeLayouts`.
final class LayoutVariantFallbackTests: XCTestCase {
    func testConvertAllVariants_RussianPhoneticToEnglish_RecoversHello() throws {
        let mapper = LayoutMapper.shared

        // Simulate: user intended "hello" (EN US), but had Russian Phonetic active.
        guard let typedOnRuPhonetic = mapper.convertBest("hello", fromLayout: "us", toLayout: "russian_phonetic") else {
            XCTFail("Failed to generate RU phonetic typed text for 'hello'")
            return
        }

        // Misconfigured/detected layouts: RU is set to russianwin (not phonetic).
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]

        let variants = mapper.convertAllVariants(typedOnRuPhonetic, from: .russian, to: .english, activeLayouts: activeLayouts)
        XCTAssertTrue(
            variants.contains(where: { $0.result == "hello" }),
            "Expected to recover 'hello' from RU phonetic input; got: \(variants.map { $0.result })"
        )
    }

    func testConvertAllVariants_HebrewMacToEnglish_RecoversHello_WhenConfiguredQwerty() throws {
        let mapper = LayoutMapper.shared

        // Simulate: user intended "hello" (EN US), but had Hebrew (Mac) active.
        guard let typedOnHebrewMac = mapper.convertBest("hello", fromLayout: "us", toLayout: "hebrew") else {
            XCTFail("Failed to generate HE(Mac) typed text for 'hello'")
            return
        }

        // Misconfigured/detected layouts: HE is set to hebrew_qwerty (not Mac Hebrew).
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]

        let variants = mapper.convertAllVariants(typedOnHebrewMac, from: .hebrew, to: .english, activeLayouts: activeLayouts)
        XCTAssertTrue(
            variants.contains(where: { $0.result == "hello" }),
            "Expected to recover 'hello' from HE(Mac) input; got: \(variants.map { $0.result })"
        )
    }

    func testConvertAllVariants_HebrewQwertyToEnglish_RecoversHello_WhenConfiguredMac() throws {
        let mapper = LayoutMapper.shared

        // Simulate: user intended "hello" (EN US), but had Hebrew QWERTY active.
        guard let typedOnHebrewQwerty = mapper.convertBest("hello", fromLayout: "us", toLayout: "hebrew_qwerty") else {
            XCTFail("Failed to generate HE(QWERTY) typed text for 'hello'")
            return
        }

        // Misconfigured/detected layouts: HE is set to hebrew (Mac), not QWERTY.
        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew"]

        let variants = mapper.convertAllVariants(typedOnHebrewQwerty, from: .hebrew, to: .english, activeLayouts: activeLayouts)
        XCTAssertTrue(
            variants.contains(where: { $0.result == "hello" }),
            "Expected to recover 'hello' from HE(QWERTY) input; got: \(variants.map { $0.result })"
        )
    }
}

