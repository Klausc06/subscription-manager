import SubscriptionCore
import SwiftUI

func subscriptionStatusLocalizationKey(
    _ status: SubscriptionStatus
) -> String {
    switch status {
    case .active:
        "Active"
    case .trial:
        "Trial"
    case .cancelledWithAccess:
        "Cancelled with Access"
    case .expired:
        "Expired"
    }
}

func localizedSubscriptionStatus(
    _ status: SubscriptionStatus
) -> String {
    String(
        localized: String.LocalizationValue(
            subscriptionStatusLocalizationKey(status)
        )
    )
}

func lifecycleActionErrorText(
    _ error: SubscriptionLifecycleActionError
) -> LocalizedStringKey {
    LocalizedStringKey(lifecycleActionErrorTextKey(error))
}

func lifecycleActionErrorTextKey(
    _ error: SubscriptionLifecycleActionError
) -> String {
    switch error {
    case .invalidLifecycleTransition:
        "This action isn’t available for the subscription’s current status."
    case .cancellationDateInFuture:
        "The cancellation date cannot be in the future."
    case .accessEndsBeforeCancellation:
        "Access Until cannot be before the cancellation date."
    case .nextRenewalInPast:
        "The next renewal cannot be in the past."
    case .persistenceFailed:
        "Couldn’t save lifecycle changes. Try again."
    }
}

struct SubscriptionStatusBadge: View {
    let status: SubscriptionStatus

    var body: some View {
        Text(localizedSubscriptionStatus(status))
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("subscription.status")
    }
}
