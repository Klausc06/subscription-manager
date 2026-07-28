import Foundation
import Observation

public enum Currency: String, CaseIterable, Codable, Sendable {
    case cny = "CNY"
    case usd = "USD"
}

public struct Money: Codable, Equatable, Sendable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }
}

public struct ServiceIdentity: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ExpectedCharge: Codable, Equatable, Sendable {
    public let subscriptionID: UUID
    public let scheduledDate: Date
    public let amount: Money

    public init(
        subscriptionID: UUID,
        scheduledDate: Date,
        amount: Money
    ) {
        self.subscriptionID = subscriptionID
        self.scheduledDate = scheduledDate
        self.amount = amount
    }
}

public struct Subscription: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let serviceIdentity: ServiceIdentity
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money
    public let billingSchedule: FixedBillingSchedule
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String
    public let confirmedCharges: [ConfirmedCharge]
    public let lifecycle: SubscriptionLifecycle
    public let isArchived: Bool

    public var billingCycle: BillingInterval {
        billingSchedule.interval
    }

    public init(
        id: UUID,
        serviceIdentity: ServiceIdentity,
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money,
        billingSchedule: FixedBillingSchedule,
        startDate: Date,
        confirmedNextRenewal: Date? = nil,
        managementURL: URL?,
        notes: String,
        confirmedCharges: [ConfirmedCharge] = [],
        lifecycle: SubscriptionLifecycle = .active,
        isArchived: Bool = false
    ) {
        self.id = id
        self.serviceIdentity = serviceIdentity
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.billingSchedule = billingSchedule
        self.startDate = startDate
        self.confirmedNextRenewal =
            confirmedNextRenewal ?? billingSchedule.renewalAnchor
        self.managementURL = managementURL
        self.notes = notes
        self.confirmedCharges = confirmedCharges
        self.lifecycle = lifecycle
        self.isArchived = isArchived
    }

    public init(
        id: UUID,
        serviceIdentity: ServiceIdentity,
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money,
        billingCycle: BillingInterval,
        startDate: Date,
        confirmedNextRenewal: Date,
        billingTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        managementURL: URL?,
        notes: String,
        confirmedCharges: [ConfirmedCharge] = [],
        lifecycle: SubscriptionLifecycle = .active,
        isArchived: Bool = false
    ) {
        self.init(
            id: id,
            serviceIdentity: serviceIdentity,
            serviceName: serviceName,
            plan: plan,
            category: category,
            originalAmount: originalAmount,
            billingSchedule: FixedBillingSchedule(
                interval: billingCycle,
                renewalAnchor: startDate,
                timeZoneIdentifier: billingTimeZoneIdentifier
            ),
            startDate: startDate,
            confirmedNextRenewal: confirmedNextRenewal,
            managementURL: managementURL,
            notes: notes,
            confirmedCharges: confirmedCharges,
            lifecycle: lifecycle,
            isArchived: isArchived
        )
    }
}

public struct SubscriptionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let serviceIdentity: ServiceIdentity
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money
    public let billingSchedule: FixedBillingSchedule
    public let confirmedNextRenewal: Date
    public let status: SubscriptionStatus
    public let nextExpectedCharge: ExpectedCharge?

    public init(
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    ) {
        id = subscription.id
        serviceIdentity = subscription.serviceIdentity
        serviceName = subscription.serviceName
        plan = subscription.plan
        category = subscription.category
        originalAmount = subscription.originalAmount
        billingSchedule = subscription.billingSchedule
        confirmedNextRenewal = subscription.confirmedNextRenewal
        self.status = status
        self.nextExpectedCharge = nextExpectedCharge
    }
}

public struct SubscriptionCreationInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money?
    public let billingInterval: BillingInterval
    public let startDate: Date
    public let renewalAnchor: Date
    public let confirmedNextRenewal: Date
    public let billingTimeZoneIdentifier: String
    public let managementURL: URL?
    public let notes: String
    public let initialStatus: SubscriptionInitialStatus

    public init(
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money?,
        billingInterval: BillingInterval = .monthly,
        startDate: Date,
        renewalAnchor: Date? = nil,
        confirmedNextRenewal: Date,
        billingTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        managementURL: URL?,
        notes: String,
        initialStatus: SubscriptionInitialStatus = .active
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.billingInterval = billingInterval
        self.startDate = startDate
        self.renewalAnchor = renewalAnchor ?? startDate
        self.confirmedNextRenewal = confirmedNextRenewal
        self.billingTimeZoneIdentifier = billingTimeZoneIdentifier
        self.managementURL = managementURL
        self.notes = notes
        self.initialStatus = initialStatus
    }
}

@available(*, deprecated, renamed: "SubscriptionCreationInput")
public typealias MonthlySubscriptionCreationInput = SubscriptionCreationInput

public struct SubscriptionEditInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money?
    public let billingSchedule: FixedBillingSchedule
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String

    public init(
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money?,
        billingSchedule: FixedBillingSchedule,
        startDate: Date,
        confirmedNextRenewal: Date? = nil,
        managementURL: URL?,
        notes: String
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.billingSchedule = billingSchedule
        self.startDate = startDate
        self.confirmedNextRenewal =
            confirmedNextRenewal ?? billingSchedule.renewalAnchor
        self.managementURL = managementURL
        self.notes = notes
    }

    public init(
        subscription: Subscription,
        billingSchedule: FixedBillingSchedule
    ) {
        self.init(
            serviceName: subscription.serviceName,
            plan: subscription.plan,
            category: subscription.category,
            originalAmount: subscription.originalAmount,
            billingSchedule: billingSchedule,
            startDate: subscription.startDate,
            confirmedNextRenewal: subscription.confirmedNextRenewal,
            managementURL: subscription.managementURL,
            notes: subscription.notes
        )
    }
}

public enum SubscriptionCreationField: Hashable, Sendable {
    case serviceName
    case plan
    case category
    case originalAmount
    case renewalAnchor
    case confirmedNextRenewal
    case billingSchedule
}

public enum SubscriptionCreationValidationError: Equatable, Sendable {
    case required
    case mustBePositive
    case beforeStartDate
}

public enum SubscriptionLibraryScope: Hashable, Sendable {
    case current
    case archived
}

public enum SubscriptionLibraryState: Equatable, Sendable {
    case loading(SubscriptionLibraryScope)
    case empty(SubscriptionLibraryScope)
    case loaded(SubscriptionLibraryScope, [SubscriptionSummary])
    case failed(SubscriptionLibraryScope)
}

public enum SubscriptionDetailState: Equatable, Sendable {
    case notLoaded
    case loaded(
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    )
    case notFound
    case failed
}

@MainActor
public protocol SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws
    func updateSubscription(_ subscription: Subscription) throws
    func listSubscriptions() throws -> [Subscription]
    func subscription(id: UUID) throws -> Subscription?
}

@MainActor
@Observable
public final class SubscriptionWorkspace {
    public private(set) var libraryState: SubscriptionLibraryState =
        .loading(.current)
    public private(set) var detailState: SubscriptionDetailState = .notLoaded
    public private(set) var creationValidationErrors:
        [SubscriptionCreationField: SubscriptionCreationValidationError] = [:]
    public private(set) var editingValidationErrors:
        [SubscriptionCreationField: SubscriptionCreationValidationError] = [:]
    public private(set) var expectedCharges: [ExpectedCharge]?

    private let repository: any SubscriptionRepository
    private let identifierGenerator: () -> UUID
    private let now: () -> Date
    private let calendar: Calendar
    private var expectedChargesRequest: ExpectedChargesRequest?

    public init(
        repository: any SubscriptionRepository,
        identifierGenerator: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar? = nil
    ) {
        self.repository = repository
        self.identifierGenerator = identifierGenerator
        self.now = now
        self.calendar = calendar ?? Self.defaultRenewalCalendar()
    }

    nonisolated static func defaultRenewalCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    public func createSubscription(
        _ input: SubscriptionCreationInput
    ) {
        creationValidationErrors = validate(input)
        guard creationValidationErrors.isEmpty,
              let originalAmount = input.originalAmount
        else {
            return
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        let id = identifierGenerator()
        let subscription = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(id.uuidString)"
            ),
            serviceName: input.serviceName.trimmingCharacters(in: whitespace),
            plan: input.plan.trimmingCharacters(in: whitespace),
            category: input.category.trimmingCharacters(in: whitespace),
            originalAmount: originalAmount,
            billingSchedule: FixedBillingSchedule(
                interval: input.billingInterval,
                renewalAnchor: input.renewalAnchor,
                timeZoneIdentifier: input.billingTimeZoneIdentifier
            ),
            startDate: input.startDate,
            confirmedNextRenewal: input.confirmedNextRenewal,
            managementURL: input.managementURL,
            notes: input.notes
        )

        do {
            try repository.createSubscription(subscription)
            detailState = makeDetail(subscription)
            loadLibrary()
        } catch {
            detailState = .failed
        }
    }

    @available(*, deprecated, renamed: "createSubscription")
    public func createMonthlySubscription(
        _ input: SubscriptionCreationInput
    ) {
        createSubscription(input)
    }

    public func editSubscription(
        id: UUID,
        input: SubscriptionEditInput,
        forecastThrough: Date? = nil
    ) {
        editingValidationErrors = validate(input)
        guard editingValidationErrors.isEmpty,
              let originalAmount = input.originalAmount
        else {
            return
        }

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            let whitespace = CharacterSet.whitespacesAndNewlines
            let edited = Subscription(
                id: existing.id,
                serviceIdentity: existing.serviceIdentity,
                serviceName: input.serviceName.trimmingCharacters(
                    in: whitespace
                ),
                plan: input.plan.trimmingCharacters(in: whitespace),
                category: input.category.trimmingCharacters(in: whitespace),
                originalAmount: originalAmount,
                billingSchedule: input.billingSchedule,
                startDate: input.startDate,
                confirmedNextRenewal: input.confirmedNextRenewal,
                managementURL: input.managementURL,
                notes: input.notes,
                confirmedCharges: existing.confirmedCharges,
                lifecycle: existing.lifecycle,
                isArchived: existing.isArchived
            )
            try repository.updateSubscription(edited)
            detailState = makeDetail(edited)
            loadLibrary()
            let forecastRequest = forecastThrough.map {
                ExpectedChargesRequest(
                    subscriptionID: id,
                    horizon: $0,
                    maximumCount: .max
                )
            } ?? expectedChargesRequest
            if let forecastRequest,
               forecastRequest.subscriptionID == id
            {
                expectedCharges = makeExpectedCharges(
                    for: edited,
                    through: forecastRequest.horizon,
                    maximumCount: forecastRequest.maximumCount
                )
                expectedChargesRequest = forecastRequest
            }
        } catch {
            detailState = .failed
        }
    }

    public func loadLibrary(
        scope: SubscriptionLibraryScope = .current
    ) {
        libraryState = .loading(scope)
        do {
            let subscriptions = try repository.listSubscriptions()
                .filter { $0.isArchived == (scope == .archived) }
            let summaries = subscriptions.map(makeSummary)
            libraryState = summaries.isEmpty
                ? .empty(scope)
                : .loaded(scope, summaries)
        } catch {
            libraryState = .failed(scope)
        }
    }

    public func beginEditing() {
        editingValidationErrors = [:]
    }

    public func loadSubscription(id: UUID) {
        do {
            if let subscription = try repository.subscription(id: id) {
                detailState = makeDetail(subscription)
            } else {
                detailState = .notFound
            }
        } catch {
            detailState = .failed
        }
    }

    public func loadExpectedCharges(
        subscriptionID: UUID,
        through horizon: Date,
        maximumCount: Int = .max
    ) {
        expectedChargesRequest = ExpectedChargesRequest(
            subscriptionID: subscriptionID,
            horizon: horizon,
            maximumCount: maximumCount
        )
        do {
            guard let subscription = try repository.subscription(
                id: subscriptionID
            ) else {
                expectedCharges = nil
                return
            }
            expectedCharges = makeExpectedCharges(
                for: subscription,
                through: horizon,
                maximumCount: maximumCount
            )
        } catch {
            expectedCharges = nil
        }
    }

    private func validate(
        _ input: SubscriptionCreationInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.plan.trimmingCharacters(in: whitespace).isEmpty {
            errors[.plan] = .required
        }
        if input.category.trimmingCharacters(in: whitespace).isEmpty {
            errors[.category] = .required
        }
        if let originalAmount = input.originalAmount {
            if originalAmount.minorUnits <= 0 {
                errors[.originalAmount] = .mustBePositive
            }
        } else {
            errors[.originalAmount] = .required
        }
        if input.confirmedNextRenewal < input.startDate {
            errors[.confirmedNextRenewal] = .beforeStartDate
        }
        if input.renewalAnchor < input.startDate {
            errors[.renewalAnchor] = .beforeStartDate
        }
        if !input.billingInterval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingTimeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }

    private func validate(
        _ input: SubscriptionEditInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.plan.trimmingCharacters(in: whitespace).isEmpty {
            errors[.plan] = .required
        }
        if input.category.trimmingCharacters(in: whitespace).isEmpty {
            errors[.category] = .required
        }
        if let originalAmount = input.originalAmount {
            if originalAmount.minorUnits <= 0 {
                errors[.originalAmount] = .mustBePositive
            }
        } else {
            errors[.originalAmount] = .required
        }
        if input.billingSchedule.renewalAnchor < input.startDate {
            errors[.renewalAnchor] = .beforeStartDate
        }
        if input.confirmedNextRenewal < input.startDate {
            errors[.confirmedNextRenewal] = .beforeStartDate
        }
        if !input.billingSchedule.interval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingSchedule.timeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }

    private func makeExpectedCharges(
        for subscription: Subscription,
        through horizon: Date,
        maximumCount: Int
    ) -> [ExpectedCharge] {
        guard maximumCount > 0,
              isEligibleForExpectedCharges(subscription),
              subscription.billingSchedule.interval.isValid,
              let timeZone = TimeZone(
                  identifier: subscription.billingSchedule.timeZoneIdentifier
              )
        else {
            return []
        }

        var renewalCalendar = calendar
        renewalCalendar.timeZone = timeZone
        let currentDate = now()
        let firstForecastDate = max(
            currentDate,
            subscription.confirmedNextRenewal
        )
        var charges: [ExpectedCharge] = []
        var occurrenceIndex = estimatedOccurrenceIndex(
            for: subscription.billingSchedule,
            onOrAfter: firstForecastDate,
            calendar: renewalCalendar
        )

        while charges.count < maximumCount {
            guard let scheduledDate = scheduledDate(
                for: subscription.billingSchedule,
                occurrenceIndex: occurrenceIndex,
                calendar: renewalCalendar
            ) else {
                break
            }
            if scheduledDate > horizon {
                break
            }
            if scheduledDate >= firstForecastDate {
                charges.append(
                    ExpectedCharge(
                        subscriptionID: subscription.id,
                        scheduledDate: scheduledDate,
                        amount: subscription.originalAmount
                    )
                )
            }
            occurrenceIndex += 1
        }

        return charges
    }

    private func makeSummary(
        _ subscription: Subscription
    ) -> SubscriptionSummary {
        let presentation = makePresentation(for: subscription)
        return SubscriptionSummary(
            subscription: subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }

    private func makeDetail(
        _ subscription: Subscription
    ) -> SubscriptionDetailState {
        let presentation = makePresentation(for: subscription)
        return .loaded(
            subscription: subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }

    private func makePresentation(
        for subscription: Subscription
    ) -> (
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    ) {
        let timeZone = TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
        let status = subscription.lifecycle.status(
            asOf: now(),
            timeZone: timeZone
        )
        let nextExpectedCharge = makeExpectedCharges(
            for: subscription,
            through: .distantFuture,
            maximumCount: 1
        ).first
        return (status, nextExpectedCharge)
    }

    private func isEligibleForExpectedCharges(
        _ subscription: Subscription
    ) -> Bool {
        guard !subscription.isArchived else {
            return false
        }
        if case .cancelled = subscription.lifecycle {
            return false
        }
        return true
    }

    private func estimatedOccurrenceIndex(
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

    private func estimatedDayOccurrenceIndex(
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

    private func estimatedMonthOccurrenceIndex(
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

    private func scheduledDate(
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

    private func dayBasedDate(
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

    private func monthBasedDate(
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

    private struct ExpectedChargesRequest {
        let subscriptionID: UUID
        let horizon: Date
        let maximumCount: Int
    }
}
