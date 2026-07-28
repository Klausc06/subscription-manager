import SubscriptionCore
import SwiftUI

struct SubscriptionDetailView: View {
    let workspace: SubscriptionWorkspace
    let subscriptionID: UUID
    @State private var subscriptionToEdit: Subscription?
    @State private var lifecycleSheet: LifecycleSheet?
    @State private var subscriptionPendingDeletion: Subscription?

    var body: some View {
        detailContent
            .navigationTitle("Subscription Details")
            .toolbar {
                if case .loaded(
                    let subscription,
                    let status,
                    _
                ) = workspace.detailState,
                    subscription.id == subscriptionID
                {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Actions", systemImage: "ellipsis.circle") {
                            if subscription.isArchived {
                                Button(
                                    "Restore",
                                    systemImage: "arrow.uturn.backward"
                                ) {
                                    workspace.restore(id: subscription.id)
                                }
                                .accessibilityIdentifier(
                                    "subscription.lifecycle.restore"
                                )
                            } else {
                                Button("Edit", systemImage: "pencil") {
                                    workspace.beginEditing()
                                    subscriptionToEdit = subscription
                                }
                                .accessibilityIdentifier("subscription.edit")

                                switch status {
                                case .trial, .active:
                                    Button(
                                        "Record Cancellation",
                                        systemImage: "xmark.circle"
                                    ) {
                                        lifecycleSheet = .recordCancellation(
                                            subscription
                                        )
                                    }
                                    .accessibilityIdentifier(
                                        "subscription.lifecycle.record-cancellation"
                                    )

                                case .cancelledWithAccess, .expired:
                                    Button(
                                        "Reactivate",
                                        systemImage: "arrow.clockwise"
                                    ) {
                                        lifecycleSheet = .reactivate(subscription)
                                    }
                                    .accessibilityIdentifier(
                                        "subscription.lifecycle.reactivate"
                                    )
                                }

                                Button(
                                    "Archive",
                                    systemImage: "archivebox"
                                ) {
                                    workspace.archive(id: subscription.id)
                                }
                                .accessibilityIdentifier(
                                    "subscription.lifecycle.archive"
                                )
                            }

                            Button(
                                "Permanently Delete",
                                systemImage: "trash",
                                role: .destructive
                            ) {
                                subscriptionPendingDeletion = subscription
                            }
                            .accessibilityIdentifier(
                                "subscription.lifecycle.delete"
                            )
                        }
                        .accessibilityIdentifier(
                            "subscription.lifecycle.actions"
                        )
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
            .sheet(item: $lifecycleSheet) { sheet in
                NavigationStack {
                    switch sheet {
                    case .recordCancellation(let subscription):
                        RecordCancellationView(
                            workspace: workspace,
                            subscription: subscription
                        )
                    case .reactivate(let subscription):
                        ReactivateSubscriptionView(
                            workspace: workspace,
                            subscription: subscription
                        )
                    }
                }
            }
            .confirmationDialog(
                deletionConfirmationTitle,
                isPresented: Binding(
                    get: {
                        subscriptionPendingDeletion != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            subscriptionPendingDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: subscriptionPendingDeletion
            ) { subscription in
                Button("Delete Permanently", role: .destructive) {
                    subscriptionPendingDeletion = nil
                    workspace.deletePermanently(id: subscription.id)
                }
                Button("Cancel", role: .cancel) {
                    subscriptionPendingDeletion = nil
                }
            } message: { _ in
                Text("This action cannot be undone.")
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

    private var deletionConfirmationTitle: LocalizedStringKey {
        guard let subscriptionPendingDeletion else {
            return "Permanently Delete"
        }
        return "Permanently Delete “\(subscriptionPendingDeletion.serviceName)”?"
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
                    .accessibilityIdentifier(
                        "subscription.detail.expected-charge.date"
                    )
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
                .accessibilityIdentifier(
                    "subscription.detail.renewal-anchor"
                )
                .accessibilityValue(
                    formattedBillingDate(
                        subscription.billingSchedule.renewalAnchor,
                        timeZoneIdentifier:
                            subscription.billingSchedule.timeZoneIdentifier,
                        locale: locale
                    )
                )
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

            if case .cancelled(
                let cancelledAt,
                let accessUntil
            ) = subscription.lifecycle {
                Section("Lifecycle") {
                    LabeledContent {
                        Text(formattedBillingDate(
                            cancelledAt,
                            timeZoneIdentifier:
                                subscription.billingSchedule.timeZoneIdentifier,
                            locale: locale
                        ))
                    } label: {
                        Text("Cancellation Date")
                    }
                    .accessibilityIdentifier(
                        "subscription.detail.cancellation-date"
                    )

                    LabeledContent {
                        Text(formattedBillingDate(
                            accessUntil,
                            timeZoneIdentifier:
                                subscription.billingSchedule.timeZoneIdentifier,
                            locale: locale
                        ))
                    } label: {
                        Text("Access Until")
                    }
                    .accessibilityIdentifier(
                        "subscription.detail.access-until"
                    )
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

private enum LifecycleSheet: Identifiable {
    case recordCancellation(Subscription)
    case reactivate(Subscription)

    var id: String {
        switch self {
        case .recordCancellation(let subscription):
            "record-cancellation-\(subscription.id)"
        case .reactivate(let subscription):
            "reactivate-\(subscription.id)"
        }
    }
}
