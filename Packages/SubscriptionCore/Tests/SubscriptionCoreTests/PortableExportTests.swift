import Foundation
import Testing
@testable import SubscriptionCore

@Suite("Portable exports")
struct PortableExportTests {

    @Test("Widget privacy presentation omits amounts but keeps stable deep links")
    func widgetPrivacyPresentationRedactsAmount() {
        let identifier = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_704_067_200),
            nextRenewal: WidgetRenewalSnapshot(
                subscriptionID: identifier,
                serviceName: "Atlas",
                renewalDate: Date(timeIntervalSince1970: 1_706_745_600),
                amountDescription: "US$9.99",
                isRateStale: true
            )
        )

        let presentation = WidgetPresentationBuilder().makePresentation(
            snapshot: snapshot,
            privacy: .redacted,
            dateFormatter: { _ in "Jan 31" }
        )

        #expect(presentation.title == "Atlas")
        #expect(presentation.subtitle == "Rates are stale · Jan 31")
        #expect(presentation.amountDescription == nil)
        #expect(
            presentation.deepLink == URL(
                string: "subscription-manager://subscription/"
                    + identifier.uuidString
            )
        )
    }

    @Test("Widget snapshots round trip through a local shared store")
    func widgetSnapshotStoreRoundTripsOnlyCurrentSchema() {
        let suiteName = "SubscriptionCoreTests.WidgetSnapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_704_067_200),
            nextRenewal: nil
        )
        let store = WidgetSnapshotStore(defaults: defaults)

        store.write(snapshot)

        #expect(store.read() == snapshot)
    }
    @Test("A versioned backup round trips stable subscription and preference data")
    func backupRoundTrips() throws {
        let subscription = Subscription(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!,
            serviceIdentity: ServiceIdentity(rawValue: "atlas"),
            serviceName: "Atlas, 国际版",
            plan: "Pro\nAnnual",
            category: "Productivity",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            billingCycle: .yearly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_735_689_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: "A \"quoted\" note",
            confirmedCharges: [
                ConfirmedCharge(
                    id: UUID(uuidString: "99999999-2222-3333-4444-555555555556")!,
                    chargedDate: Date(timeIntervalSince1970: 1_704_067_200),
                    amount: Money(minorUnits: 1_299, currency: .usd)
                )
            ],
            priceChanges: [
                PriceChange(
                    id: UUID(uuidString: "99999999-2222-3333-4444-555555555557")!,
                    effectiveDate: Date(timeIntervalSince1970: 1_735_689_600),
                    amount: Money(minorUnits: 1_499, currency: .usd)
                )
            ],
            lifecycle: .active,
            isArchived: true,
            pinnedAt: Date(timeIntervalSince1970: 1_736_000_000.75)
        )
        let backup = PortableBackup(
            preferences: UserPreferences(
                primaryCurrency: .cny,
                calendarProjectionHorizon: .sixMonths,
                hideAmountsInCalendar: true,
                setupStatus: .completed
            ),
            subscriptions: [subscription]
        )

        let encoder = PortableBackupEncoder()
        let firstExport = try encoder.encode(backup)
        let secondExport = try encoder.encode(backup)
        let decoded = try encoder.decode(firstExport)
        let repeatedExport = try encoder.decode(secondExport)

        #expect(decoded == backup)
        #expect(repeatedExport == decoded)
        #expect(decoded.schemaVersion == 1)
        #expect(
            decoded.subscriptions.first?.pinnedAt
                == Date(timeIntervalSince1970: 1_736_000_000.75)
        )
    }

    @Test("Backups still decode legacy ISO 8601 dates")
    func backupDecodesLegacyDates() throws {
        let subscription = Subscription(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555558")!,
            serviceIdentity: ServiceIdentity(rawValue: "atlas"),
            serviceName: "Atlas",
            plan: "Pro",
            category: "Productivity",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_706_745_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: ""
        )
        let data = try PortableBackupEncoder().encode(
            PortableBackup(
                preferences: .default,
                subscriptions: [subscription]
            )
        )
        let numericDate = "1704067200"
        let legacyDate = "\"2024-01-01T00:00:00Z\""
        let legacyData = Data(
            String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: numericDate, with: legacyDate)
                .utf8
        )

        let decoded = try PortableBackupEncoder().decode(legacyData)

        #expect(decoded.subscriptions.first?.startDate == subscription.startDate)
    }

    @Test("CSV quotes Unicode commas quotes and line breaks with machine money")
    func csvEscapesMachineReadableFields() throws {
        let subscription = Subscription(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!,
            serviceIdentity: ServiceIdentity(rawValue: "atlas"),
            serviceName: "Atlas, 国际版",
            plan: "Pro\nAnnual",
            category: "Productivity",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            billingCycle: .yearly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_735_689_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: "A \"quoted\" note",
            isArchived: true,
            pinnedAt: Date(timeIntervalSince1970: 1_736_000_000)
        )

        let data = PortableCSVEncoder().encode(
            preferences: .default,
            subscriptions: [subscription]
        )
        let rows = try CSVFixtureParser().parse(data)

        #expect(rows.count == 2)
        #expect(rows[0][0] == "subscription_id")
        #expect(rows[1][1] == "Atlas, 国际版")
        #expect(rows[1][2] == "Pro\nAnnual")
        #expect(rows[1][6] == "1299")
        #expect(rows[1][7] == "USD")
        #expect(rows[1][11].isEmpty)
        #expect(rows[1][12] == "A \"quoted\" note")
        #expect(rows[1][13] == "true")
        #expect(rows[0][14] == "pinned_at")
        #expect(rows[1][14] == "2025-01-04T14:13:20Z")
    }

    @Test("Workspace export includes archived records without changing the library")
    @MainActor
    func workspaceExportIsReadOnlyAndIncludesArchivedSubscriptions() throws {
        let archived = Subscription(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!,
            serviceIdentity: ServiceIdentity(rawValue: "atlas"),
            serviceName: "Atlas",
            plan: "Pro",
            category: "Productivity",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            billingCycle: .yearly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_735_689_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: "",
            isArchived: true
        )
        let repository = ExportRepositoryFixture(
            subscriptions: [archived]
        )
        let workspace = SubscriptionWorkspace(repository: repository)

        let backup = try #require(workspace.makePortableBackup())

        #expect(backup.subscriptions == [archived])
        #expect(try repository.listSubscriptions() == [archived])
    }

    @Test("Backup validation rejects unsupported schemas and previews stable merge buckets")
    func validatorAndMergePlannerRejectAndClassify() throws {
        let unchanged = portableSubscription(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Unchanged"
        )
        let conflictFromBackup = portableSubscription(
            id: UUID(uuidString: "22222222-2222-3333-4444-555555555555")!,
            name: "Backup name"
        )
        let addition = portableSubscription(
            id: UUID(uuidString: "33333333-2222-3333-4444-555555555555")!,
            name: "Addition"
        )
        let backup = PortableBackup(
            preferences: .default,
            subscriptions: [addition, conflictFromBackup, unchanged]
        )
        let validData = try PortableBackupEncoder().encode(backup)
        let invalidText = try #require(String(data: validData, encoding: .utf8))
            .replacingOccurrences(
                of: PortableBackup.schemaName,
                with: "unknown-backup"
            )

        #expect(
            throws: PortableBackupValidationError.unsupportedSchema
        ) {
            try PortableBackupValidator().decode(Data(invalidText.utf8))
        }

        let conflictLocal = portableSubscription(
            id: conflictFromBackup.id,
            name: "Local name"
        )
        let retainedLocal = portableSubscription(
            id: UUID(uuidString: "44444444-2222-3333-4444-555555555555")!,
            name: "Retained"
        )
        let preview = try PortableBackupMergePlanner().makePreview(
            backup: backup,
            localSubscriptions: [retainedLocal, conflictLocal, unchanged],
            localPreferences: .default
        )

        #expect(preview.additions == [addition])
        #expect(preview.unchangedSubscriptionIDs == [unchanged.id])
        #expect(preview.conflicts == [
            PortableBackupMergeConflict(
                local: conflictLocal,
                backup: conflictFromBackup
            )
        ])
        #expect(preview.retainedLocalSubscriptionIDs == [retainedLocal.id])
        #expect(preview.preferences == .unchanged)
    }

    @Test("Workspace only submits a fully resolved portable merge")
    @MainActor
    func workspaceSubmitsResolvedPortableMergeOnce() throws {
        let local = portableSubscription(
            id: UUID(uuidString: "55555555-2222-3333-4444-555555555555")!,
            name: "Local"
        )
        let backupVersion = portableSubscription(id: local.id, name: "Backup")
        let addition = portableSubscription(
            id: UUID(uuidString: "66666666-2222-3333-4444-555555555555")!,
            name: "Addition"
        )
        let repository = ExportRepositoryFixture(subscriptions: [local])
        let importer = RecordingPortableImportRepository()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            portableBackupImportRepository: importer
        )
        let data = try PortableBackupEncoder().encode(
            PortableBackup(preferences: .default, subscriptions: [backupVersion, addition])
        )
        let preview = try workspace.preparePortableBackupImport(data)

        #expect(throws: PortableBackupImportError.incompleteConflictResolution) {
            try workspace.applyPortableBackupImport(
                preview: preview,
                selectedAdditionIDs: Set([addition.id]),
                conflictResolutions: [:],
                preferencesResolution: nil
            )
        }
        #expect(importer.merges.isEmpty)

        try workspace.applyPortableBackupImport(
            preview: preview,
            selectedAdditionIDs: Set([addition.id]),
            conflictResolutions: [local.id: .useBackup],
            preferencesResolution: nil
        )
        #expect(importer.merges == [
            PortableBackupMerge(
                additions: [addition],
                replacements: [backupVersion],
                preferences: nil
            )
        ])
    }

    @Test("Backup replacement refreshes loaded subscription consumers")
    @MainActor
    func backupReplacementRefreshesLoadedConsumers() throws {
        let id = UUID(
            uuidString: "77777777-2222-3333-4444-555555555555"
        )!
        let local = portableSubscription(id: id, name: "Local")
        let confirmedCharge = ConfirmedCharge(
            id: UUID(
                uuidString: "88888888-2222-3333-4444-555555555555"
            )!,
            chargedDate: Date(timeIntervalSince1970: 1_706_745_600),
            amount: Money(minorUnits: 1_999, currency: .usd),
            sourceScheduledChargeID: ScheduledChargeID(
                subscriptionID: id,
                year: 2024,
                month: 2,
                day: 1
            )
        )
        let backupVersion = portableSubscription(
            id: id,
            name: "Backup",
            amount: Money(minorUnits: 1_999, currency: .usd),
            confirmedCharges: [confirmedCharge]
        )
        let repository = ExportRepositoryFixture(subscriptions: [local])
        let importer = ApplyingPortableImportRepository(
            repository: repository
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            portableBackupImportRepository: importer
        )
        let data = try PortableBackupEncoder().encode(
            PortableBackup(
                preferences: .default,
                subscriptions: [backupVersion]
            )
        )
        let preview = try workspace.preparePortableBackupImport(data)

        workspace.loadSubscription(id: id)
        workspace.loadExpectedCharges(
            subscriptionID: id,
            through: .distantFuture,
            maximumCount: 1
        )
        #expect(workspace.expectedCharges?.first?.amount == local.originalAmount)
        #expect(
            workspace.paymentHistory.contains(.confirmed(confirmedCharge))
                == false
        )

        try workspace.applyPortableBackupImport(
            preview: preview,
            selectedAdditionIDs: [],
            conflictResolutions: [id: .useBackup],
            preferencesResolution: nil
        )

        guard case .loaded(let detail, _, _) = workspace.detailState else {
            Issue.record("Expected refreshed imported detail")
            return
        }
        #expect(detail.serviceName == "Backup")
        #expect(
            workspace.expectedCharges?.first?.amount
                == backupVersion.originalAmount
        )
        #expect(
            workspace.paymentHistory.contains(.confirmed(confirmedCharge))
        )
    }
}

private struct CSVFixtureParser {
    func parse(_ data: Data) throws -> [[String]] {
        let text = try #require(String(data: data, encoding: .utf8))
        var rows: [[String]] = [[]]
        var field = ""
        var isQuoted = false
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                if isQuoted, index + 1 < scalars.count,
                   scalars[index + 1] == "\""
                {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if scalar == ",", !isQuoted {
                rows[rows.count - 1].append(field)
                field = ""
            } else if scalar == "\n", !isQuoted {
                rows[rows.count - 1].append(field)
                rows.append([])
                field = ""
            } else if scalar != "\r" {
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !rows[rows.count - 1].isEmpty {
            rows[rows.count - 1].append(field)
        } else {
            rows.removeLast()
        }
        return rows
    }
}

@MainActor
private final class ExportRepositoryFixture: SubscriptionRepository {
    private var subscriptions: [UUID: Subscription]

    init(subscriptions: [Subscription]) {
        self.subscriptions = Dictionary(
            uniqueKeysWithValues: subscriptions.map { ($0.id, $0) }
        )
    }

    func createSubscription(_ subscription: Subscription) throws {
        subscriptions[subscription.id] = subscription
    }

    func updateSubscription(_ subscription: Subscription) throws {
        subscriptions[subscription.id] = subscription
    }

    func deleteSubscription(id: UUID) throws {
        subscriptions.removeValue(forKey: id)
    }

    func listSubscriptions() throws -> [Subscription] {
        subscriptions.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func subscription(id: UUID) throws -> Subscription? { subscriptions[id] }
}

@MainActor
private final class RecordingPortableImportRepository: PortableBackupImportRepository {
    private(set) var merges: [PortableBackupMerge] = []

    func apply(_ merge: PortableBackupMerge) throws {
        merges.append(merge)
    }
}

@MainActor
private final class ApplyingPortableImportRepository:
    PortableBackupImportRepository
{
    private let repository: ExportRepositoryFixture

    init(repository: ExportRepositoryFixture) {
        self.repository = repository
    }

    func apply(_ merge: PortableBackupMerge) throws {
        for addition in merge.additions {
            try repository.createSubscription(addition)
        }
        for replacement in merge.replacements {
            try repository.updateSubscription(replacement)
        }
    }
}

private func portableSubscription(
    id: UUID,
    name: String,
    amount: Money = Money(minorUnits: 999, currency: .usd),
    confirmedCharges: [ConfirmedCharge] = []
) -> Subscription {
    Subscription(
        id: id,
        serviceIdentity: ServiceIdentity(rawValue: name.lowercased()),
        serviceName: name,
        plan: "Standard",
        category: "Other",
        originalAmount: amount,
        billingCycle: .monthly,
        startDate: Date(timeIntervalSince1970: 1_704_067_200),
        confirmedNextRenewal: Date(timeIntervalSince1970: 1_706_745_600),
        billingTimeZoneIdentifier: "UTC",
        managementURL: nil,
        notes: "",
        confirmedCharges: confirmedCharges
    )
}
