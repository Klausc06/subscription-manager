import CloudKit
import Foundation
import SwiftData
import SubscriptionCore
import Testing
@testable import SubscriptionManager

private enum Task4LegacySchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [UserPreferencesRecord.self]
    }

    @Model
    final class UserPreferencesRecord {
        var primaryCurrencyRawValue: String = "CNY"
        var calendarProjectionHorizonMonths: Int = 12
        var hideAmountsInCalendar: Bool = false
        var menuBarModeEnabled: Bool = false
        var setupStatusRawValue: String = "notCompleted"

        init(
            primaryCurrencyRawValue: String = "CNY",
            calendarProjectionHorizonMonths: Int = 12,
            hideAmountsInCalendar: Bool = false,
            menuBarModeEnabled: Bool = false,
            setupStatusRawValue: String = "notCompleted"
        ) {
            self.primaryCurrencyRawValue = primaryCurrencyRawValue
            self.calendarProjectionHorizonMonths =
                calendarProjectionHorizonMonths
            self.hideAmountsInCalendar = hideAmountsInCalendar
            self.menuBarModeEnabled = menuBarModeEnabled
            self.setupStatusRawValue = setupStatusRawValue
        }
    }
}

private enum Task4CurrentSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SubscriptionManager.UserPreferencesRecord.self]
    }
}

private enum Task4MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [Task4LegacySchema.self, Task4CurrentSchema.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: Task4LegacySchema.self,
                toVersion: Task4CurrentSchema.self
            ),
        ]
    }
}

private final class ReloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

@MainActor
private struct StubLegacyCalendarProjectionMappingValidator:
    LegacyCalendarProjectionMappingValidating
{
    let availability: LegacyCalendarProjectionMappingValidationAvailability
    let calendarIdentifiers: Set<String>
    let eventIdentifiersByCalendarIdentifier: [String: Set<String>]

    func containsCalendar(identifier: String) -> Bool {
        calendarIdentifiers.contains(identifier)
    }

    func containsEvent(
        identifier: String,
        inCalendarWithIdentifier calendarIdentifier: String
    ) -> Bool {
        eventIdentifiersByCalendarIdentifier[calendarIdentifier]?
            .contains(identifier) == true
    }

    static let unavailable = Self(
        availability: .unavailable,
        calendarIdentifiers: [],
        eventIdentifiersByCalendarIdentifier: [:]
    )

    static func available(
        calendarIdentifier: String,
        eventIdentifiers: Set<String>
    ) -> Self {
        Self(
            availability: .available,
            calendarIdentifiers: [calendarIdentifier],
            eventIdentifiersByCalendarIdentifier: [
                calendarIdentifier: eventIdentifiers,
            ]
        )
    }
}

struct AppDependenciesTests {
    @Test("Production SwiftData schema is compatible with CloudKit")
    @MainActor
    func productionSchemaSupportsCloudKit() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerCloudKitSchemaTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let schema = Schema([
            SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            UserPreferencesRecord.self,
        ])
        let configuration = ModelConfiguration(
            "CloudKitCompatibility",
            schema: schema,
            url: directory.appending(path: "CloudKitCompatibility.store"),
            cloudKitDatabase: .private(AppDependencies.cloudKitContainerID)
        )

        _ = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    @Test("Only production storage selects the private CloudKit container")
    @MainActor
    func cloudKitSelectionKeepsUITestingOffline() {
        #expect(
            AppDependencies.cloudKitSelection(for: .production)
                == .privateContainer(AppDependencies.cloudKitContainerID)
        )
        #expect(
            AppDependencies.cloudKitSelection(
                for: .production,
                hasCloudKitEntitlement: false
            ) == .disabled
        )
        #expect(
            AppDependencies.cloudKitSelection(for: .ephemeralUITesting)
                == .disabled
        )
        #expect(
            AppDependencies.cloudKitSelection(
                for: .namedUITesting(token: "fixture")
            ) == .disabled
        )
    }

    @Test("CloudKit account states map to user-visible library sync states")
    @MainActor
    func cloudKitAccountStatusMapsToSyncStatus() async {
        let signedOut = CloudKitLibrarySyncMonitor(
            accountStatus: { .noAccount }
        )
        let available = CloudKitLibrarySyncMonitor(
            accountStatus: { .available }
        )

        #expect(await signedOut.refreshStatus() == .signedOut)
        #expect(await available.refreshStatus() == .synchronizing)
    }

    @Test("A completed remote import becomes current and reloads once")
    @MainActor
    func completedRemoteImportBecomesCurrentAndReloadsOnce() async {
        let reloads = ReloadCounter()
        let monitor = CloudKitLibrarySyncMonitor(
            accountStatus: { .available },
            onRemoteImport: { reloads.increment() }
        )
        let eventID = UUID(
            uuidString: "70000000-0000-4000-8000-000000000001"
        )!

        #expect(await monitor.refreshStatus() == .synchronizing)
        await monitor.notifyRemoteImport(id: eventID)
        await monitor.notifyRemoteImport(id: eventID)

        #expect(await monitor.refreshStatus() == .current)
        #expect(reloads.value == 1)
    }

    @Test("CloudKit event deduplication evicts the oldest ID at its fixed capacity")
    @MainActor
    func cloudKitEventDeduplicationEvictsOldestIDAtFixedCapacity() async throws {
        let reloads = ReloadCounter()
        let monitor = CloudKitLibrarySyncMonitor(
            accountStatus: { .available },
            onRemoteImport: { reloads.increment() }
        )

        func eventID(_ index: Int) throws -> UUID {
            try #require(
                UUID(
                    uuidString: String(
                        format: "70000000-0000-4000-8000-%012d",
                        index
                    )
                )
            )
        }

        let oldestID = try eventID(1)
        await monitor.notifyRemoteImport(id: oldestID)
        await monitor.notifyRemoteImport(id: oldestID)
        #expect(reloads.value == 1)

        for index in 2...256 {
            await monitor.notifyRemoteImport(id: try eventID(index))
        }
        #expect(reloads.value == 256)

        await monitor.notifyRemoteImport(id: try eventID(2))
        await monitor.notifyRemoteImport(id: oldestID)
        #expect(reloads.value == 256)

        await monitor.notifyRemoteImport(id: try eventID(257))
        await monitor.notifyRemoteImport(id: oldestID)
        await monitor.notifyRemoteImport(id: oldestID)
        await monitor.notifyRemoteImport(id: try eventID(2))
        #expect(reloads.value == 259)
    }

    @Test("A remote import preserves archived scope and reloads requested consumers")
    @MainActor
    func completedRemoteImportReloadsArchivedWorkspaceState() async throws {
        let monitor = CloudKitLibrarySyncMonitor(
            accountStatus: { .available }
        )
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        guard case .ready(let dependencies) = AppDependencies.make(
            syncMonitor: monitor,
            modelContainer: { container }
        ) else {
            Issue.record("Expected a ready application dependency graph")
            return
        }

        let archivedRecord = SubscriptionRecord(
            id: UUID(
                uuidString: "70000000-0000-4000-8000-000000000002"
            )!
        )
        archivedRecord.serviceName = "Before remote import"
        archivedRecord.isArchived = true
        let currentRecord = SubscriptionRecord(
            id: UUID(
                uuidString: "70000000-0000-4000-8000-000000000008"
            )!
        )
        currentRecord.serviceName = "Current record"
        container.mainContext.insert(archivedRecord)
        container.mainContext.insert(currentRecord)
        try container.mainContext.save()

        dependencies.workspace.loadLibrary(scope: .archived)
        dependencies.workspace.loadSubscription(id: archivedRecord.id)

        archivedRecord.serviceName = "Imported remotely"
        try container.mainContext.save()

        await monitor.notifyRemoteImport(
            id: UUID(uuidString: "70000000-0000-4000-8000-000000000003")!
        )

        guard case .loaded(.archived, let summaries) =
            dependencies.workspace.libraryState
        else {
            Issue.record("Expected the workspace to retain archived scope")
            return
        }
        #expect(summaries.count == 1)
        #expect(summaries.first?.id == archivedRecord.id)
        #expect(summaries.first?.serviceName == "Imported remotely")
        guard case .loaded(let subscription, _, _) =
            dependencies.workspace.detailState
        else {
            Issue.record("Expected the requested detail to reload")
            return
        }
        #expect(subscription.serviceName == "Imported remotely")
    }

    @Test("The remote import callback does not retain the workspace")
    @MainActor
    func remoteImportCallbackDoesNotRetainWorkspace() async throws {
        let monitor = CloudKitLibrarySyncMonitor(
            accountStatus: { .available }
        )
        weak var weakWorkspace: SubscriptionWorkspace?
        do {
            let container = try ModelContainer(
                for: SubscriptionRecord.self,
                configurations: ModelConfiguration(
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            )
            guard case .ready(let dependencies) = AppDependencies.make(
                syncMonitor: monitor,
                modelContainer: { container }
            ) else {
                Issue.record("Expected a ready application dependency graph")
                return
            }
            weakWorkspace = dependencies.workspace
            #expect(weakWorkspace != nil)
        }
        #expect(weakWorkspace == nil)
        let eventID = try #require(
            UUID(
                uuidString: "70000000-0000-4000-8000-000000000009"
            )
        )

        await monitor.notifyRemoteImport(id: eventID)

        #expect(await monitor.refreshStatus() == .current)
    }

    @Test("A completed export becomes current without reloading")
    @MainActor
    func completedExportBecomesCurrentWithoutReloading() async {
        let reloads = ReloadCounter()
        let monitor = CloudKitLibrarySyncMonitor(
            accountStatus: { .available },
            onRemoteImport: { reloads.increment() }
        )

        #expect(await monitor.refreshStatus() == .synchronizing)
        monitor.notifySuccessfulExport(
            id: UUID(uuidString: "70000000-0000-4000-8000-000000000004")!
        )

        #expect(await monitor.refreshStatus() == .current)
        #expect(reloads.value == 0)
    }

    @Test("A completed setup becomes current without reloading")
    @MainActor
    func completedSetupBecomesCurrentWithoutReloading() async {
        let reloads = ReloadCounter()
        let monitor = CloudKitLibrarySyncMonitor(
            accountStatus: { .available },
            onRemoteImport: { reloads.increment() }
        )

        #expect(await monitor.refreshStatus() == .synchronizing)
        monitor.notifySuccessfulSetup(
            id: UUID(uuidString: "70000000-0000-4000-8000-000000000005")!
        )

        #expect(await monitor.refreshStatus() == .current)
        #expect(reloads.value == 0)
    }

    @Test("A failed terminal event requires attention until a later success")
    @MainActor
    func failedTerminalEventRequiresAttentionUntilSuccess() async {
        let monitor = CloudKitLibrarySyncMonitor(
            accountStatus: { .available }
        )

        monitor.notifyFailedEvent(
            id: UUID(uuidString: "70000000-0000-4000-8000-000000000006")!
        )
        #expect(await monitor.refreshStatus() == .requiresAttention)

        monitor.notifySuccessfulExport(
            id: UUID(uuidString: "70000000-0000-4000-8000-000000000007")!
        )
        #expect(await monitor.refreshStatus() == .current)
    }

    @Test("Calendar projection mappings use a local-only model configuration")
    @MainActor
    func calendarProjectionMappingsUseLocalOnlyConfiguration() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerConfigurationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        guard case .ready(let dependencies) = AppDependencies.live(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                "configuration-ownership",
            ],
            storeDirectory: rootDirectory,
            isRunningTests: false,
            hasCloudKitEntitlement: false,
            hasAppGroupEntitlement: false
        ) else {
            Issue.record("Expected a ready application dependency graph")
            return
        }

        let mappingEntityName = Schema.entityName(
            for: CalendarProjectionMappingRecord.self
        )
        let subscriptionEntityName = Schema.entityName(for: SubscriptionRecord.self)
        let mappingConfigurations = dependencies.modelContainer.configurations
            .filter {
                $0.schema?.entitiesByName[mappingEntityName] != nil
            }
        let subscriptionConfigurations = dependencies.modelContainer.configurations
            .filter {
                $0.schema?.entitiesByName[subscriptionEntityName] != nil
            }

        #expect(mappingConfigurations.count == 1)
        #expect(
            mappingConfigurations.allSatisfy {
                $0.cloudKitContainerIdentifier == nil
            }
        )
        #expect(
            subscriptionConfigurations.allSatisfy {
                $0.schema?.entitiesByName[mappingEntityName] == nil
            }
        )

        let mappingRepository = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: dependencies.modelContainer
        )
        try mappingRepository.saveEventIdentifier(
            "event-local",
            for: "projection-local",
            calendarIdentifier: "calendar-local"
        )
        #expect(
            try mappingRepository.eventIdentifier(for: "projection-local")
                == "event-local"
        )
    }

    @Test("Legacy calendar projection mappings move to the local store")
    @MainActor
    func legacyCalendarProjectionMappingsMoveToLocalStore() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerMappingMigration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let token = "mapping-migration"
        let storeDirectory = rootDirectory.appending(
            path: "SubscriptionManagerUITests",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let legacyStoreURL = storeDirectory.appending(path: "\(token).store")

        do {
            let legacySchema = Schema([
                SubscriptionRecord.self,
                ConfirmedChargeRecord.self,
                PriceChangeRecord.self,
                UserPreferencesRecord.self,
                CalendarProjectionMappingRecord.self,
            ])
            let legacyConfiguration = ModelConfiguration(
                "LegacyCalendarMappings",
                schema: legacySchema,
                url: legacyStoreURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [legacyConfiguration]
            )
            let metadata = CalendarProjectionMappingRecord(
                calendarIdentifier: "legacy-calendar"
            )
            metadata.calendarSyncDisabled = true
            legacyContainer.mainContext.insert(metadata)
            legacyContainer.mainContext.insert(
                CalendarProjectionMappingRecord(
                    projectionUID: "legacy-projection",
                    eventIdentifier: "legacy-event",
                    calendarIdentifier: "legacy-calendar"
                )
            )
            try legacyContainer.mainContext.save()
        }

        do {
            guard case .ready(let dependencies) = AppDependencies.live(
                arguments: [
                    "SubscriptionManager",
                    "--ui-testing",
                    "--ui-testing-store",
                    token,
                ],
                storeDirectory: rootDirectory,
                isRunningTests: false,
                hasCloudKitEntitlement: false,
                hasAppGroupEntitlement: false,
                legacyCalendarProjectionMappingValidator:
                    StubLegacyCalendarProjectionMappingValidator.available(
                        calendarIdentifier: "legacy-calendar",
                        eventIdentifiers: ["legacy-event"]
                    )
            ) else {
                Issue.record("Expected migrated application dependencies")
                return
            }
            let mappings = SwiftDataCalendarProjectionMappingRepository(
                modelContainer: dependencies.modelContainer
            )

            #expect(try mappings.calendarIdentifier() == "legacy-calendar")
            #expect(try mappings.isCalendarSyncDisabled())
            #expect(
                try mappings.eventIdentifier(for: "legacy-projection")
                    == "legacy-event"
            )
            try mappings.removeEventMapping(for: "legacy-projection")
            #expect(
                try mappings.eventIdentifier(for: "legacy-projection") == nil
            )
        }

        guard case .ready(let relaunchedDependencies) = AppDependencies.live(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                token,
            ],
            storeDirectory: rootDirectory,
            isRunningTests: false,
            hasCloudKitEntitlement: false,
            hasAppGroupEntitlement: false,
            legacyCalendarProjectionMappingValidator:
                StubLegacyCalendarProjectionMappingValidator.unavailable
        ) else {
            Issue.record("Expected relaunched application dependencies")
            return
        }
        let relaunchedMappings = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: relaunchedDependencies.modelContainer
        )
        #expect(
            try relaunchedMappings.eventIdentifier(for: "legacy-projection")
                == nil
        )
    }

    @Test("Unavailable legacy mapping validation leaves migration retryable")
    @MainActor
    func unavailableLegacyMappingValidationLeavesMigrationRetryable() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerRetryableMappingMigration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let token = "retryable-mapping-migration"
        let storeDirectory = rootDirectory.appending(
            path: "SubscriptionManagerUITests",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let legacyStoreURL = storeDirectory.appending(path: "\(token).store")
        let legacySchema = Schema([
            SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self,
        ])

        do {
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [
                    ModelConfiguration(
                        "LegacyCalendarMappings",
                        schema: legacySchema,
                        url: legacyStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .none
                    )
                ]
            )
            legacyContainer.mainContext.insert(
                CalendarProjectionMappingRecord(
                    calendarIdentifier: "current-calendar"
                )
            )
            legacyContainer.mainContext.insert(
                CalendarProjectionMappingRecord(
                    projectionUID: "current-projection",
                    eventIdentifier: "current-event",
                    calendarIdentifier: "current-calendar"
                )
            )
            try legacyContainer.mainContext.save()
        }

        do {
            guard case .ready(let dependencies) = AppDependencies.live(
                arguments: [
                    "SubscriptionManager",
                    "--ui-testing",
                    "--ui-testing-store",
                    token,
                ],
                storeDirectory: rootDirectory,
                isRunningTests: false,
                hasCloudKitEntitlement: false,
                hasAppGroupEntitlement: false,
                legacyCalendarProjectionMappingValidator:
                    StubLegacyCalendarProjectionMappingValidator.unavailable
            ) else {
                Issue.record("Expected dependencies while validation is unavailable")
                return
            }
            let records = try dependencies.modelContainer.mainContext.fetch(
                FetchDescriptor<CalendarProjectionMappingRecord>()
            )

            #expect(records.isEmpty)
        }

        guard case .ready(let dependencies) = AppDependencies.live(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                token,
            ],
            storeDirectory: rootDirectory,
            isRunningTests: false,
            hasCloudKitEntitlement: false,
            hasAppGroupEntitlement: false,
            legacyCalendarProjectionMappingValidator:
                StubLegacyCalendarProjectionMappingValidator.available(
                    calendarIdentifier: "current-calendar",
                    eventIdentifiers: ["current-event"]
                )
        ) else {
            Issue.record("Expected dependencies after validation becomes available")
            return
        }
        let mappings = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: dependencies.modelContainer
        )
        let records = try dependencies.modelContainer.mainContext.fetch(
            FetchDescriptor<CalendarProjectionMappingRecord>()
        )

        #expect(try mappings.calendarIdentifier() == "current-calendar")
        #expect(
            try mappings.eventIdentifier(for: "current-projection")
                == "current-event"
        )
        #expect(
            records.first(where: { $0.projectionUID.isEmpty })?
                .legacyMappingMigrationCompleted == true
        )
    }

    @Test("Mixed legacy mapping rows migrate only current-device identifiers")
    @MainActor
    func mixedLegacyMappingRowsMigrateOnlyCurrentDeviceIdentifiers() throws {
        for foreignRowsFirst in [true, false] {
            let rootDirectory = FileManager.default.temporaryDirectory.appending(
                path: "SubscriptionManagerMixedMappingMigration-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            defer { try? FileManager.default.removeItem(at: rootDirectory) }
            let token = foreignRowsFirst
                ? "mixed-mapping-foreign-first"
                : "mixed-mapping-current-first"
            let storeDirectory = rootDirectory.appending(
                path: "SubscriptionManagerUITests",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true
            )
            let legacyStoreURL = storeDirectory.appending(path: "\(token).store")
            let legacySchema = Schema([
                SubscriptionRecord.self,
                ConfirmedChargeRecord.self,
                PriceChangeRecord.self,
                UserPreferencesRecord.self,
                CalendarProjectionMappingRecord.self,
            ])

            do {
                let legacyContainer = try ModelContainer(
                    for: legacySchema,
                    configurations: [
                        ModelConfiguration(
                            "LegacyCalendarMappings",
                            schema: legacySchema,
                            url: legacyStoreURL,
                            allowsSave: true,
                            cloudKitDatabase: .none
                        )
                    ]
                )
                let orderedCalendarIdentifiers = foreignRowsFirst
                    ? ["foreign-calendar", "current-calendar"]
                    : ["current-calendar", "foreign-calendar"]
                for calendarIdentifier in orderedCalendarIdentifiers {
                    let isCurrentDevice = calendarIdentifier == "current-calendar"
                    let metadata = CalendarProjectionMappingRecord(
                        calendarIdentifier: calendarIdentifier
                    )
                    metadata.calendarSyncDisabled = isCurrentDevice
                    legacyContainer.mainContext.insert(metadata)
                    legacyContainer.mainContext.insert(
                        CalendarProjectionMappingRecord(
                            projectionUID: isCurrentDevice
                                ? "current-projection"
                                : "foreign-projection",
                            eventIdentifier: isCurrentDevice
                                ? "current-event"
                                : "foreign-event",
                            calendarIdentifier: calendarIdentifier
                        )
                    )
                    if isCurrentDevice {
                        legacyContainer.mainContext.insert(
                            CalendarProjectionMappingRecord(
                                projectionUID: "unresolvable-current-projection",
                                eventIdentifier: "unresolvable-current-event",
                                calendarIdentifier: calendarIdentifier
                            )
                        )
                    }
                }
                try legacyContainer.mainContext.save()
            }

            let validator = StubLegacyCalendarProjectionMappingValidator(
                availability: .available,
                calendarIdentifiers: ["current-calendar"],
                eventIdentifiersByCalendarIdentifier: [
                    "current-calendar": ["current-event"],
                ]
            )
            guard case .ready(let dependencies) = AppDependencies.live(
                arguments: [
                    "SubscriptionManager",
                    "--ui-testing",
                    "--ui-testing-store",
                    token,
                ],
                storeDirectory: rootDirectory,
                isRunningTests: false,
                hasCloudKitEntitlement: false,
                hasAppGroupEntitlement: false,
                legacyCalendarProjectionMappingValidator: validator
            ) else {
                Issue.record("Expected mixed mappings to migrate")
                continue
            }
            let mappings = SwiftDataCalendarProjectionMappingRepository(
                modelContainer: dependencies.modelContainer
            )

            #expect(try mappings.calendarIdentifier() == "current-calendar")
            #expect(try mappings.isCalendarSyncDisabled())
            #expect(
                try mappings.eventIdentifier(for: "current-projection")
                    == "current-event"
            )
            #expect(
                try mappings.eventIdentifier(for: "foreign-projection") == nil
            )
            #expect(
                try mappings.eventIdentifier(
                    for: "unresolvable-current-projection"
                ) == nil
            )
        }
    }

    @Test("Entirely foreign legacy mappings complete without importing identifiers")
    @MainActor
    func entirelyForeignLegacyMappingsCompleteWithoutImportingIdentifiers() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerForeignMappingMigration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let token = "foreign-mapping-migration"
        let storeDirectory = rootDirectory.appending(
            path: "SubscriptionManagerUITests",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let legacyStoreURL = storeDirectory.appending(path: "\(token).store")
        let legacySchema = Schema([
            SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self,
        ])

        do {
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [
                    ModelConfiguration(
                        "LegacyCalendarMappings",
                        schema: legacySchema,
                        url: legacyStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .none
                    )
                ]
            )
            legacyContainer.mainContext.insert(
                CalendarProjectionMappingRecord(
                    calendarIdentifier: "foreign-calendar"
                )
            )
            legacyContainer.mainContext.insert(
                CalendarProjectionMappingRecord(
                    projectionUID: "foreign-projection",
                    eventIdentifier: "foreign-event",
                    calendarIdentifier: "foreign-calendar"
                )
            )
            try legacyContainer.mainContext.save()
        }

        let validator = StubLegacyCalendarProjectionMappingValidator(
            availability: .available,
            calendarIdentifiers: [],
            eventIdentifiersByCalendarIdentifier: [:]
        )
        guard case .ready(let dependencies) = AppDependencies.live(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                token,
            ],
            storeDirectory: rootDirectory,
            isRunningTests: false,
            hasCloudKitEntitlement: false,
            hasAppGroupEntitlement: false,
            legacyCalendarProjectionMappingValidator: validator
        ) else {
            Issue.record("Expected foreign mappings to complete safely")
            return
        }
        let mappings = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: dependencies.modelContainer
        )
        let records = try dependencies.modelContainer.mainContext.fetch(
            FetchDescriptor<CalendarProjectionMappingRecord>()
        )

        #expect(try mappings.calendarIdentifier() == nil)
        #expect(
            try mappings.eventIdentifier(for: "foreign-projection") == nil
        )
        #expect(records.count == 1)
        #expect(
            records.first?.legacyMappingMigrationCompleted == true
        )
    }

    @Test("An existing local mapping store stays authoritative during migration upgrade")
    @MainActor
    func existingLocalMappingStoreStaysAuthoritativeDuringMigrationUpgrade() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerMappingUpgrade-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let token = "mapping-upgrade"
        let storeDirectory = rootDirectory.appending(
            path: "SubscriptionManagerUITests",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let legacyStoreURL = storeDirectory.appending(path: "\(token).store")
        let localStoreURL = storeDirectory.appending(
            path: "\(token).calendar-mappings.store"
        )

        do {
            let legacySchema = Schema([
                SubscriptionRecord.self,
                ConfirmedChargeRecord.self,
                PriceChangeRecord.self,
                UserPreferencesRecord.self,
                CalendarProjectionMappingRecord.self,
            ])
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [
                    ModelConfiguration(
                        "LegacyCalendarMappings",
                        schema: legacySchema,
                        url: legacyStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .none
                    )
                ]
            )
            legacyContainer.mainContext.insert(
                CalendarProjectionMappingRecord(
                    projectionUID: "deleted-local-projection",
                    eventIdentifier: "stale-legacy-event",
                    calendarIdentifier: "legacy-calendar"
                )
            )
            try legacyContainer.mainContext.save()
        }

        do {
            let localSchema = Schema([
                CalendarProjectionMappingRecord.self,
            ])
            let localContainer = try ModelContainer(
                for: localSchema,
                configurations: [
                    ModelConfiguration(
                        "LocalCalendarMappings",
                        schema: localSchema,
                        url: localStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .none
                    )
                ]
            )
            localContainer.mainContext.insert(
                CalendarProjectionMappingRecord(
                    calendarIdentifier: "local-calendar"
                )
            )
            try localContainer.mainContext.save()
        }

        guard case .ready(let dependencies) = AppDependencies.live(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                token,
            ],
            storeDirectory: rootDirectory,
            isRunningTests: false,
            hasCloudKitEntitlement: false,
            hasAppGroupEntitlement: false,
            legacyCalendarProjectionMappingValidator:
                StubLegacyCalendarProjectionMappingValidator.unavailable
        ) else {
            Issue.record("Expected upgraded application dependencies")
            return
        }
        let mappings = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: dependencies.modelContainer
        )
        let records = try dependencies.modelContainer.mainContext.fetch(
            FetchDescriptor<CalendarProjectionMappingRecord>()
        )

        #expect(try mappings.calendarIdentifier() == "local-calendar")
        #expect(
            try mappings.eventIdentifier(for: "deleted-local-projection")
                == nil
        )
        #expect(
            records.first(where: { $0.projectionUID.isEmpty })?
                .legacyMappingMigrationCompleted == true
        )
    }

    @Test("An empty legacy mapping store remains unconfigured after migration")
    @MainActor
    func emptyLegacyMappingStoreRemainsUnconfiguredAfterMigration() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerEmptyMappingMigration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let token = "empty-mapping-migration"
        let storeDirectory = rootDirectory.appending(
            path: "SubscriptionManagerUITests",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let legacyStoreURL = storeDirectory.appending(path: "\(token).store")
        let legacySchema = Schema([
            SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self,
        ])
        _ = try ModelContainer(
            for: legacySchema,
            configurations: [
                ModelConfiguration(
                    "EmptyLegacyCalendarMappings",
                    schema: legacySchema,
                    url: legacyStoreURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            ]
        )

        guard case .ready(let dependencies) = AppDependencies.live(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                token,
            ],
            storeDirectory: rootDirectory,
            isRunningTests: false,
            hasCloudKitEntitlement: false,
            hasAppGroupEntitlement: false,
            legacyCalendarProjectionMappingValidator:
                StubLegacyCalendarProjectionMappingValidator(
                    availability: .available,
                    calendarIdentifiers: [],
                    eventIdentifiersByCalendarIdentifier: [:]
                )
        ) else {
            Issue.record("Expected migrated application dependencies")
            return
        }
        let mappings = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: dependencies.modelContainer
        )
        let records = try dependencies.modelContainer.mainContext.fetch(
            FetchDescriptor<CalendarProjectionMappingRecord>()
        )

        #expect(try mappings.calendarIdentifier() == nil)
        #expect(
            records.first(where: { $0.projectionUID.isEmpty })?
                .legacyMappingMigrationCompleted == true
        )
    }

    @Test("A named UI testing store is ignored outside UI testing")
    @MainActor
    func namedStoreRequiresUITestingMode() throws {
        let selection = try AppDependencies.storeSelection(
            arguments: [
                "SubscriptionManager",
                "--ui-testing-store",
                "must-not-select-a-test-store",
            ]
        )

        #expect(selection == .production)
    }

    @Test("UI testing can select a named persistent store")
    @MainActor
    func namedStoreIsAvailableInUITestingMode() throws {
        let selection = try AppDependencies.storeSelection(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                "relaunch-contract",
            ]
        )

        #expect(selection == .namedUITesting(token: "relaunch-contract"))
    }

    @Test("Preferences survive a SwiftData repository reload")
    @MainActor
    func preferencesRoundTripThroughSwiftData() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let expected = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths,
            hideAmountsInCalendar: true,
            menuBarModeEnabled: true,
            appearanceMode: .dark,
            setupStatus: .completed
        )

        try SwiftDataUserPreferencesRepository(modelContainer: container)
            .savePreferences(expected)

        let reloaded = try SwiftDataUserPreferencesRepository(
            modelContainer: container
        ).loadPreferences()

        #expect(reloaded == expected)
    }

    @Test("Duplicate preferences merge into the stable canonical record")
    @MainActor
    func duplicatePreferencesMergeDeterministically() throws {
        let container = try ModelContainer(
            for: UserPreferencesRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let duplicate = UserPreferencesRecord(
            id: UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!,
            primaryCurrencyRawValue: "EUR",
            calendarProjectionHorizonMonths: 6,
            hideAmountsInCalendar: true,
            menuBarModeEnabled: true,
            appearanceModeRawValue: "dark",
            setupStatusRawValue: "completed"
        )
        let canonical = UserPreferencesRecord(
            id: UserPreferencesRecord.canonicalID,
            primaryCurrencyRawValue: "USD",
            calendarProjectionHorizonMonths: 12,
            hideAmountsInCalendar: false,
            menuBarModeEnabled: false,
            appearanceModeRawValue: "light",
            setupStatusRawValue: "notCompleted"
        )
        context.insert(duplicate)
        context.insert(canonical)
        try context.save()

        let repository = SwiftDataUserPreferencesRepository(
            modelContainer: container
        )
        let loaded = try repository.loadPreferences()
        #expect(
            loaded == UserPreferences(
                primaryCurrency: .usd,
                calendarProjectionHorizon: .twelveMonths,
                hideAmountsInCalendar: false,
                menuBarModeEnabled: false,
                appearanceMode: .light,
                setupStatus: .notCompleted
            )
        )

        let remaining = try context.fetch(
            FetchDescriptor<UserPreferencesRecord>()
        )
        #expect(remaining.count == 2)
        #expect(
            remaining.contains { $0.id == UserPreferencesRecord.canonicalID }
        )
        #expect(remaining.contains { $0.id == duplicate.id })
    }

    @Test("Legacy duplicate preferences use a deterministic value tie-break")
    @MainActor
    func legacyDuplicatePreferencesUseDeterministicValueTieBreak() throws {
        let container = try ModelContainer(
            for: UserPreferencesRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let first = UserPreferencesRecord(
            id: UserPreferencesRecord.canonicalID,
            primaryCurrencyRawValue: "USD"
        )
        let second = UserPreferencesRecord(
            id: UserPreferencesRecord.canonicalID,
            primaryCurrencyRawValue: "EUR"
        )
        let context = ModelContext(container)
        context.insert(first)
        context.insert(second)
        try context.save()

        let loaded = try SwiftDataUserPreferencesRepository(
            modelContainer: container
        ).loadPreferences()

        #expect(loaded?.primaryCurrency == .eur)
        #expect(
            try context.fetch(FetchDescriptor<UserPreferencesRecord>()).count
                == 2
        )
    }

    @Test("All appearance modes survive repository rebuilds")
    @MainActor
    func appearanceModesRoundTrip() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let repository = SwiftDataUserPreferencesRepository(
            modelContainer: container
        )

        for appearanceMode in AppearanceMode.allCases {
            let expected = UserPreferences(
                primaryCurrency: .usd,
                calendarProjectionHorizon: .twelveMonths,
                appearanceMode: appearanceMode,
                setupStatus: .completed
            )
            try repository.savePreferences(expected)
            let reloaded = try SwiftDataUserPreferencesRepository(
                modelContainer: container
            ).loadPreferences()
            #expect(reloaded == expected)
        }

    }

    @Test("Reopening a real pre-appearance store defaults the missing field to system")
    @MainActor
    func reopeningLegacyStoreDefaultsMissingAppearanceToSystem() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerTask4LegacyStore-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storeURL = directory.appending(path: "SubscriptionManager.store")

        do {
            let legacySchema = Schema(versionedSchema: Task4LegacySchema.self)
            let legacyConfiguration = ModelConfiguration(
                "Task4Legacy",
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [legacyConfiguration]
            )
            let context = ModelContext(legacyContainer)
            context.insert(
                Task4LegacySchema.UserPreferencesRecord(
                    primaryCurrencyRawValue: "EUR",
                    calendarProjectionHorizonMonths: 6,
                    setupStatusRawValue: "completed"
                )
            )
            try context.save()
        }

        let currentSchema = Schema(versionedSchema: Task4CurrentSchema.self)
        let currentConfiguration = ModelConfiguration(
            "Task4Current",
            schema: currentSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let reopenedContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: Task4MigrationPlan.self,
            configurations: [currentConfiguration]
        )

        let migratedPreferences = try SwiftDataUserPreferencesRepository(
            modelContainer: reopenedContainer
        ).loadPreferences()
        #expect(migratedPreferences?.primaryCurrency == .eur)
        #expect(migratedPreferences?.calendarProjectionHorizon == .sixMonths)
        #expect(migratedPreferences?.setupStatus == .completed)
        #expect(migratedPreferences?.appearanceMode == .system)
    }

    @Test("Calendar projection mappings survive a SwiftData repository reload")
    @MainActor
    func calendarProjectionMappingsRoundTripThroughSwiftData() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let repository = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: container
        )

        try repository.saveCalendarIdentifier("calendar-1")
        try repository.saveEventIdentifier(
            "event-1",
            for: "renewal-1",
            calendarIdentifier: "calendar-1"
        )
        try repository.saveCalendarIdentifier("calendar-2")

        let reloaded = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: container
        )

        #expect(try reloaded.calendarIdentifier() == "calendar-2")
        #expect(try reloaded.eventIdentifier(for: "renewal-1") == "event-1")
    }

    @Test("Exchange-rate cache preserves snapshots and refresh attempts")
    @MainActor
    func exchangeRateCacheRoundTripsState() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_769_356_800)
        let expected = ExchangeRateCacheState(
            snapshot: ExchangeRateSnapshot(
                base: .eur,
                providerDate: now,
                fetchedAt: now,
                source: "fixture",
                rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
            ),
            lastAttemptAt: now
        )
        let cache = FileExchangeRateCache(directory: directory)

        try cache.saveState(expected)

        #expect(try cache.loadState() == expected)
    }

    @Test("Frankfurter v2 rates decode only complete requested quotes")
    @MainActor
    func frankfurterRatesDecodeIntoSnapshot() throws {
        let data = Data("""
        [
          {"date":"2026-07-29","base":"EUR","quote":"CNY","rate":8.4},
          {"date":"2026-07-29","base":"EUR","quote":"USD","rate":1.2}
        ]
        """.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 1_769_356_800)

        let snapshot = try FrankfurterExchangeRateSource.decodeSnapshot(
            data: data,
            base: .eur,
            quotes: [.cny, .usd],
            fetchedAt: fetchedAt
        )

        #expect(snapshot.base == .eur)
        #expect(snapshot.rates == [.eur: 1, .cny: 8.4, .usd: 1.2])
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.source == "Frankfurter v2")
    }
}
