import Foundation
import AppKit
import Carbon
import ApplicationServices
import os.log

package enum TextEditIntent: String, Sendable {
    case autoCorrection
    case manualSelection
    case manualCycle
    case manualUndo
    case transliterationHint

    var isManual: Bool {
        switch self {
        case .autoCorrection:
            return false
        case .manualSelection, .manualCycle, .manualUndo, .transliterationHint:
            return true
        }
    }
}

package enum TextEditStrategy: String, Sendable {
    case axSelectedTextReplace
    case axValueRewrite
    case clipboardSelectionPaste
    case eventReplayTransaction
    case noOp

    static var events: TextEditStrategy { .eventReplayTransaction }
    static var clipboard: TextEditStrategy { .clipboardSelectionPaste }
}

struct TextEditRequest: @unchecked Sendable {
    let intent: TextEditIntent
    let expectedOriginal: String
    let replacement: String
    let verifiedRange: NSRange?
    let snapshot: FocusedTextSnapshot?
    let hostRuntimeProfile: HostRuntimeProfile
    let sessionRevision: UInt64
    let allowClipboardFallback: Bool
    let allowEventReplayFallback: Bool
    let sessionIsDirty: Bool
    let currentTypedToken: String?
}

struct TextEditResult: @unchecked Sendable {
    let strategy: TextEditStrategy
    let appliedText: String
    let caretRange: NSRange?
    let postVerified: Bool
    let needsResync: Bool
    let commitKind: TextEditCommitKind
}

/// Service responsible for verified text replacement.
@MainActor
final class SelectionReplacementService {
    static let shared = SelectionReplacementService()

    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "SelectionReplacement")
    private let eventPoster: EventPosting
    private let trace = RuntimeTraceLogger.shared

    internal var skipEventPosting = false
    internal private(set) var lastReplacement: (original: String, replacement: String)?
    internal private(set) var lastStrategy: TextEditStrategy?
    internal var testBundleId: String?

    private let restoreClipboardDelay: UInt64 = 180_000_000

    init(eventPoster: EventPosting = CGEventPoster()) {
        self.eventPoster = eventPoster
    }

    func setSkipEventPosting(_ value: Bool) {
        skipEventPosting = value
    }

    func setTestBundleId(_ id: String?) {
        testBundleId = id
    }

    @discardableResult
    func replace(_ request: TextEditRequest, proxy: CGEventTapProxy?) async throws -> TextEditResult {
        lastReplacement = (request.expectedOriginal, request.replacement)

        if skipEventPosting {
            return syntheticReplace(request)
        }

        if request.hostRuntimeProfile.editingEnvironment == .accessibility,
           let snapshot = request.snapshot,
           let verifiedRange = request.verifiedRange,
           canReplaceViaAX(snapshot: snapshot, verifiedRange: verifiedRange, expectedOriginal: request.expectedOriginal) {
            return try await replaceViaAX(
                request: request,
                snapshot: snapshot,
                verifiedRange: verifiedRange,
                proxy: proxy
            )
        }

        if request.intent == .manualSelection,
           request.allowClipboardFallback,
           !request.expectedOriginal.isEmpty {
            lastStrategy = .clipboardSelectionPaste
            return try await replaceViaClipboardSelection(request: request, proxy: proxy)
        }

        if (request.intent.isManual || request.allowEventReplayFallback),
           !request.sessionIsDirty,
           request.currentTypedToken == request.expectedOriginal,
           !request.expectedOriginal.isEmpty {
            lastStrategy = .eventReplayTransaction
            return try await replaceViaEventReplay(request: request, proxy: proxy)
        }

        lastStrategy = .noOp
        return TextEditResult(
            strategy: .noOp,
            appliedText: request.expectedOriginal,
            caretRange: request.verifiedRange,
            postVerified: false,
            needsResync: true,
            commitKind: .aborted
        )
    }

    private func syntheticReplace(_ request: TextEditRequest) -> TextEditResult {
        if request.hostRuntimeProfile.editingEnvironment == .accessibility,
           let snapshot = request.snapshot,
           let verifiedRange = request.verifiedRange,
           canReplaceViaAX(snapshot: snapshot, verifiedRange: verifiedRange, expectedOriginal: request.expectedOriginal) {
            let strategy: TextEditStrategy =
                snapshot.capabilities.supportsSelectedRangeWrite && snapshot.capabilities.supportsSelectedTextWrite
                ? .axSelectedTextReplace
                : .axValueRewrite
            lastStrategy = strategy
            return TextEditResult(
                strategy: strategy,
                appliedText: request.replacement,
                caretRange: NSRange(location: verifiedRange.location + request.replacement.utf16.count, length: 0),
                postVerified: true,
                needsResync: false,
                commitKind: .verifiedCommit
            )
        }

        if request.intent == .manualSelection,
           request.allowClipboardFallback,
           !request.expectedOriginal.isEmpty {
            lastStrategy = .clipboardSelectionPaste
            return TextEditResult(
                strategy: .clipboardSelectionPaste,
                appliedText: request.replacement,
                caretRange: nil,
                postVerified: true,
                needsResync: false,
                commitKind: .verifiedCommit
            )
        }

        if !request.expectedOriginal.isEmpty,
           !request.sessionIsDirty,
           request.currentTypedToken == request.expectedOriginal {
            let commitKind: TextEditCommitKind =
                request.hostRuntimeProfile.editingEnvironment == .accessibility ? .verifiedCommit : .blindCommit
            lastStrategy = .eventReplayTransaction
            return TextEditResult(
                strategy: .eventReplayTransaction,
                appliedText: request.replacement,
                caretRange: nil,
                postVerified: true,
                needsResync: false,
                commitKind: commitKind
            )
        }

        lastStrategy = .noOp
        return TextEditResult(
            strategy: .noOp,
            appliedText: request.expectedOriginal,
            caretRange: request.verifiedRange,
            postVerified: false,
            needsResync: true,
            commitKind: .aborted
        )
    }

    /// Compatibility shim for older tests/callers.
    @discardableResult
    func replace(original: String, replacement: String, proxy: CGEventTapProxy?) async throws -> TextEditResult {
        let snapshot = await MainActor.run { FocusedTextContextService.shared.snapshotFocusedText() }
        let effectiveSnapshot = testBundleId == nil ? snapshot : nil
        let request = TextEditRequest(
            intent: .manualCycle,
            expectedOriginal: original,
            replacement: replacement,
            verifiedRange: nil,
            snapshot: effectiveSnapshot,
            hostRuntimeProfile: HostRuntimeProfile.resolve(
                bundleId: testBundleId ?? snapshot?.bundleId ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                capabilities: testBundleId == nil ? snapshot?.capabilities : nil,
                forceAccessibility: skipEventPosting && testBundleId == nil
            ),
            sessionRevision: 0,
            allowClipboardFallback: false,
            allowEventReplayFallback: true,
            sessionIsDirty: false,
            currentTypedToken: original
        )
        return try await replace(request, proxy: proxy)
    }

    func getSelectedText(proxy: CGEventTapProxy?) async throws -> String? {
        if let selected = await MainActor.run(body: { () -> String? in
            FocusedTextContextService.shared.snapshotSelectionForManualAction()?.selectedText
        }),
           !selected.isEmpty {
            return selected
        }
        return nil
    }

    private func replaceViaAX(
        request: TextEditRequest,
        snapshot: FocusedTextSnapshot,
        verifiedRange: NSRange,
        proxy: CGEventTapProxy?
    ) async throws -> TextEditResult {
        let caretRange = NSRange(location: verifiedRange.location + request.replacement.utf16.count, length: 0)
        trace.log(
            .replacementStarted,
            fields: [
                "strategy": "ax",
                "intent": request.intent.rawValue,
                "host_profile": request.hostRuntimeProfile.rawValue
            ]
        )

        if skipEventPosting {
            return TextEditResult(
                strategy: snapshot.capabilities.supportsSelectedRangeWrite && snapshot.capabilities.supportsSelectedTextWrite ? .axSelectedTextReplace : .axValueRewrite,
                appliedText: request.replacement,
                caretRange: caretRange,
                postVerified: true,
                needsResync: false,
                commitKind: .verifiedCommit
            )
        }

        if snapshot.capabilities.supportsSelectedRangeWrite,
           snapshot.capabilities.supportsSelectedTextWrite,
           replaceSelectedRange(
                element: snapshot.element,
                range: verifiedRange,
                replacement: request.replacement
           ) {
            let postSnapshot = await MainActor.run { FocusedTextContextService.shared.snapshotFocusedText() }
            let postVerified = postSnapshot.map { post in
                substring(in: post.fullText, range: NSRange(location: verifiedRange.location, length: request.replacement.utf16.count)) == request.replacement
            } ?? (snapshot.source == .accessibilityPartial && request.intent == .manualSelection)

            lastStrategy = .axSelectedTextReplace
            return TextEditResult(
                strategy: .axSelectedTextReplace,
                appliedText: request.replacement,
                caretRange: caretRange,
                postVerified: postVerified,
                needsResync: !postVerified,
                commitKind: postVerified ? .verifiedCommit : .aborted
            )
        }

        guard snapshot.capabilities.capabilityClass == .axFull,
              snapshot.capabilities.supportsValueWrite,
              snapshot.capabilities.supportsFullTextRead else {
            if request.allowEventReplayFallback {
                lastStrategy = .eventReplayTransaction
                return try await replaceViaEventReplay(request: request, proxy: proxy)
            }
            return TextEditResult(
                strategy: .noOp,
                appliedText: request.expectedOriginal,
                caretRange: nil,
                postVerified: false,
                needsResync: true,
                commitKind: .aborted
            )
        }

        guard let originalRange = Range(verifiedRange, in: snapshot.fullText) else {
            if request.allowEventReplayFallback {
                lastStrategy = .eventReplayTransaction
                return try await replaceViaEventReplay(request: request, proxy: proxy)
            }
            return TextEditResult(
                strategy: .axValueRewrite,
                appliedText: request.expectedOriginal,
                caretRange: nil,
                postVerified: false,
                needsResync: true,
                commitKind: .aborted
            )
        }

        var rewritten = snapshot.fullText
        rewritten.replaceSubrange(originalRange, with: request.replacement)

        let setValueResult = AXUIElementSetAttributeValue(
            snapshot.element,
            kAXValueAttribute as CFString,
            rewritten as CFString
        )
        guard setValueResult == .success else {
            logger.warning("AX value write failed: \(String(describing: setValueResult.rawValue), privacy: .public)")
            if request.allowEventReplayFallback {
                lastStrategy = .eventReplayTransaction
                return try await replaceViaEventReplay(request: request, proxy: proxy)
            }
            return TextEditResult(
                strategy: .axValueRewrite,
                appliedText: request.expectedOriginal,
                caretRange: nil,
                postVerified: false,
                needsResync: true,
                commitKind: .aborted
            )
        }

        if snapshot.capabilities.supportsSelectedRangeWrite {
            var cfRange = CFRange(location: caretRange.location, length: 0)
            if let axRange = AXValueCreate(.cfRange, &cfRange) {
                _ = AXUIElementSetAttributeValue(
                    snapshot.element,
                    kAXSelectedTextRangeAttribute as CFString,
                    axRange
                )
            }
        }

        let postSnapshot = await MainActor.run { FocusedTextContextService.shared.snapshotFocusedText() }
        let postVerified = postSnapshot.map { post in
            substring(in: post.fullText, range: NSRange(location: verifiedRange.location, length: request.replacement.utf16.count)) == request.replacement
        } ?? false

        lastStrategy = .axValueRewrite
        return TextEditResult(
            strategy: .axValueRewrite,
            appliedText: request.replacement,
            caretRange: caretRange,
            postVerified: postVerified,
            needsResync: !postVerified,
            commitKind: postVerified ? .verifiedCommit : .aborted
        )
    }

    private func replaceSelectedRange(
        element: AXUIElement,
        range: NSRange,
        replacement: String
    ) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else {
            return false
        }

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        ) == .success else {
            return false
        }

        let setSelectedText = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )
        guard setSelectedText == .success else {
            return false
        }

        var caretRange = CFRange(location: range.location + replacement.utf16.count, length: 0)
        if let axCaretRange = AXValueCreate(.cfRange, &caretRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axCaretRange
            )
        }

        return true
    }

    private func replaceViaClipboardSelection(
        request: TextEditRequest,
        proxy: CGEventTapProxy?
    ) async throws -> TextEditResult {
        if skipEventPosting {
            return TextEditResult(
                strategy: .clipboardSelectionPaste,
                appliedText: request.replacement,
                caretRange: nil,
                postVerified: true,
                needsResync: false,
                commitKind: .verifiedCommit
            )
        }

        let (snapshot, sentinel) = await MainActor.run {
            (ClipboardSnapshot(pasteboard: .general), UUID().uuidString)
        }

        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(request.replacement, forType: .string)
            pasteboard.setString(sentinel, forType: NSPasteboard.PasteboardType("com.chernistry.rightlayout.sentinel"))
        }

        eventPoster.postShortcut(keyCode: 9, flags: .maskCommand, proxy: proxy)
        try? await Task.sleep(nanoseconds: 120_000_000)
        restoreClipboard(snapshot: snapshot, sentinel: sentinel)

        let postSnapshot = await MainActor.run { FocusedTextContextService.shared.snapshotFocusedText() }
        let postVerified = postSnapshot.map { !$0.selectedText.contains(request.expectedOriginal) } ?? false

        return TextEditResult(
            strategy: .clipboardSelectionPaste,
            appliedText: request.replacement,
            caretRange: postSnapshot?.selectedRange,
            postVerified: postVerified,
            needsResync: postSnapshot == nil,
            commitKind: postVerified ? .verifiedCommit : .aborted
        )
    }

    private func replaceViaEventReplay(
        request: TextEditRequest,
        proxy: CGEventTapProxy?
    ) async throws -> TextEditResult {
        if skipEventPosting {
            return TextEditResult(
                strategy: .eventReplayTransaction,
                appliedText: request.replacement,
                caretRange: nil,
                postVerified: true,
                needsResync: false,
                commitKind: request.hostRuntimeProfile.editingEnvironment == .accessibility ? .verifiedCommit : .blindCommit
            )
        }

        guard request.intent.isManual || request.allowEventReplayFallback else {
            return TextEditResult(
                strategy: .eventReplayTransaction,
                appliedText: request.expectedOriginal,
                caretRange: nil,
                postVerified: false,
                needsResync: true,
                commitKind: .aborted
            )
        }

        let replayProfile = replayProfile(for: request)
        trace.log(
            .replacementStarted,
            fields: [
                "strategy": TextEditStrategy.eventReplayTransaction.rawValue,
                "intent": request.intent.rawValue,
                "host_profile": request.hostRuntimeProfile.rawValue,
                "expected_text": request.expectedOriginal
            ]
        )

        if replayProfile.boundarySettleDelay > 0 {
            try? await Task.sleep(nanoseconds: replayProfile.boundarySettleDelay)
        }

        for _ in request.expectedOriginal {
            eventPoster.postKeyEvent(keyCode: 0x33, flags: [], proxy: proxy)
            try? await Task.sleep(nanoseconds: replayProfile.deleteDelay)
        }

        for character in request.replacement {
            eventPoster.postUnicodeString(String(character), proxy: proxy)
            try? await Task.sleep(nanoseconds: replayProfile.insertDelay)
        }

        try? await Task.sleep(nanoseconds: replayProfile.postApplyDelay)

        let verification = await MainActor.run {
            FocusedTextContextService.shared.verifyExpectedSuffix(request.replacement, revision: request.sessionRevision)
        }
        switch verification {
        case .verified(let context):
            let caretRange = NSRange(location: context.verifiedRange.location + request.replacement.utf16.count, length: 0)
            return TextEditResult(
                strategy: .eventReplayTransaction,
                appliedText: request.replacement,
                caretRange: caretRange,
                postVerified: true,
                needsResync: false,
                commitKind: .verifiedCommit
            )
        case .unavailable:
            guard request.hostRuntimeProfile.allowsOptimisticBlindCommit else {
                return TextEditResult(
                    strategy: .eventReplayTransaction,
                    appliedText: request.expectedOriginal,
                    caretRange: nil,
                    postVerified: false,
                    needsResync: true,
                    commitKind: .aborted
                )
            }
            return TextEditResult(
                strategy: .eventReplayTransaction,
                appliedText: request.replacement,
                caretRange: nil,
                postVerified: false,
                needsResync: false,
                commitKind: .blindCommit
            )
        case .mismatch:
            if !request.expectedOriginal.isEmpty {
                eventPoster.postUnicodeString(request.expectedOriginal, proxy: proxy)
            }
            return TextEditResult(
                strategy: .eventReplayTransaction,
                appliedText: request.expectedOriginal,
                caretRange: nil,
                postVerified: false,
                needsResync: true,
                commitKind: .rollbackAttempted
            )
        }
    }

    private func replayProfile(for request: TextEditRequest) -> ReplayTimingProfile {
        let base = request.hostRuntimeProfile.replayTimingProfile
        let isBoundaryReplay =
            request.expectedOriginal.last?.isWhitespace == true
            || request.expectedOriginal.last?.isNewline == true

        if isBoundaryReplay {
            return base
        }

        return ReplayTimingProfile(
            boundarySettleDelay: 0,
            deleteDelay: base.deleteDelay,
            insertDelay: base.insertDelay,
            postApplyDelay: base.postApplyDelay
        )
    }

    package func getSelectedTextViaClipboard(proxy: CGEventTapProxy?) async -> String? {
        if skipEventPosting { return nil }

        let snapshot = await MainActor.run { ClipboardSnapshot(pasteboard: .general) }
        let oldChangeCount = await MainActor.run { NSPasteboard.general.changeCount }

        eventPoster.postShortcut(keyCode: 8, flags: .maskCommand, proxy: proxy)

        var copied: String?
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let currentCount = await MainActor.run { NSPasteboard.general.changeCount }
            if currentCount != oldChangeCount {
                copied = await MainActor.run { NSPasteboard.general.string(forType: .string) }
                break
            }
        }

        if copied != nil {
            await MainActor.run {
                snapshot.restore(to: .general)
            }
        }

        return copied
    }

    private func restoreClipboard(snapshot: ClipboardSnapshot, sentinel: String) {
        Task {
            try? await Task.sleep(nanoseconds: restoreClipboardDelay)
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                let markerType = NSPasteboard.PasteboardType("com.chernistry.rightlayout.sentinel")
                guard pasteboard.string(forType: markerType) == sentinel else { return }
                snapshot.restore(to: pasteboard)
            }
        }
    }

    private func substring(in text: String, range: NSRange) -> String? {
        let nsText = text as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= nsText.length else {
            return nil
        }
        return nsText.substring(with: range)
    }

    private func canReplaceViaAX(
        snapshot: FocusedTextSnapshot,
        verifiedRange: NSRange,
        expectedOriginal: String
    ) -> Bool {
        if snapshot.source == .synthetic {
            return true
        }

        if snapshot.capabilities.supportsFullTextRead,
           substring(in: snapshot.fullText, range: verifiedRange) == expectedOriginal {
            return snapshot.capabilities.supportsSelectedRangeWrite || snapshot.capabilities.supportsValueWrite
        }

        if snapshot.selectedRange == verifiedRange,
           snapshot.selectedText == expectedOriginal {
            return snapshot.capabilities.supportsSelectedRangeWrite && snapshot.capabilities.supportsSelectedTextWrite
        }

        return false
    }
}
