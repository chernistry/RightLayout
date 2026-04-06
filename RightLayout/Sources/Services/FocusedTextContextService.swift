import Foundation
import AppKit
import ApplicationServices

package enum FocusedTextSnapshotSource: String, Sendable {
    case accessibility
    case accessibilityPartial
    case synthetic
}

package struct FocusedElementCapabilities: @unchecked Sendable {
    package let element: AXUIElement
    package let bundleId: String?
    package let pid: pid_t
    package let capabilities: AppEditCapabilities
}

package struct FocusedTextSnapshot: @unchecked Sendable {
    package let element: AXUIElement
    package let bundleId: String?
    package let pid: pid_t
    package let fullText: String
    package let selectedRange: NSRange
    package let selectedText: String
    package let caretLocation: Int
    package let supportsAXSelectedTextWrite: Bool
    package let supportsAXValueWrite: Bool
    package let supportsAXRangeWrite: Bool
    package let capabilities: AppEditCapabilities
    package let source: FocusedTextSnapshotSource
    package let revision: UInt64
}

package struct VerifiedEditContext: @unchecked Sendable {
    package let snapshot: FocusedTextSnapshot
    package let verifiedRange: NSRange
    package let verifiedText: String
}

package struct InputSessionSeed: Sendable {
    package let typedToken: String
    package let phraseContext: String
    package let sourceApp: String?
    package let snapshotRevision: UInt64
}

package enum SessionSyncResult: @unchecked Sendable {
    case verified(VerifiedEditContext)
    case mismatch(snapshot: FocusedTextSnapshot?, seed: InputSessionSeed?)
    case unavailable
}

@MainActor
package final class FocusedTextContextService {
    package static let shared = FocusedTextContextService()

    private var revisionCounter: UInt64 = 0

    package init() {}

    package func resolveFocusedElementCapabilities() -> FocusedElementCapabilities? {
        guard let element = focusedElement() else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let capabilities = buildCapabilities(on: element, pid: pid)

        return FocusedElementCapabilities(
            element: element,
            bundleId: bundleId,
            pid: pid,
            capabilities: capabilities
        )
    }

    package func snapshotFocusedText() -> FocusedTextSnapshot? {
        guard let focused = resolveFocusedElementCapabilities() else { return nil }
        guard focused.capabilities.supportsFullTextRead,
              let fullText = stringAttribute(kAXValueAttribute, on: focused.element),
              let selectedRange = rangeAttribute(kAXSelectedTextRangeAttribute, on: focused.element) else {
            return nil
        }

        revisionCounter &+= 1

        let selectedText = stringAttribute(kAXSelectedTextAttribute, on: focused.element)
            ?? substring(in: fullText, range: selectedRange)
            ?? ""

        return FocusedTextSnapshot(
            element: focused.element,
            bundleId: focused.bundleId,
            pid: focused.pid,
            fullText: fullText,
            selectedRange: selectedRange,
            selectedText: selectedText,
            caretLocation: selectedRange.location,
            supportsAXSelectedTextWrite: focused.capabilities.supportsSelectedTextWrite,
            supportsAXValueWrite: focused.capabilities.supportsValueWrite,
            supportsAXRangeWrite: focused.capabilities.supportsSelectedRangeWrite,
            capabilities: focused.capabilities,
            source: .accessibility,
            revision: revisionCounter
        )
    }

    package func snapshotSelectionForManualAction() -> FocusedTextSnapshot? {
        if let snapshot = snapshotFocusedText(),
           snapshot.selectedRange.length > 0 || !snapshot.selectedText.isEmpty {
            return snapshot
        }

        guard let focused = resolveFocusedElementCapabilities() else { return nil }
        guard focused.capabilities.capabilityClass != .blind,
              focused.capabilities.capabilityClass != .secure,
              let selectedRange = rangeAttribute(kAXSelectedTextRangeAttribute, on: focused.element),
              let selectedText = stringAttribute(kAXSelectedTextAttribute, on: focused.element),
              selectedRange.length > 0 || !selectedText.isEmpty else {
            return nil
        }

        revisionCounter &+= 1

        return FocusedTextSnapshot(
            element: focused.element,
            bundleId: focused.bundleId,
            pid: focused.pid,
            fullText: focused.capabilities.supportsFullTextRead ? (stringAttribute(kAXValueAttribute, on: focused.element) ?? selectedText) : selectedText,
            selectedRange: selectedRange,
            selectedText: selectedText,
            caretLocation: selectedRange.location + selectedRange.length,
            supportsAXSelectedTextWrite: focused.capabilities.supportsSelectedTextWrite,
            supportsAXValueWrite: focused.capabilities.supportsValueWrite,
            supportsAXRangeWrite: focused.capabilities.supportsSelectedRangeWrite,
            capabilities: focused.capabilities,
            source: .accessibilityPartial,
            revision: revisionCounter
        )
    }

    package func verifyTrailingToken(localToken: String, revision: UInt64) -> SessionSyncResult {
        verifyExpectedSuffix(localToken, revision: revision)
    }

    package func verifyCommittedBoundary(token: String, separator: String, revision: UInt64) -> SessionSyncResult {
        guard !token.isEmpty else { return .unavailable }
        guard let snapshot = snapshotFocusedText() else { return .unavailable }
        guard snapshot.selectedRange.length == 0 else {
            return .mismatch(snapshot: snapshot, seed: seedSession(from: snapshot))
        }

        let beforeCaret = prefix(in: snapshot.fullText, utf16Length: snapshot.selectedRange.location)
        let committedText = token + separator

        if beforeCaret.hasSuffix(committedText) {
            let location = beforeCaret.utf16.count - committedText.utf16.count
            let range = NSRange(location: location, length: committedText.utf16.count)
            return .verified(
                VerifiedEditContext(
                    snapshot: snapshot,
                    verifiedRange: range,
                    verifiedText: committedText
                )
            )
        }

        if beforeCaret.hasSuffix(token) {
            let location = beforeCaret.utf16.count - token.utf16.count
            let range = NSRange(location: location, length: token.utf16.count)
            return .verified(
                VerifiedEditContext(
                    snapshot: snapshot,
                    verifiedRange: range,
                    verifiedText: token
                )
            )
        }

        return .mismatch(snapshot: snapshot, seed: seedSession(from: snapshot))
    }

    package func verifyExpectedSuffix(_ expectedText: String, revision: UInt64) -> SessionSyncResult {
        guard !expectedText.isEmpty else { return .unavailable }
        guard let snapshot = snapshotFocusedText() else { return .unavailable }
        guard snapshot.selectedRange.length == 0 else {
            return .mismatch(snapshot: snapshot, seed: seedSession(from: snapshot))
        }

        let beforeCaret = prefix(in: snapshot.fullText, utf16Length: snapshot.selectedRange.location)
        guard beforeCaret.hasSuffix(expectedText) else {
            return .mismatch(snapshot: snapshot, seed: seedSession(from: snapshot))
        }

        let location = beforeCaret.utf16.count - expectedText.utf16.count
        let range = NSRange(location: location, length: expectedText.utf16.count)
        return .verified(
            VerifiedEditContext(
                snapshot: snapshot,
                verifiedRange: range,
                verifiedText: expectedText
            )
        )
    }

    package func seedSession(from snapshot: FocusedTextSnapshot) -> InputSessionSeed {
        let beforeCaret = prefix(in: snapshot.fullText, utf16Length: snapshot.selectedRange.location)
        let typedToken: String
        if snapshot.selectedRange.length == 0 {
            typedToken = trailingToken(in: beforeCaret)
        } else {
            typedToken = ""
        }

        let phraseContext = trailingPhraseContext(in: beforeCaret)
        return InputSessionSeed(
            typedToken: typedToken,
            phraseContext: phraseContext,
            sourceApp: snapshot.bundleId,
            snapshotRevision: snapshot.revision
        )
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success else { return nil }
        return focused as! AXUIElement?
    }

    private func stringAttribute(_ name: String, on element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func rangeAttribute(_ name: String, on element: AXUIElement) -> NSRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        guard range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private func isAttributeReadable(_ name: String, on element: AXUIElement) -> Bool {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
    }

    private func buildCapabilities(on element: AXUIElement, pid: pid_t) -> AppEditCapabilities {
        let supportsSelectedTextWrite = isAttributeSettable(kAXSelectedTextAttribute, on: element)
        let supportsSelectedRangeWrite = isAttributeSettable(kAXSelectedTextRangeAttribute, on: element)
        let supportsValueWrite = isAttributeSettable(kAXValueAttribute, on: element)
        let supportsSelectionRead = isAttributeReadable(kAXSelectedTextAttribute, on: element)
        let supportsRangeRead = isAttributeReadable(kAXSelectedTextRangeAttribute, on: element)
        let supportsFullTextRead = isAttributeReadable(kAXValueAttribute, on: element)

        let role = stringAttribute(kAXRoleAttribute, on: element)?.lowercased()
        let subrole = stringAttribute(kAXSubroleAttribute, on: element)?.lowercased()
        let secureRole = role?.contains("secure") == true || subrole?.contains("secure") == true

        let capabilityClass: CapabilityClass
        if secureRole {
            capabilityClass = .secure
        } else if supportsFullTextRead && supportsRangeRead {
            capabilityClass = .axFull
        } else if supportsSelectionRead || supportsSelectedTextWrite || supportsSelectedRangeWrite || supportsValueWrite || supportsRangeRead {
            capabilityClass = .axPartial
        } else {
            capabilityClass = .blind
        }

        return AppEditCapabilities(
            supportsSelectedTextWrite: supportsSelectedTextWrite,
            supportsSelectedRangeWrite: supportsSelectedRangeWrite,
            supportsValueWrite: supportsValueWrite,
            supportsSelectionRead: supportsSelectionRead,
            supportsFullTextRead: supportsFullTextRead,
            isSecureOrReadBlind: capabilityClass == .secure || capabilityClass == .blind,
            capabilityClass: capabilityClass,
            elementFingerprint: elementFingerprint(element: element, pid: pid, role: role, subrole: subrole)
        )
    }

    private func elementFingerprint(element: AXUIElement, pid: pid_t, role: String?, subrole: String?) -> String {
        "\(pid):\(CFHash(element)):\(role ?? "unknown"):\(subrole ?? "unknown")"
    }

    private func prefix(in text: String, utf16Length: Int) -> String {
        let nsText = text as NSString
        guard utf16Length >= 0, utf16Length <= nsText.length else {
            return text
        }
        return nsText.substring(to: utf16Length)
    }

    private func substring(in text: String, range: NSRange) -> String? {
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return nil }
        return nsText.substring(with: range)
    }

    private func trailingToken(in text: String) -> String {
        let scalars = Array(text)
        guard !scalars.isEmpty else { return "" }

        var start = scalars.endIndex
        while start > scalars.startIndex {
            let previous = scalars.index(before: start)
            let char = scalars[previous]
            if char.isWhitespace || char.isNewline {
                break
            }
            start = previous
        }
        return String(scalars[start..<scalars.endIndex])
    }

    private func trailingPhraseContext(in text: String) -> String {
        let suffix = String(text.suffix(100))
        let words = suffix.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).suffix(5)
        return words.joined(separator: " ")
    }
}
