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
        let encodedBackup = try #require(
            String(data: data, encoding: .utf8)
        )
        let legacyData = Data(
            encodedBackup
                .replacingOccurrences(of: numericDate, with: legacyDate)
                .utf8
        )

        let decoded = try PortableBackupEncoder().decode(legacyData)

        #expect(decoded.subscriptions.first?.startDate == subscription.startDate)
    }

    @Test("Blank optional metadata survives backup validation and preview")
    func blankOptionalMetadataSurvivesValidationAndPreview() throws {
        let subscription = Subscription(
            id: try #require(
                UUID(uuidString: "99999999-2222-3333-4444-555555555559")
            ),
            serviceIdentity: ServiceIdentity(rawValue: "manual:blank-metadata"),
            serviceName: "Atlas",
            plan: "",
            category: " \n\t ",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_706_745_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: ""
        )
        let backup = PortableBackup(
            preferences: .default,
            subscriptions: [subscription]
        )
        let data = try PortableBackupEncoder().encode(backup)

        let validated = try PortableBackupValidator().decode(
            data,
            asOf: portableBackupValidationAsOf
        )
        let preview = try PortableBackupMergePlanner().makePreview(
            backup: validated,
            localSubscriptions: [],
            localPreferences: .default,
            asOf: portableBackupValidationAsOf
        )

        #expect(validated.subscriptions == [subscription])
        #expect(preview.additions == [subscription])
        #expect(preview.conflicts.isEmpty)
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

    @Test("CSV exports spreadsheet formulas as documented literal text")
    func csvExportsSpreadsheetFormulasAsLiteralText() throws {
        let subscription = Subscription(
            id: try #require(
                UUID(uuidString: "99999999-2222-3333-4444-555555555560")
            ),
            serviceIdentity: ServiceIdentity(rawValue: "manual:csv-literal"),
            serviceName: "=SUM(1,2), 国际 \"版\"\n续行",
            plan: " \t+SUM(1,2)",
            category: "\u{000B}-国际",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_706_745_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: "\n@quoted \"value\""
        )

        let data = PortableCSVEncoder().encode(
            preferences: .default,
            subscriptions: [subscription]
        )
        let rows = try CSVFixtureParser().parse(data)

        #expect(rows[1][1] == "'=SUM(1,2), 国际 \"版\"\n续行")
        #expect(rows[1][2] == "' \t+SUM(1,2)")
        #expect(rows[1][3] == "'\u{000B}-国际")
        #expect(rows[1][4] == "manual:csv-literal")
        #expect(rows[1][12] == "'\n@quoted \"value\"")
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

    @Test(
        "Export reports skipped unreadable records without including them"
    )
    @MainActor
    func exportReportsSkippedUnreadableRecords() throws {
        let firstGood = portableSubscription(
            id: UUID(uuidString: "12111111-2222-3333-4444-555555555555")!,
            name: "Good one"
        )
        let secondGood = portableSubscription(
            id: UUID(uuidString: "12222222-2222-3333-4444-555555555555")!,
            name: "Good two"
        )
        let repository = SkippedRecordRepositoryFixture(
            readableSubscriptions: [firstGood, secondGood],
            skippedRecordCount: 1
        )
        let workspace = SubscriptionWorkspace(repository: repository)

        let export = try #require(workspace.makePortableBackupExport())

        #expect(export.backup.subscriptions == [firstGood, secondGood])
        #expect(export.skippedRecordCount == 1)
    }

    @Test("A clean library export reports no skipped records")
    @MainActor
    func cleanLibraryExportReportsNoSkippedRecords() throws {
        let subscription = portableSubscription(
            id: UUID(uuidString: "12333333-2222-3333-4444-555555555555")!,
            name: "Only good"
        )
        let repository = SkippedRecordRepositoryFixture(
            readableSubscriptions: [subscription],
            skippedRecordCount: 0
        )
        let workspace = SubscriptionWorkspace(repository: repository)

        let export = try #require(workspace.makePortableBackupExport())

        #expect(export.backup.subscriptions == [subscription])
        #expect(export.skippedRecordCount == 0)
    }

    @Test(
        "Repositories without skip reporting export zero skipped records"
    )
    @MainActor
    func repositoriesWithoutSkipReportingDefaultToZeroSkipped() throws {
        let subscription = portableSubscription(
            id: UUID(uuidString: "12444444-2222-3333-4444-555555555555")!,
            name: "Reported"
        )
        let repository = ExportRepositoryFixture(subscriptions: [subscription])
        let workspace = SubscriptionWorkspace(repository: repository)

        let export = try #require(workspace.makePortableBackupExport())

        #expect(export.backup.subscriptions == [subscription])
        #expect(export.skippedRecordCount == 0)
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
            try PortableBackupValidator().decode(
                Data(invalidText.utf8),
                asOf: portableBackupValidationAsOf
            )
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
            localPreferences: .default,
            asOf: portableBackupValidationAsOf
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

    @Test(
        "Invalid subscription facts are rejected before merge preview"
    )
    func invalidSubscriptionFactsAreRejectedBeforePreview() throws {
        for fixture in InvalidPortableSubscriptionFixture.allCases {
            let backup = PortableBackup(
                preferences: .default,
                subscriptions: [try fixture.makeSubscription()]
            )
            let data = try PortableBackupEncoder().encode(backup)

            #expect(
                throws: PortableBackupValidationError.invalidSubscription
            ) {
                try PortableBackupValidator().decode(
                    data,
                    asOf: portableBackupValidationAsOf
                )
            }
            #expect(
                throws: PortableBackupValidationError.invalidSubscription
            ) {
                try PortableBackupMergePlanner().makePreview(
                    backup: backup,
                    localSubscriptions: [],
                    localPreferences: .default,
                    asOf: portableBackupValidationAsOf
                )
            }
        }
    }

    @Test("Cancellation ordering uses the billing-local day")
    func cancellationOrderingUsesBillingLocalDay() throws {
        let subscription = portableSubscription(
            id: try #require(
                UUID(uuidString: "88888888-2222-3333-4444-555555555570")
            ),
            name: "Same-day cancellation",
            lifecycle: .cancelled(
                cancelledAt: Date(timeIntervalSince1970: 1_706_788_800),
                accessUntil: Date(timeIntervalSince1970: 1_706_745_600)
            )
        )
        let backup = PortableBackup(
            preferences: .default,
            subscriptions: [subscription]
        )
        let data = try PortableBackupEncoder().encode(backup)

        let validated = try PortableBackupValidator().decode(
            data,
            asOf: portableBackupValidationAsOf
        )
        let preview = try PortableBackupMergePlanner().makePreview(
            backup: backup,
            localSubscriptions: [],
            localPreferences: .default,
            asOf: portableBackupValidationAsOf
        )

        #expect(validated.subscriptions == [subscription])
        #expect(preview.additions == [subscription])
    }

    @Test("Historical confirmed source survives a later schedule edit")
    func historicalConfirmedSourceSurvivesScheduleEdit() throws {
        let subscriptionID = try #require(
            UUID(uuidString: "88888888-2222-3333-4444-555555555560")
        )
        let currentStart = Date(timeIntervalSince1970: 1_770_336_000)
        let historicalCharge = ConfirmedCharge(
            id: try #require(
                UUID(uuidString: "88888888-2222-3333-4444-555555555561")
            ),
            chargedDate: Date(timeIntervalSince1970: 1_706_832_000),
            amount: Money(minorUnits: 999, currency: .usd),
            sourceScheduledChargeID: ScheduledChargeID(
                subscriptionID: subscriptionID,
                year: 2024,
                month: 2,
                day: 1
            )
        )
        let subscription = portableSubscription(
            id: subscriptionID,
            name: "Edited schedule",
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: currentStart,
                timeZoneIdentifier: "UTC"
            ),
            startDate: currentStart,
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_772_755_200
            ),
            confirmedCharges: [historicalCharge]
        )
        let backup = PortableBackup(
            preferences: .default,
            subscriptions: [subscription]
        )
        let data = try PortableBackupEncoder().encode(backup)

        let validated = try PortableBackupValidator().decode(
            data,
            asOf: portableBackupValidationAsOf
        )
        let preview = try PortableBackupMergePlanner().makePreview(
            backup: backup,
            localSubscriptions: [],
            localPreferences: .default,
            asOf: portableBackupValidationAsOf
        )

        #expect(validated.subscriptions == [subscription])
        #expect(preview.additions == [subscription])
    }

    @Test("Rejected backup leaves storage and valid preview unchanged")
    @MainActor
    func rejectedBackupLeavesStorageAndPreviewUnchanged() throws {
        let local = portableSubscription(
            id: try #require(
                UUID(uuidString: "77777777-2222-3333-4444-555555555550")
            ),
            name: "Local"
        )
        let validAddition = portableSubscription(
            id: try #require(
                UUID(uuidString: "77777777-2222-3333-4444-555555555551")
            ),
            name: "Valid addition"
        )
        let repository = ExportRepositoryFixture(subscriptions: [local])
        let importer = RecordingPortableImportRepository()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            portableBackupImportRepository: importer,
            now: { portableBackupValidationAsOf }
        )
        let validData = try PortableBackupEncoder().encode(
            PortableBackup(
                preferences: .default,
                subscriptions: [validAddition]
            )
        )
        let previewBeforeRejection = try workspace
            .preparePortableBackupImport(validData)

        for fixture in [
            InvalidPortableSubscriptionFixture.futureScheduledCharge,
            .futureChargedDate,
            .futureCancellation,
        ] {
            let invalidData = try PortableBackupEncoder().encode(
                PortableBackup(
                    preferences: .default,
                    subscriptions: [try fixture.makeSubscription()]
                )
            )

            #expect(
                throws: PortableBackupValidationError.invalidSubscription
            ) {
                try workspace.preparePortableBackupImport(invalidData)
            }
        }

        let previewAfterRejection = try workspace
            .preparePortableBackupImport(validData)
        #expect(previewAfterRejection == previewBeforeRejection)
        #expect(try repository.listSubscriptions() == [local])
        #expect(importer.merges.isEmpty)
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
            portableBackupImportRepository: importer,
            now: { portableBackupValidationAsOf }
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
            portableBackupImportRepository: importer,
            now: { portableBackupValidationAsOf }
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
private final class SkippedRecordRepositoryFixture:
    SubscriptionRepository,
    SkippedRecordReporting
{
    private let readableSubscriptions: [Subscription]
    private let skippedRecordCount: Int
    private(set) var skippedRecordCountAfterLastLoad = 0

    init(
        readableSubscriptions: [Subscription],
        skippedRecordCount: Int
    ) {
        self.readableSubscriptions = readableSubscriptions
        self.skippedRecordCount = skippedRecordCount
    }

    func createSubscription(_ subscription: Subscription) throws {
        fatalError("Unused by export tests")
    }

    func updateSubscription(_ subscription: Subscription) throws {
        fatalError("Unused by export tests")
    }

    func deleteSubscription(id: UUID) throws {
        fatalError("Unused by export tests")
    }

    func listSubscriptions() throws -> [Subscription] {
        // Simulates the real repository's behavior: unreadable records are
        // dropped from the result and counted for reporting.
        skippedRecordCountAfterLastLoad = self.skippedRecordCount
        return readableSubscriptions.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }

    func subscription(id: UUID) throws -> Subscription? {
        readableSubscriptions.first { $0.id == id }
    }
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

private enum InvalidPortableSubscriptionFixture:
    CaseIterable,
    Sendable
{
    case trialFirstPaidBeforeStart
    case cancellationAccessBeforeCancellation
    case futureCancellation
    case unsupportedManagementURL
    case nonPositiveConfirmedCharge
    case duplicateConfirmedChargeID
    case duplicateScheduledCharge
    case foreignScheduledCharge
    case invalidScheduledChargeDate
    case futureScheduledCharge
    case futureChargedDate
    case nonPositivePriceChange
    case priceChangeBeforeStart
    case duplicatePriceChangeID
    case duplicatePriceChangeDay

    func makeSubscription() throws -> Subscription {
        let subscriptionID = try #require(
            UUID(uuidString: "88888888-2222-3333-4444-555555555550")
        )
        let firstChildID = try #require(
            UUID(uuidString: "88888888-2222-3333-4444-555555555551")
        )
        let secondChildID = try #require(
            UUID(uuidString: "88888888-2222-3333-4444-555555555552")
        )
        let foreignSubscriptionID = try #require(
            UUID(uuidString: "88888888-2222-3333-4444-555555555553")
        )
        let startDate = Date(timeIntervalSince1970: 1_704_067_200)
        let nextRenewal = Date(timeIntervalSince1970: 1_706_745_600)
        let scheduledChargeID = ScheduledChargeID(
            subscriptionID: subscriptionID,
            year: 2024,
            month: 2,
            day: 1
        )

        switch self {
        case .trialFirstPaidBeforeStart:
            return portableSubscription(
                id: subscriptionID,
                name: "Invalid trial ordering",
                startDate: startDate.addingTimeInterval(3_600),
                confirmedNextRenewal: nextRenewal,
                lifecycle: .trial(firstPaidChargeAt: startDate)
            )
        case .cancellationAccessBeforeCancellation:
            return portableSubscription(
                id: subscriptionID,
                name: "Invalid cancellation ordering",
                startDate: startDate,
                confirmedNextRenewal: nextRenewal,
                lifecycle: .cancelled(
                    cancelledAt: nextRenewal.addingTimeInterval(3_600),
                    accessUntil: nextRenewal.addingTimeInterval(-86_400)
                )
            )
        case .futureCancellation:
            return portableSubscription(
                id: subscriptionID,
                name: "Future cancellation",
                lifecycle: .cancelled(
                    cancelledAt: portableBackupValidationAsOf
                        .addingTimeInterval(86_400),
                    accessUntil: portableBackupValidationAsOf
                        .addingTimeInterval(172_800)
                )
            )
        case .unsupportedManagementURL:
            return portableSubscription(
                id: subscriptionID,
                name: "Invalid management URL",
                managementURL: URL(
                    filePath: "/tmp/portable-backup-invalid-management"
                )
            )
        case .nonPositiveConfirmedCharge:
            return portableSubscription(
                id: subscriptionID,
                name: "Invalid confirmed amount",
                confirmedCharges: [
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: startDate,
                        amount: Money(minorUnits: 0, currency: .usd)
                    )
                ]
            )
        case .duplicateConfirmedChargeID:
            return portableSubscription(
                id: subscriptionID,
                name: "Duplicate confirmed ID",
                confirmedCharges: [
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: startDate,
                        amount: Money(minorUnits: 999, currency: .usd)
                    ),
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: nextRenewal,
                        amount: Money(minorUnits: 999, currency: .usd)
                    )
                ]
            )
        case .duplicateScheduledCharge:
            return portableSubscription(
                id: subscriptionID,
                name: "Duplicate scheduled charge",
                confirmedCharges: [
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: startDate,
                        amount: Money(minorUnits: 999, currency: .usd),
                        sourceScheduledChargeID: scheduledChargeID
                    ),
                    ConfirmedCharge(
                        id: secondChildID,
                        chargedDate: nextRenewal,
                        amount: Money(minorUnits: 999, currency: .usd),
                        sourceScheduledChargeID: scheduledChargeID
                    )
                ]
            )
        case .foreignScheduledCharge:
            return portableSubscription(
                id: subscriptionID,
                name: "Foreign scheduled charge",
                confirmedCharges: [
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: startDate,
                        amount: Money(minorUnits: 999, currency: .usd),
                        sourceScheduledChargeID: ScheduledChargeID(
                            subscriptionID: foreignSubscriptionID,
                            year: 2024,
                            month: 2,
                            day: 1
                        )
                    )
                ]
            )
        case .invalidScheduledChargeDate:
            return portableSubscription(
                id: subscriptionID,
                name: "Invalid scheduled charge date",
                confirmedCharges: [
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: startDate,
                        amount: Money(minorUnits: 999, currency: .usd),
                        sourceScheduledChargeID: ScheduledChargeID(
                            subscriptionID: subscriptionID,
                            year: 2024,
                            month: 2,
                            day: 30
                        )
                    )
                ]
            )
        case .futureScheduledCharge:
            return portableSubscription(
                id: subscriptionID,
                name: "Future scheduled charge",
                confirmedCharges: [
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: startDate,
                        amount: Money(minorUnits: 999, currency: .usd),
                        sourceScheduledChargeID: ScheduledChargeID(
                            subscriptionID: subscriptionID,
                            year: 2030,
                            month: 1,
                            day: 1
                        )
                    )
                ]
            )
        case .futureChargedDate:
            return portableSubscription(
                id: subscriptionID,
                name: "Future charged date",
                confirmedCharges: [
                    ConfirmedCharge(
                        id: firstChildID,
                        chargedDate: Date(timeIntervalSince1970: 1_893_456_000),
                        amount: Money(minorUnits: 999, currency: .usd),
                        sourceScheduledChargeID: ScheduledChargeID(
                            subscriptionID: subscriptionID,
                            year: 2024,
                            month: 1,
                            day: 1
                        )
                    )
                ]
            )
        case .nonPositivePriceChange:
            return portableSubscription(
                id: subscriptionID,
                name: "Invalid price amount",
                priceChanges: [
                    PriceChange(
                        id: firstChildID,
                        effectiveDate: nextRenewal,
                        amount: Money(minorUnits: 0, currency: .usd)
                    )
                ]
            )
        case .priceChangeBeforeStart:
            return portableSubscription(
                id: subscriptionID,
                name: "Price change before start",
                priceChanges: [
                    PriceChange(
                        id: firstChildID,
                        effectiveDate: startDate.addingTimeInterval(-86_400),
                        amount: Money(minorUnits: 1_099, currency: .usd)
                    )
                ]
            )
        case .duplicatePriceChangeID:
            return portableSubscription(
                id: subscriptionID,
                name: "Duplicate price ID",
                priceChanges: [
                    PriceChange(
                        id: firstChildID,
                        effectiveDate: startDate,
                        amount: Money(minorUnits: 1_099, currency: .usd)
                    ),
                    PriceChange(
                        id: firstChildID,
                        effectiveDate: nextRenewal,
                        amount: Money(minorUnits: 1_199, currency: .usd)
                    )
                ]
            )
        case .duplicatePriceChangeDay:
            return portableSubscription(
                id: subscriptionID,
                name: "Duplicate price day",
                priceChanges: [
                    PriceChange(
                        id: firstChildID,
                        effectiveDate: nextRenewal,
                        amount: Money(minorUnits: 1_099, currency: .usd)
                    ),
                    PriceChange(
                        id: secondChildID,
                        effectiveDate: nextRenewal.addingTimeInterval(3_600),
                        amount: Money(minorUnits: 1_199, currency: .usd)
                    )
                ]
            )
        }
    }
}

private let portableBackupValidationAsOf = Date(
    timeIntervalSince1970: 1_800_000_000
)

private func portableSubscription(
    id: UUID,
    name: String,
    plan: String = "Standard",
    category: String = "Other",
    amount: Money = Money(minorUnits: 999, currency: .usd),
    billingSchedule: FixedBillingSchedule? = nil,
    startDate: Date = Date(timeIntervalSince1970: 1_704_067_200),
    confirmedNextRenewal: Date = Date(timeIntervalSince1970: 1_706_745_600),
    managementURL: URL? = nil,
    confirmedCharges: [ConfirmedCharge] = [],
    priceChanges: [PriceChange] = [],
    lifecycle: SubscriptionLifecycle = .active
) -> Subscription {
    Subscription(
        id: id,
        serviceIdentity: ServiceIdentity(rawValue: name.lowercased()),
        serviceName: name,
        plan: plan,
        category: category,
        originalAmount: amount,
        billingSchedule: billingSchedule ?? FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: startDate,
            timeZoneIdentifier: "UTC"
        ),
        startDate: startDate,
        confirmedNextRenewal: confirmedNextRenewal,
        managementURL: managementURL,
        notes: "",
        confirmedCharges: confirmedCharges,
        priceChanges: priceChanges,
        lifecycle: lifecycle
    )
}
