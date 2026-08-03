import SubscriptionCore
import SwiftUI

struct CatalogAddFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let onCompleted: () -> Void

    var body: some View {
        NavigationStack {
            CatalogBrowserView(
                workspace: workspace,
                onSubscriptionCreated: finish,
                onCancel: { dismiss() }
            )
        }
    }

    private func finish() {
        onCompleted()
        dismiss()
    }
}

struct CatalogBrowserView: View {
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    let onSubscriptionCreated: () -> Void
    let onCancel: () -> Void

    @State private var searchQuery = ""
    @State private var selectedCategoryID: String?
    @State private var isRefreshing = false

    var body: some View {
        catalogContent
            .navigationTitle("Browse Catalog")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(
                text: $searchQuery,
                prompt: "Search services or categories"
            )
            .onChange(of: searchQuery) { _, query in
                workspace.setCatalogSearchQuery(query)
            }
            .task {
                workspace.loadCatalog(locale: locale)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("catalog.cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        AddSubscriptionView(
                            workspace: workspace,
                            showsCancellationAction: false,
                            onSuccessfulSave: onSubscriptionCreated
                        )
                    } label: {
                        Text("Add Manually")
                    }
                    .accessibilityIdentifier("catalog.add-manually")
                }
            }
    }

    @ViewBuilder
    private var catalogContent: some View {
        switch workspace.catalogState {
        case .notLoaded:
            ProgressView("Loading Catalog")
                .accessibilityIdentifier("catalog.loading")

        case .failed:
            ContentUnavailableView {
                Label("Couldn’t Load Catalog", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Try reopening the app.")
            }
            .accessibilityIdentifier("catalog.failed")

        case .loaded(let categories, let presets):
            let sections = CatalogIndexProjection.sections(
                for: presets,
                locale: locale
            )
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    List {
                        Section {
                            Menu {
                                Button("Categories") {
                                    selectedCategoryID = nil
                                    workspace.setCatalogCategory(nil)
                                }

                                ForEach(categories) { category in
                                    Button(category.title.value(for: locale)) {
                                        selectedCategoryID = category.id
                                        workspace.setCatalogCategory(category.id)
                                    }
                                }
                            } label: {
                                Label(
                                    selectedCategoryTitle(in: categories),
                                    systemImage: "line.3.horizontal.decrease.circle"
                                )
                                .accessibilityIdentifier("catalog.category")
                            }
                        }

                        if sections.isEmpty {
                            Section("Catalog") {
                                ContentUnavailableView.search(text: searchQuery)
                            }
                        } else {
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.presets) { preset in
                                        NavigationLink {
                                            AddSubscriptionView(
                                                workspace: workspace,
                                                preset: preset,
                                                showsCancellationAction: false,
                                                onSuccessfulSave:
                                                    onSubscriptionCreated
                                            )
                                        } label: {
                                            CatalogPresetRow(
                                                preset: preset,
                                                locale: locale
                                            )
                                        }
                                        .accessibilityIdentifier(
                                            "catalog.preset.\(preset.id)"
                                        )
                                    }
                                } header: {
                                    Text(section.title)
                                        .accessibilityIdentifier(
                                            "catalog.section.\(section.id)"
                                        )
                                }
                                .id(section.id)
                            }
                        }

                        catalogDiagnostics
                    }
                    .contentMargins(.trailing, 28, for: .scrollContent)
                    .accessibilityIdentifier("catalog.list")

                    if shouldShowAlphabetIndex(for: sections) {
                        CatalogAlphabetIndex(
                            letters: sections.map(\.id)
                        ) { letter in
                            withAnimation(.snappy) {
                                proxy.scrollTo(letter, anchor: .top)
                            }
                        }
                        .padding(.trailing, 2)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var catalogDiagnostics: some View {
        if let diagnostics = workspace.catalogDiagnostics {
            Section {
                Text(
                    "Catalog version \(diagnostics.version) · "
                        + diagnostics.source.localizedTitle
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("catalog.diagnostics")

                Button("Check for Catalog Updates") {
                    Task {
                        isRefreshing = true
                        await workspace.refreshCatalog()
                        if workspace.catalogDiagnostics?.refreshStatus
                            == .updated
                        {
                            workspace.reconcileCatalogAssociations(
                                locale: locale
                            )
                        }
                        isRefreshing = false
                    }
                }
                .disabled(isRefreshing)
                .accessibilityIdentifier("catalog.refresh")

                if diagnostics.refreshStatus == .failed {
                    Text("Couldn’t update the catalog. Your offline catalog is still available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectedCategoryTitle(
        in categories: [CatalogCategory]
    ) -> String {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID })
        else {
            return String(localized: "Category")
        }
        return category.title.value(for: locale)
    }

    private func shouldShowAlphabetIndex(
        for sections: [CatalogIndexSection]
    ) -> Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sections.isEmpty
    }
}

private extension CatalogSource {
    var localizedTitle: String {
        switch self {
        case .bundled:
            String(localized: "Bundled")
        case .cached:
            String(localized: "Updated")
        }
    }
}

private struct CatalogPresetRow: View {
    let preset: CatalogPreset
    let locale: Locale

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.icon.systemImageName)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.serviceName.value(for: locale))
                Text(preset.category.value(for: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension CatalogIcon {
    var systemImageName: String {
        switch self {
        case .cloud:
            "icloud"
        case .game:
            "gamecontroller"
        case .membership:
            "person.crop.circle.badge.checkmark"
        case .music:
            "music.note"
        case .news:
            "newspaper"
        case .other:
            "square.grid.2x2"
        case .productivity:
            "checklist"
        case .reading:
            "book"
        case .video:
            "play.rectangle"
        }
    }
}
