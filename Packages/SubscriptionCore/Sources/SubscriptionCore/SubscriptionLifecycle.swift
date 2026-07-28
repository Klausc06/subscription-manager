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

public enum SubscriptionLifecycle: Codable, Equatable, Sendable {
    case trial(firstPaidChargeAt: Date)
    case active
    case cancelled(cancelledAt: Date, accessUntil: Date)

    public func status(
        asOf date: Date,
        timeZone: TimeZone
    ) -> SubscriptionStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
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
