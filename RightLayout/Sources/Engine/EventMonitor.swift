import Foundation
import AppKit
import CoreGraphics
import Carbon
import ApplicationServices
import os.log
import _Concurrency

@MainActor
public final class EventMonitor {
    private struct InputSession {
        var sessionEpoch: UInt64 = 0
        var mutationSeq: UInt64 = 0
        var typedToken: String = ""
        var phraseContext: String = ""
        var startedAt: Date = .distantPast
        var lastMutationAt: Date = .distantPast
        var isDirty: Bool = false
        var sourceApp: String = ""
        var lastVerifiedSnapshot: FocusedTextSnapshot?
    }

    private struct ManualTriggerState {
        var isPressed = false
        var isStandaloneCandidate = false
        var lastStandaloneReleaseAt: Date?
    }

    private struct CommittedTokenContext {
        let token: String
        let separator: String
    }

    private struct PendingTransliterationHint {
        let suggestion: TransliterationSuggestion
        let separator: String
        let commitRevision: UInt64
        let createdAt: Date
    }

    private struct CommittedTransaction {
        let visibleText: String
        let timestamp: Date
    }

    private struct SelectionIntentState {
        var lastExplicitSelectionAt: Date?
        var source: String?

        mutating func mark(now: Date, source: String) {
            lastExplicitSelectionAt = now
            self.source = source
        }

        mutating func clear() {
            lastExplicitSelectionAt = nil
            source = nil
        }

        func isActive(at now: Date, timeout: TimeInterval = 3.0) -> Bool {
            guard let lastExplicitSelectionAt else { return false }
            return now.timeIntervalSince(lastExplicitSelectionAt) <= timeout
        }
    }

    private struct PendingLayoutSwitch {
        let transactionId: UUID?
        let expectedLayoutId: String?
        let expiresAt: Date

        func matches(currentLayoutId: String?, now: Date) -> Bool {
            guard now <= expiresAt else { return false }
            guard let expectedLayoutId else { return true }
            return currentLayoutId == expectedLayoutId
        }
    }

    private enum RuntimeState: String {
        case tracking
        case boundaryPending
        case replacing
        case dirtyNeedsResync
    }

    private static let axNotificationCallback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        Task { @MainActor in
            monitor.handleAXNotification(name)
        }
    }

    let engine: CorrectionEngine
    private let textContextService: FocusedTextContextService
    private let replacementService: SelectionReplacementService
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseMonitor: Any?
    private var layoutChangeObserver: Any?
    private var appChangeObserver: Any?
    private let logger = Logger.events
    private let trace = RuntimeTraceLogger.shared
    private let settings = SettingsManager.shared
    private let timeProvider: TimeProvider
    private let charEncoder: CharacterEncoder

    package var skipPIDCheck = false
    package var skipSecureInputCheck = false
    package var skipEventPosting = false

    private var inputSession = InputSession()
    private var lastActiveApp: String = ""
    private var backspaceCount = 0
    private var lastCorrectionTrackingId: UUID?
    private var backspaceReportedForId: UUID?
    private var lastBackspaceTime: Date?
    private var lastCorrectionTime: Date = .distantPast
    private var keyTimings: [TimeInterval] = []
    private var lastKeyTime: Date?
    private var lastCommittedToken: CommittedTokenContext?
    private var pendingTransliterationHint: PendingTransliterationHint?
    private var manualTriggerState = ManualTriggerState()
    private var activeSyntheticTransactions = 0
    private var transliterationApplyObserver: Any?
    private var axObserver: AXObserver?
    private var observedAppPID: pid_t?
    private var lastCommittedTransaction: CommittedTransaction?
    private var selectionIntentState = SelectionIntentState()
    private var pendingLayoutSwitch: PendingLayoutSwitch?
    private var runtimeState: RuntimeState = .tracking

    package private(set) var lastReplacement: (deletedCount: Int, insertedText: String)?

    package convenience init(engine: CorrectionEngine) {
        self.init(
            engine: engine,
            timeProvider: RealTimeProvider(),
            charEncoder: DefaultCharacterEncoder(),
            textContextService: .shared,
            replacementService: .shared
        )
    }

    init(
        engine: CorrectionEngine,
        timeProvider: TimeProvider = RealTimeProvider(),
        charEncoder: CharacterEncoder = DefaultCharacterEncoder(),
        textContextService: FocusedTextContextService = .shared,
        replacementService: SelectionReplacementService = .shared
    ) {
        self.engine = engine
        self.timeProvider = timeProvider
        self.charEncoder = charEncoder
        self.textContextService = textContextService
        self.replacementService = replacementService
        setupAppChangeObserver()
        setupLayoutChangeObserver()
        setupTransliterationApplyObserver()
        updateObservedAXApp()
    }

    private func setupLayoutChangeObserver() {
        layoutChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleLayoutChange()
            }
        }
    }

    private func handleLayoutChange() async {
        let now = timeProvider.now
        let currentLayoutId = InputSourceManager.shared.currentLayoutId()
        if let pendingLayoutSwitch,
           pendingLayoutSwitch.matches(currentLayoutId: currentLayoutId, now: now) {
            trace.log(
                .layoutSwitchObserved,
                fields: [
                    "result": "suppressed",
                    "layout_id": currentLayoutId,
                    "transaction_id": pendingLayoutSwitch.transactionId?.uuidString
                ]
            )
            self.pendingLayoutSwitch = nil
            return
        }
        pendingLayoutSwitch = nil

        let timeSinceCorrection = now.timeIntervalSince(lastCorrectionTime)
        guard timeSinceCorrection < 2.0 else { return }

        if let id = lastCorrectionTrackingId {
            if let transaction = await engine.transaction(for: id) {
                let currentBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                guard transaction.bundleId == nil || transaction.bundleId == currentBundleId else {
                    return
                }
                if let transactionEpoch = transaction.sessionEpoch,
                   transactionEpoch != inputSession.sessionEpoch {
                    return
                }
                if currentLayoutId == transaction.inputSourceAfterExpected {
                    return
                }
            }
            trace.log(
                .layoutSwitchObserved,
                fields: [
                    "result": "negative_feedback",
                    "layout_id": currentLayoutId,
                    "transaction_id": id.uuidString
                ]
            )
            await engine.reportNegativeFeedback(id: id, reason: .manualSwitch)
            lastCorrectionTrackingId = nil
            return
        }

        guard let fallbackId = await engine.currentPendingFeedbackId() else { return }
        await engine.reportNegativeFeedback(id: fallbackId, reason: .manualSwitch)
    }

    private func setupAppChangeObserver() {
        appChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetOnAppChange()
            }
        }
    }

    private func resetOnAppChange() {
        let newApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if newApp != lastActiveApp {
            Task { await engine.resetCycling() }
            clearPendingCorrectionTracking()
            selectionIntentState.clear()
            pendingLayoutSwitch = nil
            resetSession(reason: "App Change", clearPhraseContext: true)
            lastCommittedTransaction = nil
        }
        lastActiveApp = newApp
        updateObservedAXApp()
    }

    private func setupTransliterationApplyObserver() {
        transliterationApplyObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("ApplyTransliterationHint"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let idString = notification.userInfo?["id"] as? String,
                  let id = UUID(uuidString: idString) else { return }

            Task { @MainActor [weak self] in
                await self?.applyTransliterationHint(id: id)
            }
        }
    }

    package func start() async {
        let types: [CGEventType] = [
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (1 << type.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout {
                    monitor.logger.warning("Event tap disabled by timeout; re-enabling")
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    monitor.resetSession(reason: "Tap Timeout", clearPhraseContext: false)
                    return nil
                }

                if type == .tapDisabledByUserInput {
                    monitor.logger.warning("Event tap disabled by user input; re-enabling")
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    monitor.resetSession(reason: "Tap User Input", clearPhraseContext: false)
                    return nil
                }

                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExternalInvalidation(reason: "Mouse/Scroll", clearPhraseContext: false)
            }
        }
    }

    package func stop() {
        stopAXObserver()

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }

        if let observer = layoutChangeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            layoutChangeObserver = nil
        }

        if let observer = appChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appChangeObserver = nil
        }

        if let observer = transliterationApplyObserver {
            NotificationCenter.default.removeObserver(observer)
            transliterationApplyObserver = nil
        }
    }
    internal func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        expireStandaloneOptionTapIfNeeded()

        if !skipSecureInputCheck && IsSecureEventInputEnabled() {
            resetSession(reason: "Secure Input", clearPhraseContext: true)
            return Unmanaged.passUnretained(event)
        }

        if !skipPIDCheck && event.getIntegerValueField(.eventSourceUserData) == SyntheticEventMarker.value {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            if type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
                selectionIntentState.mark(now: timeProvider.now, source: "mouseDrag")
            }
            handleExternalInvalidation(reason: "Mouse/Scroll", clearPhraseContext: false)
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(proxy: proxy, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if settings.hotkeyEnabled,
           settings.manualTriggerMode == .doubleTapOption,
           keyCode == settings.manualTriggerOptionKeyCode {
            handleOptionFlagsChanged(flags: flags)
            return Unmanaged.passUnretained(event)
        }

        if manualTriggerState.isPressed {
            cancelStandaloneOptionTap()
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            handleExternalInvalidation(reason: "Modifier", clearPhraseContext: false)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleOptionFlagsChanged(flags: CGEventFlags) {
        let now = timeProvider.now

        if flags.contains(.maskAlternate) {
            manualTriggerState.isPressed = true
            manualTriggerState.isStandaloneCandidate = true
            return
        }

        guard manualTriggerState.isPressed else { return }
        manualTriggerState.isPressed = false

        guard manualTriggerState.isStandaloneCandidate else {
            manualTriggerState.lastStandaloneReleaseAt = nil
            return
        }

        if let lastRelease = manualTriggerState.lastStandaloneReleaseAt,
           now.timeIntervalSince(lastRelease) <= settings.manualTriggerDoubleTapWindow {
            manualTriggerState.lastStandaloneReleaseAt = nil
            manualTriggerState.isStandaloneCandidate = false
            Task { @MainActor in
                await handleHotkeyPress()
            }
            return
        }

        manualTriggerState.lastStandaloneReleaseAt = now
        manualTriggerState.isStandaloneCandidate = false
    }

    private func handleKeyDown(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let now = timeProvider.now

        if flags.contains(.maskCommand) {
            cancelStandaloneOptionTap()
            if keyCode == 6 {
                Task { await engine.handleUndo() }
            }
            clearTransliterationHint()
            handleExternalInvalidation(reason: "Command Shortcut", clearPhraseContext: false)
            return Unmanaged.passUnretained(event)
        }

        if flags.contains(.maskControl) {
            cancelStandaloneOptionTap()
            clearTransliterationHint()
            handleExternalInvalidation(reason: "Control Shortcut", clearPhraseContext: false)
            return Unmanaged.passUnretained(event)
        }

        if keyCode == 51 {
            cancelStandaloneOptionTap()
            handleBackspace()
            return Unmanaged.passUnretained(event)
        } else {
            backspaceCount = 0
            backspaceReportedForId = nil
        }

        let navigationKeys: Set<CGKeyCode> = [123, 124, 125, 126, 115, 119, 116, 121, 117]
        if navigationKeys.contains(keyCode) {
            if flags.contains(.maskShift) {
                selectionIntentState.mark(now: now, source: "shiftNavigation")
            }
            clearTransliterationHint()
            handleExternalInvalidation(reason: "Navigation", clearPhraseContext: false)
            Task { await engine.resetCycling() }
            return Unmanaged.passUnretained(event)
        }

        guard let chars = charEncoder.encode(event: event), !chars.isEmpty else {
            cancelStandaloneOptionTap()
            return Unmanaged.passUnretained(event)
        }

        cancelStandaloneOptionTap()

        if inputSession.typedToken.isEmpty, let first = chars.first, first.isLetter || first.isNumber {
            NotificationCenter.default.post(name: Notification.Name("ProactiveLayoutHint"), object: nil, userInfo: nil)
            clearTransliterationHint()
        }

        if !inputSession.typedToken.isEmpty,
           let last = lastKeyTime,
           now.timeIntervalSince(last) > ThresholdsConfig.shared.timing.bufferTimeout {
            inputSession.typedToken = ""
            keyTimings.removeAll()
        }

        if isWordBoundaryTrigger(chars) {
            let token = inputSession.typedToken
            inputSession.typedToken = ""
            bumpSessionMutation(at: now)
            lastKeyTime = now

            if token.isEmpty {
                if let last = lastCommittedToken {
                    lastCommittedToken = CommittedTokenContext(token: last.token, separator: last.separator + chars)
                }
                return Unmanaged.passUnretained(event)
            }

            let expectedMutationSeq = inputSession.mutationSeq
            Task { @MainActor in
                await processCommittedBoundary(
                    token: token,
                    separator: chars,
                    proxy: proxy,
                    expectedMutationSeq: expectedMutationSeq
                )
            }
            return Unmanaged.passUnretained(event)
        }

        inputSession.typedToken.append(chars)
        bumpSessionMutation(at: now)

        if let last = lastKeyTime {
            keyTimings.append(now.timeIntervalSince(last))
        } else {
            keyTimings.append(0)
        }
        lastKeyTime = now

        Task { await engine.resetCycling() }

        return Unmanaged.passUnretained(event)
    }

    private func handleBackspace() {
        clearTransliterationHint()

        if !inputSession.typedToken.isEmpty {
            inputSession.typedToken.removeLast()
            bumpSessionMutation(at: timeProvider.now)
        } else {
            inputSession.isDirty = true
            inputSession.lastVerifiedSnapshot = nil
            inputSession.mutationSeq &+= 1
            lastCommittedToken = nil
        }

        lastKeyTime = timeProvider.now
        Task { await engine.resetCycling() }

        let now = timeProvider.now
        let timeSinceLastBackspace = now.timeIntervalSince(lastBackspaceTime ?? .distantPast)
        lastBackspaceTime = now

        if timeSinceLastBackspace < 0.5 {
            backspaceCount += 1
        } else {
            backspaceCount = 1
        }

        if backspaceCount >= 3 {
            if let id = lastCorrectionTrackingId, backspaceReportedForId != id {
                Task {
                    if let transaction = await engine.transaction(for: id),
                       let transactionEpoch = transaction.sessionEpoch,
                       transactionEpoch != self.inputSession.sessionEpoch {
                        return
                    }
                    await engine.reportNegativeFeedback(id: id, reason: .backspaceBurst)
                }
                backspaceReportedForId = id
                return
            }

            Task { @MainActor in
                let engineFallbackId = await engine.currentPendingFeedbackId()
                let fallbackId = lastCorrectionTrackingId ?? engineFallbackId
                guard let id = fallbackId, backspaceReportedForId != id else { return }
                await engine.reportNegativeFeedback(id: id, reason: .backspaceBurst)
                backspaceReportedForId = id
            }
        }
    }

    private func processCommittedBoundary(
        token: String,
        separator: String,
        proxy: CGEventTapProxy,
        expectedMutationSeq: UInt64
    ) async {
        runtimeState = .boundaryPending
        guard expectedMutationSeq == inputSession.mutationSeq else {
            preserveCommittedBoundaryIfNeeded(token: token, separator: separator)
            return
        }

        let expectedVisibleText = token + separator
        let focusedCapabilities = textContextService.resolveFocusedElementCapabilities()
        let bundleId = focusedCapabilities?.bundleId ?? lastActiveApp
        let hostProfile = currentHostRuntimeProfile(bundleId: bundleId, capabilities: focusedCapabilities?.capabilities)
        trace.log(
            .boundaryDetected,
            fields: [
                "bundle_id": bundleId,
                "host_profile": hostProfile.rawValue,
                "session_epoch": String(inputSession.sessionEpoch),
                "mutation_seq": String(inputSession.mutationSeq),
                "token": token,
                "separator": separator
            ]
        )
        let verifiedContext = await committedBoundaryVerificationContext(
            token: token,
            separator: separator
        )
        let editingEnvironment = hostProfile.editingEnvironment
        let matchedExpectedText = verifiedContext?.verifiedText ?? expectedVisibleText
        let matchedReplacementSuffix = verifiedContext?.verifiedText.hasSuffix(separator) == true ? separator : ""

        if await engine.checkForRetype(text: token, bundleId: verifiedContext?.snapshot.bundleId ?? lastActiveApp) {
            keyTimings.removeAll()
            updatePhraseBuffer(with: splitBufferContent(token).token)
            lastCommittedToken = CommittedTokenContext(token: token, separator: separator)
            clearTransliterationHint()
            lastCorrectionTrackingId = nil
            lastCorrectionTime = .distantPast
            Task { await engine.resetCycling() }
            return
        }

        if let acceptedId = lastCorrectionTrackingId {
            await engine.acceptTransactionIfTracked(acceptedId)
            lastCorrectionTrackingId = nil
            backspaceReportedForId = nil
        }

        let currentLayoutId = InputSourceManager.shared.currentLayoutId()
        let currentLanguage = mapLayoutToLanguage(currentLayoutId)

        var planned = await engine.planCorrection(
            token,
            phraseBuffer: inputSession.phraseContext,
            expectedLayout: currentLanguage,
            latencies: keyTimings,
            editingEnvironment: editingEnvironment
        )
        trace.log(
            .planReady,
            fields: [
                "bundle_id": bundleId,
                "host_profile": hostProfile.rawValue,
                "confidence": planned.result.confidence.map { String(format: "%.3f", $0) },
                "action": planned.plan.traceValue,
                "target_language": planned.result.targetLanguage?.rawValue,
                "token": token
            ]
        )

        if skipEventPosting,
           case .hint = planned.plan,
           let forced = await engine.applyPendingSuggestion(),
           let corrected = forced.corrected {
            planned = PlannedCorrection(
                result: forced,
                plan: .autoReplace(
                    CorrectionCandidate(
                        original: token,
                        replacement: corrected,
                        pendingOriginal: forced.pendingOriginal,
                        pendingReplacement: forced.pendingCorrection,
                        trackingId: forced.transaction?.id,
                        transaction: forced.transaction,
                        transliterationSuggestion: forced.transliterationSuggestion
                    )
                )
            )
        }
        keyTimings.removeAll()

        await engine.updateCyclingTrailingSeparator(separator)

        guard expectedMutationSeq == inputSession.mutationSeq else {
            preserveCommittedBoundaryIfNeeded(token: token, separator: separator)
            await engine.resetCycling()
            return
        }

        let outputToken = planned.result.corrected ?? token

        let previousCommitted = recentCommittedTokenContext()
        let fallbackCascade: (original: String, replacement: String)?
        if planned.result.pendingCorrection == nil,
           case .autoReplace = planned.plan,
           editingEnvironment == .accessibility,
           let last = previousCommitted,
           last.token.filter(\.isLetter).count <= 2,
           let targetLanguage = planned.result.targetLanguage {
            let contextual = await engine.contextualCascadeCorrection(for: last.token, targetLanguage: targetLanguage)
            if let contextual {
            fallbackCascade = (last.token, contextual)
            } else {
                fallbackCascade = nil
            }
        } else {
            fallbackCascade = nil
        }

        if let pendingCorrection = planned.result.pendingCorrection ?? fallbackCascade?.replacement,
           let pendingOriginal = planned.result.pendingOriginal ?? fallbackCascade?.original,
           let last = previousCommitted,
           last.token == pendingOriginal {
            let combinedStem = pendingOriginal + last.separator + token
            guard let combinedContext = await committedBoundaryVerificationContext(
                token: combinedStem,
                separator: separator
            ) else {
                return
            }

            let combinedOriginal = combinedContext.verifiedText
            let inserted = pendingCorrection + last.separator + outputToken + (combinedOriginal.hasSuffix(separator) ? separator : "")
            let applied = await performReplacement(
                intent: .autoCorrection,
                expectedOriginal: combinedOriginal,
                replacement: inserted,
                verifiedContext: combinedContext,
                allowClipboardFallback: false,
                allowEventReplayFallback: false,
                currentVisibleText: combinedOriginal,
                hostRuntimeProfile: hostProfile,
                proxy: proxy
            )
            guard let applied else { return }

            replaceLastPhraseBufferWord(from: pendingOriginal, to: pendingCorrection)
            updatePhraseBuffer(with: splitBufferContent(outputToken).token)
            lastCommittedToken = CommittedTokenContext(token: outputToken, separator: separator)
            setTransliterationHint(planned.result.transliterationSuggestion, separator: separator, commitRevision: expectedMutationSeq)
            await commitReplacementTransaction(
                planned.result.transaction,
                editResult: applied,
                verifiedContext: combinedContext
            )
            if let transactionId = planned.result.transaction?.id {
                lastCorrectionTrackingId = transactionId
                lastCorrectionTime = timeProvider.now
                backspaceReportedForId = nil
            }
            if shouldSwitchLayout(after: applied, hostRuntimeProfile: hostProfile) {
                switchInputSourceIfNeeded(to: planned.result.targetLanguage, transactionId: planned.result.transaction?.id)
            }
            return
        }

        switch planned.plan {
        case .autoReplace(let candidate):
            let allowEventReplayFallback =
                hostProfile.allowsAutomaticBlindReplay &&
                shouldAllowAutomaticReplayFallback(
                    for: matchedExpectedText,
                    confidence: planned.result.confidence,
                    hostRuntimeProfile: hostProfile
                )
            guard verifiedContext != nil || allowEventReplayFallback else {
                updatePhraseBuffer(with: splitBufferContent(token).token)
                lastCommittedToken = CommittedTokenContext(token: token, separator: separator)
                setTransliterationHint(nil, separator: separator, commitRevision: expectedMutationSeq)
                return
            }

            let applied = await performReplacement(
                intent: .autoCorrection,
                expectedOriginal: matchedExpectedText,
                replacement: candidate.replacement + (verifiedContext == nil ? separator : matchedReplacementSuffix),
                verifiedContext: verifiedContext,
                allowClipboardFallback: false,
                allowEventReplayFallback: allowEventReplayFallback,
                currentVisibleText: matchedExpectedText,
                hostRuntimeProfile: hostProfile,
                proxy: proxy
            )
            guard let applied else { return }

            lastCommittedToken = CommittedTokenContext(token: candidate.replacement, separator: separator)
            updatePhraseBuffer(with: splitBufferContent(candidate.replacement).token)
            setTransliterationHint(nil, separator: separator, commitRevision: expectedMutationSeq)
            await commitReplacementTransaction(
                candidate.transaction ?? planned.result.transaction,
                editResult: applied,
                verifiedContext: verifiedContext
            )
            if let transactionId = (candidate.transaction ?? planned.result.transaction)?.id {
                lastCorrectionTrackingId = transactionId
                lastCorrectionTime = timeProvider.now
                backspaceReportedForId = nil
            }
            if shouldSwitchLayout(after: applied, hostRuntimeProfile: hostProfile) {
                switchInputSourceIfNeeded(
                    to: planned.result.targetLanguage,
                    transactionId: (candidate.transaction ?? planned.result.transaction)?.id
                )
            }
        case .hint, .none:
            updatePhraseBuffer(with: splitBufferContent(outputToken).token)
            lastCommittedToken = CommittedTokenContext(token: outputToken, separator: separator)
            setTransliterationHint(planned.result.transliterationSuggestion, separator: separator, commitRevision: expectedMutationSeq)
        case .manualCycle:
            break
        }
        runtimeState = .tracking
    }

    private func switchInputSourceIfNeeded(to language: Language?, transactionId: UUID? = nil) {
        guard let language else { return }
        guard settings.autoSwitchLayout else { return }
        trace.log(
            .layoutSwitchRequested,
            fields: [
                "transaction_id": transactionId?.uuidString,
                "language": language.rawValue
            ]
        )

        let activeLayouts = settings.activeLayouts
        if let preferredLayout = activeLayouts[language.rawValue] {
            pendingLayoutSwitch = PendingLayoutSwitch(
                transactionId: transactionId,
                expectedLayoutId: preferredLayout,
                expiresAt: timeProvider.now.addingTimeInterval(1.0)
            )
            if InputSourceManager.shared.switchToLayoutVariant(preferredLayout) {
                return
            }
        }
        pendingLayoutSwitch = PendingLayoutSwitch(
            transactionId: transactionId,
            expectedLayoutId: nil,
            expiresAt: timeProvider.now.addingTimeInterval(1.0)
        )
        InputSourceManager.shared.switchTo(language: language)
    }

    private func shouldSwitchLayout(after result: TextEditResult, hostRuntimeProfile: HostRuntimeProfile) -> Bool {
        switch result.commitKind {
        case .verifiedCommit:
            return true
        case .blindCommit:
            return hostRuntimeProfile.switchSafeAfterBlindReplay
        case .aborted, .rollbackAttempted:
            return false
        }
    }

    private func currentHostRuntimeProfile(
        bundleId: String?,
        capabilities: AppEditCapabilities?
    ) -> HostRuntimeProfile {
        HostRuntimeProfile.resolve(
            bundleId: bundleId,
            capabilities: capabilities,
            forceAccessibility: skipEventPosting || skipPIDCheck,
            forceSecure: !skipSecureInputCheck && IsSecureEventInputEnabled()
        )
    }

    private func handleHotkeyPress() async {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let focusedCapabilities = textContextService.resolveFocusedElementCapabilities()
        let hostProfile = currentHostRuntimeProfile(bundleId: bundleId, capabilities: focusedCapabilities?.capabilities)

        if await engine.hasCyclingState(),
           let currentVisible = await engine.getCurrentCyclingText() {
            let trailingSeparator = await engine.cyclingTrailingSeparator()
            let expectedOriginal = currentVisible + trailingSeparator
            guard let newText = await engine.cycleCorrection(bundleId: bundleId) else { return }
            let replacement = newText + trailingSeparator
            let verified = await verificationContext(
                forExpectedSuffix: expectedOriginal,
                preserveSessionOnUnavailable: true
            )
            guard verified != nil || canUseManualReplayFallback(for: expectedOriginal, hostRuntimeProfile: hostProfile) else { return }

            let cyclingOriginal = await engine.getCyclingOriginalText()
            let intent: TextEditIntent = newText == cyclingOriginal ? .manualUndo : .manualCycle
            let applied = await performReplacement(
                intent: intent,
                expectedOriginal: expectedOriginal,
                replacement: replacement,
                verifiedContext: verified,
                allowClipboardFallback: false,
                allowEventReplayFallback: false,
                currentVisibleText: expectedOriginal,
                hostRuntimeProfile: hostProfile,
                proxy: nil
            )
            if let applied {
                let manualTransaction = await buildManualTransaction(
                    original: currentVisible,
                    replacement: newText,
                    intent: intent,
                    bundleId: bundleId
                )
                await commitReplacementTransaction(manualTransaction, editResult: applied, verifiedContext: verified)
                if shouldSwitchLayout(after: applied, hostRuntimeProfile: hostProfile) {
                    switchInputSourceIfNeeded(to: await engine.currentCyclingTargetLanguage(), transactionId: manualTransaction?.id)
                }
            }
            return
        }

        if let result = await engine.applyPendingSuggestion(),
           let corrected = result.corrected {
            let trailingSeparator = await engine.cyclingTrailingSeparator()
            let original = await engine.getCyclingOriginalText() ?? corrected
            let expectedOriginal = original + trailingSeparator
            let verified = await verificationContext(
                forExpectedSuffix: expectedOriginal,
                preserveSessionOnUnavailable: true
            )
            guard verified != nil || canUseManualReplayFallback(for: expectedOriginal, hostRuntimeProfile: hostProfile) else { return }
            let replacement = corrected + trailingSeparator

            let applied = await performReplacement(
                intent: .manualCycle,
                expectedOriginal: expectedOriginal,
                replacement: replacement,
                verifiedContext: verified,
                allowClipboardFallback: false,
                allowEventReplayFallback: false,
                currentVisibleText: expectedOriginal,
                hostRuntimeProfile: hostProfile,
                proxy: nil
            )
            if let applied {
                await commitReplacementTransaction(result.transaction, editResult: applied, verifiedContext: verified)
                if shouldSwitchLayout(after: applied, hostRuntimeProfile: hostProfile) {
                    switchInputSourceIfNeeded(to: result.targetLanguage, transactionId: result.transaction?.id)
                }
            }
            return
        }

        if let selectionSnapshot = textContextService.snapshotSelectionForManualAction(),
           !selectionSnapshot.selectedText.isEmpty,
           let replacement = await engine.correctLastWord(selectionSnapshot.selectedText, bundleId: bundleId) {
            let verified = VerifiedEditContext(
                snapshot: selectionSnapshot,
                verifiedRange: selectionSnapshot.selectedRange,
                verifiedText: selectionSnapshot.selectedText
            )
            let applied = await performReplacement(
                intent: .manualSelection,
                expectedOriginal: selectionSnapshot.selectedText,
                replacement: replacement,
                verifiedContext: verified,
                allowClipboardFallback: true,
                allowEventReplayFallback: false,
                currentVisibleText: selectionSnapshot.selectedText,
                hostRuntimeProfile: hostProfile,
                proxy: nil
            )
            if let applied {
                let transaction = await buildManualTransaction(
                    original: selectionSnapshot.selectedText,
                    replacement: replacement,
                    intent: .manualSelection,
                    bundleId: bundleId
                )
                await commitReplacementTransaction(transaction, editResult: applied, verifiedContext: verified)
                if shouldSwitchLayout(after: applied, hostRuntimeProfile: hostProfile) {
                    switchInputSourceIfNeeded(to: await engine.currentCyclingTargetLanguage(), transactionId: transaction?.id)
                }
            }
            return
        }

        if !inputSession.typedToken.isEmpty,
           let replacement = await engine.correctLastWord(inputSession.typedToken, bundleId: bundleId) {
            let verified = await verificationContext(
                forExpectedSuffix: inputSession.typedToken,
                preserveSessionOnUnavailable: true
            )
            guard verified != nil || canUseManualReplayFallback(for: inputSession.typedToken, hostRuntimeProfile: hostProfile) else { return }
            let applied = await performReplacement(
                intent: .manualCycle,
                expectedOriginal: inputSession.typedToken,
                replacement: replacement,
                verifiedContext: verified,
                allowClipboardFallback: false,
                allowEventReplayFallback: false,
                currentVisibleText: inputSession.typedToken,
                hostRuntimeProfile: hostProfile,
                proxy: nil
            )
            if let applied {
                let transaction = await buildManualTransaction(
                    original: inputSession.typedToken,
                    replacement: replacement,
                    intent: .manualCycle,
                    bundleId: bundleId
                )
                await commitReplacementTransaction(transaction, editResult: applied, verifiedContext: verified)
                if shouldSwitchLayout(after: applied, hostRuntimeProfile: hostProfile) {
                    switchInputSourceIfNeeded(to: await engine.currentCyclingTargetLanguage(), transactionId: transaction?.id)
                }
            }
            return
        }

        if let last = lastCommittedToken,
           let replacement = await engine.correctLastWord(last.token, bundleId: bundleId) {
            let expectedOriginal = last.token + last.separator
            let verified = await verificationContext(
                forExpectedSuffix: expectedOriginal,
                preserveSessionOnUnavailable: true
            )
            guard verified != nil || canUseManualReplayFallback(for: expectedOriginal, hostRuntimeProfile: hostProfile) else { return }
            let applied = await performReplacement(
                intent: .manualCycle,
                expectedOriginal: expectedOriginal,
                replacement: replacement + last.separator,
                verifiedContext: verified,
                allowClipboardFallback: false,
                allowEventReplayFallback: false,
                currentVisibleText: expectedOriginal,
                hostRuntimeProfile: hostProfile,
                proxy: nil
            )
            if let applied {
                let transaction = await buildManualTransaction(
                    original: last.token,
                    replacement: replacement,
                    intent: .manualCycle,
                    bundleId: bundleId
                )
                await commitReplacementTransaction(transaction, editResult: applied, verifiedContext: verified)
                if shouldSwitchLayout(after: applied, hostRuntimeProfile: hostProfile) {
                    switchInputSourceIfNeeded(to: await engine.currentCyclingTargetLanguage(), transactionId: transaction?.id)
                }
            }
            return
        }

        guard hostProfile.allowsManualSelectionClipboardFallback,
              selectionIntentState.isActive(at: timeProvider.now) else { return }

        if let clipboardSelection = await replacementService.getSelectedTextViaClipboard(proxy: nil),
           !clipboardSelection.isEmpty,
           let replacement = await engine.correctLastWord(clipboardSelection, bundleId: bundleId) {
            let request = TextEditRequest(
                intent: .manualSelection,
                expectedOriginal: clipboardSelection,
                replacement: replacement,
                verifiedRange: nil,
                snapshot: nil,
                hostRuntimeProfile: hostProfile,
                sessionRevision: inputSession.mutationSeq,
                allowClipboardFallback: true,
                allowEventReplayFallback: false,
                sessionIsDirty: false,
                currentTypedToken: clipboardSelection
            )
            let result = await applyRequest(request, proxy: nil)
            if let result, !result.needsResync {
                let transaction = await buildManualTransaction(
                    original: clipboardSelection,
                    replacement: replacement,
                    intent: .manualSelection,
                    bundleId: bundleId
                )
                await commitReplacementTransaction(transaction, editResult: result, verifiedContext: nil)
                if shouldSwitchLayout(after: result, hostRuntimeProfile: hostProfile) {
                    switchInputSourceIfNeeded(to: await engine.currentCyclingTargetLanguage(), transactionId: transaction?.id)
                }
            }
        }
    }

    private func performReplacement(
        intent: TextEditIntent,
        expectedOriginal: String,
        replacement: String,
        verifiedContext: VerifiedEditContext?,
        allowClipboardFallback: Bool,
        allowEventReplayFallback: Bool,
        currentVisibleText: String,
        hostRuntimeProfile: HostRuntimeProfile,
        proxy: CGEventTapProxy?
    ) async -> TextEditResult? {
        replacementService.setSkipEventPosting(skipEventPosting)
        runtimeState = .replacing

        if skipEventPosting {
            lastReplacement = (expectedOriginal.count, replacement)
        }

        let request = TextEditRequest(
            intent: intent,
            expectedOriginal: expectedOriginal,
            replacement: replacement,
            verifiedRange: verifiedContext?.verifiedRange,
            snapshot: verifiedContext?.snapshot,
            hostRuntimeProfile: hostRuntimeProfile,
            sessionRevision: inputSession.mutationSeq,
            allowClipboardFallback: allowClipboardFallback,
            allowEventReplayFallback: allowEventReplayFallback,
            sessionIsDirty: inputSession.isDirty,
            currentTypedToken: currentVisibleText
        )

        let result = await applyRequest(request, proxy: proxy)
        guard let result, !result.needsResync else {
            runtimeState = .dirtyNeedsResync
            return nil
        }

        if let snapshot = textContextService.snapshotFocusedText() {
            applySeed(textContextService.seedSession(from: snapshot), snapshot: snapshot)
        } else {
            inputSession.typedToken = ""
            inputSession.lastVerifiedSnapshot = nil
        }
        inputSession.isDirty = false
        lastCommittedTransaction = CommittedTransaction(visibleText: replacement, timestamp: timeProvider.now)
        runtimeState = .tracking
        return result
    }

    private func commitReplacementTransaction(
        _ transaction: CorrectionTransaction?,
        editResult: TextEditResult,
        verifiedContext: VerifiedEditContext?
    ) async {
        guard let transaction else { return }
        let committed = transaction.committed(
            sessionEpoch: inputSession.sessionEpoch,
            mutationSequence: inputSession.mutationSeq,
            strategy: editResult.strategy,
            verifiedContext: verifiedContext
        )
        await engine.commitTransaction(committed)
        if committed.wasAutoApplied {
            lastCorrectionTrackingId = committed.id
            lastCorrectionTime = timeProvider.now
        }
    }

    private func buildManualTransaction(
        original: String,
        replacement: String,
        intent: TextEditIntent,
        bundleId: String?
    ) async -> CorrectionTransaction? {
        guard let targetLanguage = await engine.currentCyclingTargetLanguage() else { return nil }
        let hypothesis = await engine.currentCyclingHypothesis()
        let focusedCapabilities = textContextService.resolveFocusedElementCapabilities()
        return CorrectionTransaction(
            sessionEpoch: inputSession.sessionEpoch,
            mutationSequence: inputSession.mutationSeq,
            token: original,
            replacement: replacement,
            bundleId: bundleId,
            elementFingerprint: focusedCapabilities?.capabilities.elementFingerprint,
            capabilityClass: focusedCapabilities?.capabilities.capabilityClass,
            intent: intent,
            targetLanguage: targetLanguage,
            hypothesis: hypothesis,
            features: nil,
            wasAutoApplied: false,
            inputSourceBefore: InputSourceManager.shared.currentLayoutId(),
            inputSourceAfterExpected: settings.activeLayouts[targetLanguage.rawValue]
        )
    }

    private func applyRequest(_ request: TextEditRequest, proxy: CGEventTapProxy?) async -> TextEditResult? {
        activeSyntheticTransactions += 1
        defer { activeSyntheticTransactions = max(0, activeSyntheticTransactions - 1) }

        do {
            let result = try await replacementService.replace(request, proxy: proxy)
            trace.log(
                .replacementFinished,
                fields: [
                    "strategy": result.strategy.rawValue,
                    "commit_kind": result.commitKind.rawValue,
                    "needs_resync": result.needsResync ? "true" : "false",
                    "host_profile": request.hostRuntimeProfile.rawValue,
                    "intent": request.intent.rawValue
                ]
            )
            if result.needsResync {
                if let snapshot = textContextService.snapshotFocusedText() {
                    applySeed(textContextService.seedSession(from: snapshot), snapshot: snapshot)
                } else {
                    resetSession(reason: "Replacement Resync", clearPhraseContext: false)
                }
            }
            return result
        } catch {
            logger.error("Failed to replace text: \(error.localizedDescription, privacy: .public)")
            resetSession(reason: "Replacement Error", clearPhraseContext: false)
            return nil
        }
    }

    private func verificationContext(
        forExpectedSuffix expectedText: String,
        preserveSessionOnUnavailable: Bool = false
    ) async -> VerifiedEditContext? {
        guard !expectedText.isEmpty else { return nil }

        if skipEventPosting || skipPIDCheck {
            return syntheticVerifiedContext(for: expectedText)
        }

        switch textContextService.verifyExpectedSuffix(expectedText, revision: inputSession.mutationSeq) {
        case .verified(let context):
            trace.log(
                .verificationResult,
                fields: [
                    "mode": "suffix",
                    "result": "verified",
                    "verified_text": context.verifiedText
                ]
            )
            inputSession.lastVerifiedSnapshot = context.snapshot
            inputSession.isDirty = false
            return context
        case .mismatch(let snapshot, let seed):
            trace.log(
                .verificationResult,
                fields: [
                    "mode": "suffix",
                    "result": "mismatch",
                    "expected_text": expectedText
                ]
            )
            if let snapshot, let seed {
                applySeed(seed, snapshot: snapshot, bumpSessionEpoch: true)
            } else {
                resetSession(reason: "Verification Mismatch", clearPhraseContext: false)
            }
            lastCommittedToken = nil
            clearTransliterationHint()
            Task { await engine.resetCycling() }
            return nil
        case .unavailable:
            trace.log(
                .verificationResult,
                fields: [
                    "mode": "suffix",
                    "result": "unavailable",
                    "expected_text": expectedText
                ]
            )
            if preserveSessionOnUnavailable {
                return nil
            }
            if let snapshot = textContextService.snapshotFocusedText() {
                applySeed(textContextService.seedSession(from: snapshot), snapshot: snapshot, bumpSessionEpoch: true)
            } else {
                resetSession(reason: "Verification Unavailable", clearPhraseContext: false)
            }
            lastCommittedToken = nil
            clearTransliterationHint()
            Task { await engine.resetCycling() }
            return nil
        }
    }

    private func committedBoundaryVerificationContext(
        token: String,
        separator: String
    ) async -> VerifiedEditContext? {
        if skipEventPosting || skipPIDCheck {
            return syntheticVerifiedContext(for: token + separator)
        }

        var latestSnapshot: FocusedTextSnapshot?
        var latestSeed: InputSessionSeed?

        for attempt in 0..<5 {
            switch textContextService.verifyCommittedBoundary(token: token, separator: separator, revision: inputSession.mutationSeq) {
            case .verified(let context):
                trace.log(
                    .verificationResult,
                    fields: [
                        "mode": "boundary",
                        "result": "verified",
                        "verified_text": context.verifiedText,
                        "attempt": String(attempt)
                    ]
                )
                inputSession.lastVerifiedSnapshot = context.snapshot
                inputSession.isDirty = false
                return context
            case .unavailable:
                trace.log(
                    .verificationResult,
                    fields: [
                        "mode": "boundary",
                        "result": "unavailable",
                        "attempt": String(attempt),
                        "token": token,
                        "separator": separator
                    ]
                )
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 15_000_000)
                    continue
                }
                return nil
            case .mismatch(let snapshot, let seed):
                trace.log(
                    .verificationResult,
                    fields: [
                        "mode": "boundary",
                        "result": "mismatch",
                        "attempt": String(attempt),
                        "token": token,
                        "separator": separator
                    ]
                )
                latestSnapshot = snapshot
                latestSeed = seed
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 15_000_000)
                    continue
                }
            }
        }

        if let latestSnapshot, let latestSeed {
            applySeed(latestSeed, snapshot: latestSnapshot, bumpSessionEpoch: true)
        } else {
            resetSession(reason: "Boundary Verification Mismatch", clearPhraseContext: false)
        }
        lastCommittedToken = nil
        clearTransliterationHint()
        Task { await engine.resetCycling() }
        return nil
    }

    private func canUseManualReplayFallback(
        for expectedText: String,
        hostRuntimeProfile: HostRuntimeProfile
    ) -> Bool {
        guard !expectedText.isEmpty else { return false }
        guard hostRuntimeProfile.allowsManualLastWordReplay else { return false }
        guard !inputSession.isDirty, activeSyntheticTransactions == 0 else { return false }

        let now = timeProvider.now
        if inputSession.typedToken == expectedText {
            return now.timeIntervalSince(lastKeyTime ?? .distantPast) <= 4.0
        }

        if let transaction = lastCommittedTransaction, transaction.visibleText == expectedText {
            return now.timeIntervalSince(transaction.timestamp) <= 10.0
        }

        if let last = lastCommittedToken, (last.token + last.separator) == expectedText {
            return now.timeIntervalSince(lastKeyTime ?? .distantPast) <= 10.0
        }

        return false
    }

    private func shouldAllowAutomaticReplayFallback(
        for expectedText: String,
        confidence: Double?,
        hostRuntimeProfile: HostRuntimeProfile
    ) -> Bool {
        guard !expectedText.isEmpty else { return false }
        guard hostRuntimeProfile.allowsAutomaticBlindReplay else { return false }
        guard !inputSession.isDirty, activeSyntheticTransactions == 0 else { return false }
        guard timeProvider.now.timeIntervalSince(inputSession.lastMutationAt) <= 0.55 else { return false }

        let trimmed = expectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count <= 18, trimmed.allSatisfy({ $0.isLetter }) else {
            return false
        }

        let threshold = max(settings.standardPathThreshold + 0.06, 0.88)
        guard let confidence, confidence >= threshold else {
            return false
        }

        return true
    }

    private func syntheticVerifiedContext(for expectedText: String) -> VerifiedEditContext {
        let snapshot = FocusedTextSnapshot(
            element: AXUIElementCreateSystemWide(),
            bundleId: lastActiveApp,
            pid: ProcessInfo.processInfo.processIdentifier,
            fullText: expectedText,
            selectedRange: NSRange(location: expectedText.utf16.count, length: 0),
            selectedText: "",
            caretLocation: expectedText.utf16.count,
            supportsAXSelectedTextWrite: false,
            supportsAXValueWrite: false,
            supportsAXRangeWrite: false,
            capabilities: AppEditCapabilities(
                supportsSelectedTextWrite: false,
                supportsSelectedRangeWrite: false,
                supportsValueWrite: false,
                supportsSelectionRead: false,
                supportsFullTextRead: true,
                isSecureOrReadBlind: true,
                capabilityClass: .secure,
                elementFingerprint: nil
            ),
            source: .synthetic,
            revision: inputSession.mutationSeq
        )
        return VerifiedEditContext(
            snapshot: snapshot,
            verifiedRange: NSRange(location: 0, length: expectedText.utf16.count),
            verifiedText: expectedText
        )
    }

    private func handleExternalInvalidation(reason: String, clearPhraseContext: Bool) {
        runtimeState = .dirtyNeedsResync
        trace.log(
            .sessionInvalidated,
            fields: [
                "reason": reason,
                "clear_phrase_context": clearPhraseContext ? "true" : "false",
                "session_epoch": String(inputSession.sessionEpoch),
                "mutation_seq": String(inputSession.mutationSeq)
            ]
        )
        clearTransliterationHint()
        cancelStandaloneOptionTap()
        clearPendingCorrectionTracking()

        if skipEventPosting {
            resetSession(reason: reason, clearPhraseContext: clearPhraseContext)
        } else if let snapshot = textContextService.snapshotFocusedText() {
            applySeed(
                textContextService.seedSession(from: snapshot),
                snapshot: snapshot,
                clearPhraseContext: clearPhraseContext,
                bumpSessionEpoch: true
            )
        } else {
            resetSession(reason: reason, clearPhraseContext: clearPhraseContext)
        }

        lastCommittedToken = nil
        Task { await engine.resetCycling() }
    }

    private func matchesAutoReplace(_ plan: CorrectionPlan) -> Bool {
        if case .autoReplace = plan {
            return true
        }
        return false
    }

    private func resetSession(reason: String, clearPhraseContext: Bool) {
        logger.debug("Reset session: \(reason, privacy: .public)")
        runtimeState = .dirtyNeedsResync
        trace.log(
            .sessionInvalidated,
            fields: [
                "reason": reason,
                "clear_phrase_context": clearPhraseContext ? "true" : "false",
                "session_epoch": String(inputSession.sessionEpoch),
                "mutation_seq": String(inputSession.mutationSeq)
            ]
        )
        inputSession.sessionEpoch &+= 1
        inputSession.mutationSeq &+= 1
        inputSession.typedToken = ""
        if clearPhraseContext {
            inputSession.phraseContext = ""
        }
        inputSession.isDirty = true
        inputSession.lastVerifiedSnapshot = nil
        inputSession.lastMutationAt = timeProvider.now
        inputSession.startedAt = .distantPast
        keyTimings.removeAll()
        lastKeyTime = nil
        lastCommittedToken = nil
        pendingLayoutSwitch = nil
    }

    private func recentCommittedTokenContext() -> CommittedTokenContext? {
        if let lastCommittedToken {
            return lastCommittedToken
        }

        let words = inputSession.phraseContext
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)

        guard let token = words.last, !token.isEmpty else {
            return nil
        }

        return CommittedTokenContext(token: token, separator: "")
    }

    private func preserveCommittedBoundaryIfNeeded(token: String, separator: String) {
        guard !inputSession.isDirty else { return }

        let normalized = splitBufferContent(token).token
        guard !normalized.isEmpty else { return }

        if lastCommittedToken?.token != normalized {
            updatePhraseBuffer(with: normalized)
        }

        lastCommittedToken = CommittedTokenContext(token: normalized, separator: separator)
        lastCommittedTransaction = CommittedTransaction(
            visibleText: normalized + separator,
            timestamp: timeProvider.now
        )
    }

    private func applySeed(
        _ seed: InputSessionSeed,
        snapshot: FocusedTextSnapshot,
        clearPhraseContext: Bool = false,
        bumpSessionEpoch: Bool = false
    ) {
        if bumpSessionEpoch {
            inputSession.sessionEpoch &+= 1
        }
        inputSession.mutationSeq &+= 1
        inputSession.typedToken = seed.typedToken
        inputSession.phraseContext = clearPhraseContext ? "" : seed.phraseContext
        inputSession.sourceApp = seed.sourceApp ?? ""
        inputSession.lastVerifiedSnapshot = snapshot
        inputSession.isDirty = false
        inputSession.lastMutationAt = timeProvider.now
        inputSession.startedAt = timeProvider.now
        keyTimings.removeAll()
        lastKeyTime = nil
    }

    private func bumpSessionMutation(at date: Date) {
        inputSession.mutationSeq &+= 1
        inputSession.lastMutationAt = date
        if inputSession.startedAt == .distantPast {
            inputSession.startedAt = date
        }
        inputSession.isDirty = false
    }

    private func expireStandaloneOptionTapIfNeeded() {
        guard let lastRelease = manualTriggerState.lastStandaloneReleaseAt else { return }
        if timeProvider.now.timeIntervalSince(lastRelease) > settings.manualTriggerDoubleTapWindow {
            manualTriggerState.lastStandaloneReleaseAt = nil
        }
    }

    private func cancelStandaloneOptionTap() {
        manualTriggerState.isPressed = false
        manualTriggerState.isStandaloneCandidate = false
        manualTriggerState.lastStandaloneReleaseAt = nil
    }

    package func splitBufferContent(_ content: String) -> (leading: String, token: String, trailing: String) {
        let chars = Array(content)
        var start = 0
        var end = chars.count

        while start < end {
            let char = chars[start]
            if isDelimiterLikeCharacter(char) {
                start += 1
            } else {
                break
            }
        }

        while end > start {
            let char = chars[end - 1]
            if isDelimiterLikeCharacter(char) {
                if LayoutMapper.shared.isAmbiguousBoundaryChar(char) {
                    break
                }
                end -= 1
            } else {
                break
            }
        }

        return (
            String(chars[0..<start]),
            String(chars[start..<end]),
            String(chars[end..<chars.count])
        )
    }

    private func isDelimiterLikeCharacter(_ ch: Character) -> Bool {
        ch.isWhitespace
            || ch.isNewline
            || ch == ","
            || ch == "."
            || ch == "!"
            || ch == "?"
            || ch == ";"
            || ch == ":"
            || ch == "\""
            || ch == "'"
            || ch == "("
            || ch == ")"
            || ch == "["
            || ch == "]"
            || ch == "{"
            || ch == "}"
            || ch == "-"
            || ch == "—"
    }

    private func isWordBoundaryTrigger(_ text: String) -> Bool {
        guard let char = text.first else { return false }
        return char.isWhitespace || char.isNewline
    }

    private func mapLayoutToLanguage(_ layoutId: String?) -> Language? {
        guard let id = layoutId?.lowercased() else { return nil }
        if id.contains("russian") || id.contains("ru") { return .russian }
        if id.contains("hebrew") || id.contains("he") { return .hebrew }
        if id.contains("us") || id.contains("en") || id.contains("abc") || id.contains("british") { return .english }
        return nil
    }

    private func setTransliterationHint(_ suggestion: TransliterationSuggestion?, separator: String, commitRevision: UInt64) {
        if let suggestion {
            pendingTransliterationHint = PendingTransliterationHint(
                suggestion: suggestion,
                separator: separator,
                commitRevision: commitRevision,
                createdAt: timeProvider.now
            )
        } else {
            pendingTransliterationHint = nil
        }
        postTransliterationHint(suggestion)
    }

    private func clearTransliterationHint() {
        guard pendingTransliterationHint != nil else { return }
        pendingTransliterationHint = nil
        postTransliterationHint(nil)
    }

    private func postTransliterationHint(_ suggestion: TransliterationSuggestion?) {
        let userInfo: [AnyHashable: Any]? = suggestion.map {
            let token = splitBufferContent($0.replacement).token
            return [
                "id": $0.id.uuidString,
                "text": token,
                "language": $0.targetLanguage.rawValue
            ]
        }
        NotificationCenter.default.post(name: Notification.Name("TransliterationHint"), object: nil, userInfo: userInfo)
    }

    private func applyTransliterationHint(id: UUID) async {
        if !skipSecureInputCheck && IsSecureEventInputEnabled() {
            clearTransliterationHint()
            return
        }

        guard let pending = pendingTransliterationHint,
              pending.suggestion.id == id,
              pending.commitRevision == inputSession.mutationSeq,
              timeProvider.now.timeIntervalSince(pending.createdAt) < 8.0 else {
            clearTransliterationHint()
            return
        }

        let expectedOriginal = pending.suggestion.original + pending.separator
        let focusedCapabilities = textContextService.resolveFocusedElementCapabilities()
        let hostProfile = currentHostRuntimeProfile(
            bundleId: focusedCapabilities?.bundleId ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            capabilities: focusedCapabilities?.capabilities
        )
        let verified = await verificationContext(
            forExpectedSuffix: expectedOriginal,
            preserveSessionOnUnavailable: true
        )
        guard verified != nil || canUseManualReplayFallback(for: expectedOriginal, hostRuntimeProfile: hostProfile) else {
            clearTransliterationHint()
            return
        }

        let replacement = pending.suggestion.replacement + pending.separator
        let applied = await performReplacement(
            intent: .transliterationHint,
            expectedOriginal: expectedOriginal,
            replacement: replacement,
            verifiedContext: verified,
            allowClipboardFallback: false,
            allowEventReplayFallback: false,
            currentVisibleText: expectedOriginal,
            hostRuntimeProfile: hostProfile,
            proxy: nil
        )
        guard let applied else {
            clearTransliterationHint()
            return
        }

        let oldWord = splitBufferContent(pending.suggestion.original).token
        let newWord = splitBufferContent(pending.suggestion.replacement).token
        if !oldWord.isEmpty, !newWord.isEmpty {
            replaceLastPhraseBufferWord(from: oldWord, to: newWord)
        }

        lastCommittedToken = CommittedTokenContext(token: pending.suggestion.replacement, separator: pending.separator)
        if let transaction = await buildManualTransaction(
            original: pending.suggestion.original,
            replacement: pending.suggestion.replacement,
            intent: .transliterationHint,
            bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ) {
            await commitReplacementTransaction(transaction, editResult: applied, verifiedContext: verified)
        }
        clearTransliterationHint()
    }

    private func replaceLastPhraseBufferWord(from old: String, to new: String) {
        let words = inputSession.phraseContext.split(separator: " ").map(String.init)
        guard let last = words.last, last == old else { return }
        let updated = words.dropLast() + [new]
        inputSession.phraseContext = updated.joined(separator: " ")
    }

    private func updatePhraseBuffer(with word: String) {
        guard !word.isEmpty else { return }

        if inputSession.phraseContext.isEmpty {
            inputSession.phraseContext = word
        } else {
            inputSession.phraseContext += " " + word
        }

        if inputSession.phraseContext.count > 100 {
            inputSession.phraseContext = String(inputSession.phraseContext.suffix(100))
            if let firstSpace = inputSession.phraseContext.firstIndex(of: " ") {
                inputSession.phraseContext = String(inputSession.phraseContext[inputSession.phraseContext.index(after: firstSpace)...])
            }
        }
    }

    private func updateObservedAXApp() {
        stopAXObserver()

        guard !skipEventPosting,
              let app = NSWorkspace.shared.frontmostApplication else { return }

        observedAppPID = app.processIdentifier

        var observer: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, Self.axNotificationCallback, &observer)
        guard result == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let notifications = [
            kAXFocusedUIElementChangedNotification,
            kAXSelectedTextChangedNotification,
            kAXValueChangedNotification
        ]

        for notification in notifications {
            AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }

        axObserver = observer
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func stopAXObserver() {
        if let observer = axObserver {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        axObserver = nil
        observedAppPID = nil
    }

    private func clearPendingCorrectionTracking() {
        lastCorrectionTrackingId = nil
        backspaceReportedForId = nil
        lastCorrectionTime = .distantPast
    }

    private func handleAXNotification(_ notification: String) {
        guard activeSyntheticTransactions == 0 else { return }

        switch notification {
        case String(kAXFocusedUIElementChangedNotification):
            handleExternalInvalidation(reason: "AX Focused UI Element Changed", clearPhraseContext: false)
        case String(kAXSelectedTextChangedNotification), String(kAXValueChangedNotification):
            if timeProvider.now.timeIntervalSince(inputSession.lastMutationAt) < 0.12 || !inputSession.typedToken.isEmpty {
                return
            }
            guard let snapshot = textContextService.snapshotFocusedText() else { return }
            applySeed(textContextService.seedSession(from: snapshot), snapshot: snapshot)
        default:
            handleExternalInvalidation(reason: "AX \(notification)", clearPhraseContext: false)
        }
    }
}

private extension CorrectionPlan {
    var traceValue: String {
        switch self {
        case .none:
            return "none"
        case .hint:
            return "hint"
        case .manualCycle:
            return "manual_cycle"
        case .autoReplace:
            return "auto_replace"
        }
    }
}

extension CGEvent {
    var keyboardEventCharacters: String? {
        guard let nsEvent = NSEvent(cgEvent: self) else { return nil }
        return nsEvent.characters
    }
}
