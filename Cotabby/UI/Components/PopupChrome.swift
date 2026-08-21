import SwiftUI

/// Caret-adjacent HUD chrome. Quiet, engineered, committed-dark so the panel does not compete
/// with the host document by flipping to a bright card over light apps.
enum PopupTheme {
    static let cornerRadius: CGFloat = TabfastDesign.Radius.hud

    static let backgroundGradient = LinearGradient(
        colors: [
            TabfastDesign.ColorToken.hudTop,
            TabfastDesign.ColorToken.hudBottom
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let hairline = TabfastDesign.ColorToken.hudHairline
    static let selectionFill = TabfastDesign.ColorToken.hudSelection
    static let primaryText = TabfastDesign.ColorToken.hudPrimary
    static let secondaryText = TabfastDesign.ColorToken.hudSecondary
}

struct PopupHUDChrome: ViewModifier {
    var cornerRadius: CGFloat = PopupTheme.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PopupTheme.backgroundGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PopupTheme.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func popupHUDChrome(cornerRadius: CGFloat = PopupTheme.cornerRadius) -> some View {
        modifier(PopupHUDChrome(cornerRadius: cornerRadius))
    }
}
