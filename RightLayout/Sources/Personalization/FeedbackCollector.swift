import Foundation
import os.log

enum UserOutcome: String, Codable, Sendable {
    case accepted
    case manualRevert
    case undo
    case backspaceBurst
    case manualSwitch
    case unknown
}

private struct TrackedTransaction: Sendable {
    let transaction: CorrectionTransaction
    let targetLayout: String
    let features: PersonalFeatures?
}

actor FeedbackCollector {
    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "OutcomeTracker")

    private var pendingTransactions: [UUID: TrackedTransaction] = [:]
    private let pendingWindow: TimeInterval = 60.0

    private let store: PersonalizationStore
    private let adapter: OnlineAdapter
    private let riskController: RiskController

    init(
        store: PersonalizationStore,
        adapter: OnlineAdapter = .shared,
        riskController: RiskController = .shared
    ) {
        self.store = store
        self.adapter = adapter
        self.riskController = riskController
    }

    func begin(transaction: CorrectionTransaction) {
        expireStaleTransactions()
        pendingTransactions[transaction.id] = TrackedTransaction(
            transaction: transaction,
            targetLayout: transaction.targetLanguage?.rawValue ?? "en",
            features: transaction.features
        )
    }

    func register(targetLayout: String, features: PersonalFeatures) -> UUID {
        let transaction = CorrectionTransaction(
            token: "",
            replacement: "",
            bundleId: nil,
            intent: .autoCorrection,
            targetLanguage: Language(rawValue: targetLayout),
            hypothesis: nil,
            features: features,
            wasAutoApplied: true
        )
        begin(transaction: transaction)
        return transaction.id
    }

    func accept(transactionId: UUID, source: OutcomeSource = .verifiedContinuation) async {
        await finish(transactionId: transactionId, outcome: .accepted, source: source)
    }

    func reportOutcome(transactionId: UUID, outcome: TransactionOutcome, source: OutcomeSource) async {
        await finish(transactionId: transactionId, outcome: outcome, source: source)
    }

    func reportOutcome(trackingId: UUID, outcome: UserOutcome) async {
        guard let mapped = map(outcome) else { return }
        await finish(transactionId: trackingId, outcome: mapped, source: mapped.defaultSource)
    }

    func transaction(for id: UUID) -> CorrectionTransaction? {
        pendingTransactions[id]?.transaction
    }

    func expireStaleTransactions(now: Date = Date()) {
        let expiredIds = pendingTransactions.compactMap { id, tracked in
            now.timeIntervalSince(tracked.transaction.createdAt) > pendingWindow ? id : nil
        }

        for id in expiredIds {
            pendingTransactions.removeValue(forKey: id)
            logger.debug("Dropping stale transaction \(id.uuidString, privacy: .public) as expiredUnknown")
        }
    }

    func waitForIdle() async {}

    private func finish(transactionId: UUID, outcome: TransactionOutcome, source: OutcomeSource) async {
        expireStaleTransactions()
        guard let tracked = pendingTransactions.removeValue(forKey: transactionId) else { return }
        await processOutcome(tracked: tracked, outcome: outcome, source: source)
    }

    private func processOutcome(
        tracked: TrackedTransaction,
        outcome: TransactionOutcome,
        source: OutcomeSource
    ) async {
        guard tracked.transaction.wasAutoApplied else {
            logger.debug("Skipping learning for manual transaction \(tracked.transaction.id.uuidString, privacy: .public)")
            return
        }

        if tracked.transaction.strategy == .axValueRewrite {
            logger.debug("Skipping learning for full-value rewrite transaction \(tracked.transaction.id.uuidString, privacy: .public)")
            return
        }

        if tracked.transaction.strategy == .eventReplayTransaction {
            logger.debug("Skipping learning for replay transaction \(tracked.transaction.id.uuidString, privacy: .public)")
            return
        }

        if tracked.transaction.capabilityClass == .blind || tracked.transaction.capabilityClass == .secure {
            logger.debug("Skipping learning for blind/secure transaction \(tracked.transaction.id.uuidString, privacy: .public)")
            return
        }

        guard let features = tracked.features else {
            logger.debug("Skipping learning for transaction without features: \(tracked.transaction.id.uuidString, privacy: .public)")
            return
        }

        let action: AdapterAction
        switch tracked.targetLayout {
        case "ru":
            action = .correctToRu
        case "he":
            action = .correctToHe
        default:
            action = .correctToEn
        }

        logger.info(
            "Processed outcome=\(outcome.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public) target=\(tracked.targetLayout, privacy: .public)"
        )

        switch outcome {
        case .accepted:
            await adapter.update(action: action, features: features, reward: 0.4)
            await store.updatePriors(for: features.appBundleIdHash, layout: tracked.targetLayout, delta: 0.5)
            await riskController.recordFeedback(contextKey: features.contextKey, isSuccess: true)
        case .undo, .manualRevert, .backspaceBurst, .manualSwitch:
            await adapter.update(action: action, features: features, reward: -0.75)
            await store.updatePriors(for: features.appBundleIdHash, layout: tracked.targetLayout, delta: -0.75)
            await riskController.recordFeedback(contextKey: features.contextKey, isSuccess: false)
        case .expiredUnknown:
            break
        }
    }

    private func map(_ outcome: UserOutcome) -> TransactionOutcome? {
        switch outcome {
        case .accepted:
            return .accepted
        case .manualRevert:
            return .manualRevert
        case .undo:
            return .undo
        case .backspaceBurst:
            return .backspaceBurst
        case .manualSwitch:
            return .manualSwitch
        case .unknown:
            return nil
        }
    }
}

private extension TransactionOutcome {
    var defaultSource: OutcomeSource {
        switch self {
        case .accepted:
            return .verifiedContinuation
        case .undo:
            return .undoCommand
        case .manualRevert:
            return .manualCycle
        case .backspaceBurst:
            return .backspaceBurst
        case .manualSwitch:
            return .layoutSwitch
        case .expiredUnknown:
            return .timeout
        }
    }
}
