import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("EventKit calendar projection importer", .serialized)
@MainActor
struct EventKitCalendarProjectionImporterTests {
    @Test("Granted repeat import reuses one calendar and its mapped event")
    func repeatImportIsIdempotent() async throws {
        let originalDefaultTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalDefaultTimeZone }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!

        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let events = [
            calendarEvent(uid: "renewal-1", timeZoneIdentifier: "Asia/Tokyo")
        ]

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
        #expect(store.eventIdentifierLookupCount == 1)
        #expect(store.savedProjectionEvents == events)
    }

    @Test("All-day dates preserve the billing local day")
    func allDayDatesUseProjectionLocalDay() {
        let originalDefaultTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalDefaultTimeZone }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!

        let event = calendarEvent(
            uid: "renewal-1",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let dates = EventKitCalendarProjectionSemantics.allDayDates(
            for: event
        )
        var billingCalendar = Calendar(identifier: .gregorian)
        billingCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var systemCalendar = Calendar(identifier: .gregorian)
        systemCalendar.timeZone = NSTimeZone.default
        let projectionComponents = billingCalendar.dateComponents(
            [.year, .month, .day],
            from: event.startDate
        )
        let storedComponents = systemCalendar.dateComponents(
            [.year, .month, .day],
            from: dates.startDate
        )

        #expect(projectionComponents.year == 2026)
        #expect(projectionComponents.month == 8)
        #expect(projectionComponents.day == 2)
        #expect(storedComponents.year == 2026)
        #expect(storedComponents.month == 8)
        #expect(storedComponents.day == 2)
        #expect(dates.startDate != event.startDate)
    }

    @Test("Repeated unchanged reconciliation performs no additional save")
    func repeatedReconciliationIsIdempotent() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let event = calendarEvent(uid: "renewal-1")

        _ = await importer.importProjection(events: [event])
        let physicalEventsAfterImport = store.physicalEventIdentifiers
        let mappingsAfterImport = try mappings.eventMappings()
        let firstReconcile = await importer.perform(.reconcile([event]))
        let secondReconcile = await importer.perform(.reconcile([event]))

        #expect(firstReconcile == .reconciled)
        #expect(secondReconcile == .reconciled)
        #expect(store.saveCount == 1)
        #expect(store.physicalEventIdentifiers == physicalEventsAfterImport)
        #expect(try mappings.eventMappings() == mappingsAfterImport)
        #expect(try mappings.eventIdentifier(for: event.uid) == "event-1")
    }

    @Test("Managed field changes each trigger a physical update")
    func everyManagedFieldChangeTriggersWrite() async throws {
        for field in ManagedFieldChange.allCases {
            let store = CalendarEventStoreFixture(access: .granted)
            let mappings = CalendarMappingFixture()
            let importer = EventKitCalendarProjectionImporter(
                eventStore: store,
                mappingRepository: mappings
            )
            let original = calendarEvent(uid: "renewal-1")
            _ = await importer.importProjection(events: [original])
            let baselineSaveCount = store.saveCount
            #expect(baselineSaveCount == 1)

            var revised = original
            switch field {
            case .title:
                revised = projection(from: original, title: "Revised")
            case .notesAndUIDMarker:
                store.mutatePhysicalEvent(identifier: "event-1") {
                    $0.notes = "Pro\n\nSubscription Manager Projection UID: renewal-1-extra"
                }
            case .url:
                revised = projection(
                    from: original,
                    managementURL: URL(string: "https://example.com/revised")
                )
            case .allDay:
                store.mutatePhysicalEvent(identifier: "event-1") {
                    $0.isAllDay = false
                }
            case .start:
                revised = projection(
                    from: original,
                    startDate: original.startDate.addingTimeInterval(86_400)
                )
            case .end:
                revised = projection(
                    from: original,
                    endDate: original.endDate.addingTimeInterval(86_400)
                )
            case .timeZone:
                revised = projection(
                    from: original,
                    timeZoneIdentifier: "Europe/London"
                )
            case .alarms:
                revised = projection(from: original, alarmOffsets: [-1])
            case .targetCalendar:
                store.mutatePhysicalEvent(identifier: "event-1") {
                    $0.calendarIdentifier = "calendar-other"
                }
            }

            #expect(
                await importer.perform(.reconcile([revised])) == .reconciled
            )
            #expect(store.saveCount == baselineSaveCount + 1)
            #expect(store.savedProjectionEvents.last == revised)
            #expect(store.physicalEventIdentifiers == ["event-1"])
            #expect(
                try mappings.eventIdentifier(for: original.uid) == "event-1"
            )
        }
    }

    @Test("UID recovery ignores calendar, date, and marker decoys")
    func UIDRecoveryUsesDedicatedCalendarDateWindowAndExactMarker() async throws {
        let originalDefaultTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalDefaultTimeZone }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!

        let event = calendarEvent(
            uid: "renewal-1",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let dates = EventKitCalendarProjectionSemantics.allDayDates(
            for: event
        )
        let exactNotes = EventKitCalendarProjectionSemantics.projectionNotes(
            for: event
        )
        let store = CalendarEventStoreFixture(access: .granted)
        store.seedCalendar(identifier: "calendar-1")
        store.seedPhysicalEvent(
            PhysicalCalendarEvent(
                identifier: "event-7",
                calendarIdentifier: "calendar-1",
                title: event.title,
                notes: exactNotes,
                url: event.managementURL,
                isAllDay: true,
                startDate: dates.startDate,
                endDate: dates.endDate,
                timeZoneIdentifier: event.timeZoneIdentifier,
                alarmOffsets: event.alarmOffsets
            )
        )
        store.seedPhysicalEvent(
            PhysicalCalendarEvent(
                identifier: "event-wrong-calendar",
                calendarIdentifier: "calendar-other",
                title: event.title,
                notes: exactNotes,
                url: event.managementURL,
                isAllDay: true,
                startDate: dates.startDate,
                endDate: dates.endDate,
                timeZoneIdentifier: event.timeZoneIdentifier,
                alarmOffsets: event.alarmOffsets
            )
        )
        store.seedPhysicalEvent(
            PhysicalCalendarEvent(
                identifier: "event-outside-window",
                calendarIdentifier: "calendar-1",
                title: event.title,
                notes: exactNotes,
                url: event.managementURL,
                isAllDay: true,
                startDate: dates.startDate.addingTimeInterval(-3 * 86_400),
                endDate: dates.endDate.addingTimeInterval(-3 * 86_400),
                timeZoneIdentifier: event.timeZoneIdentifier,
                alarmOffsets: event.alarmOffsets
            )
        )
        store.seedPhysicalEvent(
            PhysicalCalendarEvent(
                identifier: "event-similar-marker",
                calendarIdentifier: "calendar-1",
                title: event.title,
                notes: "Pro\n\nSubscription Manager Projection UID: renewal-1-extra",
                url: event.managementURL,
                isAllDay: true,
                startDate: dates.startDate,
                endDate: dates.endDate,
                timeZoneIdentifier: event.timeZoneIdentifier,
                alarmOffsets: event.alarmOffsets
            )
        )
        let mappings = CalendarMappingFixture()
        mappings.seedCalendarIdentifier("calendar-1")
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )

        let result = await importer.importProjection(events: [event])

        #expect(
            result == .imported(
                CalendarProjectionImportSummary(
                    createdCount: 0,
                    updatedCount: 0
                )
            )
        )
        #expect(
            store.physicalEventIdentifiers == [
                "event-7",
                "event-wrong-calendar",
                "event-outside-window",
                "event-similar-marker"
            ]
        )
        #expect(try mappings.eventIdentifier(for: event.uid) == "event-7")
        #expect(try mappings.eventMappings() == [
            CalendarProjectionEventMapping(
                projectionUID: event.uid,
                eventIdentifier: "event-7"
            )
        ])
        #expect(store.saveCount == 0)
    }

    @Test("Direct import recovers a stale mapped identifier before saving")
    func directImportRecoversStaleMappedIdentifier() async throws {
        let event = calendarEvent(uid: "renewal-1")
        let dates = EventKitCalendarProjectionSemantics.allDayDates(
            for: event
        )
        let store = CalendarEventStoreFixture(access: .granted)
        store.seedCalendar(identifier: "calendar-1")
        store.seedPhysicalEvent(
            PhysicalCalendarEvent(
                identifier: "event-rotated",
                calendarIdentifier: "calendar-1",
                title: "Outdated title",
                notes: "Outdated notes\n\n"
                    + EventKitCalendarProjectionSemantics
                    .projectionUIDMarker(for: event.uid),
                url: event.managementURL,
                isAllDay: true,
                startDate: dates.startDate,
                endDate: dates.endDate,
                timeZoneIdentifier: event.timeZoneIdentifier,
                alarmOffsets: event.alarmOffsets
            )
        )
        let mappings = CalendarMappingFixture()
        mappings.seedCalendarIdentifier("calendar-1")
        mappings.seedEventIdentifier("event-stale", for: event.uid)
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )

        let result = await importer.importProjection(events: [event])

        #expect(
            result == .imported(
                CalendarProjectionImportSummary(
                    createdCount: 0,
                    updatedCount: 1
                )
            )
        )
        #expect(store.physicalEventIdentifiers == ["event-rotated"])
        #expect(store.savedEventIdentifiers == ["event-rotated"])
        #expect(store.savedProjectionEvents == [event])
        #expect(
            try mappings.eventIdentifier(for: event.uid) == "event-rotated"
        )
        #expect(store.saveCount == 1)
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

    @Test("Rebuild preserves partial import failure")
    func rebuildPreservesPartialImportFailure() async {
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

        let result = await importer.perform(.rebuild(events))

        #expect(result == .partialFailure(failedCount: 1))
        #expect(store.savedEventIdentifiers == ["event-1"])
    }

    @Test("Reconciliation preserves successful sibling writes after one failure")
    func reconciliationPreservesSuccessfulSiblingWritesAfterFailure() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let first = calendarEvent(uid: "renewal-1")
        let second = calendarEvent(uid: "renewal-2")
        _ = await importer.importProjection(events: [first, second])

        store.failingUIDs = [first.uid]
        let revisedFirst = projection(from: first, title: "Failed update")
        let revisedSecond = projection(from: second, title: "Successful update")

        let result = await importer.perform(
            .reconcile([revisedFirst, revisedSecond])
        )

        #expect(result == .partialFailure(failedCount: 1))
        #expect(store.saveCount == 3)
        #expect(store.savedProjectionEvents == [first, second, revisedSecond])
        #expect(try mappings.eventIdentifier(for: second.uid) == "event-2")
    }

    @Test("Reconciliation reports mapping persistence failure and continues")
    func reconciliationReportsMappingPersistenceFailureAndContinues() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let first = calendarEvent(uid: "renewal-1")
        let second = calendarEvent(uid: "renewal-2")
        _ = await importer.importProjection(events: [first, second])

        mappings.failNextEventMappingSave = true
        let revisedFirst = projection(from: first, title: "Mapping failure")
        let revisedSecond = projection(from: second, title: "Continued update")

        let result = await importer.perform(
            .reconcile([revisedFirst, revisedSecond])
        )

        #expect(result == .partialFailure(failedCount: 1))
        #expect(store.saveCount == 4)
        #expect(
            store.savedProjectionEvents
                == [first, second, revisedFirst, revisedSecond]
        )
        #expect(try mappings.eventIdentifier(for: first.uid) == "event-1")
        #expect(try mappings.eventIdentifier(for: second.uid) == "event-2")
    }

    @Test("A preflight mapping read failure remains unavailable")
    func preflightMappingReadFailureRemainsUnavailable() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        store.seedCalendar(identifier: "calendar-1")
        let mappings = CalendarMappingFixture()
        mappings.seedCalendarIdentifier("calendar-1")
        mappings.failEventMappingsRead = true
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )

        let result = await importer.perform(
            .reconcile([calendarEvent(uid: "renewal-1")])
        )

        #expect(result == .unavailable)
        #expect(store.saveCount == 0)
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

    @Test("A stale mapping save failure rolls back for a safe retry")
    func staleMappingSaveFailureIsRetryable() async throws {
        let store = CalendarEventStoreFixture(access: .granted)
        let mappings = CalendarMappingFixture()
        let importer = EventKitCalendarProjectionImporter(
            eventStore: store,
            mappingRepository: mappings
        )
        let current = calendarEvent(uid: "renewal-1")
        let stale = calendarEvent(uid: "renewal-2")

        _ = await importer.importProjection(events: [current, stale])
        mappings.failNextEventMappingRemovalSave = true

        let firstResult = await importer.perform(.reconcile([current]))

        #expect(firstResult == .partialFailure(failedCount: 1))
        #expect(store.physicalEventIdentifiers == ["event-1"])
        #expect(try mappings.eventIdentifier(for: current.uid) == "event-1")
        #expect(try mappings.eventIdentifier(for: stale.uid) == "event-2")
        #expect(store.savedProjectionEvents == [current, stale])

        let secondResult = await importer.perform(.reconcile([current]))

        #expect(secondResult == .reconciled)
        #expect(store.physicalEventIdentifiers == ["event-1"])
        #expect(try mappings.eventIdentifier(for: current.uid) == "event-1")
        #expect(try mappings.eventIdentifier(for: stale.uid) == nil)
        #expect(try mappings.eventMappings() == [
            CalendarProjectionEventMapping(
                projectionUID: current.uid,
                eventIdentifier: "event-1"
            )
        ])
        #expect(store.savedProjectionEvents == [current, stale])
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
    var calendarIdentifier: String
    let title: String
    var notes: String
    let url: URL?
    var isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let timeZoneIdentifier: String?
    let alarmOffsets: [Int]

    var managedFields: EventKitCalendarProjectionManagedFields {
        EventKitCalendarProjectionManagedFields(
            title: title,
            notes: notes,
            url: url,
            isAllDay: isAllDay,
            startDate: startDate,
            endDate: endDate,
            timeZoneIdentifier: timeZoneIdentifier,
            alarmOffsets: alarmOffsets.map { TimeInterval($0) * 86_400 },
            calendarIdentifier: calendarIdentifier
        )
    }
}

@MainActor
private final class CalendarEventStoreFixture: CalendarEventStore {
    let access: CalendarEventAccess
    var accessRequestCount = 0
    var calendarCreationCount = 0
    var saveCount = 0
    var eventIdentifierLookupCount = 0
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
            EventKitCalendarProjectionSemantics
                .containsExactProjectionUIDMarker(
                    in: $0.value.notes,
                    uid: uid
                )
        })?.key else {
            return
        }
        physicalEventsByIdentifier.removeValue(forKey: identifier)
    }

    func mutatePhysicalEvent(
        identifier: String,
        _ mutate: (inout PhysicalCalendarEvent) -> Void
    ) {
        guard var event = physicalEventsByIdentifier[identifier] else {
            Issue.record(
                "No physical calendar event \(identifier) to mutate."
            )
            return
        }
        mutate(&event)
        physicalEventsByIdentifier[identifier] = event
    }

    func seedCalendar(identifier: String) {
        calendar = CalendarProjectionCalendar(identifier: identifier)
    }

    func seedPhysicalEvent(_ event: PhysicalCalendarEvent) {
        physicalEventsByIdentifier[event.identifier] = event
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
        eventIdentifierLookupCount += 1
        let recoveryInterval = EventKitCalendarProjectionSemantics
            .recoveryInterval(for: projection)
        return physicalEventsByIdentifier.values.first { event in
            event.calendarIdentifier == calendar.identifier
                && event.startDate < recoveryInterval.end
                && event.endDate > recoveryInterval.start
                && EventKitCalendarProjectionSemantics
                    .containsExactProjectionUIDMarker(
                        in: event.notes,
                        uid: projectionUID
                    )
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
            ?? nextEventIdentifier()
        let allDayDates = EventKitCalendarProjectionSemantics.allDayDates(
            for: event
        )
        let desiredEvent = PhysicalCalendarEvent(
            identifier: eventIdentifier,
            calendarIdentifier: calendar.identifier,
            title: event.title,
            notes: EventKitCalendarProjectionSemantics.projectionNotes(
                for: event
            ),
            url: event.managementURL,
            isAllDay: true,
            startDate: allDayDates.startDate,
            endDate: allDayDates.endDate,
            timeZoneIdentifier: event.timeZoneIdentifier,
            alarmOffsets: event.alarmOffsets
        )
        if let existingEvent,
           EventKitCalendarProjectionSemantics.eventMatchesProjection(
               existingEvent.managedFields,
               projection: event,
               calendar: calendar
           )
        {
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

    private var nextEventIdentifierValue = 1

    private func nextEventIdentifier() -> String {
        defer { nextEventIdentifierValue += 1 }
        return "event-\(nextEventIdentifierValue)"
    }
}

@MainActor
private final class CalendarMappingFixture: CalendarProjectionMappingRepository {
    private var calendarID: String?
    private var isDisabled = false
    private var eventIDs: [String: String] = [:]
    var failNextEventMappingSave = false
    var failNextEventMappingRemovalSave = false
    var failEventMappingsRead = false

    func calendarIdentifier() throws -> String? { calendarID }

    func isCalendarSyncDisabled() throws -> Bool { isDisabled }

    func setCalendarSyncDisabled(_ disabled: Bool) throws {
        isDisabled = disabled
    }

    func saveCalendarIdentifier(_ identifier: String) throws {
        calendarID = identifier
    }

    func seedCalendarIdentifier(_ identifier: String) {
        calendarID = identifier
    }

    func seedEventIdentifier(_ identifier: String, for projectionUID: String) {
        eventIDs[projectionUID] = identifier
    }

    func eventIdentifier(for projectionUID: String) throws -> String? {
        eventIDs[projectionUID]
    }

    func eventMappings() throws -> [CalendarProjectionEventMapping] {
        if failEventMappingsRead {
            throw CalendarEventStoreError.writeFailed
        }
        return eventIDs.map {
            CalendarProjectionEventMapping(
                projectionUID: $0.key,
                eventIdentifier: $0.value
            )
        }
    }

    func removeEventMapping(for projectionUID: String) throws {
        let removedEventIdentifier = eventIDs.removeValue(forKey: projectionUID)
        if failNextEventMappingRemovalSave {
            failNextEventMappingRemovalSave = false
            if let removedEventIdentifier {
                eventIDs[projectionUID] = removedEventIdentifier
            }
            throw CalendarEventStoreError.writeFailed
        }
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

private func calendarEvent(
    uid: String,
    timeZoneIdentifier: String = "UTC"
) -> CalendarProjectionEvent {
    CalendarProjectionEvent(
        uid: uid,
        startDate: Date(timeIntervalSince1970: 1_785_628_800),
        endDate: Date(timeIntervalSince1970: 1_785_715_200),
        title: "Atlas — US$12.99",
        notes: "Pro",
        managementURL: URL(string: "https://example.com/manage")!,
        alarmOffsets: [-7, -1],
        timeZoneIdentifier: timeZoneIdentifier
    )
}

private enum ManagedFieldChange: CaseIterable {
    case title
    case notesAndUIDMarker
    case url
    case allDay
    case start
    case end
    case timeZone
    case alarms
    case targetCalendar
}

private func projection(
    from event: CalendarProjectionEvent,
    startDate: Date? = nil,
    endDate: Date? = nil,
    title: String? = nil,
    notes: String? = nil,
    managementURL: URL? = nil,
    alarmOffsets: [Int]? = nil,
    timeZoneIdentifier: String? = nil
) -> CalendarProjectionEvent {
    CalendarProjectionEvent(
        uid: event.uid,
        startDate: startDate ?? event.startDate,
        endDate: endDate ?? event.endDate,
        title: title ?? event.title,
        notes: notes ?? event.notes,
        managementURL: managementURL ?? event.managementURL,
        alarmOffsets: alarmOffsets ?? event.alarmOffsets,
        timeZoneIdentifier: timeZoneIdentifier ?? event.timeZoneIdentifier
    )
}
