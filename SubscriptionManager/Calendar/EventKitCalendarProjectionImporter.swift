import EventKit
import Foundation
import SubscriptionCore
import SwiftData

@MainActor
enum CalendarEventAccess: Equatable {
    case granted
    case denied
    case unavailable
}

enum LegacyCalendarProjectionMappingValidationAvailability: Equatable {
    case available
    case unavailable
}

@MainActor
protocol LegacyCalendarProjectionMappingValidating {
    var availability: LegacyCalendarProjectionMappingValidationAvailability {
        get
    }

    func containsCalendar(identifier: String) -> Bool
    func containsEvent(
        identifier: String,
        inCalendarWithIdentifier calendarIdentifier: String
    ) -> Bool
}

@MainActor
struct CalendarProjectionCalendar: Equatable {
    let identifier: String
}

@MainActor
struct CalendarEventWriteResult: Equatable {
    let eventIdentifier: String
    let updatedExistingEvent: Bool
    let didSave: Bool
}

@MainActor
struct CalendarProjectionEventMapping: Equatable {
    let projectionUID: String
    let eventIdentifier: String
}

@MainActor
enum CalendarEventStoreError: Error {
    case noWritableSource
    case writeFailed
}

struct EventKitCalendarProjectionManagedFields: Equatable {
    let title: String
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let timeZoneIdentifier: String?
    let alarmOffsets: [TimeInterval]
    let calendarIdentifier: String?
}

enum EventKitCalendarProjectionSemantics {
    static func projectionUIDMarker(for uid: String) -> String {
        "Subscription Manager Projection UID: \(uid)"
    }

    static func projectionNotes(for event: CalendarProjectionEvent) -> String {
        "\(event.notes)\n\n\(projectionUIDMarker(for: event.uid))"
    }

    static func allDayDates(
        for projection: CalendarProjectionEvent
    ) -> (startDate: Date, endDate: Date) {
        (
            floatingAllDayDate(
                projection.startDate,
                projectionTimeZoneIdentifier: projection.timeZoneIdentifier
            ),
            floatingAllDayDate(
                projection.endDate,
                projectionTimeZoneIdentifier: projection.timeZoneIdentifier
            )
        )
    }

    static func recoveryInterval(
        for projection: CalendarProjectionEvent
    ) -> DateInterval {
        let dates = allDayDates(for: projection)
        return DateInterval(start: dates.startDate, end: dates.endDate)
    }

    static func containsExactProjectionUIDMarker(
        in notes: String?,
        uid: String
    ) -> Bool {
        notes?.components(separatedBy: .newlines)
            .contains(projectionUIDMarker(for: uid)) == true
    }

    static func eventMatchesProjection(
        _ fields: EventKitCalendarProjectionManagedFields,
        projection: CalendarProjectionEvent,
        calendar: CalendarProjectionCalendar
    ) -> Bool {
        let projectionTimeZone = TimeZone(
            identifier: projection.timeZoneIdentifier
        ) ?? .current
        return fields.title == projection.title
            && fields.notes == projectionNotes(for: projection)
            && fields.url == projection.managementURL
            && fields.isAllDay
            && sameDay(
                fields.startDate,
                in: NSTimeZone.default,
                as: projection.startDate,
                in: projectionTimeZone
            )
            && sameDay(
                fields.endDate,
                in: NSTimeZone.default,
                as: projection.endDate,
                in: projectionTimeZone
            )
            && fields.timeZoneIdentifier == projection.timeZoneIdentifier
            && fields.alarmOffsets
                == projection.alarmOffsets.map {
                    TimeInterval($0) * 86_400
                }
            && fields.calendarIdentifier == calendar.identifier
    }

    private static func floatingAllDayDate(
        _ date: Date,
        projectionTimeZoneIdentifier: String
    ) -> Date {
        var projectionCalendar = Calendar(identifier: .gregorian)
        projectionCalendar.timeZone = TimeZone(
            identifier: projectionTimeZoneIdentifier
        ) ?? .current
        let components = projectionCalendar.dateComponents(
            [.year, .month, .day],
            from: date
        )

        var defaultCalendar = Calendar(identifier: .gregorian)
        defaultCalendar.timeZone = NSTimeZone.default
        return defaultCalendar.date(from: components) ?? date
    }

    private static func sameDay(
        _ lhs: Date,
        in lhsTimeZone: TimeZone,
        as rhs: Date,
        in rhsTimeZone: TimeZone
    ) -> Bool {
        dayComponents(for: lhs, in: lhsTimeZone)
            == dayComponents(for: rhs, in: rhsTimeZone)
    }

    private static func dayComponents(
        for date: Date,
        in timeZone: TimeZone
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }
}

@MainActor
protocol CalendarEventStore {
    func requestFullEventAccess() async -> CalendarEventAccess
    func calendar(identifier: String) -> CalendarProjectionCalendar?
    func eventExists(identifier: String) -> Bool
    func eventIdentifier(
        for projectionUID: String,
        near projection: CalendarProjectionEvent,
        in calendar: CalendarProjectionCalendar
    ) -> String?
    func removeEvent(identifier: String) throws
    func createDedicatedCalendar(
        named: String
    ) throws -> CalendarProjectionCalendar
    func saveProjectedEvent(
        _ event: CalendarProjectionEvent,
        in calendar: CalendarProjectionCalendar,
        replacingEventWithIdentifier identifier: String?
    ) throws -> CalendarEventWriteResult
}

@MainActor
protocol CalendarProjectionMappingRepository {
    func calendarIdentifier() throws -> String?
    func isCalendarSyncDisabled() throws -> Bool
    func setCalendarSyncDisabled(_ disabled: Bool) throws
    func saveCalendarIdentifier(_ identifier: String) throws
    func eventIdentifier(for projectionUID: String) throws -> String?
    func eventMappings() throws -> [CalendarProjectionEventMapping]
    func removeEventMapping(for projectionUID: String) throws
    func saveEventIdentifier(
        _ identifier: String,
        for projectionUID: String,
        calendarIdentifier: String
    ) throws
}

@MainActor
final class EventKitCalendarProjectionImporter:
    CalendarProjectionImporter, CalendarProjectionReconciler
{
    private static let calendarTitle = "Subscription Manager"

    private enum EventIdentifierResolution {
        case mapped(String)
        case recovered(String, replacingMappedIdentifier: Bool)
        case missing(hadMappedIdentifier: Bool)
    }

    private let eventStore: any CalendarEventStore
    private let mappingRepository: any CalendarProjectionMappingRepository

    init(
        eventStore: any CalendarEventStore,
        mappingRepository: any CalendarProjectionMappingRepository
    ) {
        self.eventStore = eventStore
        self.mappingRepository = mappingRepository
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(
            eventStore: EventKitCalendarEventStore(),
            mappingRepository: SwiftDataCalendarProjectionMappingRepository(
                modelContainer: modelContainer
            )
        )
    }

    func importProjection(
        events: [CalendarProjectionEvent]
    ) async -> CalendarProjectionImportResult {
        switch await eventStore.requestFullEventAccess() {
        case .denied:
            return .accessDenied
        case .unavailable:
            return .unavailable
        case .granted:
            break
        }

        let calendar: CalendarProjectionCalendar
        var eventIdentifiersByProjectionUID: [String: String]
        do {
            eventIdentifiersByProjectionUID = eventIdentifierSnapshot(
                from: try mappingRepository.eventMappings()
            )
            if let identifier = try mappingRepository.calendarIdentifier(),
               let existing = eventStore.calendar(identifier: identifier)
            {
                calendar = existing
            } else {
                calendar = try eventStore.createDedicatedCalendar(
                    named: Self.calendarTitle
                )
                try mappingRepository.saveCalendarIdentifier(
                    calendar.identifier
                )
            }
        } catch {
            return .unavailable
        }

        var createdCount = 0
        var updatedCount = 0
        var failedCount = 0
        for event in events {
            do {
                let resolution = resolveEventIdentifier(
                    for: event,
                    mappedIdentifier:
                        eventIdentifiersByProjectionUID[event.uid],
                    in: calendar
                )
                let existingIdentifier: String?
                switch resolution {
                case .mapped(let identifier),
                     .recovered(let identifier, _):
                    existingIdentifier = identifier
                case .missing:
                    existingIdentifier = nil
                }
                let write = try eventStore.saveProjectedEvent(
                    event,
                    in: calendar,
                    replacingEventWithIdentifier: existingIdentifier
                )
                try mappingRepository.saveEventIdentifier(
                    write.eventIdentifier,
                    for: event.uid,
                    calendarIdentifier: calendar.identifier
                )
                eventIdentifiersByProjectionUID[event.uid] =
                    write.eventIdentifier
                if write.didSave {
                    if write.updatedExistingEvent {
                        updatedCount += 1
                    } else {
                        createdCount += 1
                    }
                }
            } catch {
                failedCount += 1
            }
        }

        let summary = CalendarProjectionImportSummary(
            createdCount: createdCount,
            updatedCount: updatedCount
        )
        return failedCount == 0
            ? .imported(summary)
            : .partialFailure(summary, failedCount: failedCount)
    }

    func perform(
        _ command: CalendarReconciliationCommand
    ) async -> CalendarReconciliationResult {
        switch command {
        case .reconcile(let events):
            return reconcile(events: events)
        case .rebuild(let events):
            return await rebuild(events: events)
        case .disable:
            do {
                try mappingRepository.setCalendarSyncDisabled(true)
                return .disabled
            } catch {
                return .unavailable
            }
        }
    }

    private func rebuild(
        events: [CalendarProjectionEvent]
    ) async -> CalendarReconciliationResult {
        do { try mappingRepository.setCalendarSyncDisabled(false) } catch {
            return .unavailable
        }
        switch await importProjection(events: events) {
        case .imported:
            return .reconciled
        case .partialFailure(_, let failedCount):
            return .partialFailure(failedCount: failedCount)
        case .accessDenied, .unavailable:
            return .unavailable
        }
    }

    private func reconcile(
        events: [CalendarProjectionEvent]
    ) -> CalendarReconciliationResult {
        let calendar: CalendarProjectionCalendar
        let mappings: [CalendarProjectionEventMapping]
        var eventIdentifiersByProjectionUID: [String: String] = [:]
        var mappedIdentifiers: [String: String] = [:]
        do {
            guard try !mappingRepository.isCalendarSyncDisabled() else {
                return .disabled
            }
            guard let identifier = try mappingRepository.calendarIdentifier()
            else {
                return .notConfigured
            }
            guard let existing = eventStore.calendar(identifier: identifier)
            else {
                return .needsDecision(.calendarMissing)
            }
            calendar = existing

            mappings = try mappingRepository.eventMappings()
            eventIdentifiersByProjectionUID = eventIdentifierSnapshot(
                from: mappings
            )
            var missingCount = 0
            for event in events {
                switch resolveEventIdentifier(
                    for: event,
                    mappedIdentifier:
                        eventIdentifiersByProjectionUID[event.uid],
                    in: calendar
                ) {
                case .mapped(let identifier):
                    mappedIdentifiers[event.uid] = identifier
                case .recovered(
                    let recoveredIdentifier,
                    let replacingMappedIdentifier
                ):
                    if replacingMappedIdentifier {
                        try mappingRepository.saveEventIdentifier(
                            recoveredIdentifier,
                            for: event.uid,
                            calendarIdentifier: calendar.identifier
                        )
                        eventIdentifiersByProjectionUID[event.uid] =
                            recoveredIdentifier
                    }
                    mappedIdentifiers[event.uid] = recoveredIdentifier
                case .missing(let hadMappedIdentifier):
                    if hadMappedIdentifier {
                        missingCount += 1
                    }
                }
            }

            guard missingCount == 0 else {
                return .needsDecision(.eventsMissing(count: missingCount))
            }
        } catch {
            return .unavailable
        }

        var failedCount = 0
        let desiredUIDs = Set(events.map(\.uid))
        for mapping in mappings
        where !desiredUIDs.contains(mapping.projectionUID) {
            do {
                try eventStore.removeEvent(identifier: mapping.eventIdentifier)
                try mappingRepository.removeEventMapping(
                    for: mapping.projectionUID
                )
                eventIdentifiersByProjectionUID.removeValue(
                    forKey: mapping.projectionUID
                )
            } catch {
                failedCount += 1
            }
        }

        for event in events {
            do {
                let existingIdentifier = mappedIdentifiers[event.uid]
                let write = try eventStore.saveProjectedEvent(
                    event,
                    in: calendar,
                    replacingEventWithIdentifier: existingIdentifier
                )
                try mappingRepository.saveEventIdentifier(
                    write.eventIdentifier,
                    for: event.uid,
                    calendarIdentifier: calendar.identifier
                )
                eventIdentifiersByProjectionUID[event.uid] =
                    write.eventIdentifier
                mappedIdentifiers[event.uid] = write.eventIdentifier
            } catch {
                failedCount += 1
            }
        }

        return failedCount == 0
            ? .reconciled
            : .partialFailure(failedCount: failedCount)
    }

    private func resolveEventIdentifier(
        for event: CalendarProjectionEvent,
        mappedIdentifier: String?,
        in calendar: CalendarProjectionCalendar
    ) -> EventIdentifierResolution {
        if let mappedIdentifier,
           eventStore.eventExists(identifier: mappedIdentifier)
        {
            return .mapped(mappedIdentifier)
        }
        if let recoveredIdentifier = eventStore.eventIdentifier(
            for: event.uid,
            near: event,
            in: calendar
        ) {
            return .recovered(
                recoveredIdentifier,
                replacingMappedIdentifier: mappedIdentifier != nil
            )
        }
        return .missing(hadMappedIdentifier: mappedIdentifier != nil)
    }

    private func eventIdentifierSnapshot(
        from mappings: [CalendarProjectionEventMapping]
    ) -> [String: String] {
        var snapshot: [String: String] = [:]
        for mapping in mappings.sorted(by: mappingPrecedes) {
            guard snapshot[mapping.projectionUID] == nil else { continue }
            snapshot[mapping.projectionUID] = mapping.eventIdentifier
        }
        return snapshot
    }

    private func mappingPrecedes(
        _ lhs: CalendarProjectionEventMapping,
        _ rhs: CalendarProjectionEventMapping
    ) -> Bool {
        if lhs.projectionUID != rhs.projectionUID {
            return lhs.projectionUID < rhs.projectionUID
        }
        return lhs.eventIdentifier < rhs.eventIdentifier
    }
}

@MainActor
final class UnavailableCalendarProjectionImporter: CalendarProjectionImporter {
    func importProjection(
        events: [CalendarProjectionEvent]
    ) async -> CalendarProjectionImportResult {
        .unavailable
    }
}

@MainActor
final class EventKitLegacyCalendarProjectionMappingValidator:
    LegacyCalendarProjectionMappingValidating
{
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    var availability: LegacyCalendarProjectionMappingValidationAvailability {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
            ? .available
            : .unavailable
    }

    func containsCalendar(identifier: String) -> Bool {
        eventStore.calendar(withIdentifier: identifier)?
            .allowsContentModifications == true
    }

    func containsEvent(
        identifier: String,
        inCalendarWithIdentifier calendarIdentifier: String
    ) -> Bool {
        eventStore.event(withIdentifier: identifier)?
            .calendar?.calendarIdentifier == calendarIdentifier
    }
}

@MainActor
private final class EventKitCalendarEventStore: CalendarEventStore {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func requestFullEventAccess() async -> CalendarEventAccess {
        do {
            return try await eventStore.requestFullAccessToEvents()
                ? .granted
                : .denied
        } catch {
            return .unavailable
        }
    }

    func calendar(identifier: String) -> CalendarProjectionCalendar? {
        guard let calendar = eventStore.calendar(withIdentifier: identifier),
              calendar.allowsContentModifications
        else {
            return nil
        }
        return CalendarProjectionCalendar(identifier: calendar.calendarIdentifier)
    }

    func eventExists(identifier: String) -> Bool {
        eventStore.event(withIdentifier: identifier) != nil
    }

    func eventIdentifier(
        for projectionUID: String,
        near projection: CalendarProjectionEvent,
        in calendar: CalendarProjectionCalendar
    ) -> String? {
        guard let targetCalendar = eventStore.calendar(
            withIdentifier: calendar.identifier
        ) else {
            return nil
        }
        let recoveryInterval = EventKitCalendarProjectionSemantics
            .recoveryInterval(for: projection)
        let predicate = eventStore.predicateForEvents(
            withStart: recoveryInterval.start,
            end: recoveryInterval.end,
            calendars: [targetCalendar]
        )
        return eventStore.events(matching: predicate).first { event in
            event.calendar?.calendarIdentifier == calendar.identifier
                && EventKitCalendarProjectionSemantics
                    .containsExactProjectionUIDMarker(
                        in: event.notes,
                        uid: projectionUID
                    )
        }?.eventIdentifier
    }

    func removeEvent(identifier: String) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            return
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    func createDedicatedCalendar(
        named: String
    ) throws -> CalendarProjectionCalendar {
        guard let source = eventStore.defaultCalendarForNewEvents?.source else {
            throw CalendarEventStoreError.noWritableSource
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = named
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        guard calendar.allowsContentModifications else {
            throw CalendarEventStoreError.noWritableSource
        }
        return CalendarProjectionCalendar(identifier: calendar.calendarIdentifier)
    }

    func saveProjectedEvent(
        _ projection: CalendarProjectionEvent,
        in calendar: CalendarProjectionCalendar,
        replacingEventWithIdentifier identifier: String?
    ) throws -> CalendarEventWriteResult {
        guard let targetCalendar = eventStore.calendar(
            withIdentifier: calendar.identifier
        ) else {
            throw CalendarEventStoreError.noWritableSource
        }
        let existingEvent = identifier.flatMap(eventStore.event(withIdentifier:))
        if let existingEvent,
           EventKitCalendarProjectionSemantics.eventMatchesProjection(
               EventKitCalendarProjectionManagedFields(
                   title: existingEvent.title,
                   notes: existingEvent.notes,
                   url: existingEvent.url,
                   isAllDay: existingEvent.isAllDay,
                   startDate: existingEvent.startDate,
                   endDate: existingEvent.endDate,
                   timeZoneIdentifier: existingEvent.timeZone?.identifier,
                   alarmOffsets: (existingEvent.alarms ?? [])
                       .map(\.relativeOffset),
                   calendarIdentifier: existingEvent.calendar?
                       .calendarIdentifier
               ),
               projection: projection,
               calendar: calendar
           )
        {
            guard let eventIdentifier = existingEvent.eventIdentifier else {
                throw CalendarEventStoreError.writeFailed
            }
            return CalendarEventWriteResult(
                eventIdentifier: eventIdentifier,
                updatedExistingEvent: false,
                didSave: false
            )
        }
        let event = existingEvent ?? EKEvent(eventStore: eventStore)
        let allDayDates = EventKitCalendarProjectionSemantics.allDayDates(
            for: projection
        )
        event.title = projection.title
        event.notes = EventKitCalendarProjectionSemantics.projectionNotes(
            for: projection
        )
        event.url = projection.managementURL
        event.isAllDay = true
        event.startDate = allDayDates.startDate
        event.endDate = allDayDates.endDate
        event.timeZone = TimeZone(identifier: projection.timeZoneIdentifier)
        event.alarms = projection.alarmOffsets.map {
            EKAlarm(relativeOffset: TimeInterval($0 * 86_400))
        }
        event.calendar = targetCalendar
        try eventStore.save(event, span: .thisEvent, commit: true)
        guard let eventIdentifier = event.eventIdentifier else {
            throw CalendarEventStoreError.writeFailed
        }
        return CalendarEventWriteResult(
            eventIdentifier: eventIdentifier,
            updatedExistingEvent: existingEvent != nil,
            didSave: true
        )
    }

}

@MainActor
final class SwiftDataCalendarProjectionMappingRepository:
    CalendarProjectionMappingRepository
{
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func calendarIdentifier() throws -> String? {
        guard let identifier = try calendarMetadataRecord()?.calendarIdentifier,
              !identifier.isEmpty
        else {
            return nil
        }
        return identifier
    }

    func isCalendarSyncDisabled() throws -> Bool {
        try calendarMetadataRecord()?.calendarSyncDisabled ?? false
    }

    func setCalendarSyncDisabled(_ disabled: Bool) throws {
        if let record = try calendarMetadataRecord() {
            record.calendarSyncDisabled = disabled
        } else {
            let record = CalendarProjectionMappingRecord(calendarIdentifier: "")
            record.calendarSyncDisabled = disabled
            modelContext.insert(record)
        }
        try saveContext()
    }

    func saveCalendarIdentifier(_ identifier: String) throws {
        if let record = try calendarMetadataRecord() {
            record.calendarIdentifier = identifier
        } else {
            modelContext.insert(
                CalendarProjectionMappingRecord(calendarIdentifier: identifier)
            )
        }
        try saveContext()
    }

    func eventIdentifier(for projectionUID: String) throws -> String? {
        try eventMappingRecord(for: projectionUID)?.eventIdentifier
    }

    func eventMappings() throws -> [CalendarProjectionEventMapping] {
        let metadataProjectionUID = ""
        let descriptor = FetchDescriptor<CalendarProjectionMappingRecord>(
            predicate: #Predicate {
                $0.projectionUID != metadataProjectionUID
            },
            sortBy: [
                SortDescriptor(
                    \CalendarProjectionMappingRecord.projectionUID
                ),
                SortDescriptor(
                    \CalendarProjectionMappingRecord.eventIdentifier
                ),
                SortDescriptor(
                    \CalendarProjectionMappingRecord.calendarIdentifier
                ),
            ]
        )
        return try modelContext.fetch(descriptor)
            .map {
                CalendarProjectionEventMapping(
                    projectionUID: $0.projectionUID,
                    eventIdentifier: $0.eventIdentifier
                )
            }
    }

    func removeEventMapping(for projectionUID: String) throws {
        guard let record = try eventMappingRecord(for: projectionUID) else {
            return
        }
        modelContext.delete(record)
        try saveContext()
    }

    func saveEventIdentifier(
        _ identifier: String,
        for projectionUID: String,
        calendarIdentifier: String
    ) throws {
        if let record = try eventMappingRecord(for: projectionUID) {
            record.eventIdentifier = identifier
            record.calendarIdentifier = calendarIdentifier
        } else {
            modelContext.insert(
                CalendarProjectionMappingRecord(
                    projectionUID: projectionUID,
                    eventIdentifier: identifier,
                    calendarIdentifier: calendarIdentifier
                )
            )
        }
        try saveContext()
    }

    private func saveContext() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func eventMappingRecord(
        for projectionUID: String
    ) throws -> CalendarProjectionMappingRecord? {
        let lookupProjectionUID = projectionUID
        var descriptor = FetchDescriptor<CalendarProjectionMappingRecord>(
            predicate: #Predicate {
                $0.projectionUID == lookupProjectionUID
            },
            sortBy: [
                SortDescriptor(
                    \CalendarProjectionMappingRecord.eventIdentifier
                ),
                SortDescriptor(
                    \CalendarProjectionMappingRecord.calendarIdentifier
                ),
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func calendarMetadataRecord() throws
        -> CalendarProjectionMappingRecord?
    {
        let metadataProjectionUID = ""
        var descriptor = FetchDescriptor<CalendarProjectionMappingRecord>(
            predicate: #Predicate {
                $0.projectionUID == metadataProjectionUID
            },
            sortBy: [
                SortDescriptor(
                    \CalendarProjectionMappingRecord.calendarIdentifier
                ),
                SortDescriptor(
                    \CalendarProjectionMappingRecord.eventIdentifier
                ),
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
