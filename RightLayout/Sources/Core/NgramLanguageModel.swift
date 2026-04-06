import Foundation

/// Hypothesis about the language and layout configuration
/// rawValue must match Python CLASSES in train.py exactly!
public enum LanguageHypothesis: String, CaseIterable, Sendable {
    case ru = "ru"                         // Russian as-is
    case en = "en"                         // English as-is
    case he = "he"                         // Hebrew as-is
    case enFromRuLayout = "en_from_ru"     // English typed on Russian layout
    case enFromHeLayout = "en_from_he"     // English typed on Hebrew layout
    case ruFromEnLayout = "ru_from_en"     // Russian typed on English layout
    case heFromEnLayout = "he_from_en"     // Hebrew typed on English layout
    case heFromRuLayout = "he_from_ru"     // Hebrew typed on Russian layout
    case ruFromHeLayout = "ru_from_he"     // Russian typed on Hebrew layout
    
    public var targetLanguage: Language {
        switch self {
        case .ru, .ruFromEnLayout, .ruFromHeLayout: return .russian
        case .en, .enFromRuLayout, .enFromHeLayout: return .english
        case .he, .heFromEnLayout, .heFromRuLayout: return .hebrew
        }
    }
}

/// Scores for different layout hypotheses with confidence
struct LayoutScores: Sendable {
    let scores: [LanguageHypothesis: Float]
    let best: LanguageHypothesis
    let confidence: Double  // In range [0, 1]
}

/// Context for layout detection (minimal in this ticket, for future use)
struct LayoutContext: Sendable {
    let lastLanguage: LanguageHypothesis?
    
    init(lastLanguage: LanguageHypothesis? = nil) {
        self.lastLanguage = lastLanguage
    }
}

/// N-gram language model using trigram log-probabilities
struct NgramLanguageModel: Sendable {
    private let logProbs: [UInt64: Float]
    private let smoothingValue: Float
    private let p05: Float
    private let p50: Float
    private let p95: Float
    
    init(logProbs: [UInt64: Float], smoothingValue: Float = -10.0) {
        self.logProbs = logProbs
        self.smoothingValue = smoothingValue

        let values = logProbs.values.sorted()
        if values.isEmpty {
            self.p05 = smoothingValue
            self.p50 = smoothingValue
            self.p95 = smoothingValue
        } else {
            func pct(_ p: Double) -> Float {
                let idx = max(0, min(values.count - 1, Int((Double(values.count - 1) * p).rounded(.toNearestOrAwayFromZero))))
                return values[idx]
            }
            self.p05 = pct(0.05)
            self.p50 = pct(0.50)
            self.p95 = pct(0.95)
        }
    }
    
    /// Load model from JSON file
    static func loadFrom(jsonURL: URL) throws -> NgramLanguageModel {
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONDecoder().decode(ModelJSON.self, from: data)
        
        // Validate format
        guard json.n == 3 else {
            throw ModelError.invalidFormat("Expected n=3, got n=\(json.n)")
        }
        
        // Convert trigram strings to hashes
        var logProbs: [UInt64: Float] = [:]
        for (trigram, logProb) in json.trigrams {
            guard trigram.count == 3 else { continue }
            
            let chars = Array(trigram)
            let hash = trigramHash(chars[0], chars[1], chars[2])
            logProbs[hash] = logProb
        }
        
        // Use smoothing value from JSON or fall back to default derived from min probability
        let smoothingValue: Float
        if logProbs.isEmpty {
            smoothingValue = -10.0
        } else {
            // Use minimum observed log-probability minus 2 as smoothing value
            let minLogProb = logProbs.values.min() ?? -7.0
            smoothingValue = minLogProb - 2.0
        }
        
        return NgramLanguageModel(logProbs: logProbs, smoothingValue: smoothingValue)
    }
    
    /// Load model for a specific language from app resources
    static func loadLanguage(_ lang: String) throws -> NgramLanguageModel {
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(
            forResource: "\(lang)_trigrams",
            withExtension: "json"
        ) else {
            throw ModelError.resourceNotFound(lang)
        }
        #else
        // For Xcode build
        guard let url = Bundle.main.url(
            forResource: "\(lang)_trigrams",
            withExtension: "json"
        ) else {
            throw ModelError.resourceNotFound(lang)
        }
        #endif
        
        return try loadFrom(jsonURL: url)
    }
    
    /// Compute trigram hash from 3 characters
    static func trigramHash(_ c1: Character, _ c2: Character, _ c3: Character) -> UInt64 {
        guard let s1 = c1.unicodeScalars.first,
              let s2 = c2.unicodeScalars.first,
              let s3 = c3.unicodeScalars.first else {
            return 0
        }
        // Pack three Unicode scalar values into UInt64.
        // Unicode scalars are up to U+10FFFF (21 bits). 3 * 21 = 63 bits.
        let a = UInt64(s1.value) & 0x1F_FFFF
        let b = UInt64(s2.value) & 0x1F_FFFF
        let c = UInt64(s3.value) & 0x1F_FFFF
        return (a << 42) | (b << 21) | c
    }
    
    /// Score a text by summing log-probabilities of its trigrams
    func score(_ text: String) -> Float {
        let normalized = text.lowercased().filter { $0.isLetter }
        guard normalized.count >= 3 else {
            return smoothingValue * Float(max(1, normalized.count))
        }
        
        var totalScore: Float = 0.0
        var trigramCount = 0
        
        let chars = Array(normalized)
        for i in 0...(chars.count - 3) {
            let hash = Self.trigramHash(chars[i], chars[i+1], chars[i+2])
            let prob = logProbs[hash] ?? smoothingValue
            totalScore += prob
            trigramCount += 1
        }
        
        // Normalize by number of trigrams to make scores comparable
        return trigramCount > 0 ? totalScore / Float(trigramCount) : smoothingValue
    }

    /// Score normalized to [0, 1] using model percentiles.
    func normalizedScore(_ text: String) -> Double {
        let s = score(text)
        // Higher (less negative) is better.
        // Use a sigmoid around the median to make the score comparable across languages
        // without overfitting to a "top percentile" that few real words ever reach.
        let spread = max(0.5, (p95 - p50) / 2.0)
        let z = Double((s - p50) / spread)
        return 1.0 / (1.0 + exp(-z))
    }
    
    /// Lookup log-probability for a specific trigram
    func lookup(_ c1: Character, _ c2: Character, _ c3: Character) -> Float {
        let hash = Self.trigramHash(c1, c2, c3)
        return logProbs[hash] ?? smoothingValue
    }
}

// MARK: - JSON Decoding

private struct ModelJSON: Codable {
    let lang: String
    let n: Int
    let version: Int
    let smoothing_k: Double?
    let total_count: Int?
    let unique_trigrams: Int?
    let trigrams: [String: Float]
}

enum ModelError: Error {
    case resourceNotFound(String)
    case invalidFormat(String)
}
