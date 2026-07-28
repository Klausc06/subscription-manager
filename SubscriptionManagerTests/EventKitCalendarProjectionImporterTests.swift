import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("EventKit calendar projection importer")
@MainActor
struct EventKitCalendarProjectionImporterTests {
    @Test("Granted repeat import reuses one calendar and its mapped event")
    func repeatImportIsIdempotent() async {
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
                    updatedCount: 1
                )
            )
        )
        #expect(store.accessRequestCount == 2)
        #expect(store.calendarCreationCount == 1)
        #expect(store.savedEventIdentifiers.count == 1)
        #expect(store.savedProjectionEvents.first == events.first)
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
                    updatedCount: 1
                )
            )
        )
        #expect(store.savedEventIdentifiers.count == 2)
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
}

@MainActor
private final class CalendarEventStoreFixture: CalendarEventStore {
    let access: CalendarEventAccess
    var accessRequestCount = 0
    var calendarCreationCount = 0
    var failingUIDs: Set<String>
    let allowsCalendarCreation: Bool
    private var calendar: CalendarProjectionCalendar?
    private var eventIdentifiersByUID: [String: String] = [:]
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
        Set(eventIdentifiersByUID.values)
    }

    func deleteEvent(uid: String) {
        eventIdentifiersByUID.removeValue(forKey: uid)
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
        eventIdentifiersByUID.values.contains(identifier)
    }

    func removeEvent(identifier: String) throws {
        guard let uid = eventIdentifiersByUID.first(where: {
            $0.value == identifier
        })?.key else {
            return
        }
        eventIdentifiersByUID.removeValue(forKey: uid)
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
        savedProjectionEvents.append(event)
        if let identifier,
           eventIdentifiersByUID[event.uid] == identifier
        {
            return CalendarEventWriteResult(
                eventIdentifier: identifier,
                updatedExistingEvent: true
            )
        }
        let identifier = "event-\(eventIdentifiersByUID.count + 1)"
        eventIdentifiersByUID[event.uid] = identifier
        return CalendarEventWriteResult(
            eventIdentifier: identifier,
            updatedExistingEvent: false
        )
    }
}

@MainActor
private final class CalendarMappingFixture: CalendarProjectionMappingRepository {
    private var calendarID: String?
    private var eventIDs: [String: String] = [:]

    func calendarIdentifier() throws -> String? { calendarID }

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
