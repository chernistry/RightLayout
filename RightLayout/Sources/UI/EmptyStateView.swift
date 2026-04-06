import SwiftUI

struct EmptyStateView: View {
    struct Action {
        enum Style {
            case primary
            case secondary
        }

        let title: String
        let systemImage: String?
        let style: Style
        let action: () -> Void
    }

    let title: String
    let systemImage: String
    var message: String? = nil
    var primaryAction: Action? = nil
    var secondaryAction: Action? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.Color.textMeta)

            VStack(spacing: Theme.Spacing.sm) {
                Text(UIStrings.text(title))
                    .font(Theme.Typography.heading())
                    .foregroundStyle(Theme.Color.textPrimary)

                if let message, !message.isEmpty {
                    Text(UIStrings.text(message))
                        .font(Theme.Typography.body())
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
            }

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: Theme.Spacing.md) {
                    if let primaryAction {
                        actionButton(primaryAction)
                    }
                    if let secondaryAction {
                        actionButton(secondaryAction)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
        .controlSurface(level: 0)
    }

    @ViewBuilder
    private func actionButton(_ action: Action) -> some View {
        Button(action: action.action) {
            if let systemImage = action.systemImage {
                Label(UIStrings.text(action.title), systemImage: systemImage)
            } else {
                Text(UIStrings.text(action.title))
            }
        }
        .buttonStyle(.plain)
        .modifier(EmptyStateActionStyle(style: action.style))
    }
}

private struct EmptyStateActionStyle: ViewModifier {
    let style: EmptyStateView.Action.Style

    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content.primaryActionButton()
        case .secondary:
            content.secondaryActionButton()
        }
    }
}

#Preview {
    EmptyStateView(
        title: "No corrections yet",
        systemImage: "keyboard",
        message: "RightLayout will show recent fixes and diagnostics here after you start using it.",
        primaryAction: .init(title: "Open Settings", systemImage: "gearshape", style: .primary, action: {}),
        secondaryAction: .init(title: "Learn More", systemImage: "info.circle", style: .secondary, action: {})
    )
    .frame(width: 640, height: 320)
    .padding()
}
