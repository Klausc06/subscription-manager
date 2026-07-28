import SubscriptionCore
import SwiftUI

struct SubscriptionDetailView: View {
    let workspace: SubscriptionWorkspace
    let subscriptionID: UUID
    @State private var subscriptionToEdit: Subscription?

    var body: some View {
        detailContent
            .navigationTitle("Subscription Details")
            .toolbar {
                if case .loaded(let subscription) = workspace.detailState,
                   subscription.id == subscriptionID
                {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit", systemImage: "pencil") {
                            subscriptionToEdit = subscription
                        }
                        .accessibilityIdentifier("subscription.edit")
                    }
                }
            }
            .sheet(item: $subscriptionToEdit) { subscription in
                NavigationStack {
                    EditSubscriptionView(
                        workspace: workspace,
                        subscription: subscription
                    )
                }
            }
            .task(id: subscriptionID) {
                workspace.loadSubscription(id: subscriptionID)
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch workspace.detailState {
        case .notLoaded:
            loadingView

        case let .loaded(subscription)
            where subscription.id == subscriptionID:
            SubscriptionDetailForm(subscription: subscription)

        case .loaded:
            loadingView

        case .notFound:
            ContentUnavailableView(
                "Subscription Not Found",
                systemImage: "questionmark.folder",
                description: Text(
                    "This subscription is no longer in your library."
                )
            )
            .accessibilityIdentifier("subscription.detail.not-found")

        case .failed:
            ContentUnavailableView(
                "Couldn’t Load Subscription",
                systemImage: "exclamationmark.triangle",
                description: Text("Reopen the app to try again.")
            )
            .accessibilityIdentifier("subscription.detail.failed")
        }
    }

    private var loadingView: some View {
        ProgressView("Loading Subscription")
            .accessibilityIdentifier("subscription.detail.loading")
    }
}

private struct SubscriptionDetailForm: View {
    let subscription: Subscription

    var body: some View {
        Form {
            Section("Service") {
                LabeledContent("Service Name", value: subscription.serviceName)
                    .accessibilityIdentifier("subscription.detail.service-name")
                LabeledContent("Plan", value: subscription.plan)
                    .accessibilityIdentifier("subscription.detail.plan")
                LabeledContent("Category", value: subscription.category)
                    .accessibilityIdentifier("subscription.detail.category")
            }

            Section("Price") {
                LabeledContent(
                    "Original Amount",
                    value: formattedMoney(subscription.originalAmount)
                )
                .accessibilityIdentifier("subscription.detail.amount")
                LabeledContent(
                    "Billing Schedule",
                    value: localizedBillingInterval(
                        subscription.billingSchedule.interval
                    )
                )
                .accessibilityIdentifier(
                    "subscription.detail.billing-interval"
                )
            }

            Section("Next Expected Charge") {
                LabeledContent(
                    "Amount",
                    value: formattedMoney(
                        subscription.firstExpectedCharge.amount
                    )
                )
                .accessibilityIdentifier(
                    "subscription.detail.expected-charge.amount"
                )
                LabeledContent {
                    Text(
                        subscription.firstExpectedCharge.scheduledDate,
                        format: .dateTime.year().month().day()
                    )
                } label: {
                    Text("Date")
                }
            }

            Section("Billing Dates") {
                LabeledContent {
                    Text(
                        subscription.startDate,
                        format: .dateTime.year().month().day()
                    )
                } label: {
                    Text("Start Date")
                }
                LabeledContent {
                    Text(
                        subscription.confirmedNextRenewal,
                        format: .dateTime.year().month().day()
                    )
                } label: {
                    Text("Next Renewal")
                }
            }

            if subscription.managementURL != nil || !subscription.notes.isEmpty {
                Section("Additional Information") {
                    if let managementURL = subscription.managementURL {
                        Link(
                            "Open Management Page",
                            destination: managementURL
                        )
                    }
                    if !subscription.notes.isEmpty {
                        LabeledContent("Notes", value: subscription.notes)
                    }
                }
            }
        }
        .accessibilityIdentifier("subscription.detail")
    }
}
