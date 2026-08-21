import Combine
import SwiftUI

/// File overview:
/// Macro inline-preview panel content. Pure renderer of `InlinePreviewViewModel`.
/// Dials match ghost/HUD: quiet, engineered, functional — same keycap language as ghost text.
@MainActor
final class InlinePreviewViewModel: ObservableObject {
    @Published var previewText: String = ""
    @Published var acceptKeyLabel: String?
}

struct InlinePreviewView: View {
    @ObservedObject var model: InlinePreviewViewModel
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: TabfastDesign.Space.xs) {
            Text(model.previewText)
                .font(TabfastDesign.Typography.callout.weight(.medium))
                .foregroundStyle(PopupTheme.primaryText)
                .lineLimit(1)
            if let label = model.acceptKeyLabel {
                InlinePreviewKeycap(label: label)
            }
        }
        .padding(.horizontal, TabfastDesign.Space.sm)
        .frame(height: 28)
        .popupHUDChrome()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .fixedSize()
    }
}

private struct InlinePreviewKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(TabfastDesign.Typography.keycap)
            .foregroundStyle(PopupTheme.secondaryText)
            .padding(.horizontal, TabfastDesign.Space.xxs + 1)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: TabfastDesign.Radius.keycap, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: TabfastDesign.Radius.keycap, style: .continuous)
                    .stroke(PopupTheme.hairline, lineWidth: 0.5)
            )
            .fixedSize()
    }
}
