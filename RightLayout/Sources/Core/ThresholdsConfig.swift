import Foundation

/// Loads detection thresholds from JSON configuration
public struct ThresholdsConfig: Sendable {
    public static let shared = ThresholdsConfig()
    
    // Detection thresholds
    public let correctionThreshold: Double
    public let deepConfidenceMin: Double
    public let fallbackConfidence: Double
    
    // Validation thresholds
    public let targetWordMin: Double
    public let targetWordMargin: Double
    public let targetFreqMargin: Double
    public let targetNormMin: Double
    public let targetNormMargin: Double
    public let shortWordFreqMin: Double
    
    // Scoring thresholds
    public let shortWordMargin: Double
    public let longWordMargin: Double
    public let wordConfidenceMin: Double
    
    // Heuristic thresholds
    public let sourceWordConfMax: Double
    public let baseConfMin: Double
    
    // Timing thresholds
    public let timing: TimingConfig
    
    // Correction parameters
    public let correction: CorrectionConfig
    
    public struct TimingConfig: Sendable {
        public let pendingWordTimeout: Double
        public let pendingWordMinConfidence: Double
        public let prepositionMinConfidence: Double
        public let cyclingStateTimeout: Double
        public let cyclingMinDuration: Double
        public let bufferTimeout: Double
        public let lastCorrectionTimeout: Double
        public let layoutSwitchTimeout: Double
        public let clipboardDelayNs: UInt64
        public let pasteDelayNs: UInt64
        public let typingChunkSize: Int
        public let deletionDelayNs: UInt64
        public let accessibilityPollIntervalNs: UInt64
        public let undoWindow: Double  // Ticket 43: Time window for Undo detection
        public let adoptionWindow: Double  // Ticket 43: Delay before marking correction as accepted
        
        // Ticket 50: Learning Signals
        public let manualSwitchWindow: Double
        public let backspaceBurstWindow: Double
        
        init(json: [String: Any]?) {
            let t = json ?? [:]
            pendingWordTimeout = t["pendingWordTimeout"] as? Double ?? 5.0
            pendingWordMinConfidence = t["pendingWordMinConfidence"] as? Double ?? 0.40
            prepositionMinConfidence = t["prepositionMinConfidence"] as? Double ?? 0.10
            cyclingStateTimeout = t["cyclingStateTimeout"] as? Double ?? 60.0
            cyclingMinDuration = t["cyclingMinDuration"] as? Double ?? 0.5
            bufferTimeout = t["bufferTimeout"] as? Double ?? 2.0
            lastCorrectionTimeout = t["lastCorrectionTimeout"] as? Double ?? 3.0
            layoutSwitchTimeout = t["layoutSwitchTimeout"] as? Double ?? 0.3
            let clipboardMs = t["clipboardDelayMs"] as? Int ?? 150
            clipboardDelayNs = UInt64(clipboardMs) * 1_000_000
            let pasteMs = t["pasteDelayMs"] as? Int ?? 100
            pasteDelayNs = UInt64(pasteMs) * 1_000_000
            typingChunkSize = t["typingChunkSize"] as? Int ?? 20
            let deletionMs = t["deletionDelayMs"] as? Int ?? 20
            deletionDelayNs = UInt64(deletionMs) * 1_000_000
            let pollSec = t["accessibilityPollInterval"] as? Double ?? 2.0
            accessibilityPollIntervalNs = UInt64(pollSec * 1_000_000_000)
            undoWindow = t["undoWindow"] as? Double ?? 5.0
            adoptionWindow = t["adoptionWindow"] as? Double ?? 60.0
            
            // Ticket 50 Defaults
            manualSwitchWindow = t["manualSwitchWindow"] as? Double ?? 2.0
            backspaceBurstWindow = t["backspaceBurstWindow"] as? Double ?? 1.5
        }
    }
    
    public struct CorrectionConfig: Sendable {
        public let contextBoostAmount: Double
        public let historyMaxSize: Int
        public let bufferReserveCapacity: Int
        public let visibleAlternativesRound1: Int
        public let visibleAlternativesRound2: Int
        
        // Ticket 34: Early Layout Switching
        public let earlySwitchThreshold: Double
        public let earlySwitchMinLength: Int
        
        // Ticket 71: CorrectionVerifierAgent thresholds
        public let verifierSourceQualityMax: Double
        public let verifierTargetQualityMin: Double
        public let verifierContextPenalty: Double
        public let verifierRoundTripPenalty: Double
        
        init(json: [String: Any]?) {
            let c = json ?? [:]
            contextBoostAmount = c["contextBoostAmount"] as? Double ?? 0.20
            historyMaxSize = c["historyMaxSize"] as? Int ?? 50
            bufferReserveCapacity = c["bufferReserveCapacity"] as? Int ?? 64
            visibleAlternativesRound1 = c["visibleAlternativesRound1"] as? Int ?? 2
            visibleAlternativesRound2 = c["visibleAlternativesRound2"] as? Int ?? 3
            
            // Ticket 34 Defaults
            earlySwitchThreshold = c["earlySwitchThreshold"] as? Double ?? 0.95
            earlySwitchMinLength = c["earlySwitchMinLength"] as? Int ?? 3
            
            // Ticket 71 Defaults
            verifierSourceQualityMax = c["verifierSourceQualityMax"] as? Double ?? 0.70
            verifierTargetQualityMin = c["verifierTargetQualityMin"] as? Double ?? 0.10
            verifierContextPenalty = c["verifierContextPenalty"] as? Double ?? 0.15
            verifierRoundTripPenalty = c["verifierRoundTripPenalty"] as? Double ?? 0.10
        }
    }
    
    private init() {
        guard let url = Bundle.module.url(forResource: "thresholds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Defaults
            correctionThreshold = 0.45
            deepConfidenceMin = 0.7
            fallbackConfidence = 0.5
            targetWordMin = 0.80
            targetWordMargin = 0.20
            targetFreqMargin = 0.25
            targetNormMin = 0.75
            targetNormMargin = 0.15
            shortWordFreqMin = 0.60
            shortWordMargin = 0.25
            longWordMargin = 0.70
            wordConfidenceMin = 0.80
            sourceWordConfMax = 0.80
            baseConfMin = 0.75
            timing = TimingConfig(json: nil)
            correction = CorrectionConfig(json: nil)
            return
        }
        
        let detection = json["detection"] as? [String: Any] ?? [:]
        let validation = json["validation"] as? [String: Any] ?? [:]
        let scoring = json["scoring"] as? [String: Any] ?? [:]
        let heuristic = json["heuristic"] as? [String: Any] ?? [:]
        
        correctionThreshold = detection["correctionThreshold"] as? Double ?? 0.45
        deepConfidenceMin = detection["deepConfidenceMin"] as? Double ?? 0.7
        fallbackConfidence = detection["fallbackConfidence"] as? Double ?? 0.5
        
        targetWordMin = validation["targetWordMin"] as? Double ?? 0.80
        targetWordMargin = validation["targetWordMargin"] as? Double ?? 0.20
        targetFreqMargin = validation["targetFreqMargin"] as? Double ?? 0.25
        targetNormMin = validation["targetNormMin"] as? Double ?? 0.75
        targetNormMargin = validation["targetNormMargin"] as? Double ?? 0.15
        shortWordFreqMin = validation["shortWordFreqMin"] as? Double ?? 0.60
        
        shortWordMargin = scoring["shortWordMargin"] as? Double ?? 0.25
        longWordMargin = scoring["longWordMargin"] as? Double ?? 0.70
        wordConfidenceMin = scoring["wordConfidenceMin"] as? Double ?? 0.80
        
        sourceWordConfMax = heuristic["sourceWordConfMax"] as? Double ?? 0.80
        baseConfMin = heuristic["baseConfMin"] as? Double ?? 0.75
        
        timing = TimingConfig(json: json["timing"] as? [String: Any])
        correction = CorrectionConfig(json: json["correction"] as? [String: Any])
    }
}
