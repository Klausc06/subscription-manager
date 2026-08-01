import SubscriptionCore
import SwiftUI

/// UUID/deep-link-compatible loader for the direct subscription editor.
///
/// The destination intentionally owns no `Form`. Once the requested record is
/// loaded, `EditSubscriptionView` becomes the one editable surface and appends
/// payment-history and lifecycle capabilities to the shared editor sections.
struct SubscriptionDetailView: View {
    let workspace: SubscriptionWorkspace
    let subscriptionID: UUID
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
            EditSubscriptionView(
                workspace: workspace,
                subscription: subscription,
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
                }
            )
            .id(
                "\(subscription.id)-"
                    + "\(subscription.confirmedNextRenewal.timeIntervalSinceReferenceDate)"
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
