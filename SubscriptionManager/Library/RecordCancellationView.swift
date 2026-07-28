import SubscriptionCore
import SwiftUI

struct RecordCancellationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    let subscription: Subscription

    @State private var selectedCancellationDate: Date
    @State private var selectedAccessUntil: Date

    init(
        workspace: SubscriptionWorkspace,
        subscription: Subscription
    ) {
        self.workspace = workspace
        self.subscription = subscription

        let today = Date()
        _selectedCancellationDate = State(initialValue: today)
        _selectedAccessUntil = State(
            initialValue: max(today, subscription.confirmedNextRenewal)
        )
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Cancellation Date",
                    selection: $selectedCancellationDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accessibilityIdentifier("subscription.cancellation.date")
                .accessibilityValue(
                    formattedBillingDate(
                        selectedCancellationDate,
                        timeZoneIdentifier:
                            subscription.billingSchedule.timeZoneIdentifier,
                        locale: locale
                    )
                )

                DatePicker(
                    "Access Until",
                    selection: $selectedAccessUntil,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accessibilityIdentifier(
                    "subscription.cancellation.access-until"
                )
                .accessibilityValue(
                    formattedBillingDate(
                        selectedAccessUntil,
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
                        identifier: "subscription.cancellation.error"
                    )
                }
            }
        }
        .accessibilityIdentifier("subscription.cancellation.form")
        .environment(
            \.timeZone,
            billingTimeZone(
                identifier: subscription.billingSchedule.timeZoneIdentifier
            )
        )
        .navigationTitle("Record Cancellation")
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
                Button("Save Cancellation") {
                    save()
                }
                .accessibilityIdentifier("subscription.cancellation.save")
            }
        }
    }

    private func save() {
        workspace.recordCancellation(
            id: subscription.id,
            cancelledAt: selectedCancellationDate,
            accessUntil: selectedAccessUntil
        )

        guard workspace.lifecycleActionError == nil,
              case .loaded(let updated, _, _) = workspace.detailState,
              updated.id == subscription.id,
              case .cancelled = updated.lifecycle
        else {
            return
        }
        dismiss()
    }
}
