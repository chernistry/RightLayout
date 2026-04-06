import Foundation
import AppKit
import os.log

// MARK: - Core Decision Logic (correctText, applyCorrection, earlyCorrection)

extension CorrectionEngine {

    // MARK: - Main Correction Entry Point

    func correctText(
        _ text: String,
        phraseBuffer: String = "",
        expectedLayout: Language? = nil,
        latencies: [TimeInterval] = [],
        editingEnvironment: EditingEnvironment = .accessibility
    ) async -> CorrectionResult {
        
        // Ticket 43: Don't correct empty or whitespace-only
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CorrectionResult(corrected: nil, action: .none, pendingCorrection: nil, pendingOriginal: nil, trackingId: nil, transliterationSuggestion: nil)
        }
        
        // Ticket 55: Zero Interference for international terms
        if languageData.zeroInterference.contains(text.lowercased()) {
            logger.info("🛡️ Zero Interference: '\(text)' is strictly preserved")
            return CorrectionResult(corrected: nil, action: .none, pendingCorrection: nil, pendingOriginal: nil, trackingId: nil, transliterationSuggestion: nil)
        }
        
        logger.info("🔍 === CORRECTION ATTEMPT ===")
        logger.info("Input: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        if let expected = expectedLayout {
            logger.info("Expected layout: \(expected.rawValue, privacy: .public)")
        }
        
        // Ticket 42: Safety Gating (Code/URL detection)
        // Check if text looks like code or URL/Command before expensive routing
        let intent = await intentDetector.detect(text: text)
        if intent != .prose {
             logger.info("🛡️ Intent detected: \(String(describing: intent)) - skipping correction for safety")
             return CorrectionResult(corrected: nil, action: .none, pendingCorrection: nil, pendingOriginal: nil, trackingId: nil, transliterationSuggestion: nil)
        }
        
        // Use last correction target as context
        var lastLang: Language? = nil
        if let lastRecord = history.first {
            lastLang = lastRecord.toLang
        }
        let context = DetectorContext(lastLanguage: lastLang)
        
        let evidence = await router.decisionEvidence(token: text, context: context)
        let decision = evidence.decision
        logger.info("✅ Decision: \(decision.language.rawValue, privacy: .public) (Hypothesis: \(decision.layoutHypothesis.rawValue, privacy: .public), Conf: \(decision.confidence))")
        
        var adjustedConfidence = evidence.confidence

        // Initialize personal features for V2 Personalization & Feedback
        // We do this early so it's available for both adjustment and feedback registration
        let bundleId = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier } ?? "unknown"
        
        // Ticket 53: Pass bio indicators (latencies)
        let features = await featureExtractor.extract(
            text: text, 
            phraseBuffer: phraseBuffer, // Ticket 52: Real phrase buffer
            appBundleId: bundleId,
            intent: intent == .code ? "code" : intent == .urlOrCommand ? "url" : "prose",
            latencies: latencies
        )
        
        let preset = await settings.behaviorPreset
        let baseDisposition = CorrectionDecisionPolicy.evaluate(
            evidence: evidence,
            environment: editingEnvironment,
            preset: preset
        )
        let currentTargetLang = decision.layoutHypothesis.targetLanguage
        let usesFastLane = evidence.tokenKind == .plain || evidence.isWhitelistedShort
        var riskPolicy = riskPolicy(for: baseDisposition)
        if await settings.isLearningEnabled {
            riskPolicy = await personalizationEngine.demote(
                policy: riskPolicy,
                features: features,
                isManualIntent: false
            )
        }

        if text.filter(\.isLetter).count <= 1 {
            riskPolicy = moreConservativeRiskPolicy(riskPolicy, .holdForHotkey)
        }

        if evidence.tokenKind == .short,
           evidence.isCorrection,
           BuiltinLexicon.contains(evidence.convertedText, language: evidence.targetLanguage) {
            adjustedConfidence = max(adjustedConfidence, 0.75)
        }

        let pendingCascade: (correction: String?, original: String?) = usesFastLane ? await resolvePendingCascade(
                bundleId: bundleId,
                decision: decision,
                currentTargetLanguage: currentTargetLang,
                adjustedConfidence: adjustedConfidence,
                threshold: await settings.standardPathThreshold,
                riskPolicy: riskPolicy,
                editingEnvironment: editingEnvironment
            ) : (correction: nil, original: nil)

        if usesFastLane || riskPolicy != .autoApply {
            return await handleFastLaneDecision(
                text: text,
                evidence: evidence,
                bundleId: bundleId,
                features: features,
                riskPolicy: riskPolicy,
                pendingCorrection: pendingCascade.correction,
                pendingOriginal: pendingCascade.original
            )
        }

        // Ticket 73: Apply sentence-level context boost
        if await settings.isLearningEnabled {
            let sentenceBoost = await patternTracker.confidenceBoost(
                appBundleId: bundleId,
                sequence: sentenceSequence,
                candidate: decision.layoutHypothesis.targetLanguage
            )
            if sentenceBoost > 0 {
                logger.info("🌊 Sentence Pattern Boost: \(adjustedConfidence) + \(sentenceBoost)")
                adjustedConfidence += sentenceBoost
            }
        }
        
        let threshold = await settings.standardPathThreshold
        let pendingCorrectionResult: String? = pendingCascade.correction
        let pendingOriginalText: String? = pendingCascade.original
        // Technical token guard:
        // If this token is a known "technical" shape (paths, UUIDs, semver, numeric timestamps),
        // never attempt smart splitting/correction in automatic mode.
        if router.isTechnicalToken(text) {
            logger.info("🛡️ Technical token - skipping correction: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            return CorrectionResult(corrected: nil, action: .none, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: nil, transliterationSuggestion: nil)
        }

        // Smart handling for tokens with internal punctuation/symbols:
        // - If punctuation is actually a mapped RU/HE letter (e.g. "k.,k.", "cj;fktyb."), whole-token conversion should win.
        // - If punctuation is a separator between multiple words (e.g. "ghbdtn.rfr"), split + per-word conversion should win.
        if text.contains(where: { !$0.isLetter && !$0.isNumber }) {
            let activeLayouts = await settings.activeLayouts
            if let smart = await bestSmartCorrection(
                for: text,
                wholeDecision: decision,
                wholeConfidence: decision.confidence,
                context: context,
                activeLayouts: activeLayouts,
                mode: .automatic,
                minConfidence: 0.6
            ) {
                
                // Ticket 71: Verify smart correction before applying
                if await settings.isVerifierEnabled,
                   let hyp = smart.hypothesis {
                    let verifierCtx = CorrectionVerifierAgent.VerifierContext(
                        sentenceDominantLanguage: sentenceDominantLanguage,
                        sentenceWordCount: sentenceWordCount
                    )
                    let verdict = await verifier.verify(
                        original: text,
                        proposed: smart.text,
                        hypothesis: hyp,
                        baseConfidence: decision.confidence,
                        context: verifierCtx,
                        activeLayouts: activeLayouts
                    )
                    if !verdict.shouldApply {
                        logger.info("🔍 Verifier REJECTED smart correction: \(verdict.reason)")
                        // Fall through to standard path
                    } else {
                        // Ticket 59: Only apply if significantly better, OR if it's a "technical" fix
                        // ...
                        if let from = smart.from, let to = smart.to {
                            let (applied, transaction) = await applyCorrection(original: text, corrected: smart.text, from: from, to: to, hypothesis: hyp, bundleId: bundleId, features: features, riskPolicy: riskPolicy)
                            if sentenceDominantLanguage == nil {
                                sentenceDominantLanguage = to
                                sentenceWordCount = 1
                            } else if sentenceDominantLanguage == to {
                                sentenceWordCount += 1
                            }
                            return CorrectionResult(corrected: applied, action: .applied, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: transaction?.id, transaction: transaction, transliterationSuggestion: nil, confidence: adjustedConfidence, targetLanguage: to)
                        }
                        return CorrectionResult(corrected: smart.text, action: .applied, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: nil, transliterationSuggestion: nil, confidence: adjustedConfidence, targetLanguage: nil)
                    }
                } else {
                    // Verifier disabled or no cross-layout hypothesis — apply directly
                    // Ticket 59: Only apply if significantly better, OR if it's a "technical" fix
                    // ...
                    if let hyp = smart.hypothesis, let from = smart.from, let to = smart.to {
                        let (applied, transaction) = await applyCorrection(original: text, corrected: smart.text, from: from, to: to, hypothesis: hyp, bundleId: bundleId, features: features, riskPolicy: riskPolicy)
                        if sentenceDominantLanguage == nil {
                            sentenceDominantLanguage = to
                            sentenceWordCount = 1
                        } else if sentenceDominantLanguage == to {
                            sentenceWordCount += 1
                        }
                        return CorrectionResult(corrected: applied, action: .applied, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: transaction?.id, transaction: transaction, transliterationSuggestion: nil, confidence: adjustedConfidence, targetLanguage: to)
                    }
                    return CorrectionResult(corrected: smart.text, action: .applied, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: nil, transliterationSuggestion: nil, confidence: adjustedConfidence, targetLanguage: nil)
                }
            }
        }
        
        // Update sentence dominant language when we have high confidence
        if adjustedConfidence > threshold {
            let targetLang = decision.layoutHypothesis.targetLanguage
            if sentenceDominantLanguage == nil {
                sentenceDominantLanguage = targetLang
                sentenceWordCount = 1
            } else if targetLang == sentenceDominantLanguage {
                sentenceWordCount += 1
            }
        }
        
        // Check whitelist for Hebrew short words (Ticket 55) - vital for "Yes"/"No" (כן/לא)
        // Check whitelist for Hebrew short words (Ticket 55) - vital for "Yes"/"No" (כן/לא)
        var hebrewShortWordCandidate: String? = nil
        let heWords = languageData.hebrewCommonShortWords
        
        // Robust check: does ANY English->Hebrew mapping yield a common short word?
        let enVariants = LayoutMapper.shared.convertAllVariants(text, from: .english, to: .hebrew)
        if let match = enVariants.first(where: { heWords.contains($0.result) }) {
            hebrewShortWordCandidate = match.result
        }
        
        // Check Russian->Hebrew
        if hebrewShortWordCandidate == nil {
            let ruVariants = LayoutMapper.shared.convertAllVariants(text, from: .russian, to: .hebrew)
            if let match = ruVariants.first(where: { heWords.contains($0.result) }) {
                hebrewShortWordCandidate = match.result
            }
        }
        
        let isHeShortWord = (hebrewShortWordCandidate != nil)

        // Only apply correction if adjusted confidence is high enough
        // Exception: Common Hebrew short words (like "lo"/"kt") pass with slightly lower confidence
        let isShortCorrectionCandidate = text.filter(\.isLetter).count <= 3 && decision.layoutHypothesis.rawValue.contains("_from_")
        let effectiveThreshold: Double
        if isHeShortWord {
            effectiveThreshold = min(threshold, 0.3)
        } else if isShortCorrectionCandidate {
            effectiveThreshold = min(threshold, 0.58)
        } else {
            effectiveThreshold = threshold
        }
        
        // FIX: Allow Hebrew short words to bypass confidence threshold entirely
        // They will be force-corrected later in the flow (lines 621-627)
        guard adjustedConfidence > effectiveThreshold || isHeShortWord else {
            logger.info("⏭️ Skipping correction (confidence too low after adjustment)")
            
            // Store as pending if confidence is in "uncertain" range (e.g., 0.4-0.7)
            let minPendingConfidence = ThresholdsConfig.shared.timing.pendingWordMinConfidence
            
            // For single-letter tokens that could be Russian prepositions OR common short Hebrew words, lower the threshold
            let isPrepositionCandidate = (text.count == 1 && russianPrepositionMappings[text.lowercased()] != nil) || isHeShortWord
            let effectiveMinConfidence = isPrepositionCandidate ? ThresholdsConfig.shared.timing.prepositionMinConfidence : minPendingConfidence
            
            if adjustedConfidence >= effectiveMinConfidence || isPrepositionCandidate {
                let isFirst = sentenceWordCount == 0 && pendingWord == nil
                pendingWord = PendingWord(
                    text: text,
                    decision: decision,
                    adjustedConfidence: adjustedConfidence,
                    timestamp: Date(),
                    isFirstWord: isFirst,
                    candidates: nil, 
                    isAmbiguousValid: false
                )
            }
            return CorrectionResult(corrected: nil, action: .none, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: nil, transliterationSuggestion: nil)
        }
        
        // Check if the decision implies a layout correction
        var needsCorrection = (decision.language != currentTargetLang)
        var sourceLayout: Language = decision.language
        var targetLayout: Language = decision.language
        
        switch decision.layoutHypothesis {
        case .ru, .en, .he:
            // Text is already in correct layout
            needsCorrection = false
            sourceLayout = decision.language
        case .ruFromEnLayout:
            needsCorrection = true
            sourceLayout = .english
        case .heFromEnLayout:
            needsCorrection = true
            sourceLayout = .english
        case .enFromRuLayout:
            needsCorrection = true
            sourceLayout = .russian
        case .enFromHeLayout:
            needsCorrection = true
            sourceLayout = .hebrew
        case .heFromRuLayout:
            needsCorrection = true
            sourceLayout = .russian
        case .ruFromHeLayout:
            needsCorrection = true
            sourceLayout = .hebrew
        }
        
        // Ticket 55: If we detected a valid Hebrew short word (like "lo" -> "לא"), force correction
        if !needsCorrection && isHeShortWord {
             logger.info("🇮🇱 Force-correcting Hebrew short word override: '\(text)' -> '\(hebrewShortWordCandidate ?? "")'")
             needsCorrection = true
             sourceLayout = .english 
             targetLayout = .hebrew
        }
        
        if !needsCorrection {
            // Context override for short ambiguous tokens inside a strong sentence.
            // Example: "vs" should become "мы" inside a Russian sentence.
            if let dominant = sentenceDominantLanguage,
               dominant != decision.language,
               sentenceWordCount >= 2,
               text.count <= 2,
               text.allSatisfy({ $0.isLetter }) {
                let activeLayouts = await settings.activeLayouts
                if let override = shortTokenDominantOverride(token: text, from: decision.language, to: dominant, activeLayouts: activeLayouts) {
                    let (applied, transaction) = await applyCorrection(
                        original: text,
                        corrected: override.corrected,
                        from: override.from,
                        to: override.to,
                        hypothesis: override.hypothesis,
                        bundleId: bundleId,
                        features: features,
                        riskPolicy: riskPolicy
                    )
                    return CorrectionResult(corrected: applied, action: .applied, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: transaction?.id, transaction: transaction, transliterationSuggestion: nil, confidence: adjustedConfidence, targetLanguage: override.to)
                }
            }

            // Ticket 49: If token is valid in current layout BUT is short (<= 2) and prose,
            // check if it has strong candidates in other languages. If so, store as Ambiguous Pending.
            if text.count <= 2
               && intent == .prose
               && pendingWord == nil
               && !router.isTechnicalToken(text) {

                // Generate candidates for other languages
                var strongCandidates: [Language: String] = [:]
                let activeLayouts = await settings.activeLayouts

                for target in Language.allCases where target != decision.language {
                    // Check if conversion hits BuiltinLexicon OR high frequency unigram
                    if let converted = LayoutMapper.shared.convertBest(text, from: decision.language, to: target, activeLayouts: activeLayouts) {
                        // Check weak lexicon (Builtin) or Unigram
                        let isLexicon = BuiltinLexicon.contains(converted, language: target)
                        let isSingleWord = converted.count == 1 && LanguageDataConfig.shared.russianPrepositions.values.contains(converted.lowercased())
                        let freq = unigramModels[target]?.score(converted) ?? 0.0
                        let isHighFreq = freq > 0.0001 // empirical check for common words like "ну", "на", "он"

                        if isLexicon || isSingleWord || isHighFreq {
                            strongCandidates[target] = converted
                        }
                    }
                }

                if !strongCandidates.isEmpty {
                    logger.info("⏳ Storing ambiguous pending token '\(text)' with candidates: \(strongCandidates)")
                    pendingWord = PendingWord(
                        text: text,
                        decision: decision,
                        adjustedConfidence: 1.0, // It was valid, so 1.0 confidence in source
                        timestamp: Date(),
                        isFirstWord: sentenceWordCount == 0,
                        candidates: strongCandidates,
                        isAmbiguousValid: true
                    )
                }
            }

            logger.info("ℹ️ No correction needed - text is in correct layout, but creating cycling state for manual override")

            // Even if no correction needed, create cycling state so user can force-convert
            let activeLayouts = await settings.activeLayouts
            var alternatives: [CyclingContext.Alternative] = [
                CyclingContext.Alternative(text: text, hypothesis: decision.layoutHypothesis)  // [0] Original (current)
            ]

            // Add conversions to other languages
            for target in Language.allCases where target != decision.language {
                if let alt = LayoutMapper.shared.convertBest(text, from: decision.language, to: target, activeLayouts: activeLayouts), alt != text {
                    let hyp = hypothesisFor(source: decision.language, target: target)
                    alternatives.append(CyclingContext.Alternative(text: alt, hypothesis: hyp))
                }
            }

            if alternatives.count > 1 {
                cyclingState = CyclingContext(
                    originalText: text,
                    alternatives: alternatives,
                    currentIndex: 0,  // Currently showing original
                    wasAutomatic: false,  // No auto-correction happened
                    autoHypothesis: decision.layoutHypothesis,
                    timestamp: Date(),
                    trailingSeparator: "",
                    visibleAlternativesCount: min(alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound1),
                    cycleCount: 0
                )
            }

            // Ticket 45 Fix: Ensure preposition candidates are stored as pending
            // even if they are valid in current layout (e.g. "e" is valid English, but might be "у" in context)
            if pendingWord == nil && text.count == 1 && russianPrepositionMappings[text.lowercased()] != nil {
                // Store with high confidence since it was deemed valid
                pendingWord = PendingWord(
                    text: text,
                    decision: decision,
                    adjustedConfidence: 1.0,
                    timestamp: Date(),
                    isFirstWord: sentenceWordCount == 0,
                    candidates: [.russian: russianPrepositionMappings[text.lowercased()]!],
                    isAmbiguousValid: true
                )
            }

            let transliterationSuggestion = await maybeSuggestTransliteration(for: text, intent: intent, features: features)

            // Ticket 73: Record valid word language to sentence sequence
            if intent == .prose && !router.isTechnicalToken(text) {
                sentenceSequence.append(decision.language)
            }

            return CorrectionResult(corrected: nil, action: .none, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: nil, transliterationSuggestion: transliterationSuggestion)
        }

        // Attempt conversion - try ALL target layout variants
        let activeLayouts = await settings.activeLayouts
        let variants = LayoutMapper.shared.convertAllVariants(text, from: sourceLayout, to: targetLayout, activeLayouts: activeLayouts)
        
        // Pick the variant that's in the builtin lexicon, or first one if none match
        var corrected: String? = nil
        for (_, converted) in variants {
            if BuiltinLexicon.contains(converted, language: targetLayout) {
                corrected = converted
                break
            }
            if corrected == nil {
                corrected = converted
            }
        }
        
        if let corrected = corrected {
            logger.info("✅ VALID CONVERSION FOUND! (Ensemble)")
            
            // Store cycling state for potential undo
            // Order: [0]=original (undo target), [1]=corrected (current), [2+]=other alternatives
            var alternatives: [CyclingContext.Alternative] = [
                CyclingContext.Alternative(text: text, hypothesis: nil),  // [0] Original (undo target)
                CyclingContext.Alternative(text: corrected, hypothesis: decision.layoutHypothesis)  // [1] Corrected
            ]
            
            // Add other possible conversions
            for target in Language.allCases where target != targetLayout && target != sourceLayout {
                if let alt = LayoutMapper.shared.convertBest(text, from: sourceLayout, to: target, activeLayouts: activeLayouts), alt != corrected {
                    let hyp = hypothesisFor(source: sourceLayout, target: target)
                    alternatives.append(CyclingContext.Alternative(text: alt, hypothesis: hyp))
                }
            }
            
            // currentIndex=1 means we're at corrected; next() will go to 2, then 0 (undo)
            // But we want first hotkey press to UNDO, so we need special handling
            // Wait, if we AUTO-CORRECT, we are at [1]. Next hotkey -> [2] or [0]?
            // If we SUPPRESS, we are at [0] (Original). Next hotkey -> [1] (Corrected).
            
            // Logic for indexing:
            // If AutoApply: start at 1.
            // If Suppress: start at 0.
            
            // Ticket 61: Logic for indexing based on Risk Policy
            // If AutoApply: start at 1 (Corrected).
            // If Hint/Hold: start at 0 (Original), wait for hotkey.
            
            
            // Ticket 71: Verify main conversion before applying
            if await settings.isVerifierEnabled, text.filter(\.isLetter).count > 3 {
                let verifierCtx = CorrectionVerifierAgent.VerifierContext(
                    sentenceDominantLanguage: sentenceDominantLanguage,
                    sentenceWordCount: sentenceWordCount
                )
                let verdict = await verifier.verify(
                    original: text,
                    proposed: corrected,
                    hypothesis: decision.layoutHypothesis,
                    baseConfidence: adjustedConfidence,
                    context: verifierCtx,
                    activeLayouts: activeLayouts
                )
                if !verdict.shouldApply {
                    logger.info("🔍 Verifier REJECTED main conversion: \(verdict.reason)")
                    return CorrectionResult(corrected: nil, action: .none, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: nil, transliterationSuggestion: nil)
                }
                // Use verifier's adjusted confidence for downstream RiskController
                adjustedConfidence = verdict.adjustedConfidence
            }
            
            let finalRiskPolicy = riskPolicy

            if finalRiskPolicy == .reject {
                let transliterationSuggestion = await maybeSuggestTransliteration(for: text, intent: intent, features: features)
                return CorrectionResult(
                    corrected: nil,
                    action: .none,
                    pendingCorrection: pendingCorrectionResult,
                    pendingOriginal: pendingOriginalText,
                    trackingId: nil,
                    transliterationSuggestion: transliterationSuggestion,
                    confidence: adjustedConfidence,
                    targetLanguage: nil
                )
            }
            
            let startIndex: Int
            let finalAction: CorrectionAction
            let finalCorrectedText: String?
            var finalTransaction: CorrectionTransaction?
            
            if finalRiskPolicy == .suggestHint || finalRiskPolicy == .holdForHotkey {
                startIndex = 0 // Show original
                finalAction = .hint
                finalCorrectedText = nil // Do not replace text
                
                // Store pending suggestion
                logger.info("💡 Hint-Only Mode: Storing pending suggestion '\(corrected)'")
                pendingSuggestion = PendingSuggestion(
                    original: text,
                    corrected: corrected,
                    from: sourceLayout,
                    to: decision.language,
                    hypothesis: decision.layoutHypothesis,
                    decisionLayoutHypothesis: decision.layoutHypothesis,
                    features: features,
                    timestamp: Date(),
                    bundleId: bundleId,
                    transaction: CorrectionTransaction(
                        token: text,
                        replacement: corrected,
                        bundleId: bundleId,
                        intent: .manualCycle,
                        targetLanguage: decision.language,
                        hypothesis: decision.layoutHypothesis,
                        features: features,
                        wasAutoApplied: false
                    )
                )
            } else {
                startIndex = 1 // Show corrected
                finalAction = .applied
                
                // Apply immediately
                let (appliedText, tId) = await applyCorrection(
                    original: text,
                    corrected: corrected,
                    from: sourceLayout,
                    to: decision.language,
                    hypothesis: decision.layoutHypothesis,
                    bundleId: bundleId,
                    features: features,
                    riskPolicy: finalRiskPolicy,
                    confidence: adjustedConfidence,
                    correctionPolicy: .autoApplied,
                    switchInputSource: false
                )
                finalCorrectedText = appliedText
                finalTransaction = tId
            }
            
            cyclingState = CyclingContext(
                originalText: text,
                alternatives: alternatives,
                currentIndex: startIndex,
                wasAutomatic: true,
                autoHypothesis: decision.layoutHypothesis,
                timestamp: Date(),
                trailingSeparator: "",
                visibleAlternativesCount: min(alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound1),
                cycleCount: 0
            )

            // Log for learning
            let appBundleId = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            CorrectionLogger.shared.log(
                original: text,
                final: finalAction == .applied ? corrected : "",
                autoAttempted: decision.layoutHypothesis,
                userSelected: nil,  // Auto, not user-selected
                app: appBundleId
            )

            return CorrectionResult(
                corrected: finalCorrectedText,
                action: finalAction,
                pendingCorrection: pendingCorrectionResult,
                pendingOriginal: pendingOriginalText,
                trackingId: finalTransaction?.id,
                transaction: finalTransaction,
                transliterationSuggestion: nil,
                confidence: adjustedConfidence,
                targetLanguage: decision.language
            )
        }
        
        logger.info("ℹ️ No correction found")
        let transliterationSuggestion = await maybeSuggestTransliteration(for: text, intent: intent, features: features)
        return CorrectionResult(corrected: nil, action: .none, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText, trackingId: nil, transliterationSuggestion: transliterationSuggestion)
    }

    // MARK: - Apply Pending Suggestion

    // Ticket 61: Apply pending suggestion manually
    func applyPendingSuggestion() async -> CorrectionResult? {
        guard let pending = pendingSuggestion else { return nil }
        
        // Timeout check (e.g. 10s)
        if Date().timeIntervalSince(pending.timestamp) > 10.0 {
            pendingSuggestion = nil
            return nil
        }
        
        logger.info("🚀 Applying Pending Suggestion via Hotkey: '\(pending.original)' -> '\(pending.corrected)'")
        
        // Use autoApply policy since user explicitly requested it via hotkey
        let (applied, transaction) = await applyCorrection(
            original: pending.original,
            corrected: pending.corrected,
            from: pending.from,
            to: pending.to,
            hypothesis: pending.hypothesis,
            bundleId: pending.bundleId,
            features: pending.features,
            riskPolicy: .autoApply,
            correctionPolicy: .manual,
            switchInputSource: false
        )
        
        // Update cycling state to point to corrected (index 1)
        if var state = cyclingState, state.originalText == pending.original {
            state.currentIndex = 1
            cyclingState = state
        }
        
        pendingSuggestion = nil
        
        return CorrectionResult(
            corrected: applied,
            action: .applied,
            pendingCorrection: nil,
            pendingOriginal: nil,
            trackingId: transaction?.id,
            transaction: transaction,
            transliterationSuggestion: nil,
            targetLanguage: pending.to
        )
    }

    // MARK: - Transliteration Suggestion

    func maybeSuggestTransliteration(for text: String, intent: UserIntent, features: PersonalFeatures) async -> TransliterationSuggestion? {
        guard intent == .prose else { return nil }
        guard await settings.transliterationHintsEnabled else { return nil }
        guard !router.isTechnicalToken(text) else { return nil }

        guard let suggestion = await transliterationDetector.suggest(for: text) else { return nil }

        // Ticket 55: Use RiskController to ensure we only show hints when policy allows at least hint-level behavior.
        let policy = await RiskController.shared.evaluate(candidateConfidence: suggestion.confidence, contextKey: features.contextKey)
        guard policy == .suggestHint || policy == .autoApply else { return nil }
        return suggestion
    }

    private func handleFastLaneDecision(
        text: String,
        evidence: DecisionEvidence,
        bundleId: String,
        features: PersonalFeatures,
        riskPolicy: RiskPolicy,
        pendingCorrection: String?,
        pendingOriginal: String?
    ) async -> CorrectionResult {
        let transliterationSuggestion = await maybeSuggestTransliteration(
            for: text,
            intent: .prose,
            features: features
        )

        guard evidence.isCorrection,
              let sourceLayout = evidence.sourceLayout,
              evidence.convertedText != text else {
            return CorrectionResult(
                corrected: nil,
                action: .none,
                pendingCorrection: pendingCorrection,
                pendingOriginal: pendingOriginal,
                trackingId: nil,
                transliterationSuggestion: transliterationSuggestion,
                confidence: evidence.confidence,
                targetLanguage: evidence.targetLanguage,
                evidence: evidence
            )
        }

        let alternatives = await automaticAlternatives(
            original: text,
            corrected: evidence.convertedText,
            sourceLayout: sourceLayout,
            targetLayout: evidence.targetLanguage,
            hypothesis: evidence.decision.layoutHypothesis
        )

        switch riskPolicy {
        case .autoApply:
            let (applied, transaction) = await applyCorrection(
                original: text,
                corrected: evidence.convertedText,
                from: sourceLayout,
                to: evidence.targetLanguage,
                hypothesis: evidence.decision.layoutHypothesis,
                bundleId: bundleId,
                features: features,
                riskPolicy: riskPolicy,
                confidence: evidence.confidence,
                correctionPolicy: .autoApplied,
                switchInputSource: false
            )
            cyclingState = CyclingContext(
                originalText: text,
                alternatives: alternatives,
                currentIndex: min(1, max(0, alternatives.count - 1)),
                wasAutomatic: true,
                autoHypothesis: evidence.decision.layoutHypothesis,
                timestamp: Date(),
                trailingSeparator: "",
                visibleAlternativesCount: min(alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound1),
                cycleCount: 0
            )
            registerSentenceContext(evidence.targetLanguage)
            return CorrectionResult(
                corrected: applied,
                action: .applied,
                pendingCorrection: pendingCorrection,
                pendingOriginal: pendingOriginal,
                trackingId: transaction?.id,
                transaction: transaction,
                transliterationSuggestion: nil,
                confidence: evidence.confidence,
                targetLanguage: evidence.targetLanguage,
                evidence: evidence
            )
        case .suggestHint, .holdForHotkey:
            let transaction = CorrectionTransaction(
                token: text,
                replacement: evidence.convertedText,
                bundleId: bundleId,
                intent: .manualCycle,
                targetLanguage: evidence.targetLanguage,
                hypothesis: evidence.decision.layoutHypothesis,
                features: features,
                wasAutoApplied: false
            )
            pendingSuggestion = PendingSuggestion(
                original: text,
                corrected: evidence.convertedText,
                from: sourceLayout,
                to: evidence.targetLanguage,
                hypothesis: evidence.decision.layoutHypothesis,
                decisionLayoutHypothesis: evidence.decision.layoutHypothesis,
                features: features,
                timestamp: Date(),
                bundleId: bundleId,
                transaction: transaction
            )
            cyclingState = CyclingContext(
                originalText: text,
                alternatives: alternatives,
                currentIndex: 0,
                wasAutomatic: true,
                autoHypothesis: evidence.decision.layoutHypothesis,
                timestamp: Date(),
                trailingSeparator: "",
                visibleAlternativesCount: min(alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound1),
                cycleCount: 0
            )
            return CorrectionResult(
                corrected: nil,
                action: .hint,
                pendingCorrection: pendingCorrection,
                pendingOriginal: pendingOriginal,
                trackingId: transaction.id,
                transaction: transaction,
                transliterationSuggestion: nil,
                confidence: evidence.confidence,
                targetLanguage: evidence.targetLanguage,
                evidence: evidence
            )
        case .reject:
            return CorrectionResult(
                corrected: nil,
                action: .none,
                pendingCorrection: pendingCorrection,
                pendingOriginal: pendingOriginal,
                trackingId: nil,
                transliterationSuggestion: transliterationSuggestion,
                confidence: evidence.confidence,
                targetLanguage: evidence.targetLanguage,
                evidence: evidence
            )
        }
    }

    private func registerSentenceContext(_ language: Language) {
        sentenceSequence.append(language)
        if sentenceDominantLanguage == nil {
            sentenceDominantLanguage = language
            sentenceWordCount = 1
        } else if sentenceDominantLanguage == language {
            sentenceWordCount += 1
        }
    }

    private func resolvePendingCascade(
        bundleId: String,
        decision: LanguageDecision,
        currentTargetLanguage: Language,
        adjustedConfidence: Double,
        threshold: Double,
        riskPolicy: RiskPolicy,
        editingEnvironment: EditingEnvironment
    ) async -> (correction: String?, original: String?) {
        guard let pending = pendingWord, pending.isValid else {
            return (nil, nil)
        }

        guard editingEnvironment == .accessibility,
              riskPolicy == .autoApply,
              pending.text.filter(\.isLetter).count > 1 else {
            pendingWord = nil
            return (nil, nil)
        }

        var pendingCorrectionResult: String?
        var pendingOriginalText: String?
        var cascadeApplied = false

        if pending.isAmbiguousValid,
           let candidates = pending.candidates,
           let candidateCorrection = candidates[currentTargetLanguage],
           editingEnvironment == .accessibility,
           riskPolicy != .reject,
           adjustedConfidence >= 0.68 {
            logger.info("🌊 Cascade trigger: current confirms \(currentTargetLanguage.rawValue), correcting pending '\(pending.text)' → '\(candidateCorrection)'")

            let hypothesis = hypothesisFor(source: .english, target: currentTargetLanguage)
            let (_, _) = await applyCorrection(
                original: pending.text,
                corrected: candidateCorrection,
                from: .english,
                to: currentTargetLanguage,
                hypothesis: hypothesis,
                bundleId: bundleId,
                riskPolicy: .autoApply
            )
            pendingCorrectionResult = candidateCorrection
                pendingOriginalText = pending.text
                cascadeApplied = true
        }

        if !cascadeApplied {
            if adjustedConfidence > threshold,
               currentTargetLanguage == pending.decision.layoutHypothesis.targetLanguage {
                let boostedConfidence = pending.adjustedConfidence + contextBoostAmount
                logger.info("🔗 Context boost: pending '\(pending.text)' \(pending.adjustedConfidence) → \(boostedConfidence)")

                if boostedConfidence > threshold,
                   let corrected = await applyCorrection(
                    pending.text,
                    decision: pending.decision,
                    bundleId: bundleId,
                    riskPolicy: riskPolicy
                   ) {
                    pendingCorrectionResult = corrected
                    pendingOriginalText = pending.text
                    logger.info("✅ Pending word corrected via context boost: '\(pending.text)' → '\(corrected)'")
                }
            }
        }

        pendingWord = nil
        return (pendingCorrectionResult, pendingOriginalText)
    }

    private func automaticAlternatives(
        original: String,
        corrected: String,
        sourceLayout: Language,
        targetLayout: Language,
        hypothesis: LanguageHypothesis
    ) async -> [CyclingContext.Alternative] {
        let activeLayouts = await settings.activeLayouts
        var alternatives: [CyclingContext.Alternative] = [
            CyclingContext.Alternative(text: original, hypothesis: nil),
            CyclingContext.Alternative(text: corrected, hypothesis: hypothesis)
        ]

        for target in Language.allCases where target != sourceLayout && target != targetLayout {
            guard let alternative = LayoutMapper.shared.convertBest(
                original,
                from: sourceLayout,
                to: target,
                activeLayouts: activeLayouts
            ) else {
                continue
            }
            guard alternative != original,
                  alternative != corrected,
                  !alternatives.contains(where: { $0.text == alternative }) else {
                continue
            }
            alternatives.append(
                CyclingContext.Alternative(
                    text: alternative,
                    hypothesis: hypothesisFor(source: sourceLayout, target: target)
                )
            )
        }

        return alternatives
    }

    // MARK: - Apply Correction

    func applyCorrection(original: String, corrected: String, from: Language, to: Language, hypothesis: LanguageHypothesis, bundleId: String?, features: PersonalFeatures? = nil, riskPolicy: RiskPolicy, confidence: Double? = nil, correctionPolicy: HistoryManager.CorrectionPolicy? = nil, switchInputSource: Bool = false) async -> (String, CorrectionTransaction?) {
        _ = from
        _ = riskPolicy
        _ = confidence
        _ = switchInputSource
        let intent: TextEditIntent = correctionPolicy == .manual ? .manualCycle : .autoCorrection
        let activeLayouts = await settings.activeLayouts
        let currentLayoutId = await InputSourceManager.shared.currentLayoutId()
        let transaction = CorrectionTransaction(
            token: original,
            replacement: corrected,
            bundleId: bundleId,
            intent: intent,
            targetLanguage: to,
            hypothesis: hypothesis,
            features: features,
            wasAutoApplied: correctionPolicy != .manual,
            inputSourceBefore: currentLayoutId,
            inputSourceAfterExpected: activeLayouts[to.rawValue]
        )
        return (corrected, transaction)
    }

    /// Apply correction based on a decision (for pending word boost)
    func applyCorrection(_ text: String, decision: LanguageDecision, bundleId: String? = nil, riskPolicy: RiskPolicy) async -> String? {
        let sourceLayout: Language
        switch decision.layoutHypothesis {
        case .ru, .en, .he: return nil  // No correction needed
        case .ruFromEnLayout, .heFromEnLayout: sourceLayout = .english
        case .enFromRuLayout, .heFromRuLayout: sourceLayout = .russian
        case .enFromHeLayout, .ruFromHeLayout: sourceLayout = .hebrew
        }
        
        let activeLayouts = await settings.activeLayouts
        let variants = LayoutMapper.shared.convertAllVariants(text, from: sourceLayout, to: decision.language, activeLayouts: activeLayouts)

        var corrected: String? = nil
        for (_, converted) in variants {
            if BuiltinLexicon.contains(converted, language: decision.language) {
                corrected = converted
                break
            }
            if corrected == nil {
                corrected = converted
            }
        }

        guard let corrected else { return nil }
        
        let (res, _) = await applyCorrection(
            original: text,
            corrected: corrected,
            from: sourceLayout,
            to: decision.language,
            hypothesis: decision.layoutHypothesis,
            bundleId: bundleId,
            riskPolicy: riskPolicy,
            switchInputSource: false
        )
        return res
    }

    func contextualCascadeCorrection(for text: String, targetLanguage: Language) async -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.filter(\.isLetter).count <= 2 else {
            return nil
        }

        let activeLayouts = await settings.activeLayouts
        for source in Language.allCases where source != targetLanguage {
            guard let converted = LayoutMapper.shared.convertBest(
                normalized,
                from: source,
                to: targetLanguage,
                activeLayouts: activeLayouts
            ), converted != normalized else {
                continue
            }

            if BuiltinLexicon.contains(converted, language: targetLanguage) {
                return converted
            }

            if let unigram = unigramModels[targetLanguage], unigram.score(converted) > 0.0001 {
                return converted
            }

            if converted.filter(\.isLetter).count <= 2, converted.allSatisfy(\.isLetter) {
                return converted
            }
        }

        return nil
    }

    func shortWordCorrectionCandidate(for text: String) async -> (replacement: String, targetLanguage: Language, hypothesis: LanguageHypothesis)? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.filter(\.isLetter).count <= 3 else {
            return nil
        }

        let activeLayouts = await settings.activeLayouts
        var best: (replacement: String, targetLanguage: Language, hypothesis: LanguageHypothesis, score: Double)?

        for source in Language.allCases {
            for target in Language.allCases where target != source {
                let hypothesis = hypothesisFor(source: source, target: target)
                guard let converted = LayoutMapper.shared.convertBest(
                    normalized,
                    from: source,
                    to: target,
                    activeLayouts: activeLayouts
                ), converted != normalized else {
                    continue
                }

                let builtin = BuiltinLexicon.contains(converted, language: target)
                let frequency = unigramModels[target]?.score(converted) ?? 0.0
                guard builtin || frequency > 0.0001 else { continue }

                let score = (builtin ? 1.0 : 0.0) + frequency
                if best == nil || score > best!.score {
                    best = (converted, target, hypothesis, score)
                }
            }
        }

        guard let best else { return nil }
        return (best.replacement, best.targetLanguage, best.hypothesis)
    }

    // MARK: - Early Correction

    func checkEarlyCorrection(_ text: String, bundleId: String? = nil) async -> String? {
        guard await shouldCorrect(for: bundleId) else { return nil }
        
        if let decision = await router.checkEarlySwitch(token: text) {
             logger.info("🚀 CONFIRMED Early Switch: \(text) detected as \(decision.language.rawValue)")
             
             // Determine source layout from hypothesis
             let source: Language
             switch decision.layoutHypothesis {
             case .ruFromEnLayout, .heFromEnLayout: source = .english
             case .enFromRuLayout, .heFromRuLayout: source = .russian
             case .enFromHeLayout, .ruFromHeLayout: source = .hebrew
             default: source = .english
             }
             
             // Apply correction using the single best hypothesis found by router
             let activeLayouts = await settings.activeLayouts
             let target = decision.language
             
             // Re-convert to get the string (router only returned decision, not string)
               // Optimization: We could have router return string, but for now re-computing is cheap for 3 chars.
                if let corrected = LayoutMapper.shared.convertBest(text, from: source, to: target, activeLayouts: activeLayouts) {
                    // Early correction is by definition strong/verified, so we allow AutoApply
                    let (_, _) = await applyCorrection(
                        original: text,
                        corrected: corrected,
                        from: source,
                        to: target,
                        hypothesis: decision.layoutHypothesis,
                        bundleId: bundleId,
                        riskPolicy: .autoApply,
                        switchInputSource: false
                    )
                    
                    // Update sentence stats so subsequent words know the new context
                 if sentenceDominantLanguage == nil {
                     sentenceDominantLanguage = target
                     sentenceWordCount = 1
                 }
                 
                 return corrected
             }
        }
        return nil
    }
}

private func riskPolicy(for disposition: CorrectionDisposition) -> RiskPolicy {
    switch disposition {
    case .autoApply:
        return .autoApply
    case .hint:
        return .suggestHint
    case .manualOnly:
        return .holdForHotkey
    case .reject:
        return .reject
    }
}

private func moreConservativeRiskPolicy(_ lhs: RiskPolicy, _ rhs: RiskPolicy) -> RiskPolicy {
    lhs.strictness >= rhs.strictness ? lhs : rhs
}

private extension RiskPolicy {
    var strictness: Int {
        switch self {
        case .autoApply:
            return 0
        case .suggestHint:
            return 1
        case .holdForHotkey:
            return 2
        case .reject:
            return 3
        }
    }
}
