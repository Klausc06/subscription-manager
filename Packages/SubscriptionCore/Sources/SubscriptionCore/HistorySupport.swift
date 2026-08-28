import Foundation
import Observation

public enum SubscriptionHistoryEntry: Equatable, Sendable {
    case expected(ExpectedCharge)
    case confirmed(ConfirmedCharge)
    case priceChange(PriceChange)
}

public enum PaymentHistoryActionError: Equatable, Sendable {
    case archivedSubscription
    case invalidScheduledOccurrence
    case scheduledDateInFuture
    case chargedDateInFuture
    case effectiveDateBeforeStart
    case duplicatePriceChangeDay
    case mustBePositive
    case persistenceFailed
}

internal enum HistoryOccurrenceSearch {
    /// Returns the newest unconfirmed past occurrence without crossing the
    /// supplied lower bound. Occurrence dates must move earlier as indexes
    /// decrease so the lower-bound check can terminate the search.
    static func firstUnconfirmedPastOccurrence(
        candidateIndex: Int,
        lowerBoundDay: Date,
        todayDay: Date,
        occurrenceAt: (Int) -> Date?,
        day: (Date) -> Date,
        isConfirmed: (Date) -> Bool
    ) -> Date? {
        var nextIndex = candidateIndex == Int.max
            ? candidateIndex
            : candidateIndex + 1
        while nextIndex >= 0 {
            let occurrenceIndex = nextIndex
            nextIndex = occurrenceIndex == 0 ? -1 : occurrenceIndex - 1
            guard let occurrence = occurrenceAt(occurrenceIndex) else {
                continue
            }
            let occurrenceDay = day(occurrence)
            guard occurrenceDay >= lowerBoundDay else {
                return nil
            }
            guard occurrenceDay <= todayDay,
                  !isConfirmed(occurrence)
            else {
                continue
            }
            return occurrence
        }
        return nil
    }
}
