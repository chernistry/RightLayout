import Foundation

enum CorrectionPlan: Sendable {
    case none
    case autoReplace(CorrectionCandidate)
    case hint(CorrectionCandidate)
    case manualCycle([CorrectionEngine.CyclingContext.Alternative])
}

struct CorrectionCandidate: Sendable {
    let original: String
    let replacement: String
    let pendingOriginal: String?
    let pendingReplacement: String?
    let trackingId: UUID?
    let transaction: CorrectionTransaction?
    let transliterationSuggestion: TransliterationSuggestion?
}

struct PlannedCorrection: Sendable {
    let result: CorrectionEngine.CorrectionResult
    let plan: CorrectionPlan
}

extension CorrectionEngine {
    func planCorrection(
        _ text: String,
        phraseBuffer: String = "",
        expectedLayout: Language? = nil,
        latencies: [TimeInterval] = [],
        editingEnvironment: EditingEnvironment = .accessibility
    ) async -> PlannedCorrection {
        let result = await correctText(
            text,
            phraseBuffer: phraseBuffer,
            expectedLayout: expectedLayout,
            latencies: latencies,
            editingEnvironment: editingEnvironment
        )

        let candidate = CorrectionCandidate(
            original: text,
            replacement: result.corrected ?? text,
            pendingOriginal: result.pendingOriginal,
            pendingReplacement: result.pendingCorrection,
            trackingId: result.trackingId,
            transaction: result.transaction,
            transliterationSuggestion: result.transliterationSuggestion
        )

        let plan: CorrectionPlan
        switch result.action {
        case .applied:
            if result.corrected != nil {
                plan = .autoReplace(candidate)
            } else {
                plan = .none
            }
        case .hint:
            plan = .hint(candidate)
        case .none:
            plan = .none
        }

        return PlannedCorrection(result: result, plan: plan)
    }

    func currentManualCyclePlan() -> CorrectionPlan {
        if let state = cyclingState, state.isValid {
            return .manualCycle(state.alternatives)
        }
        return .none
    }
}
