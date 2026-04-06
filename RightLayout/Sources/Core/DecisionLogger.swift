import Foundation

/// Logs language detection decisions to a local file for debugging.
/// Disabled by default; enable with `RightLayout_DEBUG_LOG=1`.
/// Note: Do not persist raw typed text (privacy requirement).
public final class DecisionLogger: @unchecked Sendable {
    public static let shared = DecisionLogger()
    private let enabled: Bool
    private let logURL: URL?
    private let queue = DispatchQueue(label: "com.rightlayout.logger")
    
    init() {
        let enabled = ProcessInfo.processInfo.environment["RightLayout_DEBUG_LOG"] == "1"
        self.enabled = enabled
        guard enabled else {
            self.logURL = nil
            return
        }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let rightlayoutDir = home.appendingPathComponent(".rightlayout")
        
        var url: URL? = nil
        do {
            try fileManager.createDirectory(at: rightlayoutDir, withIntermediateDirectories: true)
            url = rightlayoutDir.appendingPathComponent("debug.log")
            
            // Overwrite log on startup
            if let validUrl = url {
                try "".write(to: validUrl, atomically: true, encoding: .utf8)
                print("DecisionLogger: Logging to \(validUrl.path)")
            }
        } catch {
            print("DecisionLogger: Failed to setup log file: \(error)")
        }
        self.logURL = url
    }
    
    func log(_ message: String) {
        guard enabled, let url = logURL else { return }
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                // Determine if we need to create it (should exist from init, but maybe deleted)
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    func logDecision(token: String, path: String, result: LanguageDecision, scores: [LanguageHypothesis: Double]? = nil) {
        let tokenInfo = Self.tokenSummary(token)
        var msg = "Input: \(tokenInfo) | Path: \(path) | Result: \(result.language.rawValue) (Conf: \(String(format: "%.2f", result.confidence)))"
        
        if let scores = scores {
            msg += " | Scores: " + scores.map { "\($0.key): \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
        }
        
        log(msg)
    }

    static func tokenSummary(_ token: String) -> String {
        var latin = 0
        var cyrillic = 0
        var hebrew = 0
        var digits = 0
        var whitespace = 0
        var other = 0

        for scalar in token.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39:
                digits += 1
            case 0x0009, 0x000A, 0x000D, 0x0020:
                whitespace += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latin += 1
            case 0x0400...0x04FF:
                cyrillic += 1
            case 0x0590...0x05FF:
                hebrew += 1
            default:
                other += 1
            }
        }

        return "len=\(token.count) latin=\(latin) cyr=\(cyrillic) heb=\(hebrew) dig=\(digits) ws=\(whitespace) other=\(other)"
    }
}
