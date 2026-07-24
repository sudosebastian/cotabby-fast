import SwiftUI

/// File overview:
/// The small Tabfast affordance shown just outside a supported text field. Its forward-to-end
/// glyph echoes the app icon while remaining legible in the deliberately tiny field-edge chip.
struct FieldEdgeIconIndicatorView: View {
    // Sized at 0.7 of the original chip so the affordance sits more discreetly beside the input.
    private let side: CGFloat = 14
    private let cornerRadius: CGFloat = 3.5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.18, green: 0.19, blue: 0.21))
            Image(systemName: "forward.end.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .fixedSize()
    }
}
