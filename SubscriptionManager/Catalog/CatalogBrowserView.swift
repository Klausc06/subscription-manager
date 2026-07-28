import SubscriptionCore
import SwiftUI

struct CatalogBrowserView: View {
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    let onSubscriptionCreated: () -> Void

    @State private var searchQuery = ""
    @State private var selectedCategoryID: String?

    var body: some View {
        catalogContent
            .navigationTitle("Browse Catalog")
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
            List {
                Section {
                    Menu {
                        Button("All Categories") {
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
                    }
                    .accessibilityIdentifier("catalog.category")
                }

                Section("Catalog") {
                    if presets.isEmpty {
                        ContentUnavailableView.search(text: searchQuery)
                    } else {
                        ForEach(presets) { preset in
                            NavigationLink {
                                CatalogPresetDetailView(
                                    workspace: workspace,
                                    preset: preset,
                                    onSubscriptionCreated: onSubscriptionCreated
                                )
                            } label: {
                                CatalogPresetRow(preset: preset, locale: locale)
                            }
                            .accessibilityIdentifier("catalog.preset.\(preset.id)")
                        }
                    }
                }
            }
            .accessibilityIdentifier("catalog.list")
        }
    }

    private func selectedCategoryTitle(
        in categories: [CatalogCategory]
    ) -> String {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID })
        else {
            return String(localized: "All Categories")
        }
        return category.title.value(for: locale)
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
