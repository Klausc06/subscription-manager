import Foundation
import SwiftData
import SubscriptionCore

@MainActor
final class SwiftDataSubscriptionRepository: SubscriptionRepository {
    private let modelContext: ModelContext
    private let save: (ModelContext) throws -> Void
    private let defaultBillingTimeZone: () -> TimeZone
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    convenience init(modelContainer: ModelContainer) {
        self.init(
            modelContainer: modelContainer,
            save: { try $0.save() },
            defaultBillingTimeZone: { .autoupdatingCurrent }
        )
    }

    convenience init(
        modelContainer: ModelContainer,
        defaultBillingTimeZone: @escaping () -> TimeZone
    ) {
        self.init(
            modelContainer: modelContainer,
            save: { try $0.save() },
            defaultBillingTimeZone: defaultBillingTimeZone
        )
    }

    init(
        modelContainer: ModelContainer,
        save: @escaping (ModelContext) throws -> Void,
        defaultBillingTimeZone: @escaping () -> TimeZone = {
            .autoupdatingCurrent
        }
    ) {
        modelContext = ModelContext(modelContainer)
        self.save = save
        self.defaultBillingTimeZone = defaultBillingTimeZone
    }

    func createSubscription(_ subscription: Subscription) throws {
        let record = SubscriptionRecord(id: subscription.id)
        try apply(subscription, to: record)
        modelContext.insert(record)
        do {
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func updateSubscription(_ subscription: Subscription) throws {
        let lookupID = subscription.id
        var descriptor = FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.id == lookupID }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.subscriptionNotFound
        }

        do {
            try apply(subscription, to: record)
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func deleteSubscription(id: UUID) throws {
        let lookupID = id
        var descriptor = FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.id == lookupID }
        )
        descriptor.fetchLimit = 1
        do {
            guard let record = try modelContext.fetch(descriptor).first else {
                return
            }
            modelContext.delete(record)
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func listSubscriptions() throws -> [Subscription] {
        do {
            let records = try modelContext.fetch(
                FetchDescriptor<SubscriptionRecord>()
            )
            var subscriptions: [Subscription] = []
            var needsSave = false
            for record in records {
                let result = try makeSubscription(from: record)
                if let backfill = result.billingTimeZoneBackfill {
                    record.billingTimeZoneIdentifier = backfill
                    needsSave = true
                }
                if let backfill = result.renewalAnchorBackfill {
                    record.renewalAnchor = backfill
                    needsSave = true
                }
                subscriptions.append(result.subscription)
            }
            if needsSave {
                try save(modelContext)
            }
            return subscriptions
                .sorted { $0.id.uuidString < $1.id.uuidString }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func subscription(id: UUID) throws -> Subscription? {
        let lookupID = id
        var descriptor = FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.id == lookupID }
        )
        descriptor.fetchLimit = 1

        do {
            guard let record = try modelContext.fetch(descriptor).first else {
                return nil
            }
            let result = try makeSubscription(from: record)
            if let backfill = result.billingTimeZoneBackfill {
                record.billingTimeZoneIdentifier = backfill
            }
            if let backfill = result.renewalAnchorBackfill {
                record.renewalAnchor = backfill
            }
            if result.billingTimeZoneBackfill != nil
                || result.renewalAnchorBackfill != nil
            {
                try save(modelContext)
            }
            return result.subscription
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func apply(
        _ subscription: Subscription,
        to record: SubscriptionRecord
    ) throws {
        record.serviceIdentityRawValue = subscription.serviceIdentity.rawValue
        record.serviceName = subscription.serviceName
        record.plan = subscription.plan
        record.category = subscription.category
        record.originalMinorUnits = subscription.originalAmount.minorUnits
        record.currencyRawValue = subscription.originalAmount.currency.rawValue
        record.billingCycleRawValue =
            subscription.billingSchedule.interval.storageIdentifier
        record.billingIntervalValue =
            subscription.billingSchedule.interval.customValue
        record.billingIntervalUnitRawValue =
            subscription.billingSchedule.interval.customUnit?.rawValue
        record.billingTimeZoneIdentifier =
            subscription.billingSchedule.timeZoneIdentifier
        record.startDate = subscription.startDate
        record.renewalAnchor = subscription.billingSchedule.renewalAnchor
        record.confirmedNextRenewal = subscription.confirmedNextRenewal
        record.managementURLString =
            subscription.managementURL?.absoluteString
        record.notes = subscription.notes
        record.confirmedChargesData = try encoder.encode(
            subscription.confirmedCharges
        )
        record.priceChangesData = try encoder.encode(subscription.priceChanges)
        record.isArchived = subscription.isArchived
        switch subscription.lifecycle {
        case .active:
            record.lifecycleRawValue = LifecycleStorageKind.active.rawValue
            record.trialFirstPaidChargeAt = nil
            record.cancelledAt = nil
            record.accessUntil = nil
        case .trial(let firstPaidChargeAt):
            record.lifecycleRawValue = LifecycleStorageKind.trial.rawValue
            record.trialFirstPaidChargeAt = firstPaidChargeAt
            record.cancelledAt = nil
            record.accessUntil = nil
        case .cancelled(let cancelledAt, let accessUntil):
            record.lifecycleRawValue = LifecycleStorageKind.cancelled.rawValue
            record.trialFirstPaidChargeAt = nil
            record.cancelledAt = cancelledAt
            record.accessUntil = accessUntil
        }
    }

    private func makeSubscription(
        from record: SubscriptionRecord
    ) throws -> (
        subscription: Subscription,
        billingTimeZoneBackfill: String?,
        renewalAnchorBackfill: Date?
    ) {
        let serviceIdentityRawValue = record.serviceIdentityRawValue.isEmpty
            ? "manual:\(record.id.uuidString)"
            : record.serviceIdentityRawValue
        let managementURL = record.managementURLString.flatMap { value in
            value.isEmpty ? nil : URL(string: value)
        }
        let interval: BillingInterval
        if record.billingCycleRawValue == "custom",
           let value = record.billingIntervalValue,
           value > 0,
           let unitRawValue = record.billingIntervalUnitRawValue,
           let unit = BillingIntervalUnit(rawValue: unitRawValue)
        {
            interval = .custom(value: value, unit: unit)
        } else {
            interval = BillingInterval(
                rawValue: record.billingCycleRawValue
            ) ?? .monthly
        }
        let storedTimeZoneIdentifier =
            record.billingTimeZoneIdentifier.flatMap {
                TimeZone(identifier: $0) == nil ? nil : $0
            }
        let timeZoneIdentifier =
            storedTimeZoneIdentifier ?? defaultBillingTimeZone().identifier
        let renewalAnchor = record.renewalAnchor
            ?? inferredRenewalAnchor(
                from: record,
                timeZoneIdentifier: timeZoneIdentifier
            )
        let confirmedCharges: [ConfirmedCharge]
        if let data = record.confirmedChargesData {
            confirmedCharges = try decoder.decode(
                [ConfirmedCharge].self,
                from: data
            )
        } else {
            confirmedCharges = []
        }
        let priceChanges: [PriceChange]
        if let data = record.priceChangesData {
            priceChanges = try decoder.decode([PriceChange].self, from: data)
        } else {
            priceChanges = []
        }
        let lifecycle = try makeLifecycle(from: record)

        let subscription = Subscription(
            id: record.id,
            serviceIdentity: ServiceIdentity(
                rawValue: serviceIdentityRawValue
            ),
            serviceName: record.serviceName,
            plan: record.plan,
            category: record.category,
            originalAmount: Money(
                minorUnits: record.originalMinorUnits,
                currency: Currency(rawValue: record.currencyRawValue) ?? .usd
            ),
            billingSchedule: FixedBillingSchedule(
                interval: interval,
                renewalAnchor: renewalAnchor,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            startDate: record.startDate,
            confirmedNextRenewal: record.confirmedNextRenewal,
            managementURL: managementURL,
            notes: record.notes ?? "",
            confirmedCharges: confirmedCharges,
            priceChanges: priceChanges,
            lifecycle: lifecycle,
            isArchived: record.isArchived ?? false
        )
        return (
            subscription: subscription,
            billingTimeZoneBackfill: storedTimeZoneIdentifier == nil
                ? timeZoneIdentifier
                : nil,
            renewalAnchorBackfill: record.renewalAnchor == nil
                ? renewalAnchor
                : nil
        )
    }

    private func makeLifecycle(
        from record: SubscriptionRecord
    ) throws -> SubscriptionLifecycle {
        guard let rawValue = record.lifecycleRawValue else {
            guard record.trialFirstPaidChargeAt == nil,
                  record.cancelledAt == nil,
                  record.accessUntil == nil
            else {
                throw RepositoryError.invalidLifecycleStorage
            }
            return .active
        }
        guard let kind = LifecycleStorageKind(rawValue: rawValue) else {
            throw RepositoryError.invalidLifecycleStorage
        }
        switch (
            kind,
            record.trialFirstPaidChargeAt,
            record.cancelledAt,
            record.accessUntil
        ) {
        case (.active, nil, nil, nil):
            return .active
        case (.trial, let firstPaidChargeAt?, nil, nil):
            return .trial(firstPaidChargeAt: firstPaidChargeAt)
        case (
            .cancelled,
            nil,
            let cancelledAt?,
            let accessUntil?
        ) where accessUntil >= cancelledAt:
            return .cancelled(
                cancelledAt: cancelledAt,
                accessUntil: accessUntil
            )
        default:
            throw RepositoryError.invalidLifecycleStorage
        }
    }

    private func inferredRenewalAnchor(
        from record: SubscriptionRecord,
        timeZoneIdentifier: String
    ) -> Date {
        guard record.billingCycleRawValue == BillingInterval.monthly.rawValue,
              record.confirmedNextRenewal >= record.startDate,
              let timeZone = TimeZone(identifier: timeZoneIdentifier)
        else {
            return record.confirmedNextRenewal
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let start = calendar.dateComponents(
            [.year, .month],
            from: record.startDate
        )
        let renewal = calendar.dateComponents(
            [.year, .month],
            from: record.confirmedNextRenewal
        )
        guard let startYear = start.year,
              let startMonth = start.month,
              let renewalYear = renewal.year,
              let renewalMonth = renewal.month
        else {
            return record.confirmedNextRenewal
        }
        let monthOffset =
            (renewalYear - startYear) * 12 + renewalMonth - startMonth
        guard monthOffset >= 0,
              let projectedDate = clampedMonthDate(
                  from: record.startDate,
                  monthOffset: monthOffset,
                  calendar: calendar
              )
        else {
            return record.confirmedNextRenewal
        }
        let projectedDay = calendar.dateComponents(
            [.year, .month, .day],
            from: projectedDate
        )
        let renewalDay = calendar.dateComponents(
            [.year, .month, .day],
            from: record.confirmedNextRenewal
        )
        guard projectedDay == renewalDay else {
            return record.confirmedNextRenewal
        }
        return anchor(
            record.startDate,
            alignedToTimeOfDayIn: record.confirmedNextRenewal,
            calendar: calendar
        ) ?? record.startDate
    }

    private func anchor(
        _ anchor: Date,
        alignedToTimeOfDayIn reference: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: anchor
        )
        let time = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: reference
        )
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components)
    }

    private func clampedMonthDate(
        from anchor: Date,
        monthOffset: Int,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents(
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
        guard let anchorYear = components.year,
              let anchorMonth = components.month,
              let anchorDay = components.day
        else {
            return nil
        }
        let monthIndex = anchorMonth - 1 + monthOffset
        components.year = anchorYear + monthIndex / 12
        components.month = monthIndex % 12 + 1
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components),
              let days = calendar.range(
                  of: .day,
                  in: .month,
                  for: firstOfMonth
              )
        else {
            return nil
        }
        components.day = min(anchorDay, days.count)
        return calendar.date(from: components)
    }

    enum RepositoryError: Error {
        case invalidLifecycleStorage
        case subscriptionNotFound
    }

    private enum LifecycleStorageKind: String {
        case active
        case trial
        case cancelled
    }
}

@MainActor
final class SwiftDataUserPreferencesRepository: UserPreferencesRepository {
    private let modelContext: ModelContext
    private let save: (ModelContext) throws -> Void

    convenience init(modelContainer: ModelContainer) {
        self.init(
            modelContainer: modelContainer,
            save: { try $0.save() }
        )
    }

    init(
        modelContainer: ModelContainer,
        save: @escaping (ModelContext) throws -> Void
    ) {
        modelContext = ModelContext(modelContainer)
        self.save = save
    }

    func loadPreferences() throws -> UserPreferences? {
        do {
            var descriptor = FetchDescriptor<UserPreferencesRecord>()
            descriptor.fetchLimit = 1
            guard let record = try modelContext.fetch(descriptor).first else {
                return nil
            }
            return UserPreferences(
                primaryCurrency: Currency(
                    rawValue: record.primaryCurrencyRawValue
                ) ?? .cny,
                calendarProjectionHorizon: CalendarProjectionHorizon(
                    rawValue: record.calendarProjectionHorizonMonths
                ) ?? .twelveMonths,
                setupStatus: SetupStatus(rawValue: record.setupStatusRawValue)
                    ?? .notCompleted
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        do {
            var descriptor = FetchDescriptor<UserPreferencesRecord>()
            descriptor.fetchLimit = 1
            let record = try modelContext.fetch(descriptor).first
                ?? UserPreferencesRecord()
            if record.modelContext == nil {
                modelContext.insert(record)
            }
            record.primaryCurrencyRawValue = preferences.primaryCurrency.rawValue
            record.calendarProjectionHorizonMonths =
                preferences.calendarProjectionHorizon.rawValue
            record.setupStatusRawValue = preferences.setupStatus.rawValue
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
