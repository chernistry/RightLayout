import Foundation
import CryptoKit

/// Service responsible for converting raw input into privacy-safe PersonalFeatures.
/// Handles salt management to ensure hashes are unique to this device and not dictionary-attackable.
actor FeatureExtractor {
    
    // MARK: - Dependencies
    
    private let salt: Data
    
    // MARK: - Init
    
    init(saltOverride: Data? = nil) {
        if let override = saltOverride {
            self.salt = override
        } else {
            self.salt = FeatureExtractor.getOrGenerateSalt()
        }
    }
    
    private static func getOrGenerateSalt() -> Data {
        let key = "com.chernistry.rightlayout.personalization.salt"
        if let stored = UserDefaults.standard.data(forKey: key) {
            return stored
        }
        
        let newSalt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        UserDefaults.standard.set(newSalt, forKey: key)
        return newSalt
    }
    
    // MARK: - Public API
    
    // MARK: - Public API
    
    /// Extract features for the current context and text.
    /// - Parameters:
    ///   - text: The current word being typed.
    ///   - phraseBuffer: Previous words in the sentence (for context).
    ///   - appBundleId: The active application.
    ///   - intent: Detected intent (from IntentDetector).
    ///   - latencies: Optional timing data (inter-key latencies) for the word.
    func extract(text: String, phraseBuffer: String, appBundleId: String, intent: String, latencies: [TimeInterval]? = nil) -> PersonalFeatures {
        let normalizedText = text.lowercased().filter { $0.isLetter }
        
        let contextHashes = extractHierarchicalContext(appBundleId: appBundleId, intent: intent)
        let ngramHashes = extractNgrams(from: normalizedText)
        let lengthCat = extractLengthCategory(from: normalizedText)
        
        // Ticket 44: Phrase Shape Features
        // We hash properties of the phrase buffer to give the model "sentence context"
        let phraseFeatures = extractPhraseFeatures(phrase: phraseBuffer)
        
        // Ticket 53: Bio Features
        let bioHashes: [UInt16]
        if let timings = latencies, let bio = extractBioFeatures(latencies: timings) {
            bioHashes = bioToHashes(bio, salt: salt)
        } else {
            bioHashes = []
        }
        
        // Combine all features
        let combinedFeatures = ngramModels(ngrams: ngramHashes, phrase: phraseFeatures) + bioHashes
        
        return PersonalFeatures(
            appBundleIdHash: contextHashes.appHash, 
            contextKey: contextHashes.key, // New hierarchical key
            hourOfDay: contextHashes.hour,
            isWeekend: contextHashes.isWeekend,
            ngramHashes: combinedFeatures, // Combined
            lengthCategory: lengthCat,
            bioFeatures: nil // Deprecated field in PersonalFeatures struct? Or we map it?
                             // Assuming PersonalFeatures definition allows putting hashes into `ngramHashes` or similar.
                             // The `bioFeatures` field in `PersonalFeatures` struct seems unused or nil in existing code.
                             // Let's assume we just mix them into `ngramHashes` for the sparse vector.
                             // Wait, line 64 originally had `bioFeatures: nil`.
                             // Passing `bioHashes` into `ngramHashes` effectively treats them as active features.
                             // We should keep `bioFeatures: nil` if strict typing is required, OR update PersonalFeatures struct.
                             // Existing code passed `nil`.
                             // Let's pass `nil` to the property but INCLUDE the hashes in the vector. 
                             // The `ngramHashes` likely represents the "active feature set" for lookup.
        )
    }
    
    // MARK: - Extraction Logic
    
    /// Returns hierarchical context hashes
    private func extractHierarchicalContext(appBundleId: String, intent: String) -> (appHash: Int, key: ContextKey, hour: Int, isWeekend: Bool) {
        let appHash = hashToInt(appBundleId, salt: salt)
        
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = (weekday == 1 || weekday == 7)
        
        // Coarse time bucket: Early (0-6), Work (7-18), Evening (19-23)
        let timeBucket: Int
        switch hour {
        case 0...6: timeBucket = 0
        case 7...18: timeBucket = 1
        default: timeBucket = 2
        }
        
        let key = ContextKey(
            global: 0, // Constant for global bias
            app: appHash,
            appIntent: hashToInt("\(appBundleId):\(intent)", salt: salt),
            appTime: hashToInt("\(appBundleId):\(timeBucket)", salt: salt)
        )
        
        return (appHash, key, hour, isWeekend)
    }
    
    private func extractPhraseFeatures(phrase: String) -> [UInt16] {
        guard !phrase.isEmpty else { return [] }
        
        var features: [UInt16] = []
        
        // 1. Last word length category
        let words = phrase.split(separator: " ")
        if let last = words.last {
            let len = min(last.count, 10)
            features.append(hashToUInt16("prevLen:\(len)", salt: salt))
            
            // 2. Last word unicode block (e.g. is Cyrillic?)
            if last.contains(where: { $0.isCyrillic }) {
                features.append(hashToUInt16("prevScript:cyr", salt: salt))
            } else if last.contains(where: { $0.isHebrew }) {
                features.append(hashToUInt16("prevScript:heb", salt: salt))
            } else {
                features.append(hashToUInt16("prevScript:lat", salt: salt))
            }
        }
        
        return features
    }
    
    private func ngramModels(ngrams: [UInt16], phrase: [UInt16]) -> [UInt16] {
        return ngrams + phrase
    }
    
    private func extractNgrams(from text: String) -> [UInt16] {
        var hashes: [UInt16] = []
        guard text.count >= 2 else { return [] }
        
        let chars = Array(text)
        
        // 2-grams
        for i in 0..<(chars.count - 1) {
            let gram = String(chars[i...i+1])
            hashes.append(hashToUInt16(gram, salt: salt))
        }
        
        // 3-grams
        if chars.count >= 3 {
            for i in 0..<(chars.count - 2) {
                let gram = String(chars[i...i+2])
                hashes.append(hashToUInt16(gram, salt: salt))
            }
        }
        
        return hashes
    }
    
    private func extractLengthCategory(from text: String) -> Int {
        switch text.count {
        case 0...3: return 0
        case 4...7: return 1
        default: return 2
        }
    }
    
    // MARK: - Hashing Helpers
    
    private func hashToInt(_ string: String, salt: Data) -> Int {
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(string.utf8))
        let digest = hasher.finalize()
        
        // Use first 8 bytes for Int
        let bytes = digest.withUnsafeBytes { ptr in
            ptr.load(as: Int.self)
        }
        return bytes
    }
    
    private func hashToUInt16(_ string: String, salt: Data) -> UInt16 {
        var sha = SHA256()
        sha.update(data: salt)
        sha.update(data: Data(string.utf8))
        let digest = sha.finalize()
        
        // Take first 2 bytes
        return digest.withUnsafeBytes { ptr in
            ptr.load(as: UInt16.self)
        }
    }
    // MARK: - Bio Features
    
    /// Privacy-safe buckets for biometric features
    struct BioFeatures {
        let speedBucket: Int // 0=Slow, 1=Medium, 2=Fast
        let rhythmVariance: Int // 0=Steady, 1=Variable, 2=Erratic
        let pauseCount: Int // Number of long pauses within the word
    }
    
    /// Extract bio features from raw timing data
    /// - Parameters:
    ///   - latencies: Array of time intervals between keystrokes for the current word
    func extractBioFeatures(latencies: [TimeInterval]) -> BioFeatures? {
        guard !latencies.isEmpty else { return nil }
        
        // 1. Speed (Avg Latency)
        let total = latencies.reduce(0, +)
        let avg = total / Double(latencies.count)
        
        let speedBucket: Int
        switch avg {
        case 0.25...: speedBucket = 0 // Slow (> 250ms)
        case 0.12..<0.25: speedBucket = 1 // Medium (120-250ms)
        default: speedBucket = 2 // Fast (< 120ms)
        }
        
        // 2. Rhythm (Variance)
        // Simple variance: measure spread of latencies
        // We use Mean Absolute Deviation (MAD) for robustness
        let mad = latencies.map { abs($0 - avg) }.reduce(0, +) / Double(latencies.count)
        
        let rhythmBucket: Int
        switch mad {
        case ..<0.05: rhythmBucket = 0 // Very steady
        case 0.05..<0.15: rhythmBucket = 1 // Normal variance
        default: rhythmBucket = 2 // Erasures/Thinking
        }
        
        // 3. Pause Count (Latencies > 500ms)
        let pauses = latencies.filter { $0 > 0.5 }.count
        
        return BioFeatures(speedBucket: speedBucket, rhythmVariance: rhythmBucket, pauseCount: pauses)
    }
    
    private func bioToHashes(_ features: BioFeatures, salt: Data) -> [UInt16] {
        var hashes: [UInt16] = []
        hashes.append(hashToUInt16("bio:speed:\(features.speedBucket)", salt: salt))
        hashes.append(hashToUInt16("bio:rhythm:\(features.rhythmVariance)", salt: salt))
        if features.pauseCount > 0 {
            hashes.append(hashToUInt16("bio:pauses:\(min(features.pauseCount, 3))", salt: salt))
        }
        return hashes
    }
}

private extension Character {
    var isCyrillic: Bool {
        return ("\u{0400}"..."\u{04FF}").contains(self)
    }
    
    var isHebrew: Bool {
        return ("\u{0590}"..."\u{05FF}").contains(self)
    }
}
