import SwiftUI

/// Title + one-line description for Settings controls. Always-visible subtext beats tooltips.
struct SettingsRowLabel: View {
    let title: String
    let description: String
    var systemImage: String?

    init(title: String, description: String, systemImage: String? = nil) {
        self.title = title
        self.description = description
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TabfastDesign.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(TabfastDesign.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
