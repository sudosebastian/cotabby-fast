import SwiftUI

/// Settings Home — rebuilt from the design brief.
///
/// Reader job: find a setting, glance status, open a pane.
/// Hierarchy: (1) search (2) status line (3) pane list (4) links.
/// Dials: quiet · standard · medium brand · engineered · balanced.
///
/// Cut vs prior Home: logo hero, accent backdrop, three status cards, card-grid quick links,
/// feature showcase. None survived the decision filter for a daily Settings surface.
struct HomePaneView: View {
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var suggestionSettings: SuggestionSettingsModel
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var foundationModelAvailabilityService: FoundationModelAvailabilityService
    @ObservedObject var runtimeModel: RuntimeBootstrapModel
    @ObservedObject var openAICompatibleConnectionModel: OpenAICompatibleConnectionModel
    let attentionCategories: Set<SettingsCategory>

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private static let maximumSearchResults = 12

    private var browseCategories: [SettingsCategory] {
        SettingsCategory.sidebarGroups.flatMap { $0 }.filter { $0 != .home }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TabfastDesign.Space.lg) {
                identityRow
                searchField

                if trimmedQuery.isEmpty {
                    statusLine
                    paneList
                    footer
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, TabfastDesign.Space.pageInset)
            .padding(.top, TabfastDesign.Space.lg)
            .padding(.bottom, TabfastDesign.Space.xl)
            .frame(maxWidth: TabfastDesign.Space.settingsContentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: navigation.pendingSearchFocus, initial: true) { _, pending in
            guard pending else { return }
            isSearchFocused = true
            Task { navigation.consumeSearchFocusRequest() }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 4. Metadata identity (subordinate)

    private var identityRow: some View {
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - 1. Search (hero)

    private var searchField: some View {
        HStack(spacing: TabfastDesign.Space.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .font(TabfastDesign.Typography.body)
                .focused($isSearchFocused)
                .onSubmit(openTopResult)

            if trimmedQuery.isEmpty {
                Text("⌘F")
                    .font(TabfastDesign.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            } else {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, TabfastDesign.Space.sm)
        .padding(.vertical, TabfastDesign.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: TabfastDesign.Radius.surface, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TabfastDesign.Radius.surface, style: .continuous)
                .strokeBorder(
                    isSearchFocused
                        ? TabfastDesign.ColorToken.accent.opacity(0.6)
                        : Color.primary.opacity(0.12),
                    lineWidth: 1
                )
        )
        .accessibilityLabel("Search settings")
    }

    // MARK: - 2. Status (one line, not three cards)

    private var statusLine: some View {
        HStack(spacing: TabfastDesign.Space.md) {
            HStack(spacing: TabfastDesign.Space.xs) {
                Text(suggestionSettings.isGloballyEnabled ? "On" : "Off")
                    .font(TabfastDesign.Typography.callout.weight(.semibold))
                    .foregroundStyle(
                        suggestionSettings.isGloballyEnabled
                            ? TabfastDesign.ColorToken.success
                            : .secondary
                    )
                Toggle("", isOn: globallyEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("Enable Tabfast")
            }

            statusDivider

            Button {
                navigation.open(.engineAndModel)
            } label: {
                HStack(spacing: 4) {
                    Text(suggestionSettings.selectedEngine.displayLabel)
                        .font(TabfastDesign.Typography.callout.weight(.medium))
                    Text(engineCaption)
                        .font(TabfastDesign.Typography.caption)
                        .foregroundStyle(engineNeedsAttention ? TabfastDesign.ColorToken.warning : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Engine & Model")

            statusDivider

            Button {
                navigation.open(.permissions)
            } label: {
                Text(permissionManager.requiredPermissionsGranted ? "Permissions OK" : "Permissions needed")
                    .font(TabfastDesign.Typography.callout)
                    .foregroundStyle(
                        permissionManager.requiredPermissionsGranted
                            ? .secondary
                            : TabfastDesign.ColorToken.warning
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Permissions")

            Spacer(minLength: 0)
        }
        .padding(.vertical, TabfastDesign.Space.xxs)
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 14)
            .accessibilityHidden(true)
    }

    // MARK: - 3. Pane list

    private var paneList: some View {
        VStack(spacing: 0) {
            ForEach(Array(browseCategories.enumerated()), id: \.element.id) { index, category in
                Button {
                    navigation.open(category)
                } label: {
                    HStack(spacing: TabfastDesign.Space.sm) {
                        SettingsIconTile(
                            systemImage: category.systemImage,
                            tint: category.tint,
                            size: 22
                        )
                        Text(category.label)
                            .font(TabfastDesign.Typography.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Text(category.summary)
                            .font(TabfastDesign.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if attentionCategories.contains(category) {
                            Circle()
                                .fill(TabfastDesign.ColorToken.warning)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("Needs attention")
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, TabfastDesign.Space.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(category.label) settings")
                .accessibilityHint(category.summary)

                if index < browseCategories.count - 1 {
                    Divider()
                }
            }
        }
    }

    // MARK: - Search results

    private var searchResultsList: [SettingsItem] {
        Array(SettingsItem.results(for: trimmedQuery).prefix(Self.maximumSearchResults))
    }

    private var searchResults: some View {
        let results = searchResultsList
        return VStack(spacing: 0) {
            if results.isEmpty {
                Text("No settings match \u{201C}\(trimmedQuery)\u{201D}")
                    .font(TabfastDesign.Typography.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, TabfastDesign.Space.md)
            } else {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    Button {
                        open(item)
                    } label: {
                        SettingsSearchResultRow(item: item, style: .full)
                            .padding(.vertical, TabfastDesign.Space.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < results.count - 1 {
                        Divider().padding(.leading, 38)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: TabfastDesign.Space.xs) {
            if let repoURL = URL(string: "https://github.com/FuJacob/Cotabby") {
                Link("GitHub", destination: repoURL)
            }
            Text("·").foregroundStyle(.tertiary)
            if let supportURL = URL(string: "https://ko-fi.com/cotabby") {
                Link("Support", destination: supportURL)
            }
            Text("·").foregroundStyle(.tertiary)
            if let wikiURL = URL(string: "https://github.com/FuJacob/Cotabby/wiki") {
                Link("Wiki", destination: wikiURL)
            }
            Spacer(minLength: 0)
        }
        .font(TabfastDesign.Typography.caption)
        .foregroundStyle(.secondary)
        .padding(.top, TabfastDesign.Space.xs)
    }

    // MARK: - Helpers

    private var engineNeedsAttention: Bool {
        attentionCategories.contains(.engineAndModel)
    }

    private var engineCaption: String {
        switch suggestionSettings.selectedEngine {
        case .appleIntelligence:
            return foundationModelAvailabilityService.isAvailable ? "Ready" : "Unavailable"
        case .llamaOpenSource:
            let selected = runtimeModel.availableModels
                .first { $0.filename == runtimeModel.selectedModelFilename }
            return selected?.displayName ?? "No model"
        case .openAICompatible:
            if openAICompatibleConnectionModel.state.failureDetail != nil {
                return "Connection failed"
            }
            return suggestionSettings.openAICompatibleModelName.isEmpty
                ? "No model"
                : suggestionSettings.openAICompatibleModelName
        }
    }

    private var globallyEnabledBinding: Binding<Bool> {
        Binding(
            get: { suggestionSettings.isGloballyEnabled },
            set: { suggestionSettings.setGloballyEnabled($0) }
        )
    }

    private func openTopResult() {
        guard let top = searchResultsList.first else { return }
        open(top)
    }

    private func open(_ item: SettingsItem) {
        navigation.reveal(item)
        query = ""
    }
}
