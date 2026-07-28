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
                if case .loaded(let subscription, _, _) = workspace.detailState,
                   subscription.id == subscriptionID
                {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit", systemImage: "pencil") {
                            workspace.beginEditing()
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

        case let .loaded(subscription, status, nextExpectedCharge)
            where subscription.id == subscriptionID:
            SubscriptionDetailForm(
                subscription: subscription,
                status: status,
                nextExpectedCharge: nextExpectedCharge
            )

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
    @Environment(\.locale) private var locale

    let subscription: Subscription
    let status: SubscriptionStatus
    let nextExpectedCharge: ExpectedCharge?

    private var timeZone: TimeZone {
        billingTimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        )
    }

    var body: some View {
        Form {
            Section("Service") {
                SubscriptionStatusBadge(status: status)
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

            if let nextExpectedCharge {
                Section("Next Expected Charge") {
                    LabeledContent(
                        "Amount",
                        value: formattedMoney(nextExpectedCharge.amount)
                    )
                    .accessibilityIdentifier(
                        "subscription.detail.expected-charge.amount"
                    )
                    LabeledContent {
                        Text(formattedBillingDate(
                            nextExpectedCharge.scheduledDate,
                            timeZoneIdentifier:
                                subscription.billingSchedule.timeZoneIdentifier,
                            locale: locale
                        ))
                    } label: {
                        Text("Date")
                    }
                }
            }

            Section("Billing Dates") {
                LabeledContent {
                    Text(formattedBillingDate(
                        subscription.startDate,
                        timeZoneIdentifier:
                            subscription.billingSchedule.timeZoneIdentifier,
                        locale: locale
                    ))
                } label: {
                    Text("Start Date")
                }
                LabeledContent {
                    Text(formattedBillingDate(
                        subscription.billingSchedule.renewalAnchor,
                        timeZoneIdentifier:
                            subscription.billingSchedule.timeZoneIdentifier,
                        locale: locale
                    ))
                } label: {
                    Text("Renewal Anchor")
                }
                LabeledContent {
                    Text(formattedBillingDate(
                        subscription.confirmedNextRenewal,
                        timeZoneIdentifier:
                            subscription.billingSchedule.timeZoneIdentifier,
                        locale: locale
                    ))
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
        .environment(\.timeZone, timeZone)
    }
}
