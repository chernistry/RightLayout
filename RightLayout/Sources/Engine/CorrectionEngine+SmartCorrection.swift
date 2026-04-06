import Foundation
import AppKit

// MARK: - Smart Correction (Split / Whole / Per-Segment)

extension CorrectionEngine {

    // MARK: - Best Smart Correction (Orchestrator)

    func bestSmartCorrection(
        for token: String,
        wholeDecision: LanguageDecision?,
        wholeConfidence: Double?,
        context: DetectorContext,
        activeLayouts: [String: String],
        mode: DetectionMode,
        minConfidence: Double
    ) async -> SmartCorrection? {
        let originalScore = fastTextScore(token)

        let decision: LanguageDecision
        if let wholeDecision {
            decision = wholeDecision
        } else {
            // Pre-calculation: Router run (needed for SmartCorrection decision)
            decision = await router.route(token: token, context: context, mode: mode)
        }

        let confidence = wholeConfidence ?? decision.confidence

        let whole = buildWholeCandidate(
            token: token,
            decision: decision,
            confidence: confidence,
            activeLayouts: activeLayouts,
            minConfidence: minConfidence
        )
        let split = await buildSplitCandidate(
            token: token,
            context: context,
            activeLayouts: activeLayouts,
            mode: mode,
            minConfidence: minConfidence
        )

        let best: SmartCorrection
        if whole.hypothesis != nil {
            // Only force-prefer split if we're not super confident in the whole-word correction.
            // If we have high confidence (e.g. from comma boost), trust the whole-word result.
            // Ticket 64: If whole token maps to a dictionary word, PREFER IT over split,
            // even if it contains a separator like comma/dot.
            let isWholeInDict = (whole.text != "" && BuiltinLexicon.contains(whole.text, language: whole.to ?? .english))
            
            if isWholeInDict {
                best = whole
            } else if confidence < 0.9 && shouldPreferSplitOverWholeForDotCommaSeparator(original: token, split: split, whole: whole) {
                best = split
            } else {
                // When the router thinks whole-token correction is valid, only switch to split-mode
                // if it's meaningfully better. This avoids flipping to a different language just
                // because a short split-part looks "valid" by score.
                
                // Ticket 59 Fix: If whole candidate is a strong word (likely dictionary match)
                // and split candidate blindly preserves punctuation (e.g. 'xnj,' -> 'что,' instead of 'чтоб'),
                // force preference for the whole word.
                let wholeIsStrong = whole.score >= 0.9
                let splitPreservesPunct = (split.text.last == token.last && !(token.last?.isLetter ?? true))
                
                if wholeIsStrong && splitPreservesPunct {
                    best = whole
                } else {
                    best = (split.score > whole.score + 0.25) ? split : whole
                }
            }
        } else {
            // No strong whole-token correction → prefer split on ties.
            best = (split.score >= whole.score) ? split : whole
        }
        guard best.text != token else { return nil }
        // If our fast scoring can't distinguish (e.g. missing lexicon form),
        // still allow correction when the original scored as pure "unknown".
        if best.score > originalScore || (best.hypothesis != nil && originalScore == 0.0) {
            return best
        }
        return nil
    }

    // MARK: - Whole Candidate

    func buildWholeCandidate(
        token: String,
        decision: LanguageDecision,
        confidence: Double,
        activeLayouts: [String: String],
        minConfidence: Double
    ) -> SmartCorrection {
        if decision.layoutHypothesis.rawValue.contains("_from_"),
           confidence >= minConfidence,
           let (source, target) = languages(for: decision.layoutHypothesis) {
            
            // Ticket 64: Use Ensemble (all variants) to find best whole-word candidate.
            // This is critical for cases like "j," -> "об" where standard Mac mapping gives "о?"
            // but secondary (PC) mapping gives a valid lexicon word.
            let variants = LayoutMapper.shared.convertAllVariants(token, from: source, to: target, activeLayouts: activeLayouts)
            
            var bestConverted: String? = nil
            var bestScore: Double = -1.0
            
            for (_, text) in variants {
                let score = fastTextScore(text)
                // Prefer higher score. 
                // Note: fastTextScore uses BuiltinLexicon which returns 1.0 for valid words.
                if score > bestScore {
                    bestScore = score
                    bestConverted = text
                }
            }
            if let converted = bestConverted, converted != token {
                return SmartCorrection(
                    text: converted,
                    hypothesis: decision.layoutHypothesis,
                    from: source,
                    to: target,
                    score: bestScore
                )
            }
        }
        return SmartCorrection(text: token, hypothesis: nil, from: nil, to: nil, score: fastTextScore(token))
    }

    // MARK: - Split Candidate

    func buildSplitCandidate(
        token: String,
        context: DetectorContext,
        activeLayouts: [String: String],
        mode: DetectionMode,
        minConfidence: Double
    ) async -> SmartCorrection {
        let parts = splitWordRunsAndDelimiters(token)
        guard !parts.isEmpty else {
            return SmartCorrection(text: token, hypothesis: nil, from: nil, to: nil, score: 0.0)
        }

        var result = ""
        result.reserveCapacity(token.count)

        var hypCounts: [LanguageHypothesis: Int] = [:]

        for part in parts {
            guard part.isWord else {
                result.append(part.text)
                continue
            }

            let decision = await router.route(token: part.text, context: context, mode: mode)
            if decision.layoutHypothesis.rawValue.contains("_from_"),
               decision.confidence >= minConfidence,
               let (source, target) = languages(for: decision.layoutHypothesis),
               let corrected = LayoutMapper.shared.convertBest(part.text, from: source, to: target, activeLayouts: activeLayouts),
               corrected != part.text {
                result.append(corrected)
                hypCounts[decision.layoutHypothesis, default: 0] += 1
            } else {
                result.append(part.text)
            }
        }

        let dominantHypothesis = hypCounts.max(by: { $0.value < $1.value })?.key
        let langPair = dominantHypothesis.flatMap(languages(for:))

        return SmartCorrection(
            text: result,
            hypothesis: dominantHypothesis,
            from: langPair?.source,
            to: langPair?.target,
            score: fastTextScore(result)
        )
    }

    // MARK: - Separator Preference

    func shouldPreferSplitOverWholeForDotCommaSeparator(
        original: String,
        split: SmartCorrection,
        whole: SmartCorrection
    ) -> Bool {
        // If the original contains "." or "," between two reasonably long word runs, treat it as a separator,
        // and prefer the split candidate when whole-token conversion "swallows" the punctuation by mapping it to a letter.
        // Example: "ghbdtn.rfr" should become "привет.как", not "приветюкак".
        let parts = splitWordRunsAndDelimiters(original)
        guard parts.count >= 3 else { return false }

        for i in 1..<(parts.count - 1) {
            guard !parts[i].isWord else { continue }
            let delim = parts[i].text
            guard delim == "." || delim == "," else { continue }
            guard parts[i - 1].isWord, parts[i + 1].isWord else { continue }

            let leftLetters = parts[i - 1].text.filter { $0.isLetter }.count
            let rightLetters = parts[i + 1].text.filter { $0.isLetter }.count
            guard leftLetters >= 2, rightLetters >= 2 else { continue }

            if split.text.contains(delim), !whole.text.contains(delim) {
                return true
            }
        }

        return false
    }

    // MARK: - Per-Segment Correction

    /// Smart per-segment correction: analyze each word/segment and correct only wrong-layout parts
    func correctPerSegment(_ text: String, activeLayouts: [String: String]) async -> String? {
        // Split into segments preserving whitespace
        let segments = splitIntoSegments(text)
        guard segments.count > 1 else {
            // Single segment - no benefit from per-segment analysis
            return nil
        }

        var out = ""
        out.reserveCapacity(text.count)
        var anyChanged = false

        let context = DetectorContext(lastLanguage: nil)

        for segment in segments {
            // Preserve whitespace as-is
            if segment.allSatisfy({ $0.isWhitespace || $0.isNewline }) {
                out.append(segment)
                continue
            }

            if let smart = await bestSmartCorrection(
                for: segment,
                wholeDecision: nil,
                wholeConfidence: nil,
                context: context,
                activeLayouts: activeLayouts,
                mode: .manual,
                minConfidence: 0.25
            ) {
                out.append(smart.text)
                anyChanged = true
            } else {
                out.append(segment)
            }
        }

        return anyChanged ? out : nil
    }

    // MARK: - Text Splitting Helpers

    /// Split text into segments (words + whitespace preserved separately)
    func splitIntoSegments(_ text: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inWhitespace = false
        
        for char in text {
            let isWS = char.isWhitespace || char.isNewline
            if isWS != inWhitespace && !current.isEmpty {
                segments.append(current)
                current = ""
            }
            current.append(char)
            inWhitespace = isWS
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    func splitWordRunsAndDelimiters(_ text: String) -> [CompoundPart] {
        guard !text.isEmpty else { return [] }

        var parts: [CompoundPart] = []
        parts.reserveCapacity(min(16, text.count))

        var current = ""
        current.reserveCapacity(min(16, text.count))
        var inWord: Bool? = nil

        func flush() {
            guard !current.isEmpty, let inWord else { return }
            parts.append(CompoundPart(isWord: inWord, text: current))
            current.removeAll(keepingCapacity: true)
        }

        for ch in text {
            let isWordChar = ch.isLetter || ch.isNumber
            if let inWord, inWord != isWordChar {
                flush()
            }
            inWord = isWordChar
            current.append(ch)
        }
        flush()
        return parts
    }

    // MARK: - Scoring

    func fastWordScore(_ word: String, language: Language) -> Double {
        let trimmed = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }
        let unigramRaw = unigramModels[language]?.score(trimmed) ?? 0.0
        // Ignore ultra-rare unigram hits for English (they often include gibberish-like tokens).
        let unigram: Double
        switch language {
        case .english:
            unigram = unigramRaw >= 0.20 ? unigramRaw : 0.0
        case .russian, .hebrew:
            unigram = unigramRaw
        }
        let builtin = builtinValidator.confidence(for: trimmed, language: language)
        return max(unigram, builtin)
    }

    func bestWordScore(_ word: String) -> Double {
        max(
            fastWordScore(word, language: .english),
            fastWordScore(word, language: .russian),
            fastWordScore(word, language: .hebrew)
        )
    }

    func fastTextScore(_ text: String) -> Double {
        let words = text
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0.0 }
        return words.reduce(0.0) { $0 + bestWordScore($1) }
    }

    // MARK: - Short Token Override

    func shortTokenDominantOverride(
        token: String,
        from: Language,
        to: Language,
        activeLayouts: [String: String]
    ) -> ShortTokenOverride? {
        guard from != to else { return nil }
        guard token.count <= 2 else { return nil }
        guard token.allSatisfy({ $0.isLetter }) else { return nil }

        let hyp = hypothesisFor(source: from, target: to)
        guard hyp.rawValue.contains("_from_") else { return nil }

        guard let converted = LayoutMapper.shared.convertBest(token, from: from, to: to, activeLayouts: activeLayouts),
              converted != token else { return nil }

        let sourceScore = fastWordScore(token, language: from)
        let targetScore = fastWordScore(converted, language: to)

        // Only override when the target is a clearly better/common word in the dominant language.
        guard targetScore >= 0.70, targetScore >= sourceScore + 0.25 else { return nil }

        return ShortTokenOverride(corrected: converted, hypothesis: hyp, from: from, to: to)
    }
}
