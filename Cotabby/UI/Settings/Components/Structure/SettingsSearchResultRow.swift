import SwiftUI

/// One settings search hit. Compact for sidebar; full for Home.
struct SettingsSearchResultRow: View {
    enum Style {
        case compact
        case full
    }

    let item: SettingsItem
    var style: Style = .compact

    var body: some View {
        HStack(spacing: TabfastDesign.Space.xs) {
            SettingsIconTile(
                systemImage: item.systemImage,
                tint: item.category.tint,
                size: style == .full ? 24 : 18
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(TabfastDesign.Typography.body)
                    .lineLimit(1)
                if style == .full {
                    Text(item.summary)
                        .font(TabfastDesign.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: TabfastDesign.Space.xs)

            Text(item.category.label)
                .font(TabfastDesign.Typography.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), in \(item.category.label)")
    }
}
