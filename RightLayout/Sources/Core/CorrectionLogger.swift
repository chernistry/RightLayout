import Foundation
import os.log

/// Logs corrections to ~/.rightlayout/corrections.jsonl for on-the-fly learning.
/// Disabled by default; enable with `RightLayout_CORRECTION_LOG=1`.
/// Note: Never persist raw typed text (privacy requirement).
public final class CorrectionLogger: @unchecked Sendable {
    public static let shared = CorrectionLogger()
    
    private let enabled: Bool
    private let fileURL: URL
    private let maxEntries = 10000
    private let logger = Logger.engine
    private let queue = DispatchQueue(label: "com.rightlayout.correction-logger")
    
    struct CorrectionEntry: Codable {
        let ts: String
        let original: String
        let final: String
        let autoAttempted: String?
        let userSelected: String?
        let app: String?
        
        enum CodingKeys: String, CodingKey {
            case ts, original, final
            case autoAttempted = "auto_attempted"
            case userSelected = "user_selected"
            case app
        }
    }
    
    private init() {
        self.enabled = ProcessInfo.processInfo.environment["RightLayout_CORRECTION_LOG"] == "1"
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let rightlayoutDir = homeDir.appendingPathComponent(".rightlayout", isDirectory: true)
        try? FileManager.default.createDirectory(at: rightlayoutDir, withIntermediateDirectories: true)
        self.fileURL = rightlayoutDir.appendingPathComponent("corrections.jsonl")
    }
    
    /// Log a correction event
    func log(original: String, final: String, autoAttempted: LanguageHypothesis?, userSelected: LanguageHypothesis?, app: String?) {
        guard enabled else { return }
        queue.async { [weak self] in
            self?.writeEntry(CorrectionEntry(
                ts: ISO8601DateFormatter().string(from: Date()),
                original: DecisionLogger.tokenSummary(original),
                final: DecisionLogger.tokenSummary(final),
                autoAttempted: autoAttempted?.rawValue,
                userSelected: userSelected?.rawValue,
                app: app
            ))
        }
    }
    
    private func writeEntry(_ entry: CorrectionEntry) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            // Rotate if needed (async, don't block)
            rotateIfNeeded()
        } catch {
            logger.error("Failed to log correction: \(error.localizedDescription)")
        }
    }
    
    private func rotateIfNeeded() {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        if lines.count > maxEntries {
            let trimmed = lines.suffix(maxEntries).joined(separator: "\n") + "\n"
            try? trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.info("Rotated corrections log, kept last \(self.maxEntries) entries")
        }
    }
}
