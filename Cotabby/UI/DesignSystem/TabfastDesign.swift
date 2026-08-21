import SwiftUI

/// Fixed visual layer for Tabfast. See `BRIEF.md` for reader, dials, and hierarchy.
enum TabfastDesign {

    enum ColorToken {
        /// Signature accent — primary action and focus only. Never doubles as warning.
        static let accent = Color(red: 0.00, green: 0.66, blue: 0.76)
        static let accentDeep = Color(red: 0.00, green: 0.50, blue: 0.60)

        static let warning = Color.orange
        static let danger = Color.red
        static let success = Color.green

        static func ghostInk(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(white: 0.60) : Color(white: 0.40)
        }

        static let hudTop = Color(white: 0.14)
        static let hudBottom = Color(white: 0.08)
        static let hudHairline = Color.white.opacity(0.12)
        static let hudSelection = Color.white.opacity(0.14)
        static let hudPrimary = Color.white.opacity(0.95)
        static let hudSecondary = Color.white.opacity(0.50)

        // Legacy HUD names used by PopupTheme call sites.
        static let hudBackgroundTop = hudTop
        static let hudBackgroundBottom = hudBottom
        static let hudPrimaryText = hudPrimary
        static let hudSecondaryText = hudSecondary
    }

    enum Typography {
        static let display = Font.system(size: 28, weight: .semibold)
        static let title = Font.system(size: 17, weight: .semibold)
        static let headline = Font.system(.headline)
        static let body = Font.body
        static let callout = Font.callout
        static let caption = Font.caption
        static let caption2 = Font.caption2
        static let keycap = Font.system(size: 10, weight: .medium)
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32

        static let settingsSidebarMin: CGFloat = 240
        static let settingsSidebarIdeal: CGFloat = 260
        static let settingsContentMax: CGFloat = 560
        static let menuBarWidth: CGFloat = 288
        static let onboardingHorizontal: CGFloat = 32
        static let pageInset: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let surface: CGFloat = 8
        static let tileFraction: CGFloat = 0.22
        static let hud: CGFloat = 8
        static let keycap: CGFloat = 4
        static let onboardingCard: CGFloat = 8
    }

    enum Motion {
        static let reveal = Animation.easeOut(duration: 0.28)
        static let selection = Animation.easeInOut(duration: 0.22)
        static let hover = Animation.easeOut(duration: 0.1)
    }
}

enum CotabbyBrand {
    static let accent = TabfastDesign.ColorToken.accent
    static let accentSoft = TabfastDesign.ColorToken.accentDeep
}

extension View {
    func tabfastCard(cornerRadius: CGFloat = TabfastDesign.Radius.card) -> some View {
        modifier(TabfastCardChrome(cornerRadius: cornerRadius))
    }
}

private struct TabfastCardChrome: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}
