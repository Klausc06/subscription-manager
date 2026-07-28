import Foundation
@testable import SubscriptionCore
import Testing

@Suite("Fixed billing schedules")
struct FixedBillingScheduleTests {
    @Test("Custom intervals preserve their value and unit when encoded")
    func customIntervalCodableRoundTrip() throws {
        let interval = BillingInterval.custom(value: 7, unit: .week)

        let data = try JSONEncoder().encode(interval)
        let decoded = try JSONDecoder().decode(
            BillingInterval.self,
            from: data
        )

        #expect(decoded == interval)
        #expect(BillingInterval(rawValue: interval.rawValue) == interval)
    }

    @Test("A schedule copy edit preserves the confirmed next renewal")
    func scheduleCopyEditPreservesConfirmedNextRenewal() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let originalAnchor = try date(
            year: 2025,
            month: 1,
            day: 31,
            hour: 12,
            calendar: calendar
        )
        let confirmedNextRenewal = try date(
            year: 2025,
            month: 2,
            day: 28,
            hour: 12,
            calendar: calendar
        )
        let replacementAnchor = try date(
            year: 2025,
            month: 3,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: originalAnchor,
                timeZoneIdentifier: "UTC"
            ),
            confirmedNextRenewal: confirmedNextRenewal
        )

        let input = SubscriptionEditInput(
            subscription: subscription,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: replacementAnchor,
                timeZoneIdentifier: "UTC"
            )
        )

        #expect(input.confirmedNextRenewal == confirmedNextRenewal)
    }

    @Test("The production renewal calendar is Gregorian and locale-stable")
    func productionRenewalCalendarIsPinned() {
        let calendar = SubscriptionWorkspace.defaultRenewalCalendar()

        #expect(calendar.identifier == .gregorian)
        #expect(calendar.locale?.identifier == "en_US_POSIX")
    }

    @Test(
        "Every supported interval produces its next anchored renewal",
        arguments: [
            (BillingInterval.weekly, DateComponents(year: 2025, month: 1, day: 22)),
            (BillingInterval.monthly, DateComponents(year: 2025, month: 2, day: 15)),
            (BillingInterval.quarterly, DateComponents(year: 2025, month: 4, day: 15)),
            (BillingInterval.halfYearly, DateComponents(year: 2025, month: 7, day: 15)),
            (BillingInterval.yearly, DateComponents(year: 2026, month: 1, day: 15)),
            (
                BillingInterval.custom(value: 10, unit: .day),
                DateComponents(year: 2025, month: 1, day: 25)
            ),
            (
                BillingInterval.custom(value: 2, unit: .week),
                DateComponents(year: 2025, month: 1, day: 29)
            ),
            (
                BillingInterval.custom(value: 2, unit: .month),
                DateComponents(year: 2025, month: 3, day: 15)
            ),
            (
                BillingInterval.custom(value: 2, unit: .year),
                DateComponents(year: 2027, month: 1, day: 15)
            ),
        ]
    )
    @MainActor
    func supportedIntervalProducesNextRenewal(
        interval: BillingInterval,
        expectedComponents: DateComponents
    ) throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "Asia/Shanghai")
        let anchor = try date(
            year: 2025,
            month: 1,
            day: 15,
            hour: 9,
            calendar: calendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: interval,
                renewalAnchor: anchor,
                timeZoneIdentifier: "Asia/Shanghai"
            )
        )
        let repository = ScheduleRepository(subscription: subscription)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { anchor },
            calendar: calendar
        )

        workspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: try date(
                year: 2027,
                month: 2,
                day: 1,
                hour: 9,
                calendar: calendar
            ),
            maximumCount: 2
        )

        let charges = try #require(workspace.expectedCharges)
        #expect(charges.count == 2)
        #expect(
            calendar.dateComponents(
                [.year, .month, .day],
                from: charges[1].scheduledDate
            ) == expectedComponents
        )
    }

    @Test("January 31 clamps in February and returns to the original day")
    @MainActor
    func januaryMonthEndDoesNotDrift() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let anchor = try date(
            year: 2025,
            month: 1,
            day: 31,
            hour: 12,
            calendar: calendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: anchor,
                timeZoneIdentifier: "UTC"
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: ScheduleRepository(subscription: subscription),
            now: { anchor },
            calendar: calendar
        )

        workspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: try date(
                year: 2025,
                month: 4,
                day: 30,
                hour: 12,
                calendar: calendar
            )
        )

        #expect(
            try localDays(
                workspace.expectedCharges,
                calendar: calendar
            ) == [
                "2025-01-31",
                "2025-02-28",
                "2025-03-31",
                "2025-04-30",
            ]
        )
    }

    @Test("Creation keeps the next renewal separate from the original anchor")
    @MainActor
    func creationKeepsNextRenewalSeparateFromAnchor() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let anchor = try date(
            year: 2025,
            month: 1,
            day: 31,
            hour: 12,
            calendar: calendar
        )
        let nextRenewal = try date(
            year: 2025,
            month: 2,
            day: 28,
            hour: 12,
            calendar: calendar
        )
        let repository = ScheduleRepository(subscription: nil)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { nextRenewal },
            calendar: calendar
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Standard",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: anchor,
                renewalAnchor: anchor,
                confirmedNextRenewal: nextRenewal,
                billingTimeZoneIdentifier: "UTC",
                managementURL: nil,
                notes: ""
            )
        )
        workspace.loadExpectedCharges(
            subscriptionID: try #require(
                repository.storedSubscription?.id
            ),
            through: try date(
                year: 2025,
                month: 3,
                day: 31,
                hour: 12,
                calendar: calendar
            )
        )

        let created = try #require(repository.storedSubscription)
        #expect(created.billingSchedule.renewalAnchor == anchor)
        #expect(created.confirmedNextRenewal == nextRenewal)
        #expect(
            try localDays(
                workspace.expectedCharges,
                calendar: calendar
            ) == [
                "2025-02-28",
                "2025-03-31",
            ]
        )
    }

    @Test("February 29 yearly renewals return on the next leap year")
    @MainActor
    func leapDayReturnsAfterClampedYears() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let anchor = try date(
            year: 2024,
            month: 2,
            day: 29,
            hour: 12,
            calendar: calendar
        )
        let now = try date(
            year: 2025,
            month: 1,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .yearly,
                renewalAnchor: anchor,
                timeZoneIdentifier: "UTC"
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: ScheduleRepository(subscription: subscription),
            now: { now },
            calendar: calendar
        )

        workspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: try date(
                year: 2028,
                month: 2,
                day: 29,
                hour: 12,
                calendar: calendar
            )
        )

        #expect(
            try localDays(
                workspace.expectedCharges,
                calendar: calendar
            ) == [
                "2025-02-28",
                "2026-02-28",
                "2027-02-28",
                "2028-02-29",
            ]
        )
    }

    @Test("Weekly renewal keeps its local hour across daylight saving time")
    @MainActor
    func weeklyRenewalUsesCalendarDaysAcrossDST() throws {
        let calendar = pinnedCalendar(
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let anchor = try date(
            year: 2025,
            month: 3,
            day: 2,
            hour: 9,
            calendar: calendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .weekly,
                renewalAnchor: anchor,
                timeZoneIdentifier: "America/Los_Angeles"
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: ScheduleRepository(subscription: subscription),
            now: { anchor },
            calendar: calendar
        )

        workspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: try date(
                year: 2025,
                month: 3,
                day: 9,
                hour: 9,
                calendar: calendar
            )
        )

        let charges = try #require(workspace.expectedCharges)
        #expect(charges.count == 2)
        #expect(
            calendar.dateComponents(
                [.year, .month, .day, .hour],
                from: charges[1].scheduledDate
            ) == DateComponents(year: 2025, month: 3, day: 9, hour: 9)
        )
        #expect(
            charges[1].scheduledDate.timeIntervalSince(charges[0].scheduledDate)
                == 167 * 60 * 60
        )
    }

    @Test("Stored time zone wins over injected display locale and time zone")
    @MainActor
    func storedScheduleIsLocaleAndTimeZoneIndependent() throws {
        var creationCalendar = pinnedCalendar(
            timeZoneIdentifier: "America/New_York"
        )
        creationCalendar.locale = Locale(identifier: "en_US_POSIX")
        let anchor = try date(
            year: 2025,
            month: 10,
            day: 31,
            hour: 9,
            calendar: creationCalendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: anchor,
                timeZoneIdentifier: "America/New_York"
            )
        )
        var alternateCalendar = pinnedCalendar(
            timeZoneIdentifier: "Asia/Shanghai"
        )
        alternateCalendar.locale = Locale(identifier: "zh_CN")
        let repository = ScheduleRepository(subscription: subscription)
        let firstWorkspace = SubscriptionWorkspace(
            repository: repository,
            now: { anchor },
            calendar: creationCalendar
        )
        let relaunchedWorkspace = SubscriptionWorkspace(
            repository: repository,
            now: { anchor },
            calendar: alternateCalendar
        )
        let horizon = try date(
            year: 2026,
            month: 1,
            day: 31,
            hour: 9,
            calendar: creationCalendar
        )

        firstWorkspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: horizon
        )
        relaunchedWorkspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: horizon
        )

        let expectedDays = [
            "2025-10-31",
            "2025-11-30",
            "2025-12-31",
            "2026-01-31",
        ]
        #expect(
            try localDays(
                firstWorkspace.expectedCharges,
                calendar: creationCalendar
            ) == expectedDays
        )
        #expect(
            try localDays(
                relaunchedWorkspace.expectedCharges,
                calendar: creationCalendar
            ) == expectedDays
        )
    }

    @Test("Invalid custom intervals are rejected without changing the record")
    @MainActor
    func invalidCustomIntervalIsRejected() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let anchor = try date(
            year: 2025,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: anchor,
                timeZoneIdentifier: "UTC"
            )
        )
        let repository = ScheduleRepository(subscription: subscription)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { anchor },
            calendar: calendar
        )
        let invalidSchedule = FixedBillingSchedule(
            interval: .custom(value: 0, unit: .day),
            renewalAnchor: anchor,
            timeZoneIdentifier: "UTC"
        )

        workspace.editSubscription(
            id: subscription.id,
            input: SubscriptionEditInput(
                subscription: subscription,
                billingSchedule: invalidSchedule
            )
        )

        #expect(
            workspace.editingValidationErrors[.billingSchedule]
                == .mustBePositive
        )
        #expect(repository.storedSubscription == subscription)
    }

    @Test("Beginning another edit clears stale validation errors")
    @MainActor
    func beginningEditClearsStaleValidationErrors() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let anchor = try date(
            year: 2025,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: anchor,
                timeZoneIdentifier: "UTC"
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: ScheduleRepository(subscription: subscription),
            calendar: calendar
        )

        workspace.editSubscription(
            id: subscription.id,
            input: SubscriptionEditInput(
                subscription: subscription,
                billingSchedule: FixedBillingSchedule(
                    interval: .custom(value: 0, unit: .day),
                    renewalAnchor: anchor,
                    timeZoneIdentifier: "UTC"
                )
            )
        )
        #expect(!workspace.editingValidationErrors.isEmpty)

        workspace.beginEditing()

        #expect(workspace.editingValidationErrors.isEmpty)
    }

    @Test("Editing replaces future forecasts and preserves confirmed history")
    @MainActor
    func editRecomputesFutureChargesAndPreservesHistory() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let oldAnchor = try date(
            year: 2025,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let now = try date(
            year: 2025,
            month: 8,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let confirmedCharge = ConfirmedCharge(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            chargedDate: try date(
                year: 2025,
                month: 7,
                day: 1,
                hour: 12,
                calendar: calendar
            ),
            amount: Money(minorUnits: 999, currency: .usd)
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: oldAnchor,
                timeZoneIdentifier: "UTC"
            ),
            confirmedCharges: [confirmedCharge]
        )
        let repository = ScheduleRepository(subscription: subscription)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )
        let newAnchor = try date(
            year: 2025,
            month: 8,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let horizon = try date(
            year: 2025,
            month: 8,
            day: 29,
            hour: 12,
            calendar: calendar
        )

        workspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: horizon
        )
        workspace.editSubscription(
            id: subscription.id,
            input: SubscriptionEditInput(
                subscription: subscription,
                billingSchedule: FixedBillingSchedule(
                    interval: .weekly,
                    renewalAnchor: newAnchor,
                    timeZoneIdentifier: "UTC"
                )
            )
        )

        let edited = try #require(repository.storedSubscription)
        #expect(edited.confirmedCharges == [confirmedCharge])
        #expect(
            try localDays(
                workspace.expectedCharges,
                calendar: calendar
            ) == [
                "2025-08-15",
                "2025-08-22",
                "2025-08-29",
            ]
        )
    }

    @Test("Ordinary edits preserve lifecycle, archive state, and confirmed charges")
    @MainActor
    func ordinaryEditPreservesLifecycleArchiveStateAndConfirmedCharges() throws {
        let calendar = pinnedCalendar(timeZoneIdentifier: "UTC")
        let anchor = try date(
            year: 2025,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let lifecycle = SubscriptionLifecycle.cancelled(
            cancelledAt: try date(
                year: 2025,
                month: 8,
                day: 2,
                hour: 12,
                calendar: calendar
            ),
            accessUntil: try date(
                year: 2025,
                month: 8,
                day: 31,
                hour: 12,
                calendar: calendar
            )
        )
        let confirmedCharge = ConfirmedCharge(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            chargedDate: anchor,
            amount: Money(minorUnits: 999, currency: .usd)
        )
        let subscription = makeSubscription(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: anchor,
                timeZoneIdentifier: "UTC"
            ),
            confirmedCharges: [confirmedCharge],
            lifecycle: lifecycle,
            isArchived: true
        )
        let repository = ScheduleRepository(subscription: subscription)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            calendar: calendar
        )

        workspace.editSubscription(
            id: subscription.id,
            input: SubscriptionEditInput(
                subscription: subscription,
                billingSchedule: FixedBillingSchedule(
                    interval: .weekly,
                    renewalAnchor: anchor,
                    timeZoneIdentifier: "UTC"
                )
            )
        )

        let edited = try #require(repository.storedSubscription)
        #expect(edited.lifecycle == lifecycle)
        #expect(edited.isArchived == true)
        #expect(edited.confirmedCharges == [confirmedCharge])
    }
}

@MainActor
private final class ScheduleRepository: SubscriptionRepository {
    var storedSubscription: Subscription?

    init(subscription: Subscription?) {
        storedSubscription = subscription
    }

    func createSubscription(_ subscription: Subscription) throws {
        storedSubscription = subscription
    }

    func updateSubscription(_ subscription: Subscription) throws {
        storedSubscription = subscription
    }

    func deleteSubscription(id: UUID) throws {
        if storedSubscription?.id == id {
            storedSubscription = nil
        }
    }

    func listSubscriptions() throws -> [Subscription] {
        storedSubscription.map { [$0] } ?? []
    }

    func subscription(id: UUID) throws -> Subscription? {
        storedSubscription?.id == id ? storedSubscription : nil
    }
}

private func makeSubscription(
    schedule: FixedBillingSchedule,
    confirmedNextRenewal: Date? = nil,
    confirmedCharges: [ConfirmedCharge] = [],
    lifecycle: SubscriptionLifecycle = .active,
    isArchived: Bool = false
) -> Subscription {
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    return Subscription(
        id: id,
        serviceIdentity: ServiceIdentity(rawValue: "manual:\(id.uuidString)"),
        serviceName: "Example",
        plan: "Standard",
        category: "Other",
        originalAmount: Money(minorUnits: 999, currency: .usd),
        billingSchedule: schedule,
        startDate: schedule.renewalAnchor,
        confirmedNextRenewal: confirmedNextRenewal,
        managementURL: nil,
        notes: "",
        confirmedCharges: confirmedCharges,
        lifecycle: lifecycle,
        isArchived: isArchived
    )
}

private func pinnedCalendar(timeZoneIdentifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
    return calendar
}

private func date(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    calendar: Calendar
) throws -> Date {
    try #require(
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )
    )
}

private func localDays(
    _ charges: [ExpectedCharge]?,
    calendar: Calendar
) throws -> [String] {
    try #require(charges).map { charge in
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: charge.scheduledDate
        )
        return String(
            format: "%04d-%02d-%02d",
            try #require(components.year),
            try #require(components.month),
            try #require(components.day)
        )
    }
}
