import AppKit
import SwiftUI

/// Ticket 69: Opens DecisionLogView in a floating utility window
@MainActor
final class DecisionLogWindowController {
    private static var windowController: NSWindowController?

    static func show() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: DecisionLogView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Decision Log"
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DecisionLogWindow")

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        windowController = controller
    }
}
