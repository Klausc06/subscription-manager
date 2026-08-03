import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("EventKit calendar projection importer")
@MainActor
struct EventKitCalendarProjectionImporterTests {
    @Test("Granted repeat import reuses one calendar and its mapped event")
    func repeatImportIsIdempotent() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let events = [calendarEvent(uid: "renewal-1")]

        let firstResult = await importer.importProjection(events: events)
        let secondResult = await importer.importProjection(events: events)

        #expect(
            firstResult == .imported(
                CalendarProjectionImportSummary(
                    createdCount: 1,
                    updatedCount: 0
                )
            )
        )
        #expect(
            secondResult == .imported(
                CalendarProjectionImportSummary(
                    createdCount: 0,
                    updatedCount: 0
                )
            )
        )
        #expect(store.accessRequestCount == 2)
        #expect(store.calendarCreationCount == 1)
        #expect(store.physicalEventIdentifiers == ["event-1"])
        #expect(try mappings.eventIdentifier(for: "renewal-1") == "event-1")
        #expect(store.saveCount == 1)
        #expect(store.savedProjectionEvents == events)
    }

    @Test("Denied access creates no calendar or events")
    func deniedAccessLeavesCalendarUntouched() async {
        let store = CalendarEventStoreFixture(access: .denied)
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: CalendarMappingFixture()
        )

        let result = await importer.importProjection(
            events: [calendarEvent(uid: "renewal-1")]
        )

        #expect(result == .accessDenied)
        #expect(store.calendarCreationCount == 0)
        #expect(store.savedEventIdentifiers.isEmpty)
    }

    @Test("A missing writable source leaves the subscription library importable later")
    func missingWritableSourceIsReportedWithoutEvents() async {
        let store = CalendarEventStoreFixture(
            access: .granted,
            allowsCalendarCreation: false
        )
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: CalendarMappingFixture()
        )

        let result = await importer.importProjection(
            events: [calendarEvent(uid: "renewal-1")]
        )

        #expect(result == .unavailable)
        #expect(store.calendarCreationCount == 0)
        #expect(store.savedEventIdentifiers.isEmpty)
    }

    @Test("Partial write retries only the missing projection")
    func partialWriteCanRetryWithoutDuplicates() async {
        let store = CalendarEventStoreFixture(
            access: .granted,
            failingUIDs: ["renewal-2"]
        )
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: CalendarMappingFixture()
        )
        let events = [
            calendarEvent(uid: "renewal-1"),
            calendarEvent(uid: "renewal-2")
        ]

        let partialResult = await importer.importProjection(events: events)
        store.failingUIDs.removeAll()
        let retryResult = await importer.importProjection(events: events)

        #expect(
            partialResult == .partialFailure(
                CalendarProjectionImportSummary(
                    createdCount: 1,
                    updatedCount: 0
                ),
                failedCount: 1
            )
        )
        #expect(
            retryResult == .imported(
                CalendarProjectionImportSummary(
                    createdCount: 1,
                    updatedCount: 0
                )
            )
        )
        #expect(store.savedEventIdentifiers.count == 2)
    }

    @Test("Retry recovers an event when mapping persistence failed after save")
    func mappingPersistenceFailureRecoversExistingEvent() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        mappings.failNextEventMappingSave = true
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let events = [calendarEvent(uid: "renewal-1")]

        let firstResult = await importer.importProjection(events: events)
        let retryResult = await importer.importProjection(events: events)

        #expect(
            firstResult == .partialFailure(
                CalendarProjectionImportSummary(
                    createdCount: 0,
                    updatedCount: 0
                ),
                failedCount: 1
            )
        )
        #expect(
            retryResult == .imported(
                CalendarProjectionImportSummary(
                    createdCount: 0,
                    updatedCount: 0
                )
            )
        )
        #expect(store.physicalEventIdentifiers == ["event-1"])
        #expect(try mappings.eventIdentifier(for: "renewal-1") == "event-1")
        #expect(store.saveCount == 1)
        #expect(store.savedProjectionEvents == events)
    }

    @Test("Reconciliation does not recreate an externally deleted mapped event")
    func missingMappedEventRequiresDecision() async {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let events = [calendarEvent(uid: "renewal-1")]

        _ = await importer.importProjection(events: events)
        store.deleteEvent(uid: "renewal-1")

        let result = await importer.perform(.reconcile(events))

        #expect(result == .needsDecision(.eventsMissing(count: 1)))
        #expect(store.accessRequestCount == 1)
        #expect(store.calendarCreationCount == 1)
        #expect(store.savedEventIdentifiers.isEmpty)
    }

    @Test("Reconciliation removes mapped events outside the rolling projection")
    func reconciliationRemovesStaleMappedEvents() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let current = calendarEvent(uid: "renewal-1")
        let stale = calendarEvent(uid: "renewal-2")

        _ = await importer.importProjection(events: [current, stale])
        let result = await importer.perform(.reconcile([current]))

        #expect(result == .reconciled)
        #expect(store.savedEventIdentifiers.count == 1)
        #expect(try mappings.eventIdentifier(for: stale.uid) == nil)
    }

    @Test("Disabling calendar sync prevents later automatic reconciliation")
    func disabledCalendarSyncDoesNotWriteEvents() async {
        let store = CalendarEventStoreFixture(access: .granted)
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: CalendarMappingFixture()
        )
        let events = [calendarEvent(uid: "renewal-1")]

        _ = await importer.importProjection(events: events)
        let disableResult = await importer.perform(.disable)
        let reconcileResult = await importer.perform(.reconcile(events))

        #expect(disableResult == .disabled)
        #expect(reconcileResult == .disabled)
        #expect(store.accessRequestCount == 1)
        #expect(store.savedProjectionEvents.count == 1)
    }

    @Test("Reconciliation restores every managed field from the projection")
    func reconciliationRewritesTheMappedProjectionEvent() async {
        let store = CalendarEventStoreFixture(access: .granted)
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: CalendarMappingFixture()
        )
        let original = calendarEvent(uid: "renewal-1")
        let revised = CalendarProjectionEvent(
            uid: original.uid,
            startDate: original.startDate,
            endDate: original.endDate,
            title: "Atlas — US$14.99",
            notes: "Revised",
            managementURL: original.managementURL,
            alarmOffsets: [-3, -1],
            timeZoneIdentifier: original.timeZoneIdentifier
        )

        _ = await importer.importProjection(events: [original])
        #expect(await importer.perform(.reconcile([revised])) == .reconciled)
        #expect(store.savedProjectionEvents.last == revised)
    }
}

private struct PhysicalCalendarEvent: Equatable {
    let identifier: String
    let calendarIdentifier: String
    let title: String
    let notes: String
    let url: URL?
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let timeZoneIdentifier: String?
    let alarmOffsets: [Int]
}

@MainActor
private final class CalendarEventStoreFixture: CalendarEventStore {
    let access: CalendarEventAccess
    var accessRequestCount = 0
    var calendarCreationCount = 0
    var saveCount = 0
    var failingUIDs: Set<String>
    let allowsCalendarCreation: Bool
    private var calendar: CalendarProjectionCalendar?
    private var physicalEventsByIdentifier: [String: PhysicalCalendarEvent] = [:]
    private(set) var savedProjectionEvents: [CalendarProjectionEvent] = []

    init(
        access: CalendarEventAccess,
        failingUIDs: Set<String> = [],
        allowsCalendarCreation: Bool = true
    ) {
        self.access = access
        self.failingUIDs = failingUIDs
        self.allowsCalendarCreation = allowsCalendarCreation
    }

    var savedEventIdentifiers: Set<String> {
        physicalEventIdentifiers
    }

    var physicalEventIdentifiers: Set<String> {
        Set(physicalEventsByIdentifier.keys)
    }

    func deleteEvent(uid: String) {
        guard let identifier = physicalEventsByIdentifier.first(where: {
            $0.value.notes.contains(projectionMarker(for: uid))
        })?.key else {
            return
        }
        physicalEventsByIdentifier.removeValue(forKey: identifier)
    }

    func requestFullEventAccess() async -> CalendarEventAccess {
        accessRequestCount += 1
        return access
    }

    func calendar(
        identifier: String
    ) -> CalendarProjectionCalendar? {
        calendar?.identifier == identifier ? calendar : nil
    }

    func eventExists(identifier: String) -> Bool {
        physicalEventsByIdentifier[identifier] != nil
    }

    func eventIdentifier(
        for projectionUID: String,
        near projection: CalendarProjectionEvent,
        in calendar: CalendarProjectionCalendar
    ) -> String? {
        physicalEventsByIdentifier.values.first { event in
            event.calendarIdentifier == calendar.identifier
                && event.startDate < projection.endDate
                && event.endDate > projection.startDate
                && event.notes.components(separatedBy: .newlines)
                .contains(projectionMarker(for: projectionUID))
        }?.identifier
    }

    func removeEvent(identifier: String) throws {
        physicalEventsByIdentifier.removeValue(forKey: identifier)
    }

    func createDedicatedCalendar(
        named: String
    ) throws -> CalendarProjectionCalendar {
        guard allowsCalendarCreation else {
            throw CalendarEventStoreError.noWritableSource
        }
        calendarCreationCount += 1
        let created = CalendarProjectionCalendar(identifier: "calendar-1")
        calendar = created
        return created
    }

    func saveProjectedEvent(
        _ event: CalendarProjectionEvent,
        in calendar: CalendarProjectionCalendar,
        replacingEventWithIdentifier identifier: String?
    ) throws -> CalendarEventWriteResult {
        guard !failingUIDs.contains(event.uid) else {
            throw CalendarEventStoreError.writeFailed
        }
        let existingEvent = identifier.flatMap {
            physicalEventsByIdentifier[$0]
        }
        let eventIdentifier = existingEvent?.identifier
            ?? "event-\(physicalEventsByIdentifier.count + 1)"
        let desiredEvent = PhysicalCalendarEvent(
            identifier: eventIdentifier,
            calendarIdentifier: calendar.identifier,
            title: event.title,
            notes: projectionNotes(for: event),
            url: event.managementURL,
            isAllDay: true,
            startDate: event.startDate,
            endDate: event.endDate,
            timeZoneIdentifier: event.timeZoneIdentifier,
            alarmOffsets: event.alarmOffsets
        )
        if let existingEvent, existingEvent == desiredEvent {
            return CalendarEventWriteResult(
                eventIdentifier: existingEvent.identifier,
                updatedExistingEvent: false,
                didSave: false
            )
        }
        saveCount += 1
        physicalEventsByIdentifier[eventIdentifier] = desiredEvent
        savedProjectionEvents.append(event)
        return CalendarEventWriteResult(
            eventIdentifier: eventIdentifier,
            updatedExistingEvent: existingEvent != nil,
            didSave: true
        )
    }

    private func projectionNotes(for event: CalendarProjectionEvent) -> String {
        "\(event.notes)\n\n\(projectionMarker(for: event.uid))"
    }

    private func projectionMarker(for uid: String) -> String {
        "Subscription Manager Projection UID: \(uid)"
    }
}

@MainActor
private final class CalendarMappingFixture: CalendarProjectionMappingRepository {
    private var calendarID: String?
    private var isDisabled = false
    private var eventIDs: [String: String] = [:]
    var failNextEventMappingSave = false

    func calendarIdentifier() throws -> String? { calendarID }

    func isCalendarSyncDisabled() throws -> Bool { isDisabled }

    func setCalendarSyncDisabled(_ disabled: Bool) throws {
        isDisabled = disabled
    }

    func saveCalendarIdentifier(_ identifier: String) throws {
        calendarID = identifier
    }

    func eventIdentifier(for projectionUID: String) throws -> String? {
        eventIDs[projectionUID]
    }

    func eventMappings() throws -> [CalendarProjectionEventMapping] {
        eventIDs.map {
            CalendarProjectionEventMapping(
                projectionUID: $0.key,
                eventIdentifier: $0.value
            )
        }
    }

    func removeEventMapping(for projectionUID: String) throws {
        eventIDs.removeValue(forKey: projectionUID)
    }

    func saveEventIdentifier(
        _ identifier: String,
        for projectionUID: String,
        calendarIdentifier: String
    ) throws {
        if failNextEventMappingSave {
            failNextEventMappingSave = false
            throw CalendarEventStoreError.writeFailed
        }
        calendarID = calendarIdentifier
        eventIDs[projectionUID] = identifier
    }
}

private func calendarEvent(uid: String) -> CalendarProjectionEvent {
    CalendarProjectionEvent(
        uid: uid,
        startDate: Date(timeIntervalSince1970: 1_785_628_800),
        endDate: Date(timeIntervalSince1970: 1_785_715_200),
        title: "Atlas — US$12.99",
        notes: "Pro",
        managementURL: URL(string: "https://example.com/manage")!,
        alarmOffsets: [-7, -1],
        timeZoneIdentifier: "UTC"
    )
}
