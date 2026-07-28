import SubscriptionCore
import SwiftUI

struct ReactivateSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    let subscription: Subscription

    @State private var selectedNextRenewal: Date

    init(
        workspace: SubscriptionWorkspace,
        subscription: Subscription
    ) {
        self.workspace = workspace
        self.subscription = subscription
        _selectedNextRenewal = State(
            initialValue: max(Date(), subscription.confirmedNextRenewal)
        )
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Next Renewal",
                    selection: $selectedNextRenewal,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accessibilityIdentifier(
                    "subscription.reactivation.next-renewal"
                )
                .accessibilityValue(
                    formattedBillingDate(
                        selectedNextRenewal,
                        timeZoneIdentifier:
                            subscription.billingSchedule.timeZoneIdentifier,
                        locale: locale
                    )
                )
            }

            if let error = workspace.lifecycleActionError {
                Section {
                    ValidationMessage(
                        lifecycleActionErrorText(error),
                        identifier: "subscription.reactivation.error"
                    )
                }
            }
        }
        .accessibilityIdentifier("subscription.reactivation.form")
        .environment(
            \.timeZone,
            billingTimeZone(
                identifier: subscription.billingSchedule.timeZoneIdentifier
            )
        )
        .navigationTitle("Reactivate Subscription")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Reactivate") {
                    save()
                }
                .accessibilityIdentifier("subscription.reactivation.save")
            }
        }
    }

    private func save() {
        workspace.reactivate(
            id: subscription.id,
            nextRenewal: selectedNextRenewal
        )

        guard workspace.lifecycleActionError == nil,
              case .loaded(let updated, _, _) = workspace.detailState,
              updated.id == subscription.id,
              case .active = updated.lifecycle
        else {
            return
        }
        dismiss()
    }
}
