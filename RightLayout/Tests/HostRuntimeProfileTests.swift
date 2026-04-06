import XCTest
@testable import RightLayout

final class HostRuntimeProfileTests: XCTestCase {
    func testKnownGoodBlindBundleResolvesToBlindKnownGood() {
        let profile = HostRuntimeProfile.resolve(
            bundleId: "com.microsoft.VSCode",
            capabilities: AppEditCapabilities(
                supportsSelectedTextWrite: false,
                supportsSelectedRangeWrite: false,
                supportsValueWrite: false,
                supportsSelectionRead: false,
                supportsFullTextRead: false,
                isSecureOrReadBlind: true,
                capabilityClass: .blind,
                elementFingerprint: nil
            )
        )

        XCTAssertEqual(profile, .blindKnownGood)
        XCTAssertTrue(profile.allowsAutomaticBlindReplay)
        XCTAssertTrue(profile.switchSafeAfterBlindReplay)
    }

    func testUnknownBlindBundleResolvesToBlindUnknown() {
        let profile = HostRuntimeProfile.resolve(
            bundleId: "com.example.unknowneditor",
            capabilities: AppEditCapabilities(
                supportsSelectedTextWrite: false,
                supportsSelectedRangeWrite: false,
                supportsValueWrite: false,
                supportsSelectionRead: false,
                supportsFullTextRead: false,
                isSecureOrReadBlind: true,
                capabilityClass: .blind,
                elementFingerprint: nil
            )
        )

        XCTAssertEqual(profile, .blindUnknown)
        XCTAssertFalse(profile.allowsAutomaticBlindReplay)
        XCTAssertFalse(profile.switchSafeAfterBlindReplay)
        XCTAssertTrue(profile.allowsManualLastWordReplay)
    }

    func testSecureCapabilityResolvesToSecure() {
        let profile = HostRuntimeProfile.resolve(
            bundleId: "com.apple.SecurityAgent",
            capabilities: AppEditCapabilities(
                supportsSelectedTextWrite: false,
                supportsSelectedRangeWrite: false,
                supportsValueWrite: false,
                supportsSelectionRead: false,
                supportsFullTextRead: false,
                isSecureOrReadBlind: true,
                capabilityClass: .secure,
                elementFingerprint: nil
            )
        )

        XCTAssertEqual(profile, .secure)
        XCTAssertFalse(profile.allowsManualLastWordReplay)
        XCTAssertFalse(profile.allowsManualSelectionClipboardFallback)
    }
}
