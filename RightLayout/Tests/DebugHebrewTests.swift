
import Foundation
@testable import RightLayout

// Manual mock of LanguageDataConfig since we can't easily import the app module in a script without build
// But we can try to run this via 'swift run' if we add it to targets?
// No, easiest is to use 'swift repl' or just rely on 'swift run' if I add a target.
// Or I can copy the relevant files?
// Better: Write a new test file in 'tests/UnitTests' and run it via 'swift test'.
// But 'swift test' runs all tests.
// I'll create 'Sources/DebugTool/main.swift' and run it?
// No, the project structure is tailored.

// Let's create a temporary test case in `RightLayoutTests` that prints to stdout.
// Then run `swift test --filter DebugHebrew`.

import XCTest
@testable import RightLayout

final class DebugHebrewTests: XCTestCase {
    func testMapping() async {
        print("--- DEBUG START ---")
        let mapper = LayoutMapper.shared
        let config = LanguageDataConfig.shared
        
        let text = "kt"
        print("Input: '\(text)'")
        
        let heWords = config.hebrewCommonShortWords
        print("Hebrew Words count: \(heWords.count)")
        print("Contains 'לא' (lamed aleph)? \(heWords.contains("לא"))")
        
        let variants = mapper.convertAllVariants(text, from: .english, to: .hebrew)
        print("Variants count: \(variants.count)")
        for v in variants {
            print("Variant: \(v.layout) -> '\(v.result)'")
            if heWords.contains(v.result) {
                print("  MATCH FOUND!")
            }
        }
        
        let text2 = "fi" // ken
        print("Input: '\(text2)'")
        let variants2 = mapper.convertAllVariants(text2, from: .english, to: .hebrew)
        for v in variants2 {
            print("Variant: \(v.layout) -> '\(v.result)'")
             if heWords.contains(v.result) {
                print("  MATCH FOUND!")
            }
        }
        
        print("--- DEBUG END ---")
    }
}
