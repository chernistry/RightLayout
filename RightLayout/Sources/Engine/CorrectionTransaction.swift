import Foundation

package enum TransactionOutcome: String, Codable, Sendable {
    case accepted
    case undo
    case manualRevert
    case backspaceBurst
    case manualSwitch
    case expiredUnknown
}

package enum OutcomeSource: String, Codable, Sendable {
    case verifiedContinuation
    case undoCommand
    case backspaceBurst
    case layoutSwitch
    case manualCycle
    case timeout
}

package enum CapabilityClass: String, Codable, Sendable {
    case axFull
    case axPartial
    case blind
    case secure
}

package struct AppEditCapabilities: Sendable {
    package let supportsSelectedTextWrite: Bool
    package let supportsSelectedRangeWrite: Bool
    package let supportsValueWrite: Bool
    package let supportsSelectionRead: Bool
    package let supportsFullTextRead: Bool
    package let isSecureOrReadBlind: Bool
    package let capabilityClass: CapabilityClass
    package let elementFingerprint: String?
}

package struct CorrectionTransaction: Sendable, Identifiable {
    package let id: UUID
    package let sessionEpoch: UInt64?
    package let mutationSequence: UInt64?
    package let token: String
    package let replacement: String
    package let bundleId: String?
    package let elementFingerprint: String?
    package let capabilityClass: CapabilityClass?
    package let strategy: TextEditStrategy?
    package let intent: TextEditIntent
    package let createdAt: Date
    package let verifiedRange: NSRange?
    package let verifiedSnapshotRevision: UInt64?
    package let targetLanguage: Language?
    package let hypothesis: LanguageHypothesis?
    package let features: PersonalFeatures?
    package let wasAutoApplied: Bool
    package let inputSourceBefore: String?
    package let inputSourceAfterExpected: String?

    package init(
        id: UUID = UUID(),
        sessionEpoch: UInt64? = nil,
        mutationSequence: UInt64? = nil,
        token: String,
        replacement: String,
        bundleId: String?,
        elementFingerprint: String? = nil,
        capabilityClass: CapabilityClass? = nil,
        strategy: TextEditStrategy? = nil,
        intent: TextEditIntent,
        createdAt: Date = Date(),
        verifiedRange: NSRange? = nil,
        verifiedSnapshotRevision: UInt64? = nil,
        targetLanguage: Language?,
        hypothesis: LanguageHypothesis?,
        features: PersonalFeatures? = nil,
        wasAutoApplied: Bool,
        inputSourceBefore: String? = nil,
        inputSourceAfterExpected: String? = nil
    ) {
        self.id = id
        self.sessionEpoch = sessionEpoch
        self.mutationSequence = mutationSequence
        self.token = token
        self.replacement = replacement
        self.bundleId = bundleId
        self.elementFingerprint = elementFingerprint
        self.capabilityClass = capabilityClass
        self.strategy = strategy
        self.intent = intent
        self.createdAt = createdAt
        self.verifiedRange = verifiedRange
        self.verifiedSnapshotRevision = verifiedSnapshotRevision
        self.targetLanguage = targetLanguage
        self.hypothesis = hypothesis
        self.features = features
        self.wasAutoApplied = wasAutoApplied
        self.inputSourceBefore = inputSourceBefore
        self.inputSourceAfterExpected = inputSourceAfterExpected
    }

    package func committed(
        sessionEpoch: UInt64,
        mutationSequence: UInt64,
        strategy: TextEditStrategy,
        verifiedContext: VerifiedEditContext?
    ) -> CorrectionTransaction {
        CorrectionTransaction(
            id: id,
            sessionEpoch: sessionEpoch,
            mutationSequence: mutationSequence,
            token: token,
            replacement: replacement,
            bundleId: bundleId,
            elementFingerprint: verifiedContext?.snapshot.capabilities.elementFingerprint ?? elementFingerprint,
            capabilityClass: verifiedContext?.snapshot.capabilities.capabilityClass ?? capabilityClass,
            strategy: strategy,
            intent: intent,
            createdAt: createdAt,
            verifiedRange: verifiedContext?.verifiedRange,
            verifiedSnapshotRevision: verifiedContext?.snapshot.revision,
            targetLanguage: targetLanguage,
            hypothesis: hypothesis,
            features: features,
            wasAutoApplied: wasAutoApplied,
            inputSourceBefore: inputSourceBefore,
            inputSourceAfterExpected: inputSourceAfterExpected
        )
    }
}

extension TransactionOutcome {
    var userOutcome: UserOutcome? {
        switch self {
        case .accepted:
            return .accepted
        case .undo:
            return .undo
        case .manualRevert:
            return .manualRevert
        case .backspaceBurst:
            return .backspaceBurst
        case .manualSwitch:
            return .manualSwitch
        case .expiredUnknown:
            return nil
        }
    }
}
