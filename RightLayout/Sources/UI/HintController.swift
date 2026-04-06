import Cocoa
import SwiftUI

/// Controller for displaying transient correction hints
@MainActor
final class HintController {
    static let shared = HintController()
    
    private var window: NSWindow?
    private var timer: Timer?
    
    // Config
    private let displayDuration: TimeInterval = 2.5
    
    private init() {}
    
    func show(text: String = "Press ⌃CmdSpace to fix") {
        guard SettingsManager.shared.proactiveHintsEnabled else { return }
        
        cancel() // Cancel previous
        
        // Create window if needed
        if window == nil {
            setupWindow()
        }
        
        guard let win = window else { return }
        
        // Update content
        let view = NSHostingView(rootView: HintView(text: text))
        // Resize window to fit content?
        // Basic fixed size for now, or use fittingSize
        win.contentView = view
        let size = view.fittingSize
        win.setContentSize(size)
        
        // Position near cursor
        let mouse = NSEvent.mouseLocation
        // Adjust to be slightly above/right of cursor so it doesn't block text
        // Note: Cocoa coords are bottom-left.
        // We want it slightly above the cursor.
        let origin = CGPoint(x: mouse.x + 20, y: mouse.y + 20)
        
        win.setFrameOrigin(origin)
        
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            win.animator().alphaValue = 1.0
        }
        
        // Auto-hide
        timer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }
    
    func hide() {
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            win.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let win = self.window else { return }
                if win.alphaValue == 0 {
                    win.orderOut(nil)
                }
            }
        }
    }
    
    private func cancel() {
        timer?.invalidate()
        timer = nil
    }
    
    private func setupWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = true // Pass through clicks!
        self.window = win
    }
}

struct HintView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Typography.body())
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.surfaceRaised, in: Capsule())
            .overlay(Capsule().stroke(Theme.Color.borderStrong, lineWidth: 1))
            .padding(10) // Outer padding for shadow/glow
    }
}
