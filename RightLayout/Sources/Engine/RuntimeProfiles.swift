import Foundation

package struct ReplayTimingProfile: Sendable {
    package let boundarySettleDelay: UInt64
    package let deleteDelay: UInt64
    package let insertDelay: UInt64
    package let postApplyDelay: UInt64
}

package enum HostRuntimeProfile: String, Codable, Sendable {
    case axFull
    case axPartial
    case blindKnownGood
    case blindUnknown
    case secure

    package static func resolve(
        bundleId: String?,
        capabilities: AppEditCapabilities?,
        forceAccessibility: Bool = false,
        forceSecure: Bool = false
    ) -> HostRuntimeProfile {
        if forceSecure {
            return .secure
        }
        if forceAccessibility {
            return .axFull
        }

        switch capabilities?.capabilityClass {
        case .axFull:
            return .axFull
        case .axPartial:
            return .axPartial
        case .secure:
            return .secure
        case .blind:
            return isKnownGoodBlindBundleId(bundleId) ? .blindKnownGood : .blindUnknown
        case nil:
            return isKnownGoodBlindBundleId(bundleId) ? .blindKnownGood : .blindUnknown
        }
    }

    package static func isKnownGoodBlindBundleId(_ bundleId: String?) -> Bool {
        guard let normalized = bundleId?.lowercased(), !normalized.isEmpty else {
            return false
        }

        let exactMatches: Set<String> = [
            "com.microsoft.vscode",
            "com.microsoft.vscodeinsiders",
            "com.vscodium",
            "com.sublimetext.4",
            "com.google.chrome",
            "org.chromium.chromium",
            "com.brave.browser",
            "com.microsoft.edgemac",
            "com.todesktop.230313mzl4w4u92",
            "com.tinyspeck.slackmacgap",
            "com.hnc.discord",
            "notion.id",
            "md.obsidian",
            "com.jetbrains.intellij",
            "com.jetbrains.pycharm"
        ]

        if exactMatches.contains(normalized) {
            return true
        }

        return normalized.hasPrefix("com.jetbrains.")
            || normalized.hasPrefix("com.microsoft.vscode")
            || normalized.contains("chromium")
            || normalized.contains("chrome")
            || normalized.contains("brave")
            || normalized.contains("edge")
            || normalized.contains("slack")
            || normalized.contains("notion")
            || normalized.contains("obsidian")
    }

    package var editingEnvironment: EditingEnvironment {
        switch self {
        case .axFull, .axPartial:
            return .accessibility
        case .blindKnownGood, .blindUnknown:
            return .nonAccessibility
        case .secure:
            return .secureReadBlind
        }
    }

    package var allowsAutomaticBlindReplay: Bool {
        self == .blindKnownGood
    }

    package var allowsManualLastWordReplay: Bool {
        self != .secure
    }

    package var allowsManualSelectionClipboardFallback: Bool {
        self == .blindKnownGood || self == .blindUnknown
    }

    package var allowsOptimisticBlindCommit: Bool {
        self == .blindKnownGood || self == .blindUnknown
    }

    package var switchSafeAfterBlindReplay: Bool {
        self == .blindKnownGood
    }

    package var replayTimingProfile: ReplayTimingProfile {
        switch self {
        case .axFull, .axPartial:
            return ReplayTimingProfile(
                boundarySettleDelay: 0,
                deleteDelay: 5_000_000,
                insertDelay: 4_000_000,
                postApplyDelay: 80_000_000
            )
        case .blindKnownGood:
            return ReplayTimingProfile(
                boundarySettleDelay: 28_000_000,
                deleteDelay: 11_000_000,
                insertDelay: 9_000_000,
                postApplyDelay: 120_000_000
            )
        case .blindUnknown:
            return ReplayTimingProfile(
                boundarySettleDelay: 36_000_000,
                deleteDelay: 13_000_000,
                insertDelay: 11_000_000,
                postApplyDelay: 140_000_000
            )
        case .secure:
            return ReplayTimingProfile(
                boundarySettleDelay: 0,
                deleteDelay: 0,
                insertDelay: 0,
                postApplyDelay: 0
            )
        }
    }
}

package enum TextEditCommitKind: String, Sendable {
    case verifiedCommit
    case blindCommit
    case aborted
    case rollbackAttempted
}

package enum RuntimeTraceEvent: String, Sendable {
    case boundaryDetected = "boundary_detected"
    case verificationResult = "verification_result"
    case planReady = "plan_ready"
    case replacementStarted = "replacement_started"
    case replacementFinished = "replacement_finished"
    case layoutSwitchRequested = "layout_switch_requested"
    case layoutSwitchObserved = "layout_switch_observed"
    case sessionInvalidated = "session_invalidated"
}

package final class RuntimeTraceLogger: @unchecked Sendable {
    package static let shared = RuntimeTraceLogger()

    private let enabled: Bool

    private init() {
        let environment = ProcessInfo.processInfo.environment
        enabled =
            environment["RIGHTLAYOUT_RUNTIME_TRACE"] == "1"
            || environment["RightLayout_RUNTIME_TRACE"] == "1"
    }

    package func log(_ event: RuntimeTraceEvent, fields: [String: String?]) {
        guard enabled else { return }

        let payload = fields
            .compactMap { key, value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return "\(key)=\(value)"
            }
            .sorted()
            .joined(separator: " ")

        if payload.isEmpty {
            DecisionLogger.shared.log("TRACE \(event.rawValue)")
        } else {
            DecisionLogger.shared.log("TRACE \(event.rawValue) \(payload)")
        }
    }
}
