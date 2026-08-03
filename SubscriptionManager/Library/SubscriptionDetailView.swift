import SubscriptionCore
import SwiftUI

/// UUID/deep-link-compatible loader for one subscription presentation.
///
/// The presentation starts with a compact summary and switches that same
/// presentation into the existing editor when the user chooses Edit.
struct SubscriptionDetailView: View {
    private enum DetailMode: Equatable {
        case summary
        case edit
    }

    let workspace: SubscriptionWorkspace
    let subscriptionID: UUID
    @Environment(\.locale) private var locale
    @State private var mode: DetailMode = .summary
    @State private var lifecycleSheet: LifecycleSheet?
    @State private var paymentSheet: PaymentSheet?

    var body: some View {
        detailContent
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
                    case .confirmCharge(
                        let subscription,
                        let expectedOccurrence
                    ):
                        ConfirmChargeView(
                            workspace: workspace,
                            subscription: subscription,
                            expectedOccurrence: expectedOccurrence
                        )
                    }
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

        case let .loaded(subscription, _, _)
            where subscription.id == subscriptionID:
            switch mode {
            case .summary:
                SubscriptionSummaryView(subscription: subscription)
                    .navigationTitle("Subscription")
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(
                                "Edit Subscription",
                                systemImage: "pencil"
                            ) {
                                mode = .edit
                            }
                            .accessibilityIdentifier("subscription.edit")
                        }
                    }

            case .edit:
                EditSubscriptionView(
                    workspace: workspace,
                    subscription: subscription,
                    locale: locale,
                    onRecordCancellation: {
                        lifecycleSheet = .recordCancellation(subscription)
                    },
                    onReactivate: {
                        lifecycleSheet = .reactivate(subscription)
                    },
                    onConfirmCharge: { expectedOccurrence in
                        paymentSheet = .confirmCharge(
                            subscription,
                            expectedOccurrence
                        )
                    },
                    onSave: {
                        mode = .summary
                    },
                    onCancel: {
                        mode = .summary
                    }
                )
                .id(
                    "\(subscription.id)-edit-"
                        + "\(subscription.confirmedNextRenewal.timeIntervalSinceReferenceDate)"
                )
            }

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

private struct SubscriptionSummaryView: View {
    @Environment(\.locale) private var locale

    let subscription: Subscription

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    summaryRow(
                        "Service",
                        value: subscription.serviceName,
                        identifier: "subscription.summary.service"
                    )
                    summaryRow(
                        "Amount",
                        value: amountDescription,
                        identifier: "subscription.summary.amount"
                    )
                    summaryRow(
                        "Billing Interval",
                        value: localizedBillingInterval(
                            subscription.billingSchedule.interval
                        ),
                        identifier: "subscription.summary.interval"
                    )
                    summaryRow(
                        "Next Renewal",
                        value: formattedBillingDate(
                            subscription.confirmedNextRenewal,
                            timeZoneIdentifier: subscription
                                .billingSchedule.timeZoneIdentifier,
                            locale: locale
                        ),
                        identifier: "subscription.summary.next-renewal"
                    )
                    optionalSummaryRow(
                        "Category",
                        value: subscription.category,
                        identifier: "subscription.summary.category"
                    )
                    optionalSummaryRow(
                        "Plan",
                        value: subscription.plan,
                        identifier: "subscription.summary.plan"
                    )
                    optionalSummaryRow(
                        "Note",
                        value: subscription.notes,
                        identifier: "subscription.summary.note"
                    )
                }
                .padding(.vertical, 8)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .accessibilityIdentifier("subscription.summary")
    }

    private var amountDescription: String {
        let amount = subscription.amount(
            onBillingDay: subscription.confirmedNextRenewal
        )
        return "\(formattedMoney(amount)) · \(amount.currency.rawValue)"
    }

    private func summaryRow(
        _ label: LocalizedStringKey,
        value: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func optionalSummaryRow(
        _ label: LocalizedStringKey,
        value: String,
        identifier: String
    ) -> some View {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaryRow(label, value: value, identifier: identifier)
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
    case confirmCharge(Subscription, ExpectedCharge)

    var id: String {
        switch self {
        case .confirmCharge(_, let occurrence):
            "confirm-charge-\(occurrence.id.subscriptionID)-"
                + "\(occurrence.id.year)-\(occurrence.id.month)-"
                + "\(occurrence.id.day)"
        }
    }
}
