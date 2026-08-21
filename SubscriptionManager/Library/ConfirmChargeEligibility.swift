import Foundation
import SubscriptionCore

/// The conditions that make an expected charge available for confirmation.
///
/// This is intentionally pure so presentation code can decide whether to show
/// a confirm action without coupling the decision to workspace or persistence
/// state.
enum ConfirmChargeEligibility {
    static func isEligible(
        expectedOccurrence: ExpectedCharge?,
        confirmedIDs: Set<ScheduledChargeID>,
        now: Date,
        billingTimeZone: TimeZone
    ) -> Bool {
        guard let expectedOccurrence,
              !confirmedIDs.contains(expectedOccurrence.id)
        else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = billingTimeZone
        let today = calendar.startOfDay(for: now)
        let billingDay = calendar.startOfDay(
            for: expectedOccurrence.scheduledDate
        )
        return billingDay <= today
    }
}
