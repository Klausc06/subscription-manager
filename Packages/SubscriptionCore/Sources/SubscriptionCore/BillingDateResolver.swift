import Foundation

public struct BillingDateResolver: Sendable {
    private static let searchSlack = 8

    public init() {}

    public func nextRenewal(
        afterStart start: Date,
        interval: BillingInterval,
        asOf: Date,
        timeZone: TimeZone
    ) -> Date? {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              asOf.timeIntervalSinceReferenceDate.isFinite,
              interval.isValid,
              let step = calendarStep(for: interval)
        else {
            return nil
        }

        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let asOfDay = calendar.startOfDay(for: asOf)
        var occurrenceIndex = max(
            1,
            estimatedOccurrenceIndex(
                anchor: start,
                onOrAfter: asOfDay,
                step: step,
                calendar: calendar
            )
        )

        for _ in 0 ..< Self.searchSlack {
            guard let occurrence = occurrence(
                anchor: start,
                index: occurrenceIndex,
                step: step,
                calendar: calendar
            )
            else {
                return nil
            }
            if calendar.startOfDay(for: occurrence) > asOfDay {
                return occurrence
            }
            guard occurrenceIndex < Int.max else {
                return nil
            }
            occurrenceIndex += 1
        }
        return nil
    }

    public func expectedOccurrences(
        in range: ClosedRange<Date>,
        schedule: FixedBillingSchedule,
        limit: Int
    ) -> [Date] {
        guard range.lowerBound.timeIntervalSinceReferenceDate.isFinite,
              range.upperBound.timeIntervalSinceReferenceDate.isFinite,
              schedule.renewalAnchor.timeIntervalSinceReferenceDate.isFinite,
              limit > 0,
              schedule.interval.isValid,
              let timeZone = TimeZone(
                  identifier: schedule.timeZoneIdentifier
              ),
              let step = calendarStep(for: schedule.interval)
        else {
            return []
        }

        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        var occurrenceIndex = estimatedOccurrenceIndex(
            anchor: schedule.renewalAnchor,
            onOrAfter: range.lowerBound,
            step: step,
            calendar: calendar
        )
        var results: [Date] = []
        let budgetResult = limit.addingReportingOverflow(
            Self.searchSlack
        )
        let searchBudget = budgetResult.overflow
            ? Int.max
            : budgetResult.partialValue
        var examinedCount = 0

        while results.count < limit, examinedCount < searchBudget {
            guard let date = occurrence(
                anchor: schedule.renewalAnchor,
                index: occurrenceIndex,
                step: step,
                calendar: calendar
            ) else {
                break
            }
            if date > range.upperBound {
                break
            }
            if range.contains(date) {
                results.append(date)
            }
            guard occurrenceIndex < Int.max else { break }
            occurrenceIndex += 1
            examinedCount += 1
        }

        return results
    }

    public func previousCycleStart(
        before renewal: Date,
        interval: BillingInterval,
        timeZone: TimeZone
    ) -> Date? {
        guard renewal.timeIntervalSinceReferenceDate.isFinite,
              interval.isValid,
              let step = calendarStep(for: interval)
        else { return nil }

        let offset = step.value.multipliedReportingOverflow(by: -1)
        guard !offset.overflow else { return nil }

        return BillingCalendar.calendar(timeZone: timeZone).date(
            byAdding: step.component,
            value: offset.partialValue,
            to: renewal
        )
    }

    private func occurrence(
        anchor: Date,
        index: Int,
        step: (component: Calendar.Component, value: Int),
        calendar: Calendar
    ) -> Date? {
        guard index >= 0 else { return nil }
        let offset = step.value.multipliedReportingOverflow(by: index)
        guard !offset.overflow else { return nil }
        return calendar.date(
            byAdding: step.component,
            value: offset.partialValue,
            to: anchor
        )
    }

    private func estimatedOccurrenceIndex(
        anchor: Date,
        onOrAfter target: Date,
        step: (component: Calendar.Component, value: Int),
        calendar: Calendar
    ) -> Int {
        guard target > anchor, step.value > 0 else { return 0 }

        let estimate: Int
        switch step.component {
        case .day:
            let distance = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: anchor),
                to: calendar.startOfDay(for: target)
            ).day ?? 0
            estimate = distance / step.value
        case .weekOfYear:
            let distance = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: anchor),
                to: calendar.startOfDay(for: target)
            ).day ?? 0
            let days = step.value.multipliedReportingOverflow(by: 7)
            guard !days.overflow, days.partialValue > 0 else { return 0 }
            estimate = distance / days.partialValue
        case .month:
            estimate = monthDistance(
                from: anchor,
                to: target,
                calendar: calendar
            ) / step.value
        case .year:
            let months = step.value.multipliedReportingOverflow(by: 12)
            guard !months.overflow, months.partialValue > 0 else { return 0 }
            estimate = monthDistance(
                from: anchor,
                to: target,
                calendar: calendar
            ) / months.partialValue
        default:
            return 0
        }
        return max(0, estimate - 1)
    }

    private func monthDistance(
        from anchor: Date,
        to target: Date,
        calendar: Calendar
    ) -> Int {
        let anchorComponents = calendar.dateComponents(
            [.year, .month],
            from: anchor
        )
        let targetComponents = calendar.dateComponents(
            [.year, .month],
            from: target
        )
        guard let anchorYear = anchorComponents.year,
              let anchorMonth = anchorComponents.month,
              let targetYear = targetComponents.year,
              let targetMonth = targetComponents.month
        else {
            return 0
        }
        let yearDistance = targetYear.subtractingReportingOverflow(anchorYear)
        guard !yearDistance.overflow else { return 0 }
        let yearMonths = yearDistance.partialValue
            .multipliedReportingOverflow(by: 12)
        guard !yearMonths.overflow else { return 0 }
        let monthOffset = targetMonth.subtractingReportingOverflow(anchorMonth)
        guard !monthOffset.overflow else { return 0 }
        let total = yearMonths.partialValue.addingReportingOverflow(
            monthOffset.partialValue
        )
        return total.overflow ? 0 : max(0, total.partialValue)
    }

    private func calendarStep(
        for interval: BillingInterval
    ) -> (component: Calendar.Component, value: Int)? {
        switch interval {
        case .weekly:
            (.weekOfYear, 1)
        case .monthly:
            (.month, 1)
        case .quarterly:
            (.month, 3)
        case .halfYearly:
            (.month, 6)
        case .yearly:
            (.year, 1)
        case .custom(let value, let unit):
            switch unit {
            case .day:
                (.day, value)
            case .week:
                (.weekOfYear, value)
            case .month:
                (.month, value)
            case .year:
                (.year, value)
            }
        }
    }
}
