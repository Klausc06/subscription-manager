import Foundation
import OSLog
import SwiftData
import SubscriptionCore

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
                context.insert(record)
                try apply(subscription, to: record, in: context)
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
        let canonicalization = canonicalConfirmedChargeRecords(
            from: storedRecords
        )
        let desiredKeys = Set(charges.map {
            confirmedChargeCanonicalKey(from: $0)
        })
        for losingRecord in canonicalization.losingRecords {
            context.delete(losingRecord)
        }
        for (key, storedRecord) in canonicalization.recordsByKey
            where !desiredKeys.contains(key)
        {
            context.delete(storedRecord)
        }
        var storedByKey = canonicalization.recordsByKey.filter {
            desiredKeys.contains($0.key)
        }
        for (sequence, charge) in charges.enumerated() {
            let key = confirmedChargeCanonicalKey(from: charge)
            let storedRecord: ConfirmedChargeRecord
            if let existing = storedByKey[key] {
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
                storedByKey[key] = storedRecord
            }
            storedRecord.id = charge.id
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
        let canonicalization = canonicalPriceChangeRecords(
            from: storedRecords
        )
        let desiredIDs = Set(changes.map(\.id))
        for losingRecord in canonicalization.losingRecords {
            context.delete(losingRecord)
        }
        for (id, storedRecord) in canonicalization.recordsByID
            where !desiredIDs.contains(id)
        {
            context.delete(storedRecord)
        }
        var storedByID = canonicalization.recordsByID.filter {
            desiredIDs.contains($0.key)
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

enum PortableBackupImportStorageError: Error {
    case subscriptionNotFound
}
