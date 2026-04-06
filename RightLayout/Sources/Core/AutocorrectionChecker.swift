import AppKit

/// Checks for system autocorrection that may conflict with RightLayout
public enum AutocorrectionChecker {
    
    /// Check if global spelling correction is enabled
    static func isSystemAutocorrectionEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "NSAutomaticSpellingCorrectionEnabled") as? Bool ?? false
    }
    
    /// Show warning alert if autocorrection is enabled (once per install)
    public static func showWarningIfNeeded() {
        guard isSystemAutocorrectionEnabled() else { return }
        guard !UserDefaults.standard.bool(forKey: "RightLayout_AutocorrectionWarningShown") else { return }
        
        UserDefaults.standard.set(true, forKey: "RightLayout_AutocorrectionWarningShown")
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "System Autocorrection Detected"
            alert.informativeText = """
            macOS "Correct spelling automatically" is enabled and may interfere with RightLayout.
            
            To disable: System Settings → Keyboard → Text Input → Edit → Uncheck "Correct spelling automatically"
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Ignore")
            
            if alert.runModal() == .alertFirstButtonReturn {
                openKeyboardSettings()
            }
        }
    }
    
    /// Open System Settings → Keyboard
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard") {
            NSWorkspace.shared.open(url)
        }
    }
}
