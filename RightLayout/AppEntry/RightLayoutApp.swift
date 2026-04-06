import SwiftUI
import AppKit
import os
import UserNotifications
import Carbon
import RightLayout

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.rightlayout", category: "Application")
}

@main
struct RightLayoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = SettingsManager.shared
    
    init() {
        // Initialize settings
        _ = SettingsManager.shared
        
        // Ticket 43: Apply decay on launch to handle long-term forgetting
        Task {
            // Apply delay to avoid slowing down startup
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await PersonalizationStore.shared.applyDecay()
        }
        
        // Initialize logging
        _ = DecisionLogger.shared
        _ = CorrectionLogger.shared
    }

    var body: some Scene {
        MenuBarExtra("RightLayout", systemImage: "keyboard") {
            MenuBarView()
                .environment(\.locale, settings.appLanguage.locale ?? .current)
                .id(settings.appLanguage) // Force recreation on language change
        }
        .menuBarExtraStyle(.menu)
        
        // Control-center settings window
        Window("RightLayout Settings", id: "settings") {
            SettingsView()
                .environment(\.locale, settings.appLanguage.locale ?? .current)
                .id(settings.appLanguage) // Force recreation on language change
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
    }
}

// MARK: - Window Manager

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    
    func openSettings() {
        if let url = URL(string: "rightlayout://settings") {
            NSWorkspace.shared.open(url)
        }
        // Fallback: use Environment openWindow
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue == "settings" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
    
    func openHistory() {
        openSettings()
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: EventMonitor?
    private var correctionEngine: CorrectionEngine?
    private var updateCheckTimer: Timer?
    private var permissionWindowController: NSWindowController?
    private var proactiveHintObserver: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce Single Instance
        // If running as a bundled app, ensure only one instance exists.
        if let bundleId = Bundle.main.bundleIdentifier {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if runningApps.count > 1 {
                // If there's another instance, focus it and terminate this one
                // But if we are CLI, just terminate without UI focus potentially
                if !CommandLine.arguments.contains("--cli") {
                    for app in runningApps where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                        app.activate(options: .activateIgnoringOtherApps)
                        break
                    }
                }
                Logger.app.warning("Another instance detected. Terminating.")
                NSApp.terminate(nil)
                return
            }
        }
        
        Logger.app.info("RightLayout application did finish launching")
        NSApp.setActivationPolicy(.accessory)
        
        // Ticket 64/E2E: CLI/REPL Mode for headless testing
        if CommandLine.arguments.contains("--cli") || CommandLine.arguments.contains("--repl") {
            let args = CommandLine.arguments
            let verbose = args.contains("--verbose")
            Task {
                CLI.run(verbose: verbose)
            }
        }
        
        // Check for system autocorrection conflict
        AutocorrectionChecker.showWarningIfNeeded()
        
        let settings = SettingsManager.shared
        let engine = CorrectionEngine(settings: settings)
        self.correctionEngine = engine
        
        let monitor = EventMonitor(engine: engine)
        self.eventMonitor = monitor
        
        // Check permissions
        // Check permissions
        let skipPermissionCheck = ProcessInfo.processInfo.environment["RightLayout_SKIP_PERMISSION_CHECK"] != nil
        if !skipPermissionCheck && !SandboxPermissionManager.shared.checkAccessibilityPermission() {
            Logger.app.warning("Accessibility permission missing on launch")
            openPermissionWindow()
        }
        
        Task {
            Logger.app.info("Starting EventMonitor from AppDelegate")
            await monitor.start()
        }
        
        // Setup update checking
        setupUpdateChecking()

        // Ticket 53: Proactive layout hints (hint-first).
        setupProactiveHints()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        eventMonitor?.stop()
        updateCheckTimer?.invalidate()
        permissionWindowController?.close()
        if let observer = proactiveHintObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    private func openPermissionWindow() {
        let view = PermissionRequestView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "RightLayout Permissions"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.center()
        window.isReleasedWhenClosed = false
        
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.permissionWindowController = controller
    }

    // MARK: - Proactive Hints

    private func setupProactiveHints() {
        proactiveHintObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard SettingsManager.shared.proactiveHintsEnabled else {
                    self.postProactiveHint(nil)
                    return
                }

                // Never hint in Secure Input contexts.
                guard !IsSecureEventInputEnabled() else {
                    self.postProactiveHint(nil)
                    return
                }

                guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
                    self.postProactiveHint(nil)
                    return
                }

                let suggestion = await LayoutHintService.shared.suggestLayout(for: bundleId)
                self.postProactiveHint(suggestion)
            }
        }
    }

    private func postProactiveHint(_ language: Language?) {
        NotificationCenter.default.post(
            name: Notification.Name("ProactiveLayoutHint"),
            object: nil,
            userInfo: language.map { ["language": $0.rawValue] }
        )
    }
    
    // MARK: - Update Checking
    
    private func setupUpdateChecking() {
        // Request notification permissions
        requestNotificationPermissions()
        
        // Check for updates on launch if enabled and last check was >24h ago
        if SettingsManager.shared.checkForUpdatesAutomatically {
            let lastCheck = SettingsManager.shared.lastUpdateCheckDate ?? .distantPast
            let hoursSinceLastCheck = Date().timeIntervalSince(lastCheck) / 3600
            
            if hoursSinceLastCheck >= 24 {
                Logger.app.info("Checking for updates on launch (last check: \(hoursSinceLastCheck, privacy: .public) hours ago)")
                Task {
                    await performUpdateCheck(showNotification: true)
                }
            }
        }
        
        // Setup periodic 24-hour timer
        setupPeriodicUpdateCheck()
    }
    
    private func setupPeriodicUpdateCheck() {
        // Check every 24 hours while running
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard SettingsManager.shared.checkForUpdatesAutomatically else { return }
                Logger.app.info("Performing periodic update check")
                await self?.performUpdateCheck(showNotification: true)
            }
        }
    }
    
    private func performUpdateCheck(showNotification: Bool) async {
        let updateState = UpdateState.shared
        await updateState.checkForUpdate()
        
        // Show macOS notification if update available
        if showNotification, case .updateAvailable(let release) = updateState.lastResult {
            showUpdateNotification(version: release.version)
        }
    }
    
    /// Check if running as a proper app bundle (not via swift run)
    private var isRunningAsBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }
    
    private func requestNotificationPermissions() {
        // UNUserNotificationCenter requires a proper app bundle
        guard isRunningAsBundle else {
            Logger.app.info("Skipping notification permissions - not running as app bundle")
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Logger.app.error("Failed to request notification permissions: \(error.localizedDescription)")
            } else {
                Logger.app.info("Notification permissions granted: \(granted)")
            }
        }
    }
    
    private func showUpdateNotification(version: String) {
        // UNUserNotificationCenter requires a proper app bundle
        guard isRunningAsBundle else {
            Logger.app.info("Update available: v\(version) - notification skipped (not running as app bundle)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "RightLayout Update Available"
        content.body = "Version \(version) is ready to download"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "rightlayout.update.available",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.app.error("Failed to show update notification: \(error.localizedDescription)")
            }
        }
    }
}
