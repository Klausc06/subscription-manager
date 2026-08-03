import Foundation
import OSLog
import SwiftData
import SubscriptionCore

@MainActor
final class SwiftDataSubscriptionRepository: SubscriptionRepository {
    private static let logger = Logger(
        subsystem: "com.klausc06.SubscriptionManager",
        category: "persistence"
    )
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let save: (ModelContext) throws -> Void
    private let defaultBillingTimeZone: () -> TimeZone
    private let appendOrderDate: () -> Date
    private let decoder = JSONDecoder()
    private var priceChangeSnapshots: [UUID: [UUID: PriceChange]] = [:]

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
        },
        appendOrderDate: @escaping () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        modelContext = ModelContext(modelContainer)
        self.save = save
        self.defaultBillingTimeZone = defaultBillingTimeZone
        self.appendOrderDate = appendOrderDate
    }

    func createSubscription(_ subscription: Subscription) throws {
        let record = SubscriptionRecord(id: subscription.id)
        modelContext.insert(record)
        do {
            try apply(subscription, to: record)
            try save(modelContext)
            rememberPriceChanges(for: subscription)
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
            try migrateLegacyHistoryIfNeeded(for: record)
            let stalePriceChangeIDs = try stalePriceChangeIDs(
                for: subscription
            )
            try apply(
                subscription,
                to: record,
                preservingPriceChangeIDs: stalePriceChangeIDs
            )
            try save(modelContext)
            try rememberCurrentPriceChanges(for: subscription.id)
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
            let charges = try modelContext.fetch(
                FetchDescriptor<ConfirmedChargeRecord>()
            ).filter { belongsTo($0, subscriptionID: id) }
            let priceChanges = try modelContext.fetch(
                FetchDescriptor<PriceChangeRecord>()
            ).filter { belongsTo($0, subscriptionID: id) }
            for charge in charges {
                modelContext.delete(charge)
            }
            for priceChange in priceChanges {
                modelContext.delete(priceChange)
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
                do {
                    if try migrateLegacyHistoryIfNeeded(for: record) {
                        needsSave = true
                    }
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
                    rememberPriceChanges(for: result.subscription)
                } catch {
                    Self.logger.error(
                        "Skipping unreadable subscription record \(record.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                }
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
            var needsSave = try migrateLegacyHistoryIfNeeded(for: record)
            let result = try makeSubscription(from: record)
            if let backfill = result.billingTimeZoneBackfill {
                record.billingTimeZoneIdentifier = backfill
                needsSave = true
            }
            if let backfill = result.renewalAnchorBackfill {
                record.renewalAnchor = backfill
                needsSave = true
            }
            if needsSave {
                try save(modelContext)
            }
            rememberPriceChanges(for: result.subscription)
            return result.subscription
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func apply(
        _ subscription: Subscription,
        to record: SubscriptionRecord,
        preservingPriceChangeIDs: Set<UUID> = []
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
        try mergeConfirmedCharges(
            subscription.confirmedCharges,
            into: record,
            in: modelContext
        )
        try mergePriceChanges(
            subscription.priceChanges,
            into: record,
            in: modelContext,
            preservingIDs: preservingPriceChangeIDs
        )
        record.confirmedChargesData = nil
        record.priceChangesData = nil
        record.isArchived = subscription.isArchived
        record.pinnedAt = subscription.pinnedAt
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
        let confirmedCharges = try confirmedCharges(
            for: record,
            in: modelContext
        )
        let priceChanges = try priceChanges(
            for: record,
            in: modelContext
        )
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
            isArchived: record.isArchived ?? false,
            pinnedAt: record.pinnedAt
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

    private func migrateLegacyHistoryIfNeeded(
        for record: SubscriptionRecord
    ) throws -> Bool {
        let legacyCharges: [ConfirmedCharge]?
        if let data = record.confirmedChargesData {
            legacyCharges = try decoder.decode([ConfirmedCharge].self, from: data)
        } else {
            legacyCharges = nil
        }
        let legacyPriceChanges: [PriceChange]?
        if let data = record.priceChangesData {
            legacyPriceChanges = try decoder.decode(
                [PriceChange].self,
                from: data
            )
        } else {
            legacyPriceChanges = nil
        }

        guard legacyCharges != nil || legacyPriceChanges != nil else {
            return false
        }
        if let legacyCharges {
            try mergeConfirmedCharges(
                legacyCharges,
                into: record,
                in: modelContext,
                preserveInputOrderWhenEmpty: true
            )
            record.confirmedChargesData = nil
        }
        if let legacyPriceChanges {
            try mergePriceChanges(
                legacyPriceChanges,
                into: record,
                in: modelContext,
                preserveInputOrderWhenEmpty: true
            )
            record.priceChangesData = nil
        }
        return true
    }

    private func mergeConfirmedCharges(
        _ charges: [ConfirmedCharge],
        into record: SubscriptionRecord,
        in context: ModelContext,
        preserveInputOrderWhenEmpty: Bool = false
    ) throws {
        let storedRecords = try context.fetch(
            FetchDescriptor<ConfirmedChargeRecord>()
        ).filter {
            $0.subscriptionID == record.id
                || ($0.subscriptionID == nil
                    && $0.subscription?.id == record.id)
        }
        for storedRecord in storedRecords where storedRecord.subscriptionID == nil {
            storedRecord.subscriptionID = record.id
        }
        var recordsByID: [UUID: ConfirmedChargeRecord] = [:]
        for storedRecord in storedRecords
            where recordsByID[storedRecord.id] == nil
        {
            recordsByID[storedRecord.id] = storedRecord
        }
        var nextSequence = (storedRecords.map(\.sequence).max() ?? -1) + 1
        for (index, charge) in charges.enumerated() {
            guard recordsByID[charge.id] == nil else { continue }
            let sequence: Int
            if preserveInputOrderWhenEmpty && storedRecords.isEmpty {
                sequence = index
            } else {
                sequence = nextSequence
                nextSequence += 1
            }
            let source = charge.sourceScheduledChargeID
            let storedRecord = ConfirmedChargeRecord(
                id: charge.id,
                sequence: sequence,
                appendOrderDate: appendOrderDate(),
                chargedDate: charge.chargedDate,
                amountMinorUnits: charge.amount.minorUnits,
                currencyRawValue: charge.amount.currency.rawValue,
                sourceScheduledChargeSubscriptionID: source?.subscriptionID,
                sourceScheduledChargeYear: source?.year,
                sourceScheduledChargeMonth: source?.month,
                sourceScheduledChargeDay: source?.day,
                subscriptionID: record.id,
                subscription: record
            )
            context.insert(storedRecord)
            recordsByID[charge.id] = storedRecord
        }
    }

    private func mergePriceChanges(
        _ changes: [PriceChange],
        into record: SubscriptionRecord,
        in context: ModelContext,
        preserveInputOrderWhenEmpty: Bool = false,
        preservingIDs: Set<UUID> = []
    ) throws {
        let storedRecords = try context.fetch(
            FetchDescriptor<PriceChangeRecord>()
        ).filter {
            $0.subscriptionID == record.id
                || ($0.subscriptionID == nil
                    && $0.subscription?.id == record.id)
        }
        for storedRecord in storedRecords where storedRecord.subscriptionID == nil {
            storedRecord.subscriptionID = record.id
        }
        var recordsByID: [UUID: PriceChangeRecord] = [:]
        for storedRecord in storedRecords
            where recordsByID[storedRecord.id] == nil
        {
            recordsByID[storedRecord.id] = storedRecord
        }
        var nextSequence = (storedRecords.map(\.sequence).max() ?? -1) + 1
        for (index, change) in changes.enumerated() {
            if let storedRecord = recordsByID[change.id] {
                guard !preservingIDs.contains(change.id) else { continue }
                storedRecord.effectiveDate = change.effectiveDate
                storedRecord.amountMinorUnits = change.amount.minorUnits
                storedRecord.currencyRawValue = change.amount.currency.rawValue
                continue
            }
            let sequence: Int
            if preserveInputOrderWhenEmpty && storedRecords.isEmpty {
                sequence = index
            } else {
                sequence = nextSequence
                nextSequence += 1
            }
            let storedRecord = PriceChangeRecord(
                id: change.id,
                sequence: sequence,
                appendOrderDate: appendOrderDate(),
                effectiveDate: change.effectiveDate,
                amountMinorUnits: change.amount.minorUnits,
                currencyRawValue: change.amount.currency.rawValue,
                subscriptionID: record.id,
                subscription: record
            )
            context.insert(storedRecord)
            recordsByID[change.id] = storedRecord
        }
    }

    private func confirmedCharges(
        for record: SubscriptionRecord,
        in context: ModelContext
    ) throws -> [ConfirmedCharge] {
        try context.fetch(FetchDescriptor<ConfirmedChargeRecord>())
            .filter { belongsTo($0, subscriptionID: record.id) }
            .sorted {
                if $0.sequence != $1.sequence {
                    return $0.sequence < $1.sequence
                }
                if $0.appendOrderDate != $1.appendOrderDate {
                    return $0.appendOrderDate < $1.appendOrderDate
                }
                return $0.persistentModelID < $1.persistentModelID
            }
            .map { storedRecord in
                let source: ScheduledChargeID?
                if let subscriptionID =
                    storedRecord.sourceScheduledChargeSubscriptionID,
                   let year = storedRecord.sourceScheduledChargeYear,
                   let month = storedRecord.sourceScheduledChargeMonth,
                   let day = storedRecord.sourceScheduledChargeDay
                {
                    source = ScheduledChargeID(
                        subscriptionID: subscriptionID,
                        year: year,
                        month: month,
                        day: day
                    )
                } else {
                    source = nil
                }
                return ConfirmedCharge(
                    id: storedRecord.id,
                    chargedDate: storedRecord.chargedDate,
                    amount: Money(
                        minorUnits: storedRecord.amountMinorUnits,
                        currency: Currency(
                            rawValue: storedRecord.currencyRawValue
                        ) ?? .usd
                    ),
                    sourceScheduledChargeID: source
                )
            }
    }

    private func priceChanges(
        for record: SubscriptionRecord,
        in context: ModelContext
    ) throws -> [PriceChange] {
        try context.fetch(FetchDescriptor<PriceChangeRecord>())
            .filter { belongsTo($0, subscriptionID: record.id) }
            .sorted {
                if $0.sequence != $1.sequence {
                    return $0.sequence < $1.sequence
                }
                if $0.appendOrderDate != $1.appendOrderDate {
                    return $0.appendOrderDate < $1.appendOrderDate
                }
                return $0.persistentModelID < $1.persistentModelID
            }
            .map { storedRecord in
                PriceChange(
                    id: storedRecord.id,
                    effectiveDate: storedRecord.effectiveDate,
                    amount: Money(
                        minorUnits: storedRecord.amountMinorUnits,
                        currency: Currency(
                            rawValue: storedRecord.currencyRawValue
                        ) ?? .usd
                    )
                )
            }
    }

    private func belongsTo(
        _ record: ConfirmedChargeRecord,
        subscriptionID: UUID
    ) -> Bool {
        record.subscriptionID == subscriptionID
            || (record.subscriptionID == nil
                && record.subscription?.id == subscriptionID)
    }

    private func belongsTo(
        _ record: PriceChangeRecord,
        subscriptionID: UUID
    ) -> Bool {
        record.subscriptionID == subscriptionID
            || (record.subscriptionID == nil
                && record.subscription?.id == subscriptionID)
    }

    private func stalePriceChangeIDs(
        for subscription: Subscription
    ) throws -> Set<UUID> {
        guard let snapshot = priceChangeSnapshots[subscription.id] else {
            return []
        }
        let current = try currentPriceChanges(for: subscription.id)
        let currentByID = Dictionary(
            uniqueKeysWithValues: current.map { ($0.id, $0) }
        )
        return Set(
            snapshot.compactMap { id, observed in
                currentByID[id] == observed ? nil : id
            }
        )
    }

    private func currentPriceChanges(
        for subscriptionID: UUID
    ) throws -> [PriceChange] {
        let context = ModelContext(modelContainer)
        let record = try context.fetch(
            FetchDescriptor<PriceChangeRecord>()
        ).filter { belongsTo($0, subscriptionID: subscriptionID) }
        return record
            .sorted {
                if $0.sequence != $1.sequence {
                    return $0.sequence < $1.sequence
                }
                if $0.appendOrderDate != $1.appendOrderDate {
                    return $0.appendOrderDate < $1.appendOrderDate
                }
                return $0.persistentModelID < $1.persistentModelID
            }
            .map {
                PriceChange(
                    id: $0.id,
                    effectiveDate: $0.effectiveDate,
                    amount: Money(
                        minorUnits: $0.amountMinorUnits,
                        currency: Currency(
                            rawValue: $0.currencyRawValue
                        ) ?? .usd
                    )
                )
            }
    }

    private func rememberPriceChanges(for subscription: Subscription) {
        priceChangeSnapshots[subscription.id] = Dictionary(
            uniqueKeysWithValues: subscription.priceChanges.map {
                ($0.id, $0)
            }
        )
    }

    private func rememberCurrentPriceChanges(for subscriptionID: UUID) throws {
        let current = try currentPriceChanges(for: subscriptionID)
        priceChangeSnapshots[subscriptionID] = Dictionary(
            uniqueKeysWithValues: current.map { ($0.id, $0) }
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

private func preferenceRecordPrecedes(
    _ lhs: UserPreferencesRecord,
    _ rhs: UserPreferencesRecord
) -> Bool {
    let lhsIsCanonical = lhs.id == UserPreferencesRecord.canonicalID
    let rhsIsCanonical = rhs.id == UserPreferencesRecord.canonicalID
    if lhsIsCanonical != rhsIsCanonical {
        return lhsIsCanonical
    }
    if lhs.id != rhs.id {
        return lhs.id.uuidString < rhs.id.uuidString
    }
    if lhs.primaryCurrencyRawValue != rhs.primaryCurrencyRawValue {
        return lhs.primaryCurrencyRawValue < rhs.primaryCurrencyRawValue
    }
    if lhs.calendarProjectionHorizonMonths
        != rhs.calendarProjectionHorizonMonths
    {
        return lhs.calendarProjectionHorizonMonths
            < rhs.calendarProjectionHorizonMonths
    }
    if lhs.hideAmountsInCalendar != rhs.hideAmountsInCalendar {
        return !lhs.hideAmountsInCalendar
    }
    if lhs.menuBarModeEnabled != rhs.menuBarModeEnabled {
        return !lhs.menuBarModeEnabled
    }
    if lhs.appearanceModeRawValue != rhs.appearanceModeRawValue {
        return lhs.appearanceModeRawValue < rhs.appearanceModeRawValue
    }
    if lhs.setupStatusRawValue != rhs.setupStatusRawValue {
        return lhs.setupStatusRawValue < rhs.setupStatusRawValue
    }
    return false
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
            let records = try modelContext.fetch(
                FetchDescriptor<UserPreferencesRecord>(
                    sortBy: [SortDescriptor(\UserPreferencesRecord.id)]
                )
            )
            guard !records.isEmpty else {
                return nil
            }
            let record = try canonicalize(records)
            return UserPreferences(
                primaryCurrency: Currency(
                    rawValue: record.primaryCurrencyRawValue
                ) ?? .cny,
                calendarProjectionHorizon: CalendarProjectionHorizon(
                    rawValue: record.calendarProjectionHorizonMonths
                ) ?? .twelveMonths,
                hideAmountsInCalendar: record.hideAmountsInCalendar,
                menuBarModeEnabled: record.menuBarModeEnabled,
                appearanceMode: AppearanceMode(
                    rawValue: record.appearanceModeRawValue
                ) ?? .system,
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
            let records = try modelContext.fetch(
                FetchDescriptor<UserPreferencesRecord>(
                    sortBy: [SortDescriptor(\UserPreferencesRecord.id)]
                )
            )
            let record = try records.isEmpty
                ? insertCanonicalRecord()
                : canonicalize(records)
            record.primaryCurrencyRawValue = preferences.primaryCurrency.rawValue
            record.calendarProjectionHorizonMonths =
                preferences.calendarProjectionHorizon.rawValue
            record.hideAmountsInCalendar = preferences.hideAmountsInCalendar
            record.menuBarModeEnabled = preferences.menuBarModeEnabled
            record.appearanceModeRawValue = preferences.appearanceMode.rawValue
            record.setupStatusRawValue = preferences.setupStatus.rawValue
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func insertCanonicalRecord() throws -> UserPreferencesRecord {
        let record = UserPreferencesRecord()
        modelContext.insert(record)
        return record
    }

    private func canonicalize(
        _ records: [UserPreferencesRecord]
    ) throws -> UserPreferencesRecord {
        let winner = records.sorted(by: preferenceRecordPrecedes).first!

        let canonical: UserPreferencesRecord
        if winner.id == UserPreferencesRecord.canonicalID {
            canonical = winner
        } else {
            canonical = UserPreferencesRecord(
                id: UserPreferencesRecord.canonicalID,
                primaryCurrencyRawValue: winner.primaryCurrencyRawValue,
                calendarProjectionHorizonMonths:
                    winner.calendarProjectionHorizonMonths,
                hideAmountsInCalendar: winner.hideAmountsInCalendar,
                menuBarModeEnabled: winner.menuBarModeEnabled,
                appearanceModeRawValue: winner.appearanceModeRawValue,
                setupStatusRawValue: winner.setupStatusRawValue
            )
            modelContext.insert(canonical)
        }

        for record in records where record !== canonical {
            modelContext.delete(record)
        }
        if canonical.modelContext == nil {
            modelContext.insert(canonical)
        }
        try save(modelContext)
        return canonical
    }
}

@MainActor
final class SwiftDataPortableBackupImportRepository:
    PortableBackupImportRepository
{
    private let modelContainer: ModelContainer
    private let save: (ModelContext) throws -> Void

    convenience init(modelContainer: ModelContainer) {
        self.init(modelContainer: modelContainer, save: { try $0.save() })
    }

    init(
        modelContainer: ModelContainer,
        save: @escaping (ModelContext) throws -> Void
    ) {
        self.modelContainer = modelContainer
        self.save = save
    }

    func apply(_ merge: PortableBackupMerge) throws {
        let context = ModelContext(modelContainer)
        do {
            for subscription in merge.additions {
                let record = SubscriptionRecord(id: subscription.id)
                try apply(subscription, to: record, in: context)
                context.insert(record)
            }
            for subscription in merge.replacements {
                let id = subscription.id
                var descriptor = FetchDescriptor<SubscriptionRecord>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.fetchLimit = 1
                guard let record = try context.fetch(descriptor).first else {
                    throw PortableBackupImportStorageError.subscriptionNotFound
                }
                try apply(subscription, to: record, in: context)
            }
            if let preferences = merge.preferences {
                let records = try context.fetch(
                    FetchDescriptor<UserPreferencesRecord>(
                        sortBy: [SortDescriptor(\UserPreferencesRecord.id)]
                    )
                )
                let record = try canonicalPreferencesRecord(
                    from: records,
                    in: context
                )
                record.primaryCurrencyRawValue = preferences.primaryCurrency.rawValue
                record.calendarProjectionHorizonMonths =
                    preferences.calendarProjectionHorizon.rawValue
                record.hideAmountsInCalendar = preferences.hideAmountsInCalendar
                record.menuBarModeEnabled = preferences.menuBarModeEnabled
                record.appearanceModeRawValue = preferences.appearanceMode.rawValue
                record.setupStatusRawValue = preferences.setupStatus.rawValue
            }
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func apply(
        _ subscription: Subscription,
        to record: SubscriptionRecord,
        in context: ModelContext
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
        record.managementURLString = subscription.managementURL?.absoluteString
        record.notes = subscription.notes
        try replaceConfirmedCharges(
            subscription.confirmedCharges,
            in: record,
            context: context
        )
        try replacePriceChanges(
            subscription.priceChanges,
            in: record,
            context: context
        )
        record.confirmedChargesData = nil
        record.priceChangesData = nil
        record.isArchived = subscription.isArchived
        switch subscription.lifecycle {
        case .active:
            record.lifecycleRawValue = "active"
            record.trialFirstPaidChargeAt = nil
            record.cancelledAt = nil
            record.accessUntil = nil
        case .trial(let firstPaidChargeAt):
            record.lifecycleRawValue = "trial"
            record.trialFirstPaidChargeAt = firstPaidChargeAt
            record.cancelledAt = nil
            record.accessUntil = nil
        case .cancelled(let cancelledAt, let accessUntil):
            record.lifecycleRawValue = "cancelled"
            record.trialFirstPaidChargeAt = nil
            record.cancelledAt = cancelledAt
            record.accessUntil = accessUntil
        }
    }

    private func canonicalPreferencesRecord(
        from records: [UserPreferencesRecord],
        in context: ModelContext
    ) throws -> UserPreferencesRecord {
        guard let winner = records.sorted(by: preferenceRecordPrecedes).first else {
            let record = UserPreferencesRecord()
            context.insert(record)
            return record
        }

        let canonical: UserPreferencesRecord
        if winner.id == UserPreferencesRecord.canonicalID {
            canonical = winner
        } else {
            canonical = UserPreferencesRecord(
                id: UserPreferencesRecord.canonicalID,
                primaryCurrencyRawValue: winner.primaryCurrencyRawValue,
                calendarProjectionHorizonMonths:
                    winner.calendarProjectionHorizonMonths,
                hideAmountsInCalendar: winner.hideAmountsInCalendar,
                menuBarModeEnabled: winner.menuBarModeEnabled,
                appearanceModeRawValue: winner.appearanceModeRawValue,
                setupStatusRawValue: winner.setupStatusRawValue
            )
            context.insert(canonical)
        }

        for record in records where record !== canonical {
            context.delete(record)
        }
        return canonical
    }

    private func replaceConfirmedCharges(
        _ charges: [ConfirmedCharge],
        in record: SubscriptionRecord,
        context: ModelContext
    ) throws {
        let storedRecords = try context.fetch(
            FetchDescriptor<ConfirmedChargeRecord>()
        ).filter {
            $0.subscriptionID == record.id
                || ($0.subscriptionID == nil
                    && $0.subscription?.id == record.id)
        }
        let desiredIDs = Set(charges.map(\.id))
        for storedRecord in storedRecords where !desiredIDs.contains(storedRecord.id) {
            context.delete(storedRecord)
        }
        var storedByID: [UUID: ConfirmedChargeRecord] = [:]
        for storedRecord in storedRecords {
            storedByID[storedRecord.id] = storedRecord
        }
        for (sequence, charge) in charges.enumerated() {
            let storedRecord: ConfirmedChargeRecord
            if let existing = storedByID[charge.id] {
                storedRecord = existing
            } else {
                storedRecord = ConfirmedChargeRecord(
                    id: charge.id,
                    sequence: sequence,
                    appendOrderDate: Date(),
                    chargedDate: charge.chargedDate,
                    amountMinorUnits: charge.amount.minorUnits,
                    currencyRawValue: charge.amount.currency.rawValue,
                    subscriptionID: record.id,
                    subscription: record
                )
                context.insert(storedRecord)
                storedByID[charge.id] = storedRecord
            }
            storedRecord.sequence = sequence
            storedRecord.chargedDate = charge.chargedDate
            storedRecord.amountMinorUnits = charge.amount.minorUnits
            storedRecord.currencyRawValue = charge.amount.currency.rawValue
            let source = charge.sourceScheduledChargeID
            storedRecord.sourceScheduledChargeSubscriptionID =
                source?.subscriptionID
            storedRecord.sourceScheduledChargeYear = source?.year
            storedRecord.sourceScheduledChargeMonth = source?.month
            storedRecord.sourceScheduledChargeDay = source?.day
            storedRecord.subscriptionID = record.id
            storedRecord.subscription = record
        }
    }

    private func replacePriceChanges(
        _ changes: [PriceChange],
        in record: SubscriptionRecord,
        context: ModelContext
    ) throws {
        let storedRecords = try context.fetch(
            FetchDescriptor<PriceChangeRecord>()
        ).filter {
            $0.subscriptionID == record.id
                || ($0.subscriptionID == nil
                    && $0.subscription?.id == record.id)
        }
        let desiredIDs = Set(changes.map(\.id))
        for storedRecord in storedRecords where !desiredIDs.contains(storedRecord.id) {
            context.delete(storedRecord)
        }
        var storedByID: [UUID: PriceChangeRecord] = [:]
        for storedRecord in storedRecords {
            storedByID[storedRecord.id] = storedRecord
        }
        for (sequence, change) in changes.enumerated() {
            let storedRecord: PriceChangeRecord
            if let existing = storedByID[change.id] {
                storedRecord = existing
            } else {
                storedRecord = PriceChangeRecord(
                    id: change.id,
                    sequence: sequence,
                    appendOrderDate: Date(),
                    effectiveDate: change.effectiveDate,
                    amountMinorUnits: change.amount.minorUnits,
                    currencyRawValue: change.amount.currency.rawValue,
                    subscriptionID: record.id,
                    subscription: record
                )
                context.insert(storedRecord)
                storedByID[change.id] = storedRecord
            }
            storedRecord.sequence = sequence
            storedRecord.effectiveDate = change.effectiveDate
            storedRecord.amountMinorUnits = change.amount.minorUnits
            storedRecord.currencyRawValue = change.amount.currency.rawValue
            storedRecord.subscriptionID = record.id
            storedRecord.subscription = record
        }
    }
}

private enum PortableBackupImportStorageError: Error {
    case subscriptionNotFound
}
