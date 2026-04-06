import Foundation
import ApplicationServices
import os.log

@MainActor
public final class SandboxPermissionManager {
    public static let shared = SandboxPermissionManager()
    private let logger = Logger(subsystem: "com.rightlayout.app", category: "SandboxPermissionManager")
    
    private init() {}
    
    /// Checks if Accessibility permission is granted.
    /// This is the only permission RightLayout needs to function.
    public func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if trusted {
            logger.info("✅ checkAccessibilityPermission: Accessibility permission granted.")
        } else {
            logger.warning("⚠️ checkAccessibilityPermission: Accessibility permission not granted.")
        }
        return trusted
    }
    
    /// Prompts the user to grant Accessibility permission via system dialog.
    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
