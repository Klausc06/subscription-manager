import Foundation

public enum SubscriptionInitialStatus:
    String, CaseIterable, Hashable, Sendable
{
    case active
    case trial
}

public enum SubscriptionStatus: String, Codable, Equatable, Sendable {
    case trial
    case active
    case cancelledWithAccess
    case expired
}

public enum SubscriptionLifecycleActionError: Equatable, Sendable {
    case invalidLifecycleTransition
    case cancellationDateInFuture
    case accessEndsBeforeCancellation
    case nextRenewalInPast
    case persistenceFailed
}

public enum SubscriptionLifecycle: Codable, Equatable, Sendable {
    case trial(firstPaidChargeAt: Date)
    case active
    case cancelled(cancelledAt: Date, accessUntil: Date)

    public func status(
        asOf date: Date,
        timeZone: TimeZone
    ) -> SubscriptionStatus {
        let calendar = billingLocalCalendar(timeZone: timeZone)
        let day = calendar.startOfDay(for: date)

        switch self {
        case .trial(let firstPaidChargeAt):
            return day >= calendar.startOfDay(for: firstPaidChargeAt)
                ? .active
                : .trial
        case .active:
            return .active
        case .cancelled(_, let accessUntil):
            return day >= calendar.startOfDay(for: accessUntil)
                ? .expired
                : .cancelledWithAccess
        }
    }
}

func billingLocalCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
}

func normalizedBillingLocalNoon(
    _ date: Date,
    timeZone: TimeZone
) -> Date? {
    let calendar = billingLocalCalendar(timeZone: timeZone)
    var components = calendar.dateComponents(
        [.era, .year, .month, .day],
        from: date
    )
    components.hour = 12
    return calendar.date(from: components)
}

extension Subscription {
    func replacingLifecycleFacts(
        lifecycle: SubscriptionLifecycle? = nil,
        isArchived: Bool? = nil,
        confirmedNextRenewal: Date? = nil
    ) -> Subscription {
        Subscription(
            id: id,
            serviceIdentity: serviceIdentity,
            serviceName: serviceName,
            plan: plan,
            category: category,
            originalAmount: originalAmount,
            billingSchedule: billingSchedule,
            startDate: startDate,
            confirmedNextRenewal:
                confirmedNextRenewal ?? self.confirmedNextRenewal,
            managementURL: managementURL,
            notes: notes,
            confirmedCharges: confirmedCharges,
            lifecycle: lifecycle ?? self.lifecycle,
            isArchived: isArchived ?? self.isArchived
        )
    }
}
