import Foundation
import ServiceManagement

/// Helper for managing Launch at Login via SMAppService (macOS 13+)
enum LaunchAtLogin {
    
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("LaunchAtLogin error: \(error)")
                }
            }
        }
    }
}
