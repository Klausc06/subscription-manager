import Foundation
import Observation

extension SubscriptionWorkspace {
    func estimatedOccurrenceIndex(
        for schedule: FixedBillingSchedule,
        onOrAfter targetDate: Date,
        calendar: Calendar
    ) -> Int {
        guard targetDate > schedule.renewalAnchor else {
            return 0
        }

        let estimate: Int
        switch schedule.interval {
        case .weekly:
            estimate = estimatedDayOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalDays: 7,
                calendar: calendar
            )
        case .monthly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 1,
                calendar: calendar
            )
        case .quarterly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 3,
                calendar: calendar
            )
        case .halfYearly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 6,
                calendar: calendar
            )
        case .yearly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 12,
                calendar: calendar
            )
        case .custom(let value, let unit):
            switch unit {
            case .day:
                estimate = estimatedDayOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalDays: value,
                    calendar: calendar
                )
            case .week:
                let (days, overflow) = value.multipliedReportingOverflow(
                    by: 7
                )
                guard !overflow else {
                    return 0
                }
                estimate = estimatedDayOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalDays: days,
                    calendar: calendar
                )
            case .month:
                estimate = estimatedMonthOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalMonths: value,
                    calendar: calendar
                )
            case .year:
                let (months, overflow) = value.multipliedReportingOverflow(
                    by: 12
                )
                guard !overflow else {
                    return 0
                }
                estimate = estimatedMonthOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalMonths: months,
                    calendar: calendar
                )
            }
        }

        return max(0, estimate - 1)
    }
    func estimatedDayOccurrenceIndex(
        anchor: Date,
        targetDate: Date,
        intervalDays: Int,
        calendar: Calendar
    ) -> Int {
        guard intervalDays > 0 else {
            return 0
        }
        let dayDistance = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchor),
            to: calendar.startOfDay(for: targetDate)
        ).day ?? 0
        return max(0, dayDistance / intervalDays)
    }
    func estimatedMonthOccurrenceIndex(
        anchor: Date,
        targetDate: Date,
        intervalMonths: Int,
        calendar: Calendar
    ) -> Int {
        guard intervalMonths > 0 else {
            return 0
        }
        let anchorComponents = calendar.dateComponents(
            [.year, .month],
            from: anchor
        )
        let targetComponents = calendar.dateComponents(
            [.year, .month],
            from: targetDate
        )
        guard let anchorYear = anchorComponents.year,
              let anchorMonth = anchorComponents.month,
              let targetYear = targetComponents.year,
              let targetMonth = targetComponents.month
        else {
            return 0
        }
        let monthDistance =
            (targetYear - anchorYear) * 12 + targetMonth - anchorMonth
        return max(0, monthDistance / intervalMonths)
    }
    func scheduledDate(
        for schedule: FixedBillingSchedule,
        occurrenceIndex: Int,
        calendar: Calendar
    ) -> Date? {
        guard occurrenceIndex >= 0 else {
            return nil
        }

        switch schedule.interval {
        case .weekly:
            return dayBasedDate(
                anchor: schedule.renewalAnchor,
                intervalDays: 7,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .monthly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 1,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .quarterly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 3,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .halfYearly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 6,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .yearly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 12,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .custom(let value, let unit):
            guard value > 0 else {
                return nil
            }
            switch unit {
            case .day:
                return dayBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalDays: value,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            case .week:
                let (days, overflow) = value.multipliedReportingOverflow(by: 7)
                guard !overflow else {
                    return nil
                }
                return dayBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalDays: days,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            case .month:
                return monthBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalMonths: value,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            case .year:
                let (months, overflow) = value.multipliedReportingOverflow(
                    by: 12
                )
                guard !overflow else {
                    return nil
                }
                return monthBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalMonths: months,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            }
        }
    }
    func dayBasedDate(
        anchor: Date,
        intervalDays: Int,
        occurrenceIndex: Int,
        calendar: Calendar
    ) -> Date? {
        let (days, overflow) = intervalDays.multipliedReportingOverflow(
            by: occurrenceIndex
        )
        guard !overflow else {
            return nil
        }
        return calendar.date(byAdding: .day, value: days, to: anchor)
    }
    func monthBasedDate(
        anchor: Date,
        intervalMonths: Int,
        occurrenceIndex: Int,
        calendar: Calendar
    ) -> Date? {
        let (monthOffset, offsetOverflow) =
            intervalMonths.multipliedReportingOverflow(by: occurrenceIndex)
        guard !offsetOverflow else {
            return nil
        }
        var anchorComponents = calendar.dateComponents(
            [
                .era,
                .year,
                .month,
                .day,
                .hour,
                .minute,
                .second,
                .nanosecond,
            ],
            from: anchor
        )
        guard let anchorYear = anchorComponents.year,
              let anchorMonth = anchorComponents.month,
              let anchorDay = anchorComponents.day
        else {
            return nil
        }
        let (monthIndex, indexOverflow) = (anchorMonth - 1)
            .addingReportingOverflow(monthOffset)
        guard !indexOverflow else {
            return nil
        }
        let targetYearOffset = monthIndex / 12
        let (targetYear, yearOverflow) = anchorYear.addingReportingOverflow(
            targetYearOffset
        )
        guard !yearOverflow else {
            return nil
        }
        let targetMonth = monthIndex % 12 + 1
        anchorComponents.year = targetYear
        anchorComponents.month = targetMonth
        anchorComponents.day = 1
        guard let firstOfTargetMonth = calendar.date(from: anchorComponents),
              let dayRange = calendar.range(
                  of: .day,
                  in: .month,
                  for: firstOfTargetMonth
              )
        else {
            return nil
        }
        anchorComponents.day = min(anchorDay, dayRange.count)
        return calendar.date(from: anchorComponents)
    }
    func billingTimeZone(
        for subscription: Subscription
    ) -> TimeZone {
        TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
    }
    func expectedCharge(
        for subscription: Subscription,
        scheduledDate: Date,
        calendar: Calendar
    ) -> ExpectedCharge {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: scheduledDate
        )
        let id = ScheduledChargeID(
            subscriptionID: subscription.id,
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
        let amount = subscription.amount(onBillingDay: scheduledDate)
        return ExpectedCharge(
            id: id,
            subscriptionID: subscription.id,
            scheduledDate: scheduledDate,
            amount: amount
        )
    }
    func isScheduledOccurrence(
        _ date: Date,
        for subscription: Subscription,
        calendar: Calendar
    ) -> Bool {
        guard date >= subscription.startDate else {
            return false
        }
        let firstCandidateIndex = estimatedOccurrenceIndex(
            for: subscription.billingSchedule,
            onOrAfter: date,
            calendar: calendar
        )
        // The estimate is deliberately conservative so forecasting can find
        // the first occurrence on or after a boundary. Check that candidate
        // and the immediately following one when validating a user-selected
        // past occurrence.
        for occurrenceIndex in firstCandidateIndex...(firstCandidateIndex + 1) {
            guard let occurrence = scheduledDate(
                for: subscription.billingSchedule,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            ) else {
                continue
            }
            if calendar.isDate(occurrence, inSameDayAs: date) {
                return true
            }
        }
        return false
    }
}
