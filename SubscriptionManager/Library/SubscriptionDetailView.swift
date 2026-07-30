import SubscriptionCore
import SwiftUI

struct SubscriptionDetailView: View {
    let workspace: SubscriptionWorkspace
    let subscriptionID: UUID
    @State private var subscriptionToEdit: Subscription?
    @State private var lifecycleSheet: LifecycleSheet?
    @State private var paymentSheet: PaymentSheet?
    @State private var subscriptionPendingDeletion: Subscription?
    @State private var directActionError:
        SubscriptionLifecycleActionError?

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
                                    performDirectAction {
                                        workspace.restore(
                                            id: subscription.id
                                        )
                                    }
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
                                        "Confirm Charge",
                                        systemImage: "checkmark.circle"
                                    ) {
                                        paymentSheet = .confirmCharge(subscription)
                                    }
                                    .accessibilityIdentifier("subscription.confirm")

                                    Button(
                                        "Record Price Change",
                                        systemImage: "tag"
                                    ) {
                                        paymentSheet = .recordPriceChange(subscription)
                                    }
                                    .accessibilityIdentifier("subscription.price-change")

                                    Button(
                                        "Record Cancellation",
                                        systemImage: "xmark.circle"
                                    ) {
                                        beginDirectAction()
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
                                        beginDirectAction()
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
                                    performDirectAction {
                                        workspace.archive(
                                            id: subscription.id
                                        )
                                    }
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
                                beginDirectAction()
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
            .sheet(item: $paymentSheet) { sheet in
                NavigationStack {
                    switch sheet {
                    case .confirmCharge(let subscription):
                        ConfirmChargeView(
                            workspace: workspace,
                            subscription: subscription
                        )
                    case .recordPriceChange(let subscription):
                        RecordPriceChangeView(
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
                    performDirectAction {
                        workspace.deletePermanently(id: subscription.id)
                    }
                }
                Button("Cancel", role: .cancel) {
                    subscriptionPendingDeletion = nil
                }
            } message: { _ in
                Text(
                    LocalizedStringKey(
                        "This permanently removes its schedule, notes, "
                            + "lifecycle details, and payment history. This "
                            + "action cannot be undone."
                    )
                )
            }
            .alert(
                "Couldn’t Complete Action",
                isPresented: directActionErrorIsPresented,
                presenting: directActionError
            ) { _ in
                Button("OK") {
                    dismissDirectActionError()
                }
            } message: { error in
                Text(lifecycleActionErrorText(error))
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
                nextExpectedCharge: nextExpectedCharge,
                history: workspace.paymentHistory
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
        return "Permanently Delete “\(subscriptionPendingDeletion.serviceName)” (\(subscriptionPendingDeletion.plan))?"
    }

    private var directActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: {
                directActionError != nil
            },
            set: { isPresented in
                if !isPresented {
                    dismissDirectActionError()
                }
            }
        )
    }

    private func beginDirectAction() {
        directActionError = nil
        workspace.clearLifecycleActionError()
    }

    private func performDirectAction(_ action: () -> Void) {
        beginDirectAction()
        action()
        directActionError = workspace.lifecycleActionError
    }

    private func dismissDirectActionError() {
        directActionError = nil
        workspace.clearLifecycleActionError()
    }
}

private struct SubscriptionDetailForm: View {
    @Environment(\.locale) private var locale

    let subscription: Subscription
    let status: SubscriptionStatus
    let nextExpectedCharge: ExpectedCharge?
    let history: [SubscriptionHistoryEntry]

    private var timeZone: TimeZone {
        billingTimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        )
    }

    private var subscriptionIsTrial: Bool {
        if case .trial = subscription.lifecycle {
            return true
        }
        return false
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

            if !history.isEmpty {
                Section("Payment History") {
                    ForEach(Array(history.enumerated()), id: \.offset) {
                        _, entry in
                        PaymentHistoryRow(
                            entry: entry,
                            timeZoneIdentifier:
                                subscription.billingSchedule.timeZoneIdentifier,
                            locale: locale
                        )
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
                    Text(LocalizedStringKey(
                        billingStartDateLabelKey(
                            isTrial: subscriptionIsTrial
                        )
                    ))
                }
                .accessibilityIdentifier(
                    "subscription.detail.start-date"
                )
                .accessibilityValue(
                    formattedBillingDate(
                        subscription.startDate,
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
                    Text(LocalizedStringKey(
                        billingNextDateLabelKey(
                            isTrial: subscriptionIsTrial
                        )
                    ))
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
                            "Manage or Cancel Subscription",
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

private struct PaymentHistoryRow: View {
    let entry: SubscriptionHistoryEntry
    let timeZoneIdentifier: String
    let locale: Locale

    var body: some View {
        switch entry {
        case .expected(let charge):
            LabeledContent("Expected Charge") {
                Text(formattedMoney(charge.amount))
            }
            .accessibilityIdentifier("subscription.history.expected")
        case .confirmed(let charge):
            LabeledContent("Confirmed Payment") {
                Text(formattedMoney(charge.amount))
            }
            .accessibilityIdentifier("subscription.history.confirmed")
        case .priceChange(let change):
            LabeledContent("Price Change") {
                Text(formattedMoney(change.amount))
            }
            .accessibilityIdentifier("subscription.history.price-change")
        }
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

private enum PaymentSheet: Identifiable {
    case confirmCharge(Subscription)
    case recordPriceChange(Subscription)

    var id: String {
        switch self {
        case .confirmCharge(let subscription):
            "confirm-charge-\(subscription.id)"
        case .recordPriceChange(let subscription):
            "record-price-change-\(subscription.id)"
        }
    }
}
