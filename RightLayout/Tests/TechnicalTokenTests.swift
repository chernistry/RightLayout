import XCTest
@testable import RightLayout

final class TechnicalTokenTests: XCTestCase {
    
    // Helper to access the nonisolated method
    @MainActor
    private func check(_ token: String) -> Bool {
        let settings = SettingsManager.shared
        let router = ConfidenceRouter(settings: settings)
        return router.isTechnicalToken(token)
    }

    @MainActor
    func testGitHashes() {
        let hashes = [
            "a1b2c3d", // 7 chars
            "a1b2c3d4e5f6",
            "d7a8f2c3e4b5a6c7d8e9f0a1b2c3d4e5f6a7b8c9" // 40 chars
        ]
        
        for hash in hashes {
            XCTAssertTrue(check(hash), "Failed to detect git hash: \(hash)")
        }
        
        // Should NOT match simple words
        XCTAssertFalse(check("abcdefg")) // 7 chars, all letters - might be a hash but also a weird word. 
        // Real hashes usually mixed numbers/letters. 
        // If "abcdefg", technically hex, but very ambiguous. 
        // We should probably require at least one digit for short hashes?
        
        XCTAssertFalse(check("hello"))
    }
    
    @MainActor
    func testUUIDs() {
        let uuids = [
            "123e4567-e89b-12d3-a456-426614174000",
            "123E4567-E89B-12D3-A456-426614174000", // Uppercase
            "123e4567e89b12d3a456426614174000" // Dashless
        ]
        
        for uuid in uuids {
            XCTAssertTrue(check(uuid), "Failed to detect UUID: \(uuid)")
        }
    }
    
    @MainActor
    func testBase64() {
        // High entropy, ends with =
        let tokens = [
            "SGVsbG8gV29ybGQ=",
            "VGhpcyBpcyBhIHRlc3Q==",
            "c29tZV_23r+value=" // url safe?
        ]
        
        for token in tokens {
            XCTAssertTrue(check(token), "Failed to detect Base64: \(token)")
        }
    }
}
