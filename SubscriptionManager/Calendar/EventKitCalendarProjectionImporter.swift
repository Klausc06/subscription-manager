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

@MainActor
struct CalendarProjectionCalendar: Equatable {
    let identifier: String
}

@MainActor
struct CalendarEventWriteResult: Equatable {
    let eventIdentifier: String
    let updatedExistingEvent: Bool
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

@MainActor
protocol CalendarEventStore {
    func requestFullEventAccess() async -> CalendarEventAccess
    func calendar(identifier: String) -> CalendarProjectionCalendar?
    func eventExists(identifier: String) -> Bool
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
        do {
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
                let existingIdentifier = try mappingRepository.eventIdentifier(
                    for: event.uid
                )
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
                if write.updatedExistingEvent {
                    updatedCount += 1
                } else {
                    createdCount += 1
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
        }
    }

    private func reconcile(
        events: [CalendarProjectionEvent]
    ) -> CalendarReconciliationResult {
        let calendar: CalendarProjectionCalendar
        do {
            guard let identifier = try mappingRepository.calendarIdentifier()
            else {
                return .notConfigured
            }
            guard let existing = eventStore.calendar(identifier: identifier)
            else {
                return .needsDecision(.calendarMissing)
            }
            calendar = existing

            let desiredUIDs = Set(events.map(\.uid))
            for mapping in try mappingRepository.eventMappings()
            where !desiredUIDs.contains(mapping.projectionUID) {
                try eventStore.removeEvent(identifier: mapping.eventIdentifier)
                try mappingRepository.removeEventMapping(
                    for: mapping.projectionUID
                )
            }

            let missingCount = try events.reduce(into: 0) { count, event in
                guard let identifier = try mappingRepository.eventIdentifier(
                    for: event.uid
                ) else {
                    return
                }
                if !eventStore.eventExists(identifier: identifier) {
                    count += 1
                }
            }
            guard missingCount == 0 else {
                return .needsDecision(.eventsMissing(count: missingCount))
            }

            for event in events {
                let existingIdentifier = try mappingRepository.eventIdentifier(
                    for: event.uid
                )
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
            }
            return .reconciled
        } catch {
            return .unavailable
        }
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
        let event = existingEvent ?? EKEvent(eventStore: eventStore)
        event.title = projection.title
        event.notes = projectionNotes(for: projection)
        event.url = projection.managementURL
        event.isAllDay = true
        event.startDate = projection.startDate
        event.endDate = projection.endDate
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
            updatedExistingEvent: existingEvent != nil
        )
    }

    private func projectionNotes(for event: CalendarProjectionEvent) -> String {
        "\(event.notes)\n\nSubscription Manager Projection UID: \(event.uid)"
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
        try calendarMetadataRecord()?.calendarIdentifier
    }

    func saveCalendarIdentifier(_ identifier: String) throws {
        if let record = try calendarMetadataRecord() {
            record.calendarIdentifier = identifier
        } else {
            modelContext.insert(
                CalendarProjectionMappingRecord(calendarIdentifier: identifier)
            )
        }
        try modelContext.save()
    }

    func eventIdentifier(for projectionUID: String) throws -> String? {
        try records().first { $0.projectionUID == projectionUID }?
            .eventIdentifier
    }

    func eventMappings() throws -> [CalendarProjectionEventMapping] {
        try records()
            .filter { !$0.projectionUID.isEmpty }
            .map {
                CalendarProjectionEventMapping(
                    projectionUID: $0.projectionUID,
                    eventIdentifier: $0.eventIdentifier
                )
            }
    }

    func removeEventMapping(for projectionUID: String) throws {
        guard let record = try records().first(where: {
            $0.projectionUID == projectionUID
        }) else {
            return
        }
        modelContext.delete(record)
        try modelContext.save()
    }

    func saveEventIdentifier(
        _ identifier: String,
        for projectionUID: String,
        calendarIdentifier: String
    ) throws {
        if let record = try records().first(where: {
            $0.projectionUID == projectionUID
        }) {
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
        try modelContext.save()
    }

    private func records() throws -> [CalendarProjectionMappingRecord] {
        try modelContext.fetch(FetchDescriptor<CalendarProjectionMappingRecord>())
    }

    private func calendarMetadataRecord() throws
        -> CalendarProjectionMappingRecord?
    {
        try records().first { $0.projectionUID.isEmpty }
    }
}
