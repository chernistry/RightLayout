import SwiftUI

public struct PermissionRequestView: View {
    public init() {}

    @State private var isChecking = false
    @State private var isGranted = SandboxPermissionManager.shared.checkAccessibilityPermission()

    private let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                Image(systemName: isGranted ? "checkmark.shield" : "lock.open.display")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(isGranted ? Theme.Color.success : Theme.Color.accent)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(UIStrings.text(isGranted ? "Accessibility granted" : "Accessibility permission required"))
                        .font(Theme.Typography.heading())
                        .foregroundStyle(Theme.Color.textPrimary)

                    Text(
                        UIStrings.text(
                            isGranted
                            ? "RightLayout can now monitor supported text fields and apply verified corrections."
                            : "RightLayout cannot monitor keyboard input or correct text until Accessibility access is granted in System Settings."
                        )
                    )
                    .font(Theme.Typography.body())
                    .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            WorkbenchSection(title: "Why this is needed", detail: "This is the only permission RightLayout needs to observe text entry and correct the visible field.") {
                Text(UIStrings.text("Without Accessibility access, automatic correction, manual last-word correction, and diagnostics for live typing remain blocked."))
                    .font(Theme.Typography.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            WorkbenchSection(title: "What to do", detail: "Grant access once, then return here and confirm the status.") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(UIStrings.text("1. Open System Settings → Privacy & Security → Accessibility"))
                    Text(UIStrings.text("2. Enable the switch next to RightLayout"))
                    Text(UIStrings.text("3. If macOS asks, quit and reopen the app"))
                }
                .font(Theme.Typography.body())
                .foregroundStyle(Theme.Color.textSecondary)

                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        SandboxPermissionManager.shared.requestAccessibilityPermission()
                        if let privacyURL {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                NSWorkspace.shared.open(privacyURL)
                            }
                        }
                        startPolling()
                    } label: {
                        Label(UIStrings.text("Open Accessibility Settings"), systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .primaryActionButton()

                    Button {
                        checkPermission()
                    } label: {
                        Label(UIStrings.text("Check Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .secondaryActionButton()
                    .disabled(isChecking)
                }
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 480)
        .background(Theme.Color.pageBackgroundPrimary)
    }

    private func checkPermission() {
        isChecking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isGranted = SandboxPermissionManager.shared.checkAccessibilityPermission()
            isChecking = false
        }
    }

    private func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let granted = MainActor.assumeIsolated {
                SandboxPermissionManager.shared.checkAccessibilityPermission()
            }
            if granted {
                timer.invalidate()
                Task { @MainActor in
                    isGranted = true
                }
            }
        }
    }
}

#Preview {
    PermissionRequestView()
}
