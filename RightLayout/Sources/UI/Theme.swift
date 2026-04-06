import AppKit
import SwiftUI

enum Theme {
    enum Color {
        private static func dynamic(_ light: NSColor, _ dark: NSColor) -> SwiftUI.Color {
            SwiftUI.Color(
                nsColor: NSColor(name: nil) { appearance in
                    switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
                    case .darkAqua:
                        dark
                    default:
                        light
                    }
                }
            )
        }

        static let pageBackgroundPrimary = dynamic(
            NSColor(calibratedWhite: 0.96, alpha: 1),
            NSColor(calibratedWhite: 0.12, alpha: 1)
        )
        static let pageBackgroundSecondary = dynamic(
            NSColor(calibratedWhite: 0.92, alpha: 1),
            NSColor(calibratedWhite: 0.09, alpha: 1)
        )
        static let surfaceBase = dynamic(
            NSColor(calibratedWhite: 0.985, alpha: 1),
            NSColor(calibratedWhite: 0.17, alpha: 1)
        )
        static let surfaceRaised = dynamic(
            NSColor(calibratedWhite: 1.0, alpha: 1),
            NSColor(calibratedWhite: 0.20, alpha: 1)
        )
        static let surfaceInteractive = dynamic(
            NSColor(calibratedWhite: 0.90, alpha: 1),
            NSColor(calibratedWhite: 0.24, alpha: 1)
        )

        static let borderSubtle = dynamic(
            NSColor(calibratedWhite: 0.82, alpha: 1),
            NSColor(calibratedWhite: 0.30, alpha: 1)
        )
        static let borderStrong = dynamic(
            NSColor(calibratedWhite: 0.70, alpha: 1),
            NSColor(calibratedWhite: 0.42, alpha: 1)
        )
        static let borderFocus = SwiftUI.Color(nsColor: .controlAccentColor)

        static let textPrimary = SwiftUI.Color(nsColor: .labelColor)
        static let textSecondary = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let textMeta = SwiftUI.Color(nsColor: .tertiaryLabelColor)

        static let accent = SwiftUI.Color(nsColor: .controlAccentColor)
        static let success = dynamic(
            NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.38, green: 0.78, blue: 0.52, alpha: 1)
        )
        static let warning = dynamic(
            NSColor(calibratedRed: 0.66, green: 0.44, blue: 0.10, alpha: 1),
            NSColor(calibratedRed: 0.92, green: 0.72, blue: 0.30, alpha: 1)
        )
        static let error = dynamic(
            NSColor(calibratedRed: 0.70, green: 0.20, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.46, alpha: 1)
        )

        // Compatibility aliases for unconverted surfaces.
        static let backgroundDark = pageBackgroundPrimary
        static let background = pageBackgroundPrimary
        static let surface0 = surfaceBase
        static let surface1 = surfaceRaised
        static let surface2 = surfaceInteractive
        static let textTertiary = textMeta
        static let brand = accent
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
    }

    enum Size {
        static let rowHeight: CGFloat = 44
        static let compactRowHeight: CGFloat = 36
    }

    enum Typography {
        static func pageTitle() -> Font { .system(size: 28, weight: .semibold) }
        static func sectionTitle() -> Font { .system(size: 18, weight: .semibold) }
        static func heading() -> Font { .system(size: 22, weight: .semibold) }
        static func body() -> Font { .system(size: 14, weight: .regular) }
        static func bodyStrong() -> Font { .system(size: 14, weight: .medium) }
        static func label() -> Font { .system(size: 13, weight: .medium) }
        static func meta() -> Font { .system(size: 12, weight: .medium) }
        static func mono() -> Font { .system(size: 13, weight: .medium, design: .monospaced) }

        // Compatibility aliases.
        static func title() -> Font { heading() }
        static func heading1() -> Font { pageTitle() }
        static func heading2() -> Font { heading() }
        static func heading3() -> Font { sectionTitle() }
        static func bodyMain() -> Font { body() }
        static func caption() -> Font { meta() }
        static func numericData() -> Font { mono() }
    }

    enum Motion {
        static let fast = Animation.easeOut(duration: 0.14)
        static let normal = Animation.easeOut(duration: 0.22)
    }
}

extension View {
    func controlSurface(level: Int = 0) -> some View {
        let background = switch level {
        case 1: Theme.Color.surfaceRaised
        case 2: Theme.Color.surfaceInteractive
        default: Theme.Color.surfaceBase
        }

        return self
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 1)
            }
    }

    func primaryActionButton() -> some View {
        self
            .font(Theme.Typography.label())
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .foregroundStyle(SwiftUI.Color.white)
    }

    func secondaryActionButton() -> some View {
        self
            .font(Theme.Typography.label())
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.surfaceInteractive, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.Color.borderStrong, lineWidth: 1)
            }
            .foregroundStyle(Theme.Color.textPrimary)
    }
}
