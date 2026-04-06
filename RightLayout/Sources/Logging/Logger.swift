import Foundation
import os.log

extension Logger {
    static let app = Logger(subsystem: "com.chernistry.rightlayout", category: "app")
    static let engine = Logger(subsystem: "com.chernistry.rightlayout", category: "engine")
    static let detection = Logger(subsystem: "com.chernistry.rightlayout", category: "detection")
    static let events = Logger(subsystem: "com.chernistry.rightlayout", category: "events")
    static let inputSource = Logger(subsystem: "com.chernistry.rightlayout", category: "inputSource")
    static let hotkey = Logger(subsystem: "com.chernistry.rightlayout", category: "hotkey")
    static let profile = Logger(subsystem: "com.chernistry.rightlayout", category: "profile")
}
