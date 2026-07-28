import SubscriptionCore
import SwiftUI

struct CatalogPresetDetailView: View {
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    let preset: CatalogPreset
    let onSubscriptionCreated: () -> Void

    var body: some View {
        Form {
            Section {
                Label(
                    preset.serviceName.value(for: locale),
                    systemImage: preset.icon.systemImageName
                )
                .font(.headline)
            }

            Section("Suggested Details") {
                LabeledContent(
                    "Category",
                    value: preset.category.value(for: locale)
                )
                LabeledContent(
                    "Suggested Billing Interval",
                    value: localizedBillingInterval(preset.suggestedInterval)
                )
                if let managementURL = preset.managementURL {
                    Link("Management URL", destination: managementURL)
                }
            }

            Section {
                Text(
                    "Confirm your actual plan, price, currency, and renewal dates before saving."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                NavigationLink {
                    AddSubscriptionView(
                        workspace: workspace,
                        preset: preset,
                        onSuccessfulSave: onSubscriptionCreated
                    )
                } label: {
                    Text("Use This Preset")
                }
                .accessibilityIdentifier("catalog.use-preset")
            }
        }
        .navigationTitle("Catalog Details")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
