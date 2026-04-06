import Foundation
import os.log

enum RiskPolicy: String, Codable, Sendable {
    case autoApply
    case suggestHint
    case holdForHotkey
    case reject
}

struct RiskState: Codable, Sendable {
    var alpha: Double = 1.0
    var beta: Double = 1.0
    var lastUpdate: Date = Date()

    var mean: Double { alpha / (alpha + beta) }
    var totalEvidence: Double { alpha + beta }
}

private struct RiskCalibrationStore: Codable, Sendable {
    var version: Int = 3
    var states: [ContextKey: RiskState] = [:]
}

actor RiskController {
    private var states: [ContextKey: RiskState] = [:]
    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "RiskController")
    private let fileURL: URL

    private let minEvidenceForAuto = 4.0
    private let minLowerBound = 0.85
    private let decayFactor = 0.985
    private let coldStartAutoThreshold = 0.76
    private let coldStartHintThreshold = 0.68

    private var testMode: Bool = false
    private var forcedPolicy: RiskPolicy?

    static let shared = RiskController()

    func setTestMode(_ enabled: Bool) {
        testMode = enabled
    }

    func forcePolicy(_ policy: RiskPolicy?) {
        forcedPolicy = policy
    }

    init(fileManager: FileManager = .default, customDirectory: URL? = nil) {
        let storeDir: URL
        if let custom = customDirectory {
            storeDir = custom
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            storeDir = fileManager.temporaryDirectory.appendingPathComponent("rightlayout_risk_tests", isDirectory: true)
            try? fileManager.removeItem(at: storeDir.appendingPathComponent("risk_calibration.json"))
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            storeDir = appSupport.appendingPathComponent("com.chernistry.rightlayout/Personalization")
        }
        self.fileURL = storeDir.appendingPathComponent("risk_calibration.json")
        self.states = Self.loadStates(from: fileURL, logger: logger)
    }

    func evaluate(candidateConfidence: Double, contextKey: ContextKey) -> RiskPolicy {
        if let forcedPolicy { return forcedPolicy }
        if let env = ProcessInfo.processInfo.environment["RightLayout_FORCE_RISK_POLICY"],
           let policy = RiskPolicy(rawValue: env) {
            return policy
        }
        if testMode { return .autoApply }
        if candidateConfidence < 0.5 { return .reject }

        let state = states[contextKey] ?? RiskState()
        let lowerBound = calculateLowerBound(state)

        if candidateConfidence >= 0.90 {
            return .autoApply
        }

        if state.totalEvidence >= minEvidenceForAuto,
           lowerBound >= minLowerBound,
           candidateConfidence >= coldStartAutoThreshold {
            return .autoApply
        }

        if candidateConfidence >= coldStartAutoThreshold {
            return .autoApply
        }

        if candidateConfidence >= coldStartHintThreshold {
            return .suggestHint
        }

        if state.totalEvidence >= minEvidenceForAuto,
           lowerBound >= 0.70,
           candidateConfidence >= 0.60 {
            return .holdForHotkey
        }

        return .reject
    }

    func demote(policy: RiskPolicy, contextKey: ContextKey, isManual: Bool = false) -> RiskPolicy {
        if let forcedPolicy { return forcedPolicy }
        if isManual || testMode { return policy }

        let state = states[contextKey] ?? RiskState()
        let lowerBound = calculateLowerBound(state)

        switch policy {
        case .autoApply:
            if state.totalEvidence >= 4.0, lowerBound < 0.60 {
                return .suggestHint
            }
            return .autoApply
        case .suggestHint:
            if state.totalEvidence >= 6.0, lowerBound < 0.45 {
                return .holdForHotkey
            }
            return .suggestHint
        case .holdForHotkey, .reject:
            return policy
        }
    }

    func recordFeedback(contextKey: ContextKey, isSuccess: Bool) async {
        var state = states[contextKey] ?? RiskState()
        state.alpha *= decayFactor
        state.beta *= decayFactor
        if isSuccess {
            state.alpha += 1.0
        } else {
            state.beta += 1.25
        }
        state.lastUpdate = Date()
        states[contextKey] = state
        logger.debug("Risk update alpha=\(state.alpha) beta=\(state.beta)")
        await save()
    }

    private func calculateLowerBound(_ state: RiskState) -> Double {
        let uncertainty = 1.0 / sqrt(state.totalEvidence + 1.0)
        return state.mean - uncertainty
    }

    private static func loadStates(from fileURL: URL, logger: Logger) -> [ContextKey: RiskState] {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(RiskCalibrationStore.self, from: data),
               decoded.version == 3 {
                return decoded.states
            }

            logger.info("Resetting legacy risk calibration state")
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Failed to load calibration: \(error.localizedDescription)")
        }
        return [:]
    }

    private func save() async {
        do {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            let payload = RiskCalibrationStore(states: states)
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save calibration: \(error.localizedDescription)")
        }
    }
}
