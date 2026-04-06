import XCTest
@testable import RightLayout

/// Test to reproduce the bug: mixed layout text produces garbage on hotkey
final class MixedLayoutBugTests: XCTestCase {
    var engine: CorrectionEngine!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        engine = CorrectionEngine(settings: settings)
    }
    
    @MainActor
    func testMixedLayoutTextProducesGarbage() async throws {
        // User has text with BOTH correct Russian AND wrong-layout text
        // Example: "Привет ghbdtn" (Russian + English-layout Russian)
        
        let mixedInputs = [
            "Привет ghbdtn",           // Russian + wrong layout
            "Hello привет",             // English + Russian
            "Тест test тест",           // Mixed
            "ghbdtn Привет vbh",        // wrong + correct + wrong
        ]
        
        for input in mixedInputs {
            await engine.resetCycling()
            
            print("\n=== Testing: '\(input)' ===")
            
            // First correction
            let first = await engine.correctLastWord(input)
            print("First: '\(first ?? "nil")' (len: \(first?.count ?? 0))")
            
            // Cycle multiple times and track what happens
            var results: [String] = []
            if let f = first { results.append(f) }
            
            for i in 1...5 {
                let cycled = await engine.cycleCorrection()
                if let c = cycled {
                    results.append(c)
                    print("Cycle \(i): '\(c)' (len: \(c.count))")
                    
                    // BUG CHECK: length should be reasonable
                    if c.count < 3 && input.count > 10 {
                        XCTFail("BUG: Output too short! Input: \(input.count) chars, Output: \(c.count) chars")
                    }
                    
                    // BUG CHECK: length should not grow unexpectedly
                    if c.count > input.count * 2 {
                        XCTFail("BUG: Output too long! Input: \(input.count) chars, Output: \(c.count) chars")
                    }
                }
            }
            
            // Check if lengths are consistent across cycles
            let lengths = results.map { $0.count }
            let uniqueLengths = Set(lengths)
            print("Unique lengths: \(uniqueLengths)")
        }
    }
    
    @MainActor
    func testCyclingLengthGrows() async throws {
        // Specific bug: each cycle makes text longer
        let input = "Привет ghbdtn"
        
        _ = await engine.correctLastWord(input)
        
        var previousLength = 0
        var growthCount = 0
        
        for i in 1...10 {
            if let cycled = await engine.cycleCorrection() {
                print("Cycle \(i): len=\(cycled.count) '\(cycled)'")
                
                if cycled.count > previousLength && previousLength > 0 {
                    growthCount += 1
                }
                previousLength = cycled.count
            }
        }
        
        // If length keeps growing, that's a bug
        XCTAssertLessThan(growthCount, 3, "BUG: Length keeps growing on each cycle!")
    }
    
    @MainActor
    func testSingleCharacterOutput() async throws {
        // Bug: output becomes single character
        let input = "Привет мир test"
        
        let result = await engine.correctLastWord(input)
        
        print("Input: '\(input)' (\(input.count) chars)")
        print("Output: '\(result ?? "nil")' (\(result?.count ?? 0) chars)")
        
        if let r = result {
            XCTAssertGreaterThan(r.count, 1, "BUG: Output is single character!")
            XCTAssertGreaterThan(r.count, input.count / 4, "BUG: Output way too short!")
        }
    }
}
