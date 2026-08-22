import SwiftUI

/// Shared chrome for settings detail panes: optional callout, then grouped form.
struct SettingsPaneScaffold<Content: View>: View {
    let callout: SettingsPaneCallout?
    @ViewBuilder let content: () -> Content

    @Environment(\.settingsHighlightedItem) private var highlightedItem

    init(
        callout: SettingsPaneCallout? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.callout = callout
        self.content = content
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let callout {
                        SettingsCalloutView(callout: callout)
                            .padding(.horizontal, TabfastDesign.Space.md)
                            .padding(.top, TabfastDesign.Space.md)
                    }
                    Form {
                        content()
                    }
                    .formStyle(.grouped)
                    .padding(.top, TabfastDesign.Space.sm)
                }
            }
            .onAppear {
                guard let item = highlightedItem else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(TabfastDesign.Motion.selection) {
                        proxy.scrollTo(item, anchor: .center)
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(TabfastDesign.Motion.selection) {
                        proxy.scrollTo(item, anchor: .center)
                    }
                }
            }
            .onChange(of: highlightedItem) { _, item in
                guard let item else { return }
                withAnimation(TabfastDesign.Motion.selection) {
                    proxy.scrollTo(item, anchor: .center)
                }
            }
        }
    }
}

struct SettingsPaneCallout: Equatable {
    enum Tone {
        case warning
        case info
    }

    let tone: Tone
    let message: String
}

struct SettingsCalloutView: View {
    let callout: SettingsPaneCallout

    var body: some View {
        HStack(alignment: .top, spacing: TabfastDesign.Space.xs) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
            Text(callout.message)
                .font(TabfastDesign.Typography.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TabfastDesign.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: TabfastDesign.Radius.control, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TabfastDesign.Radius.control, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch callout.tone {
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch callout.tone {
        case .warning: return TabfastDesign.ColorToken.warning
        case .info: return TabfastDesign.ColorToken.accent
        }
    }
}
