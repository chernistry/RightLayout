import XCTest
@testable import RightLayout

final class UpdateCheckerTests: XCTestCase {
    
    // MARK: - Version Comparison Tests
    
    func test_version_comparison_simple_ascending() {
        // Test: 1.0 < 1.1
        Task {
            let checker = UpdateChecker.shared
            let result = await checker.compareVersions("1.0", "1.1")
            XCTAssertEqual(result, .orderedAscending)
        }
    }
    
    func test_version_comparison_simple_descending() {
        // Test: 2.0 > 1.9
        Task {
            let checker = UpdateChecker.shared
            let result = await checker.compareVersions("2.0", "1.9")
            XCTAssertEqual(result, .orderedDescending)
        }
    }
    
    func test_version_comparison_equal() {
        // Test: 1.2 == 1.2
        Task {
            let checker = UpdateChecker.shared
            let result = await checker.compareVersions("1.2", "1.2")
            XCTAssertEqual(result, .orderedSame)
        }
    }
    
    func test_version_comparison_multi_digit() {
        // Test: 1.10 > 1.9 (numeric comparison, not string)
        Task {
            let checker = UpdateChecker.shared
            let result = await checker.compareVersions("1.9", "1.10")
            XCTAssertEqual(result, .orderedAscending)
        }
    }
    
    func test_version_comparison_different_length() {
        // Test: 1.0 < 1.0.1
        Task {
            let checker = UpdateChecker.shared
            let result = await checker.compareVersions("1.0", "1.0.1")
            XCTAssertEqual(result, .orderedAscending)
        }
    }
    
    func test_version_comparison_major_version() {
        // Test: 2.0 > 1.99
        Task {
            let checker = UpdateChecker.shared
            let result = await checker.compareVersions("1.99", "2.0")
            XCTAssertEqual(result, .orderedAscending)
        }
    }
    
    // MARK: - GitHub API Parsing Tests
    
    func test_github_api_parsing_valid_json() throws {
        let json = """
        {
            "tag_name": "v1.5",
            "html_url": "https://github.com/chernistry/rightlayout/releases/tag/v1.5",
            "body": "## What's New\\n- Bug fixes\\n- Performance improvements",
            "assets": [
                {
                    "name": "RightLayout-1.5.pkg",
                    "browser_download_url": "https://github.com/chernistry/rightlayout/releases/download/v1.5/RightLayout-1.5.pkg"
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        XCTAssertEqual(release.tagName, "v1.5")
        XCTAssertEqual(release.version, "1.5")
        XCTAssertEqual(release.htmlURL, "https://github.com/chernistry/rightlayout/releases/tag/v1.5")
        XCTAssertNotNil(release.body)
        XCTAssertEqual(release.assets.count, 1)
        XCTAssertEqual(release.assets.first?.name, "RightLayout-1.5.pkg")
        XCTAssertNotNil(release.pkgDownloadURL)
        XCTAssertEqual(release.pkgDownloadURL?.absoluteString, "https://github.com/chernistry/rightlayout/releases/download/v1.5/RightLayout-1.5.pkg")
    }
    
    func test_github_api_parsing_no_pkg_asset() throws {
        let json = """
        {
            "tag_name": "v1.5",
            "html_url": "https://github.com/chernistry/rightlayout/releases/tag/v1.5",
            "body": null,
            "assets": [
                {
                    "name": "RightLayout-1.5.dmg",
                    "browser_download_url": "https://github.com/chernistry/rightlayout/releases/download/v1.5/RightLayout-1.5.dmg"
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        XCTAssertNil(release.pkgDownloadURL, "Should be nil when no .pkg asset exists")
        XCTAssertNotNil(release.releasesPageURL, "Fallback to releases page should exist")
    }
    
    func test_github_api_parsing_version_without_v_prefix() throws {
        let json = """
        {
            "tag_name": "1.5",
            "html_url": "https://github.com/chernistry/rightlayout/releases/tag/1.5",
            "body": "",
            "assets": []
        }
        """
        
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        XCTAssertEqual(release.version, "1.5", "Should handle version without 'v' prefix")
    }
    
    func test_github_api_parsing_empty_assets() throws {
        let json = """
        {
            "tag_name": "v1.5",
            "html_url": "https://github.com/chernistry/rightlayout/releases/tag/v1.5",
            "body": "Release notes",
            "assets": []
        }
        """
        
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        XCTAssertEqual(release.assets.count, 0)
        XCTAssertNil(release.pkgDownloadURL)
    }
    
    // MARK: - UpdateResult Tests
    
    func test_update_result_is_update_available() {
        let release = GitHubRelease(
            tagName: "v1.5",
            htmlURL: "https://example.com",
            body: nil,
            assets: []
        )
        
        let result = UpdateResult.updateAvailable(release: release)
        
        if case .updateAvailable(let r) = result {
            XCTAssertEqual(r.version, "1.5")
        } else {
            XCTFail("Expected updateAvailable case")
        }
    }
    
    func test_update_result_up_to_date() {
        let result = UpdateResult.upToDate
        
        if case .upToDate = result {
            // Success
        } else {
            XCTFail("Expected upToDate case")
        }
    }
    
    func test_update_result_error() {
        let result = UpdateResult.error(.networkUnavailable)
        
        if case .error(let error) = result {
            XCTAssertEqual(error.localizedDescription, "No internet connection. Please check your network and try again.")
        } else {
            XCTFail("Expected error case")
        }
    }
    
    // MARK: - UpdateError Tests
    
    func test_update_error_descriptions() {
        XCTAssertEqual(UpdateError.networkUnavailable.localizedDescription, "No internet connection. Please check your network and try again.")
        XCTAssertEqual(UpdateError.rateLimited.localizedDescription, "GitHub API rate limit exceeded. Please try again later.")
        XCTAssertEqual(UpdateError.invalidResponse.localizedDescription, "Invalid response from GitHub. Please try again later.")
        XCTAssertEqual(UpdateError.decodingFailed("test").localizedDescription, "Failed to parse update information: test")
        XCTAssertEqual(UpdateError.unknown("test error").localizedDescription, "An error occurred: test error")
    }
    
    // MARK: - Settings Persistence Tests
    
    @MainActor
    func test_settings_persistence_auto_check() {
        let settings = SettingsManager.shared
        
        // Save original value
        let original = settings.checkForUpdatesAutomatically
        
        // Toggle and verify
        settings.checkForUpdatesAutomatically = false
        XCTAssertFalse(settings.checkForUpdatesAutomatically)
        
        settings.checkForUpdatesAutomatically = true
        XCTAssertTrue(settings.checkForUpdatesAutomatically)
        
        // Restore original
        settings.checkForUpdatesAutomatically = original
    }
    
    @MainActor
    func test_settings_persistence_last_check_date() {
        let settings = SettingsManager.shared
        
        // Save original value
        let original = settings.lastUpdateCheckDate
        
        // Set and verify
        let testDate = Date()
        settings.lastUpdateCheckDate = testDate
        
        XCTAssertNotNil(settings.lastUpdateCheckDate)
        XCTAssertEqual(settings.lastUpdateCheckDate?.timeIntervalSince1970 ?? 0, testDate.timeIntervalSince1970, accuracy: 1.0)
        
        // Restore original
        settings.lastUpdateCheckDate = original
    }
    
    // MARK: - UpdateState Tests
    
    @MainActor
    func test_update_state_is_update_available() {
        let state = UpdateState.shared
        
        // Initially no result
        XCTAssertFalse(state.isUpdateAvailable)
        XCTAssertNil(state.availableRelease)
        XCTAssertNil(state.latestVersion)
    }
    
    @MainActor
    func test_update_state_with_available_update() {
        let state = UpdateState.shared
        
        let release = GitHubRelease(
            tagName: "v2.0",
            htmlURL: "https://example.com",
            body: "New version",
            assets: [
                GitHubRelease.Asset(
                    name: "RightLayout-2.0.pkg",
                    browserDownloadURL: "https://example.com/RightLayout-2.0.pkg"
                )
            ]
        )
        
        state.lastResult = .updateAvailable(release: release)
        
        XCTAssertTrue(state.isUpdateAvailable)
        XCTAssertEqual(state.latestVersion, "2.0")
        XCTAssertNotNil(state.downloadURL)
    }
    
    @MainActor
    func test_update_state_when_up_to_date() {
        let state = UpdateState.shared
        
        state.lastResult = .upToDate
        
        XCTAssertFalse(state.isUpdateAvailable)
        XCTAssertNil(state.availableRelease)
        XCTAssertNil(state.latestVersion)
    }
}
