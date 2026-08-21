import SubscriptionCore
import SwiftUI

func minimumReactivationDate(
    now: Date,
    timeZone: TimeZone
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    let today = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .day, value: 1, to: today)
        ?? .distantFuture
}

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
        "The next renewal must be after today."
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
