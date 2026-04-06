import Foundation
import NaturalLanguage
import AppKit
import os.log

/// Context for ensemble decision making
public struct EnsembleContext: Sendable {
    public let lastLanguage: Language?
    public let activeLayouts: [String: String]?
    
    public init(lastLanguage: Language? = nil, activeLayouts: [String: String]? = nil) {
        self.lastLanguage = lastLanguage
        self.activeLayouts = activeLayouts
    }
}

/// Detailed decision from the ensemble
public struct LanguageDecision: Sendable {
    public let language: Language
    public let layoutHypothesis: LanguageHypothesis
    public let confidence: Double
    public let scores: [LanguageHypothesis: Double] // Debug/logging info
}

/// Ensemble classifier that combines NLLanguageRecognizer with layout hypotheses and heuristics
actor LanguageEnsemble {
    private let recognizer = NLLanguageRecognizer()
    private let logger = Logger.detection
    private let wordValidator: WordValidator
    
    // Weights for scoring components
    private let weightNL: Double = 0.2
    private let weightChar: Double = 0.3
    private let weightNgram: Double = 0.5
    private let contextBonus: Double = 0.15
    private let hypothesisPenalty: Double = 0.2 // Penalty for mapped hypotheses
    
    // N-gram models
    private var ruModel: NgramLanguageModel?
    private var enModel: NgramLanguageModel?
    private var heModel: NgramLanguageModel?
    
    init(wordValidator: WordValidator = HybridWordValidator()) {
        self.wordValidator = wordValidator
        // Configure recognizer once
        recognizer.languageHints = [
            .russian: 0.33,
            .english: 0.33,
            .hebrew: 0.34
        ]
        recognizer.languageConstraints = [
            .russian,
            .english,
            .hebrew
        ]
        
        // Load N-gram models
        self.ruModel = try? NgramLanguageModel.loadLanguage("ru")
        self.enModel = try? NgramLanguageModel.loadLanguage("en")
        self.heModel = try? NgramLanguageModel.loadLanguage("he")
        
        if ruModel == nil { logger.warning("⚠️ LanguageEnsemble: Failed to load RU model") }
        if enModel == nil { logger.warning("⚠️ LanguageEnsemble: Failed to load EN model") }
        if heModel == nil { logger.warning("⚠️ LanguageEnsemble: Failed to load HE model") }
    }
    
    /// Classify a token using multiple signals
    func classify(_ token: String, context: EnsembleContext) -> LanguageDecision {
        guard token.count >= 2 else {
            // Fallback for very short tokens: default to English or context
            return LanguageDecision(
                language: context.lastLanguage ?? .english,
                layoutHypothesis: .en,
                confidence: 0.5,
                scores: [:]
            )
        }
        
        var hypothesisScores: [LanguageHypothesis: Double] = [:]
        let activeLayouts = context.activeLayouts
        
        // 1. Evaluate "As-Is" hypotheses
        hypothesisScores[.ru] = evaluate(text: token, target: .russian, context: context, isMapped: false)
        hypothesisScores[.en] = evaluate(text: token, target: .english, context: context, isMapped: false)
        hypothesisScores[.he] = evaluate(text: token, target: .hebrew, context: context, isMapped: false)
        
        // Check script presence to filter impossible hypotheses
        let hasLatin = checkCharacterSet(token, for: .english) // > 0.7 match
        let hasCyrillic = checkCharacterSet(token, for: .russian) // > 0.7 match
        let hasHebrew = checkCharacterSet(token, for: .hebrew) // > 0.7 match
        
        // Strict-ish check for "Pure" scripts to avoid generating "English from Russian" for Latin text
        // If text is primarily Latin, it CANNOT be source Russian or Hebrew.
        
        // 2. Evaluate "Layout Mapped" hypotheses
        
        // If input is primarily LATIN
        if hasLatin {
            // Check if input (English) maps to Russian
            if let ruMapped = LayoutMapper.shared.convert(token, from: .english, to: .russian, activeLayouts: activeLayouts) {
                 hypothesisScores[.ruFromEnLayout] = evaluate(text: ruMapped, target: .russian, context: context, isMapped: true)
            }
            
            // Check if input (English) maps to Hebrew
            if let heMapped = LayoutMapper.shared.convert(token, from: .english, to: .hebrew, activeLayouts: activeLayouts) {
                hypothesisScores[.heFromEnLayout] = evaluate(text: heMapped, target: .hebrew, context: context, isMapped: true)
            }
        }
        
        // If input is primarily CYRILLIC
        if hasCyrillic {
            // Try ALL Russian layout variants for reverse mappings.
            // This supports Russian Phonetic and other RU variants without requiring perfect layout detection.
            let heVariants = LayoutMapper.shared.convertAllSourceVariants(token, from: .russian, to: .hebrew, activeLayouts: activeLayouts)
            for (_, converted) in heVariants {
                let score = evaluate(text: converted, target: .hebrew, context: context, isMapped: true)
                if hypothesisScores[.heFromRuLayout] == nil || score > hypothesisScores[.heFromRuLayout]! {
                    hypothesisScores[.heFromRuLayout] = score
                }
            }

            let enVariants = LayoutMapper.shared.convertAllSourceVariants(token, from: .russian, to: .english, activeLayouts: activeLayouts)
            for (_, converted) in enVariants {
                let score = evaluate(text: converted, target: .english, context: context, isMapped: true)
                if hypothesisScores[.enFromRuLayout] == nil || score > hypothesisScores[.enFromRuLayout]! {
                    hypothesisScores[.enFromRuLayout] = score
                }
            }
        }
        
        // If input is primarily HEBREW
        if hasHebrew {
            // Try ALL Hebrew layout variants -> Russian
            let ruVariants = LayoutMapper.shared.convertAllSourceVariants(token, from: .hebrew, to: .russian, activeLayouts: activeLayouts)
            for (_, converted) in ruVariants {
                let score = evaluate(text: converted, target: .russian, context: context, isMapped: true)
                if hypothesisScores[.ruFromHeLayout] == nil || score > hypothesisScores[.ruFromHeLayout]! {
                    hypothesisScores[.ruFromHeLayout] = score
                }
            }
            
            // Try ALL Hebrew layout variants -> English
            let enVariants = LayoutMapper.shared.convertAllSourceVariants(token, from: .hebrew, to: .english, activeLayouts: activeLayouts)
            for (_, converted) in enVariants {
                let score = evaluate(text: converted, target: .english, context: context, isMapped: true)
                if hypothesisScores[.enFromHeLayout] == nil || score > hypothesisScores[.enFromHeLayout]! {
                    hypothesisScores[.enFromHeLayout] = score
                }
            }
        }
        
        // Fallback: If Mixed or Unknown script, maybe try all? 
        // But for Ticket 13/14 valid cases, inputs are usually clean tokens.
        // If mixed (e.g. "hello мир"), `checkCharacterSet` returns false for both (>0.7).
        // Then we skip mapped hypotheses. This is correct for "Mixed Script Rejection".
        
        // 3. Select best hypothesis
        let best = hypothesisScores.max(by: { $0.value < $1.value })?.key ?? .en

        // 4. Calculate confidence
        // Simple margin-based confidence
        let sortedScores = hypothesisScores.values.sorted(by: >)
        let confidence: Double
        if sortedScores.count >= 2 {
            let margin = sortedScores[0] - sortedScores[1]
            // Normalize margin (0.0 - 0.5 range typically) to 0-1 confidence
            confidence = min(1.0, margin * 2.0 + 0.5)
        } else {
            confidence = 0.5
        }
        
        logger.debug("Ensemble decision: \(best.targetLanguage.rawValue) (\(best.rawValue)) conf=\(String(format: "%.2f", confidence))")
        
        return LanguageDecision(
            language: best.targetLanguage,
            layoutHypothesis: best,
            confidence: confidence,
            scores: hypothesisScores
        )
    }
    
    /// Evaluate a specific text against a target language
    private func evaluate(text: String, target: Language, context: EnsembleContext, isMapped: Bool) -> Double {
        let lettersOnly = text.lowercased().filter { $0.isLetter }
        let isShortLetters = lettersOnly.count <= 3

        // A. NLLanguageRecognizer Score
        recognizer.reset()
        recognizer.processString(text)
        
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let nlProb = hypotheses[target.nlLanguage] ?? 0.0
        
        // B. Character Set Heuristic
        let charMatch = checkCharacterSet(text, for: target) ? 1.0 : 0.0
        
        // C. N-gram Score
        let ngramScore = checkNgram(text, language: target)

        // D. Word validity (strong signal for "real words" and prevents false positives from trigrams)
        let wordScore = wordValidator.confidence(for: text, language: target)
        
        // E. Context Bonus
        let isContextMatch = context.lastLanguage == target
        let contextScore = isContextMatch ? contextBonus : 0.0
        
        // F. Penalty for mapped hypotheses
        let penalty = isMapped ? hypothesisPenalty : 0.0
        
        // Weighted Sum
        // For <=3 letters, favor word validation over trigrams (trigrams are uninformative).
        // For longer text, keep n-gram as a strong signal, but still require word validity to avoid
        // "random but plausible" sequences in the wrong language.
        let wNL = isShortLetters ? 0.05 : 0.15
        let wChar = isShortLetters ? 0.25 : 0.20
        let wNgram = isShortLetters ? 0.0 : 0.35
        let wWord = isShortLetters ? 0.55 : 0.30

        let totalScore = (nlProb * wNL) +
                         (charMatch * wChar) +
                         (ngramScore * wNgram) +
                         (wordScore * wWord) +
                         contextScore -
                         penalty
        
        return totalScore
    }
    
    private func checkCharacterSet(_ text: String, for language: Language) -> Bool {
        var matchCount = 0
        var letterCount = 0
        
        for char in text.unicodeScalars {
            if Character(char).isLetter {
                letterCount += 1
            }
            
            switch language {
            case .russian:
                if (0x0410...0x044F).contains(char.value) || char.value == 0x0401 || char.value == 0x0451 { // Cyrillic + Yo
                    matchCount += 1
                }
            case .english:
                if (0x0041...0x005A).contains(char.value) || (0x0061...0x007A).contains(char.value) { // Latin
                    matchCount += 1
                }
            case .hebrew:
                if (0x0590...0x05FF).contains(char.value) { // Hebrew
                    matchCount += 1
                }
            }
        }
        
        let total = Double(letterCount > 0 ? letterCount : text.count)
        guard total > 0 else { return false }
        
        // Require > 70% match of LETTERS (or total if no letters)
        return (Double(matchCount) / total) > 0.7
    }
    
    private func checkNgram(_ text: String, language: Language) -> Double {
        let model: NgramLanguageModel?
        switch language {
        case .russian: model = ruModel
        case .english: model = enModel
        case .hebrew: model = heModel
        }
        
        guard let model = model else { return 0.0 }
        return model.normalizedScore(text)
    }
}
