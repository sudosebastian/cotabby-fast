import SwiftUI

/// Settings sidebar. Job: pick a pane or search. Brand is a quiet wordmark, not a hero.
struct SettingsSidebarView: View {
    @ObservedObject var navigation: SettingsNavigationModel
    let attentionCategories: Set<SettingsCategory>
    let onQuit: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            appHeader
            searchField

            if trimmedQuery.isEmpty {
                categoryList
            } else {
                searchResultsList
            }

            appActionsFooter
        }
        .frame(minWidth: TabfastDesign.Space.settingsSidebarMin, idealWidth: TabfastDesign.Space.settingsSidebarIdeal)
        .navigationSplitViewColumnWidth(
            min: TabfastDesign.Space.settingsSidebarMin,
            ideal: TabfastDesign.Space.settingsSidebarIdeal,
            max: 320
        )
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit(openTopResult)

            if !trimmedQuery.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, TabfastDesign.Space.xs)
        .padding(.vertical, 6)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: TabfastDesign.Radius.control, style: .continuous)
        )
        .padding(.horizontal, TabfastDesign.Space.xs)
        .padding(.bottom, TabfastDesign.Space.xxs)
    }

    private var appHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: TabfastDesign.Space.xs) {
            Text("Tabfast")
                .font(TabfastDesign.Typography.title)
            if let version = Bundle.main.cotabbyDisplayVersion {
                Text(version)
                    .font(TabfastDesign.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TabfastDesign.Space.sm)
        .padding(.top, TabfastDesign.Space.lg)
        .padding(.bottom, TabfastDesign.Space.xs)
    }

    private var appActionsFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: onQuit) {
                Text("Quit Tabfast")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("q")
            .padding(TabfastDesign.Space.sm)
        }
    }

    private var selectionBinding: Binding<SettingsCategory> {
        Binding(
            get: { navigation.selection },
            set: { navigation.open($0) }
        )
    }

    private var categoryList: some View {
        List(selection: selectionBinding) {
            ForEach(Array(SettingsCategory.sidebarGroups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { row(for: $0) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var searchResults: [SettingsItem] {
        SettingsItem.results(for: trimmedQuery)
    }

    private var searchResultsList: some View {
        let results = searchResults
        return List {
            if results.isEmpty {
                Text("No matches for \u{201C}\(trimmedQuery)\u{201D}")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { item in
                    Button {
                        open(item)
                    } label: {
                        SettingsSearchResultRow(item: item, style: .compact)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func openTopResult() {
        guard let top = searchResults.first else { return }
        open(top)
    }

    private func open(_ item: SettingsItem) {
        navigation.reveal(item)
        searchText = ""
    }

    @ViewBuilder
    private func row(for category: SettingsCategory) -> some View {
        HStack(spacing: TabfastDesign.Space.xs) {
            SettingsIconTile(systemImage: category.systemImage, tint: category.tint, size: 18)
            Text(category.label)
            Spacer(minLength: 0)
            if attentionCategories.contains(category) {
                Circle()
                    .fill(TabfastDesign.ColorToken.warning)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Needs attention")
            }
        }
        .tag(category)
    }
}
