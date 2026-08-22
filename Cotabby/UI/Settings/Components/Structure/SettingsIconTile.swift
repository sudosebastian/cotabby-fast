import SwiftUI

/// Tinted tile + white symbol. One language for sidebar and lists.
struct SettingsIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * TabfastDesign.Radius.tileFraction, style: .continuous)
                    .fill(tint)
            )
            .accessibilityHidden(true)
    }
}
