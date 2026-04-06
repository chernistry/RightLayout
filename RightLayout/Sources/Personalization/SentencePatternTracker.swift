import Foundation
import os.log
import AppKit

/// Ticket 73: Sentence-Level Contextual Learning
/// Tracks sequence of languages at the sentence level inside each app,
/// to predictably boost expected layouts (e.g. 3 Russian words usually mean the 4th is Russian).

struct SentencePatternState: Codable, Sendable {
    var version: Int = 3
    /// Map of [AppBundleId -> [PatternString: Int (Count)]]
    var appPatterns: [String: [String: Int]] = [:]
}

actor SentencePatternTracker {
    static let shared = SentencePatternTracker()

    private var state: SentencePatternState
    private let fileURL: URL
    private var isLoaded: Bool = false
    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "SentencePatternTracker")

    private static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }
    
    // Ticket 74: Flag to allow testing the tracker itself
    var isTestOverrideEnabled: Bool = false

    init(fileManager: FileManager = .default, customDirectory: URL? = nil) {
        let storeDir: URL
        if let custom = customDirectory {
            storeDir = custom
        } else if Self.isRunningTests {
            storeDir = fileManager.temporaryDirectory.appendingPathComponent("rightlayout_sentence_tests", isDirectory: true)
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("com.chernistry.rightlayout")
            storeDir = appDir.appendingPathComponent("SentencePatterns")
        }
        self.fileURL = storeDir.appendingPathComponent("store.json")
        self.state = SentencePatternState()

        if Self.isRunningTests, customDirectory == nil {
            try? fileManager.removeItem(at: fileURL)
        }

        try? fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
        self.state = Self.loadState(from: fileURL, logger: logger)
        self.isLoaded = true
    }

    // MARK: - Pattern Logic
    
    private func serializePattern(sequence: [Language], next: Language?) -> String {
        let seqStr = sequence.map { $0.rawValue }.joined(separator: ",")
        let nextStr = next?.rawValue ?? "END"
        return "\(seqStr)->\(nextStr)"
    }

    /// Records the next language (or nil if end of sentence) following a sequence of languages
    func record(appBundleId: String?, sequence: [Language], next: Language?) {
        if Self.isRunningTests && !isTestOverrideEnabled { return }
        guard let bundleId = appBundleId ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        guard !sequence.isEmpty else { return }

        var patterns = state.appPatterns[bundleId] ?? [:]
        
        // Record patterns for suffixes of length 1, 2, and 3
        let maxSuffix = min(3, sequence.count)
        for i in 1...maxSuffix {
            let suffix = Array(sequence.suffix(i))
            let patternStr = serializePattern(sequence: suffix, next: next)
            patterns[patternStr] = (patterns[patternStr] ?? 0) + 1
        }

        // LRU cap size per app
        if patterns.count > 1000 {
            let sorted = patterns.sorted { $0.value < $1.value }
            for (key, _) in sorted.prefix(200) {
                patterns.removeValue(forKey: key)
            }
        }

        state.appPatterns[bundleId] = patterns
        save()
    }

    /// Evaluates if a candidate language matches sentence patterns and returns a confidence boost (0.0 to 0.3)
    func confidenceBoost(appBundleId: String?, sequence: [Language], candidate: Language) -> Double {
        if Self.isRunningTests && !isTestOverrideEnabled { return 0.0 }
        guard let bundleId = appBundleId ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return 0.0 }
        guard !sequence.isEmpty else { return 0.0 }

        let patterns = state.appPatterns[bundleId] ?? [:]
        
        // Search longest suffix first
        let maxSuffix = min(3, sequence.count)
        for i in (1...maxSuffix).reversed() {
            let suffix = Array(sequence.suffix(i))
            let candidatePattern = serializePattern(sequence: suffix, next: candidate)
            let candidateCount = patterns[candidatePattern] ?? 0
            
            // Require at least 3 occurrences to trust the pattern
            if candidateCount >= 3 {
                var totalVariations = 0
                for target in Language.allCases {
                    let pat = serializePattern(sequence: suffix, next: target)
                    totalVariations += patterns[pat] ?? 0
                }
                let patEnd = serializePattern(sequence: suffix, next: nil)
                totalVariations += patterns[patEnd] ?? 0
                
                let probability = Double(candidateCount) / Double(totalVariations)
                
                if probability > 0.6 {
                    let boost = min(0.3, (probability - 0.6) * 0.75) // up to 0.3 boost
                    logger.debug("🌊 Sentence pattern boost for \(candidate.rawValue): \(boost) (prob: \(probability))")
                    return boost
                }
            }
        }
        return 0.0
    }

    func reset() {
        state = SentencePatternState()
        save()
    }

    // MARK: - Persistence

    private static func loadState(from fileURL: URL, logger: Logger) -> SentencePatternState {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return SentencePatternState() }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(SentencePatternState.self, from: data)
            guard decoded.version == 3 else {
                try? FileManager.default.removeItem(at: fileURL)
                return SentencePatternState()
            }
            return decoded
        } catch {
            logger.error("Failed to load sentence patterns: \(error.localizedDescription)")
        }
        return SentencePatternState()
    }

    private var pendingSaveTask: Task<Void, Error>?

    private func save() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            try Task.checkCancellation()
            await self.performSave()
        }
    }

    private func performSave() async {
        do {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            
            let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent("store.tmp")
            try data.write(to: tempURL, options: .atomic)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            logger.error("Failed to save sentence patterns: \(error.localizedDescription)")
        }
    }
}
