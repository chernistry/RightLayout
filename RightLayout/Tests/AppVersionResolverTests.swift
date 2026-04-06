import XCTest
@testable import RightLayout

final class AppVersionResolverTests: XCTestCase {
    func testEnvironmentVersionHasHighestPriority() {
        let resolved = AppVersionResolver.current(
            bundle: .main,
            environment: ["RIGHTLAYOUT_APP_VERSION": "9.8.7"],
            currentDirectory: "/tmp/nonexistent-rightlayout-version"
        )

        XCTAssertEqual(resolved, "9.8.7")
    }

    func testVersionFileOverridesBundleVersionForLocalRuns() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let versionFile = tempRoot.appendingPathComponent("VERSION")
        try "1.2".write(to: versionFile, atomically: true, encoding: .utf8)

        let resolved = AppVersionResolver.current(
            bundle: .main,
            environment: [:],
            currentDirectory: tempRoot.path
        )

        XCTAssertEqual(resolved, "1.2")
    }
}
