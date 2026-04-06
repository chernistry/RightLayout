import Foundation

/// Compact word frequency model loaded from bundled resources.
/// File format: `word<TAB>count` (sorted by descending count).
struct WordFrequencyModel: Sendable {
    private let logCountByWord: [String: Float]
    private let invMaxLogCount: Float

    static func loadLanguage(_ lang: String) throws -> WordFrequencyModel {
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: "\(lang)_unigrams", withExtension: "tsv", subdirectory: "LanguageModels") else {
            throw LexiconError.resourceNotFound(lang)
        }
        #else
        guard let url = Bundle.main.url(forResource: "\(lang)_unigrams", withExtension: "tsv", subdirectory: "LanguageModels") else {
            throw LexiconError.resourceNotFound(lang)
        }
        #endif

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LexiconError.invalidFormat("Non-UTF8 TSV for \(lang)")
        }

        var out: [String: Float] = [:]
        out.reserveCapacity(200_000)

        var maxLog: Float = 0.0
        var hasMax = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let wordRaw = parts[0]
            let countRaw = parts[1]
            guard !wordRaw.isEmpty, let count = Float(countRaw) else { continue }

            let word = wordRaw.lowercased()
            // Log-scale frequencies to preserve big differences among the top words.
            let logCount = log1p(count)

            if !hasMax {
                maxLog = logCount
                hasMax = true
            }

            // Keep the first (highest-frequency) occurrence in case of duplicates.
            if out[word] == nil {
                out[word] = logCount
            }
        }

        let invMax = maxLog > 0 ? (1.0 / maxLog) : 1.0
        return WordFrequencyModel(logCountByWord: out, invMaxLogCount: invMax)
    }

    /// Score in [0, 1]. Unknown words score 0.
    func score(_ word: String) -> Double {
        let key = word.lowercased()
        guard let v = logCountByWord[key] else { return 0.0 }
        return Double(v * invMaxLogCount)
    }

    func contains(_ word: String) -> Bool {
        logCountByWord[word.lowercased()] != nil
    }
}

enum LexiconError: Error {
    case resourceNotFound(String)
    case invalidFormat(String)
}
