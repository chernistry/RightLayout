import Foundation

extension CorrectionEngine {

    func handleUndo() async {
        guard let transaction = currentCommittedTransaction(),
              Date().timeIntervalSince(transaction.createdAt) < ThresholdsConfig.shared.timing.undoWindow else {
            if let last = history.first,
               Date().timeIntervalSince(last.timestamp) < ThresholdsConfig.shared.timing.undoWindow {
                let features = await featureExtractor.extract(
                    text: last.original,
                    phraseBuffer: "",
                    appBundleId: "unknown",
                    intent: "prose"
                )
                lastRevertedState = RevertedState(
                    transactionId: nil,
                    originalText: last.original,
                    features: features,
                    timestamp: Date()
                )
            }
            return
        }

        await feedbackCollector.reportOutcome(
            transactionId: transaction.id,
            outcome: .undo,
            source: .undoCommand
        )
        lastReportedSignal = (transaction.id, .undo)

        if let features = transaction.features {
            lastRevertedState = RevertedState(
                transactionId: transaction.id,
                originalText: transaction.token,
                features: features,
                timestamp: Date()
            )
        } else {
            let appBundleId = transaction.bundleId ?? "unknown"
            let features = await featureExtractor.extract(
                text: transaction.token,
                phraseBuffer: "",
                appBundleId: appBundleId,
                intent: "prose"
            )
            lastRevertedState = RevertedState(
                transactionId: transaction.id,
                originalText: transaction.token,
                features: features,
                timestamp: Date()
            )
        }

        await StatsStore.shared.record(.undo(appBundleId: transaction.bundleId))
    }

    func reportNegativeFeedback(id: UUID, reason: UserOutcome) async {
        guard let mapped = map(reason) else { return }
        lastReportedSignal = (id, reason)
        await feedbackCollector.reportOutcome(
            transactionId: id,
            outcome: mapped,
            source: mapped.defaultSource
        )

        let trackedTransaction = transaction(for: id)
        let pendingTransaction = await feedbackCollector.transaction(for: id)
        guard let transaction = trackedTransaction ?? pendingTransaction else {
            return
        }

        if let features = transaction.features {
            lastRevertedState = RevertedState(
                transactionId: id,
                originalText: transaction.token,
                features: features,
                timestamp: Date()
            )
        }
    }

    @discardableResult
    func checkForRetype(text: String, bundleId: String?) async -> Bool {
        guard let reverted = lastRevertedState else { return false }
        guard Date().timeIntervalSince(reverted.timestamp) < 10.0 else {
            lastRevertedState = nil
            return false
        }

        let currentFeatures = await featureExtractor.extract(
            text: text,
            phraseBuffer: "",
            appBundleId: bundleId ?? "unknown",
            intent: "prose"
        )

        if text == reverted.originalText || currentFeatures.ngramHashes == reverted.features.ngramHashes {
            if let transactionId = reverted.transactionId {
                if lastReportedSignal?.0 != transactionId {
                    await feedbackCollector.reportOutcome(
                        transactionId: transactionId,
                        outcome: .manualRevert,
                        source: .manualCycle
                    )
                }
                lastReportedSignal = (transactionId, .manualRevert)
            }
            lastRevertedState = nil
            return true
        }

        return false
    }

    func getHistory() async -> [CorrectionRecord] {
        history
    }

    func clearHistory() async {
        history.removeAll()
        committedTransactions.removeAll()
        lastCommittedTransactionId = nil
        lastRevertedState = nil
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
