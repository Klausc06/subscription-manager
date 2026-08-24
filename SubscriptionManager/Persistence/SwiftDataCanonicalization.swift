import Foundation
import SwiftData
import SubscriptionCore

enum ConfirmedChargeCanonicalKey: Hashable {
    case scheduled(ScheduledChargeID)
    case unlinked(UUID)
}

struct ConfirmedChargeRecordCanonicalization {
    let orderedRecords: [ConfirmedChargeRecord]
    let recordsByKey: [
        ConfirmedChargeCanonicalKey: ConfirmedChargeRecord
    ]
    let losingRecords: [ConfirmedChargeRecord]
}

func canonicalConfirmedChargeRecords(
    from records: [ConfirmedChargeRecord]
) -> ConfirmedChargeRecordCanonicalization {
    var orderedRecords: [ConfirmedChargeRecord] = []
    var recordsByKey: [
        ConfirmedChargeCanonicalKey: ConfirmedChargeRecord
    ] = [:]
    var losingRecords: [ConfirmedChargeRecord] = []
    for record in records.sorted(by: confirmedChargeRecordPrecedes) {
        let key = confirmedChargeCanonicalKey(from: record)
        if recordsByKey[key] == nil {
            orderedRecords.append(record)
            recordsByKey[key] = record
        } else {
            losingRecords.append(record)
        }
    }
    return ConfirmedChargeRecordCanonicalization(
        orderedRecords: orderedRecords,
        recordsByKey: recordsByKey,
        losingRecords: losingRecords
    )
}

func confirmedChargeCanonicalKey(
    from record: ConfirmedChargeRecord
) -> ConfirmedChargeCanonicalKey {
    scheduledChargeID(from: record).map {
        .scheduled($0)
    } ?? .unlinked(record.id)
}

func confirmedChargeCanonicalKey(
    from charge: ConfirmedCharge
) -> ConfirmedChargeCanonicalKey {
    charge.sourceScheduledChargeID.map {
        .scheduled($0)
    } ?? .unlinked(charge.id)
}

func scheduledChargeID(
    from record: ConfirmedChargeRecord
) -> ScheduledChargeID? {
    guard let subscriptionID =
        record.sourceScheduledChargeSubscriptionID,
        let year = record.sourceScheduledChargeYear,
        let month = record.sourceScheduledChargeMonth,
        let day = record.sourceScheduledChargeDay
    else {
        return nil
    }
    return ScheduledChargeID(
        subscriptionID: subscriptionID,
        year: year,
        month: month,
        day: day
    )
}

func confirmedChargeRecordPrecedes(
    _ lhs: ConfirmedChargeRecord,
    _ rhs: ConfirmedChargeRecord
) -> Bool {
    if lhs.sequence != rhs.sequence {
        return lhs.sequence < rhs.sequence
    }
    if lhs.appendOrderDate != rhs.appendOrderDate {
        return lhs.appendOrderDate < rhs.appendOrderDate
    }
    return lhs.persistentModelID < rhs.persistentModelID
}

struct PriceChangeRecordCanonicalization {
    let orderedRecords: [PriceChangeRecord]
    let recordsByID: [UUID: PriceChangeRecord]
    let losingRecords: [PriceChangeRecord]
}

func canonicalPriceChangeRecords(
    from records: [PriceChangeRecord]
) -> PriceChangeRecordCanonicalization {
    var orderedRecords: [PriceChangeRecord] = []
    var recordsByID: [UUID: PriceChangeRecord] = [:]
    var losingRecords: [PriceChangeRecord] = []
    for record in records.sorted(by: priceChangeRecordPrecedes) {
        if recordsByID[record.id] == nil {
            orderedRecords.append(record)
            recordsByID[record.id] = record
        } else {
            losingRecords.append(record)
        }
    }
    return PriceChangeRecordCanonicalization(
        orderedRecords: orderedRecords,
        recordsByID: recordsByID,
        losingRecords: losingRecords
    )
}

func canonicalPriceChangesByID(
    from changes: [PriceChange]
) -> [UUID: PriceChange] {
    var changesByID: [UUID: PriceChange] = [:]
    for change in changes {
        changesByID[change.id] = change
    }
    return changesByID
}

func priceChangeRecordPrecedes(
    _ lhs: PriceChangeRecord,
    _ rhs: PriceChangeRecord
) -> Bool {
    if lhs.sequence != rhs.sequence {
        return lhs.sequence < rhs.sequence
    }
    if lhs.appendOrderDate != rhs.appendOrderDate {
        return lhs.appendOrderDate < rhs.appendOrderDate
    }
    return lhs.persistentModelID < rhs.persistentModelID
}
