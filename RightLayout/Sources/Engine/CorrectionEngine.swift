import Foundation
import AppKit
import os.log

/// Core correction engine actor — orchestrates language detection, correction,
/// cycling, feedback, and personalization.
///
/// The implementation is split across multiple files:
/// - `CorrectionEngine.swift`              – State, types, init, utilities (this file)
/// - `CorrectionEngine+Decide.swift`       – `correctText`, `applyCorrection`, early correction
/// - `CorrectionEngine+SmartCorrection.swift` – Split/whole/segment correction logic
/// - `CorrectionEngine+Cycling.swift`      – Hotkey cycling, `correctLastWord`, `resetCycling`
/// - `CorrectionEngine+Feedback.swift`     – Undo, retype detection, feedback, history
package actor CorrectionEngine {

    // MARK: - Dependencies

    let router: ConfidenceRouter
    let settings: SettingsManager

    // V2 Personalization
    let personalizationEngine = PersonalizationEngine(store: .shared, adapter: .shared)
    let featureExtractor = FeatureExtractor()
    let feedbackCollector = FeedbackCollector(store: .shared)
    let intentDetector = IntentDetector()
    let transliterationDetector = TransliterationDetector.shared
    let verifier = CorrectionVerifierAgent()

    let builtinValidator = BuiltinWordValidator()
    let languageData = LanguageDataConfig.shared

    // MARK: - Logging

    let logger = Logger.engine

    // Debug helper
    func logDebug(_ msg: String) {
        #if DEBUG
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.rightlayout/debug_manual.log"
        if let data = (msg + "\n").data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        #endif
    }

    // MARK: - State

    var history: [CorrectionRecord] = []
    var cyclingState: CyclingContext?

    // Transaction/outcome tracking
    var committedTransactions: [UUID: CorrectionTransaction] = [:]
    var lastCommittedTransactionId: UUID?

    // Pending word that was below threshold but might be boosted by context
    var pendingWord: PendingWord?

    // Sentence-level language tracking for context-aware decisions
    var sentenceDominantLanguage: Language?
    var sentenceWordCount: Int = 0
    var sentenceSequence: [Language] = []
    let patternTracker = SentencePatternTracker.shared

    // Ticket 61: Pending suggestion for "Hint-First" strategy
    var pendingSuggestion: PendingSuggestion?

    // Ticket 50: Retype Detection State
    var lastRevertedState: RevertedState?

    // Test hook for verifying signals
    var lastReportedSignal: (UUID, UserOutcome)?

    // MARK: - Configuration

    /// Single-letter tokens that map to common Russian prepositions (а в к о у и я)
    let russianPrepositionMappings: [String: String] = LanguageMappingsConfig.shared.russianPrepositions

    lazy var unigramModels: [Language: WordFrequencyModel] = {
        var out: [Language: WordFrequencyModel] = [:]
        if let ru = try? WordFrequencyModel.loadLanguage("ru") { out[.russian] = ru }
        if let en = try? WordFrequencyModel.loadLanguage("en") { out[.english] = en }
        if let he = try? WordFrequencyModel.loadLanguage("he") { out[.hebrew] = he }
        return out
    }()

    // How much to boost pending word confidence when next word confirms language
    var contextBoostAmount: Double { ThresholdsConfig.shared.correction.contextBoostAmount }

    // MARK: - Init

    package init(settings: SettingsManager) {
        self.settings = settings
        self.router = ConfidenceRouter(settings: settings)
    }

    // MARK: - Guards

    func shouldCorrect(for bundleId: String?) async -> Bool {
        let enabled = await settings.isEnabled
        logger.debug("shouldCorrect check: enabled=\(enabled), bundleId=\(bundleId ?? "nil", privacy: .public)")
        
        guard enabled else {
            logger.info("❌ Correction globally disabled")
            return false
        }
        
        if let id = bundleId, await settings.isExcluded(bundleId: id) {
            logger.info("❌ App excluded: \(id, privacy: .public)")
            return false
        }
        
        logger.debug("✅ Correction allowed")
        return true
    }

    // MARK: - Nested Types

    /// Word that didn't meet threshold but could be corrected if next word confirms language
    struct PendingWord {
        let text: String
        let decision: LanguageDecision
        let adjustedConfidence: Double
        let timestamp: Date
        let isFirstWord: Bool  // True if this was the first word in sentence
        
        // Ticket 49: Expanded candidates for ambiguous tokens
        let candidates: [Language: String]? 
        let isAmbiguousValid: Bool // True if this token was valid in source but ambiguous
        
        var isValid: Bool { Date().timeIntervalSince(timestamp) < ThresholdsConfig.shared.timing.pendingWordTimeout }
    }

    /// Outcome of a correction analysis (Ticket 61)
    enum CorrectionAction: String {
        case applied    // Text was automatically replaced
        case hint       // Text was NOT replaced; hint may be shown; pending suggestion stored
        case none       // No correction needed or rejected
    }

    /// Result of correction attempt, may include pending word correction
    struct CorrectionResult: Sendable {
        let corrected: String?           // Current word correction (if applied)
        let action: CorrectionAction     // Ticket 61: Exact action taken
        let pendingCorrection: String?   // Previous pending word correction (nil if none)
        let pendingOriginal: String?     // Original pending word text (for calculating delete length)
        let trackingId: UUID?            // Ticket 50: For linking feedback signals
        let transaction: CorrectionTransaction?
        let transliterationSuggestion: TransliterationSuggestion? // Ticket 55: Hint-only suggestion
        let confidence: Double?
        let targetLanguage: Language?
        let evidence: DecisionEvidence?

        init(
            corrected: String?,
            action: CorrectionAction,
            pendingCorrection: String?,
            pendingOriginal: String?,
            trackingId: UUID?,
            transaction: CorrectionTransaction? = nil,
            transliterationSuggestion: TransliterationSuggestion?,
            confidence: Double? = nil,
            targetLanguage: Language? = nil,
            evidence: DecisionEvidence? = nil
        ) {
            self.corrected = corrected
            self.action = action
            self.pendingCorrection = pendingCorrection
            self.pendingOriginal = pendingOriginal
            self.trackingId = trackingId
            self.transaction = transaction
            self.transliterationSuggestion = transliterationSuggestion
            self.confidence = confidence
            self.targetLanguage = targetLanguage
            self.evidence = evidence
        }
    }

    struct PendingSuggestion: Sendable {
        let original: String
        let corrected: String
        let from: Language
        let to: Language
        let hypothesis: LanguageHypothesis
        let decisionLayoutHypothesis: LanguageHypothesis // Kept for cycling state recreation
        let features: PersonalFeatures?
        let timestamp: Date
        let bundleId: String
        let transaction: CorrectionTransaction?
    }

    struct CorrectionRecord: Identifiable, Sendable {
        let id = UUID()
        let original: String
        let corrected: String
        let fromLang: Language
        let toLang: Language
        let timestamp: Date

        // Ticket 69: Transparency metadata
        let confidence: Double?
        let appName: String?
        let policy: HistoryManager.CorrectionPolicy?
    }

    struct RevertedState: Sendable {
        let transactionId: UUID?
        let originalText: String
        let features: PersonalFeatures
        let timestamp: Date
    }

    struct SmartCorrection: Sendable {
        let text: String
        let hypothesis: LanguageHypothesis?
        let from: Language?
        let to: Language?
        let score: Double
    }

    struct CompoundPart: Sendable {
        let isWord: Bool
        let text: String
    }

    struct ShortTokenOverride: Sendable {
        let corrected: String
        let hypothesis: LanguageHypothesis
        let from: Language
        let to: Language
    }

    /// State for cycling through alternatives on repeated hotkey presses
    struct CyclingContext: Sendable {
        let originalText: String
        let alternatives: [Alternative]
        var currentIndex: Int
        let wasAutomatic: Bool
        let autoHypothesis: LanguageHypothesis?
        let timestamp: Date
        let trailingSeparator: String
        
        // Ticket 29: Round-based cycling
        var roundNumber: Int = 1
        var visibleAlternativesCount: Int
        var cycleCount: Int = 0 // Tracks how many times we wrapped 0->1->0
        var hasReturnedToOriginal: Bool = false // Track if user returned to index 0 after auto-correction
        var trackingId: UUID? = nil
        
        struct Alternative: Sendable {
            let text: String
            let hypothesis: LanguageHypothesis?
        }
        
        mutating func next() -> Alternative {
            let limit = visibleAlternativesCount
            let nextIndex = (currentIndex + 1)
            
            if nextIndex >= limit {
                currentIndex = 0
            } else {
                currentIndex = nextIndex
            }
            
            // Track first return to original after auto-correction
            if wasAutomatic && currentIndex == 0 && !hasReturnedToOriginal {
                hasReturnedToOriginal = true
            }
            
            return alternatives[currentIndex]
        }
        
        var current: Alternative {
            alternatives[currentIndex]
        }
        
        /// Check if cycling state is still valid (configurable timeout)
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < ThresholdsConfig.shared.timing.cyclingStateTimeout
        }
    }

    // MARK: - Utility Methods

    func languages(for hypothesis: LanguageHypothesis) -> (source: Language, target: Language)? {
        switch hypothesis {
        case .ruFromEnLayout: return (.english, .russian)
        case .heFromEnLayout: return (.english, .hebrew)
        case .enFromRuLayout: return (.russian, .english)
        case .heFromRuLayout: return (.russian, .hebrew)
        case .enFromHeLayout: return (.hebrew, .english)
        case .ruFromHeLayout: return (.hebrew, .russian)
        case .ru, .en, .he: return nil
        }
    }

    func hypothesisFor(source: Language, target: Language) -> LanguageHypothesis {
        switch (source, target) {
        case (.english, .russian): return .ruFromEnLayout
        case (.english, .hebrew): return .heFromEnLayout
        case (.russian, .english): return .enFromRuLayout
        case (.russian, .hebrew): return .heFromRuLayout
        case (.hebrew, .english): return .enFromHeLayout
        case (.hebrew, .russian): return .ruFromHeLayout
        default: return .en
        }
    }

    /// Reset sentence-level state (called on sentence boundary like . ! ? or long pause)
    package func resetSentence() {
        let currentSequence = sentenceSequence
        if !currentSequence.isEmpty {
            Task {
                let bundleId = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
                await patternTracker.record(appBundleId: bundleId, sequence: currentSequence, next: nil)
            }
        }
        sentenceDominantLanguage = nil
        sentenceWordCount = 0
        sentenceSequence.removeAll()
        pendingWord = nil
    }

    /// Check if there's an active and valid cycling state
    package func hasCyclingState() -> Bool {
        guard let state = cyclingState else { return false }
        return state.isValid
    }

    /// Get the length of current cycling text (for replacement)
    package func getCurrentCyclingTextLength() -> Int {
        return cyclingState?.current.text.count ?? 0
    }

    package func getCurrentCyclingText() -> String? {
        cyclingState?.current.text
    }

    /// Get the length of the original text in cycling state (for undo/replacement calculation)
    package func getCyclingOriginalTextLength() -> Int {
        return cyclingState?.originalText.count ?? 0
    }

    package func getCyclingOriginalText() -> String? {
        cyclingState?.originalText
    }

    package func cyclingTrailingSeparator() -> String {
        cyclingState?.trailingSeparator ?? ""
    }

    package func updateCyclingTrailingSeparator(_ separator: String) {
        guard var state = cyclingState else { return }
        state = CyclingContext(
            originalText: state.originalText,
            alternatives: state.alternatives,
            currentIndex: state.currentIndex,
            wasAutomatic: state.wasAutomatic,
            autoHypothesis: state.autoHypothesis,
            timestamp: state.timestamp,
            trailingSeparator: separator,
            roundNumber: state.roundNumber,
            visibleAlternativesCount: state.visibleAlternativesCount,
            cycleCount: state.cycleCount,
            hasReturnedToOriginal: state.hasReturnedToOriginal,
            trackingId: state.trackingId
        )
        cyclingState = state
    }

    package func currentPendingFeedbackId() -> UUID? {
        lastCommittedTransactionId
    }

    package func currentCommittedTransaction() -> CorrectionTransaction? {
        guard let lastCommittedTransactionId else { return nil }
        return committedTransactions[lastCommittedTransactionId]
    }

    package func transaction(for id: UUID) -> CorrectionTransaction? {
        committedTransactions[id]
    }

    package func currentCyclingTargetLanguage() async -> Language? {
        guard let state = cyclingState, state.isValid else { return nil }

        if let hypothesis = state.current.hypothesis {
            return hypothesis.targetLanguage
        }

        if state.currentIndex == 0 {
            if state.wasAutomatic,
               let autoHypothesis = state.autoHypothesis,
               let languages = languages(for: autoHypothesis) {
                return languages.source
            }

            let decision = await router.route(
                token: state.originalText,
                context: DetectorContext(lastLanguage: nil),
                mode: .manual
            )
            return decision.language
        }

        return nil
    }

    package func currentCyclingHypothesis() -> LanguageHypothesis? {
        guard let state = cyclingState, state.isValid else { return nil }
        return state.current.hypothesis ?? state.autoHypothesis
    }

    package func getLastCorrectionTargetLanguage() async -> Language? {
        await currentCyclingTargetLanguage()
    }

    func commitTransaction(_ transaction: CorrectionTransaction) async {
        committedTransactions[transaction.id] = transaction
        lastCommittedTransactionId = transaction.id

        if committedTransactions.count > 32,
           let oldest = committedTransactions.values.sorted(by: { $0.createdAt < $1.createdAt }).first {
            committedTransactions.removeValue(forKey: oldest.id)
        }

        let appName: String? = await MainActor.run {
            if let bid = transaction.bundleId {
                return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid })?.localizedName ?? bid
            }
            return nil
        }

        if let targetLanguage = transaction.targetLanguage,
           let hypothesis = transaction.hypothesis,
           let languages = languages(for: hypothesis) {
            addToHistory(
                original: transaction.token,
                corrected: transaction.replacement,
                from: languages.source,
                to: targetLanguage,
                confidence: nil,
                appName: appName,
                policy: transaction.wasAutoApplied ? .autoApplied : .manual
            )
            sentenceSequence.append(targetLanguage)
            await StatsStore.shared.record(
                transaction.wasAutoApplied
                ? .autoFixed(appBundleId: transaction.bundleId, from: languages.source, to: targetLanguage)
                : .manualHotkey(appBundleId: transaction.bundleId, from: languages.source, to: targetLanguage)
            )

            Task { @MainActor in
                DecisionLogStore.shared.log(
                    token: "\(transaction.token) → \(transaction.replacement)",
                    confidence: nil,
                    appName: appName,
                    action: transaction.wasAutoApplied ? "Applied" : "Manual",
                    hypothesis: hypothesis.rawValue
                )
            }
        }

        await feedbackCollector.begin(transaction: transaction)
    }

    func acceptTransactionIfTracked(_ id: UUID) async {
        guard committedTransactions[id] != nil else { return }
        await feedbackCollector.accept(transactionId: id, source: .verifiedContinuation)
    }

    func addToHistory(
        original: String,
        corrected: String,
        from: Language,
        to: Language,
        confidence: Double? = nil,
        appName: String? = nil,
        policy: HistoryManager.CorrectionPolicy? = nil
    ) {
        let record = CorrectionRecord(
            original: original,
            corrected: corrected,
            fromLang: from,
            toLang: to,
            timestamp: Date(),
            confidence: confidence,
            appName: appName,
            policy: policy
        )
        history.insert(record, at: 0)
        if history.count > ThresholdsConfig.shared.correction.historyMaxSize {
            history.removeLast()
        }
        
        // Also update shared HistoryManager for UI
        Task { @MainActor in
            HistoryManager.shared.add(
                original: original,
                corrected: corrected,
                from: from,
                to: to,
                confidence: confidence,
                appName: appName,
                policy: policy
            )
        }
    }
}
