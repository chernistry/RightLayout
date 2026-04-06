import AppKit
import CoreGraphics

@MainActor
final class TestHostAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?
    private lazy var valueURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".rightlayout")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("testhost_value.txt")
    }()
    private var focusTimer: Timer?
    private var localKeyMonitor: Any?
    private var buffer = ""
    private var selectionAll = false
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private var pendingSyntheticUndoSnapshot: String?

    private struct KeySnapshot: Sendable {
        let keyCode: Int
        let modifierFlags: NSEvent.ModifierFlags
        let characters: String?
        let isSynthetic: Bool
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RightLayout Test Host"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.setAccessibilityIdentifier("rightlayout_test_text")
        textView.string = ""
        scrollView.documentView = textView

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.window = window
        self.textView = textView

        buffer = ""
        selectionAll = false
        persistBuffer()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)

        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(enforceFocus), userInfo: nil, repeats: true)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let marker = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
            let isSynthetic = marker == 0x524C // "RL"
            let snapshot = KeySnapshot(
                keyCode: Int(event.keyCode),
                modifierFlags: event.modifierFlags,
                characters: event.characters,
                isSynthetic: isSynthetic
            )
            DispatchQueue.main.async { [weak self] in
                self?.handleKeyDown(snapshot)
            }
            return nil
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let window, let textView {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
        }
    }

    @objc private func enforceFocus() {
        guard NSApp.isActive, let window, let textView else { return }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    private func finalizeSyntheticUndoIfNeeded() {
        guard let snapshot = pendingSyntheticUndoSnapshot else { return }
        pendingSyntheticUndoSnapshot = nil
        pushUndoSnapshot(snapshot)
    }

    private func pushUndoSnapshot(_ snapshot: String) {
        undoStack.append(snapshot)
        if undoStack.count > 250 {
            undoStack.removeFirst(undoStack.count - 250)
        }
        redoStack.removeAll(keepingCapacity: true)
    }

    private func applyUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(buffer)
        buffer = previous
        selectionAll = false
        persistBuffer()
    }

    private func applyRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(buffer)
        buffer = next
        selectionAll = false
        persistBuffer()
    }

    private func handleKeyDown(_ event: KeySnapshot) {
        let isCommand = event.modifierFlags.contains(.command)
        let isShift = event.modifierFlags.contains(.shift)
        let keyCode = event.keyCode
        let isSynthetic = event.isSynthetic

        if !isSynthetic {
            finalizeSyntheticUndoIfNeeded()
        }

        // Cmd+A → select all
        if isCommand, keyCode == 0 {
            selectionAll = true
            return
        }

        // Cmd+Z → undo; Cmd+Shift+Z → redo
        if isCommand, keyCode == 6 {
            if isShift {
                applyRedo()
            } else {
                applyUndo()
            }
            return
        }

        // Cmd+V → paste
        if isCommand, keyCode == 9 {
            let paste = NSPasteboard.general.string(forType: .string) ?? ""
            pushUndoSnapshot(buffer)
            insertText(paste)
            return
        }

        // Ignore other command shortcuts.
        if isCommand {
            return
        }

        // Delete / Backspace
        if keyCode == 51 {
            if isSynthetic {
                if pendingSyntheticUndoSnapshot == nil {
                    pendingSyntheticUndoSnapshot = buffer
                }
            } else {
                pushUndoSnapshot(buffer)
            }
            if selectionAll {
                buffer.removeAll(keepingCapacity: true)
                selectionAll = false
            } else if !buffer.isEmpty {
                buffer.removeLast()
            }
            persistBuffer()
            return
        }

        // Esc (used by E2E runner to end cycling/commit learning) — ignore.
        if keyCode == 53 {
            return
        }

        guard let chars = event.characters, !chars.isEmpty else { return }

        // Normalize CR to LF.
        let text = chars == "\r" ? "\n" : chars
        if isSynthetic {
            if pendingSyntheticUndoSnapshot == nil {
                pendingSyntheticUndoSnapshot = buffer
            }
        } else {
            pushUndoSnapshot(buffer)
        }
        insertText(text)
    }

    private func insertText(_ text: String) {
        if selectionAll {
            buffer = text
            selectionAll = false
        } else {
            buffer.append(contentsOf: text)
        }
        persistBuffer()
    }

    private func persistBuffer() {
        let data = buffer.data(using: .utf8) ?? Data()
        try? data.write(to: valueURL, options: .atomic)
        textView?.string = buffer
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

@main
struct RightLayoutTestHostMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = TestHostAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
