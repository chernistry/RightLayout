import XCTest
@testable import RightLayout

@MainActor
final class UIWorkbenchModelTests: XCTestCase {
    func testAppStatusSnapshotBuildsCriticalAndInfoIssues() {
        let source = AppStatusSnapshot.Source(
            isEnabled: false,
            hasAccessibilityPermission: false,
            updateAvailableVersion: "1.2",
            isStatsCollectionEnabled: false,
            isStrictPrivacyMode: true,
            behaviorPresetTitle: "Balanced+",
            preferredLanguageTitle: "RU",
            activeLayouts: ["en": "us", "ru": "russianwin"],
            excludedAppsCount: 2,
            recentCorrectionDescription: "ghbdtn → привет"
        )

        let snapshot = AppStatusSnapshot.build(from: source)

        XCTAssertEqual(snapshot.runtimeTitle, "Blocked")
        XCTAssertEqual(snapshot.coverageSummary, "2 excluded apps")
        XCTAssertEqual(snapshot.recentCorrectionDescription, "ghbdtn → привет")
        XCTAssertTrue(snapshot.layoutSummary.contains("EN: us"))
        XCTAssertTrue(snapshot.issues.contains(where: { $0.title == "Accessibility required" && $0.severity == .critical }))
        XCTAssertTrue(snapshot.issues.contains(where: { $0.title == "Update available" && $0.severity == .info }))
        XCTAssertTrue(snapshot.issues.contains(where: { $0.title == "Runtime paused" && $0.severity == .warning }))
    }

    func testAppStatusSnapshotReadyStateHasNoBlockingIssue() {
        let source = AppStatusSnapshot.Source(
            isEnabled: true,
            hasAccessibilityPermission: true,
            updateAvailableVersion: nil,
            isStatsCollectionEnabled: true,
            isStrictPrivacyMode: false,
            behaviorPresetTitle: "Balanced+",
            preferredLanguageTitle: "EN",
            activeLayouts: ["en": "us"],
            excludedAppsCount: 0,
            recentCorrectionDescription: nil
        )

        let snapshot = AppStatusSnapshot.build(from: source)

        XCTAssertEqual(snapshot.runtimeTitle, "Ready")
        XCTAssertEqual(snapshot.coverageSummary, "All apps")
        XCTAssertTrue(snapshot.issues.isEmpty)
    }

    func testNavigationStateOpenUpdatesPaneAndDiagnosticsTab() {
        let navigation = SettingsNavigationState()

        navigation.open(.diagnostics, diagnosticsTab: .decisionLog)

        XCTAssertEqual(navigation.selectedPane, .diagnostics)
        XCTAssertEqual(navigation.selectedDiagnosticsTab, .decisionLog)
    }
}
