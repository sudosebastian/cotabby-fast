import SwiftUI

/// File overview:
/// Tiny field-edge affordance. Quiet and functional — no shadow, no brand glow. Presence alone
/// signals Tabfast is watching this field; the mark stays subordinate to the host document.
struct FieldEdgeIconIndicatorView: View {
    private let side: CGFloat = 12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TabfastDesign.Radius.keycap, style: .continuous)
                .fill(Color(white: 0.16))
            Image(systemName: "forward.end.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: side, height: side)
        .fixedSize()
        .accessibilityHidden(true)
    }
}
