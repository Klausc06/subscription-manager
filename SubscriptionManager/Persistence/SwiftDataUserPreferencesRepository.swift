import Foundation
import OSLog
import SwiftData
import SubscriptionCore

func preferenceRecordPrecedes(
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
            let record = records.sorted(by: preferenceRecordPrecedes).first!
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
        return canonical
    }
}
