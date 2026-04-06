import XCTest
@testable import RightLayout

final class IntentDetectorTests: XCTestCase {
    
    actor TestHost {
        let detector = IntentDetector()
        func check(_ text: String) async -> UserIntent {
            return await detector.detect(text: text)
        }
    }
    
    func testProseDetection() async {
        let host = TestHost()
        
        let proseSamples = [
            "Hello world",
            "This is a normal sentence.",
            "Privet mir, kak dela?",
            "Just checking in on the project.",
            "See you at 5pm!",
            "Why is the sky blue?",
            "I love using RightLayout app."
        ]
        
        for sample in proseSamples {
            let intent = await host.check(sample)
            XCTAssertEqual(intent, .prose, "Failed on prose: \(sample)")
        }
    }
    
    func testCodeDetection() async {
        let host = TestHost()
        
        let codeSamples = [
            "let x = [1, 2, 3]",
            "var count = 0;",
            "func test() { return }",
            "import Foundation",
            "class MyClass: NSObject { }",
            "x += 1",
            "if (a == b) { c = d }",
            "const data = { id: 1 };",
            "def my_function(args):"
        ]
        
        for sample in codeSamples {
            let intent = await host.check(sample)
            XCTAssertEqual(intent, .code, "Failed on code: \(sample)")
        }
    }
    
    func testUrlAndCommandDetection() async {
        let host = TestHost()
        
        let samples = [
            "https://google.com",
            "http://localhost:8080",
            "www.example.com",
            "git status",
            "ssh user@host",
            "cd /usr/bin",
            "rm -rf *",
            "docker ps",
            "npm install",
            "/tmp/example/file.txt",
            "./script.sh"
        ]
        
        for sample in samples {
            let intent = await host.check(sample)
            XCTAssertEqual(intent, .urlOrCommand, "Failed on URL/CMD: \(sample)")
        }
    }
    
    func testEdgeCases() async {
        let host = TestHost()
        
        // Short text likely prose unless purely symbols
        let res1 = await host.check("hi")
        XCTAssertEqual(res1, .prose)
        
        let res2 = await host.check("Fix it")
        XCTAssertEqual(res2, .prose)
        
        // Mixed content
        // Current logic: StartsWith check for URL. So this is prose.
        let res3 = await host.check("Check out https://site.com")
        XCTAssertEqual(res3, .prose)
        
        // Code-like prose
        // "function is a word" -> prose (only 1 keyword, no symbols)
        let res4 = await host.check("function is a word")
        XCTAssertEqual(res4, .prose)
    }

    // MARK: - Ticket 48 Hardening
    
    func testCodeIdentifiers() async {
        let host = TestHost()
        
        let identifiers = [
            "camelCaseVar",
            "PascalCaseClass",
            "snake_case_variable",
            "kebab-case-id",
            "UPPER_SNAKE_CONST",
            "userId",
            "isAuthorized"
        ]
        
        for id in identifiers {
            let intent = await host.check(id)
            XCTAssertEqual(intent, .code, "Failed on identifier: \(id)")
        }
    }
    
    func testCLIFlagsAndOptions() async {
        let host = TestHost()
        
        // These should be flagged as code or urlOrCommand (technical)
        let flags = [
            "--verbose",
            "--force",
            "-m",
            "-rf",
            "--name=value",
            "-X"
        ]
        
        for flag in flags {
            let intent = await host.check(flag)
            // Either code or command is fine, as long as it's not prose
            XCTAssertTrue(intent == .urlOrCommand || intent == .code, "Failed on CLI flag: \(flag)")
        }
    }
    
    func testEmailsAndDomains() async {
        let host = TestHost()
        
        let inputs = [
            "user@example.com",
            "support@domain.co.uk",
            "localhost",
            "api.internal",
            "server.local"
        ]
        
        for input in inputs {
            let intent = await host.check(input)
            XCTAssertTrue(intent == .urlOrCommand || intent == .code, "Failed on Email/Domain: \(input)")
        }
    }
    
    func testMarkdownCode() async {
        let host = TestHost()
        
        // Paired/triple backticks should treat it as code/tech (Markdown code spans/fences).
        let inputs = [
            "`code`",
            "```block```",
            "`inline`"
        ]
        
        for input in inputs {
            let intent = await host.check(input)
            XCTAssertEqual(intent, .code, "Failed on Markdown: \(input)")
        }
    }

    func testBacktickUsedAsYoKeyIsNotTreatedAsCode() async {
        let host = TestHost()

        // Ticket 46: On RU layouts, the grave/backtick key maps to "ё".
        // Single backticks in short tokens must NOT automatically classify as code,
        // otherwise common words like "ещё" ("to`") would never be fixed.
        let samples = [
            "to`",   // "ещё"
            "TO~",   // "ЕЩЁ"
            "`krf"   // "ёлка"
        ]

        for sample in samples {
            let intent = await host.check(sample)
            XCTAssertEqual(intent, .prose, "Failed on backtick-as-yo token: \(sample)")
        }
    }
}
