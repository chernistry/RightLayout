import CoreGraphics

package enum SyntheticEventMarker {
    package static let value: Int64 = 0x524C
}

package protocol EventPosting: AnyObject {
    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, proxy: CGEventTapProxy?)
    func postUnicodeString(_ string: String, proxy: CGEventTapProxy?)
    func postShortcut(keyCode: CGKeyCode, flags: CGEventFlags, proxy: CGEventTapProxy?)
}

package final class CGEventPoster: @unchecked Sendable, EventPosting {
    private let source = CGEventSource(stateID: .privateState)

    package init() {}

    package func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags = [], proxy: CGEventTapProxy?) {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = flags
        keyUp?.flags = flags

        post(keyDown, proxy: proxy)
        post(keyUp, proxy: proxy)
    }

    package func postUnicodeString(_ string: String, proxy: CGEventTapProxy?) {
        for scalar in string.utf16 {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { continue }
            var code = UniChar(scalar)
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
            post(keyDown, proxy: proxy)

            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
            post(keyUp, proxy: proxy)
        }
    }

    package func postShortcut(keyCode: CGKeyCode, flags: CGEventFlags, proxy: CGEventTapProxy?) {
        postKeyEvent(keyCode: keyCode, flags: flags, proxy: proxy)
    }

    private func post(_ event: CGEvent?, proxy: CGEventTapProxy?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.value)
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }
}
