import Foundation
import SubscriptionCore
import Testing

@Suite("Subscription workspace")
struct SubscriptionWorkspaceTests {
    @Test("Calendar projection hides amounts and uses trial alarm offsets")
    @MainActor
    func calendarProjectionUsesPreferencesAndTrialAlarms() throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let renewal = try actionDate(
            year: 2026,
            month: 2,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let subscription = makeSubscription(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            lifecycle: .trial(firstPaidChargeAt: renewal),
            confirmedNextRenewal: renewal,
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            serviceName: "Atlas",
            plan: "Pro",
            notes: "Use the team account"
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(
                subscriptions: [subscription]
            ),
            preferencesRepository: CalendarPreferencesFixture(
                preferences: UserPreferences(
                    primaryCurrency: .usd,
                    calendarProjectionHorizon: .sixMonths,
                    hideAmountsInCalendar: true,
                    setupStatus: .completed
                )
            ),
            now: { now },
            calendar: calendar
        )

        workspace.loadSetup(libraryIsEmpty: false)
        workspace.loadCalendarProjection(locale: Locale(identifier: "en_US"))

        let first = try #require(workspace.calendarProjection.first)
        let expectedDate = try actionDate(
            year: 2026,
            month: 3,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        #expect(first.startDate == calendar.startOfDay(for: expectedDate))
        #expect(first.title == "Atlas")
        #expect(first.alarmOffsets == [-3, -1])
        #expect(!first.notes.contains("12.99"))
        #expect(first.notes.contains("Use the team account"))
    }

    @Test("Calendar import only starts after an explicit preview confirmation")
    @MainActor
    func calendarImportUsesThePreviewSnapshotAfterConfirmation() async throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let importer = CalendarImporterFixture(result: .accessDenied)
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(
                subscriptions: [
                    makeSubscription(
                        id: UUID(
                            uuidString: "99999999-2222-3333-4444-555555555555"
                        )!
                    )
                ]
            ),
            preferencesRepository: CalendarPreferencesFixture(
                preferences: UserPreferences(
                    primaryCurrency: .usd,
                    calendarProjectionHorizon: .sixMonths,
                    setupStatus: .completed
                )
            ),
            calendarProjectionImporter: importer,
            now: { now },
            calendar: calendar
        )

        workspace.loadSetup(libraryIsEmpty: false)
        workspace.loadCalendarProjection(locale: Locale(identifier: "en_US"))
        let preview = workspace.calendarProjection

        #expect(importer.importedEvents() == nil)
        #expect(workspace.calendarImportState == .notRequested)

        await workspace.importCalendarProjection(preview)

        #expect(importer.importedEvents() == preview)
        #expect(workspace.calendarImportState == .accessDenied)
    }

    @Test("Sync status remains local-first when iCloud is signed out")
    @MainActor
    func signedOutSyncStatusDoesNotBlockCreation() async throws {
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let repository = InMemorySubscriptionRepository()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            syncMonitor: SyncMonitorFixture(result: .signedOut)
        )

        await workspace.refreshSyncStatus()
        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Atlas",
                plan: "Monthly",
                category: "Productivity",
                originalAmount: Money(minorUnits: 999, currency: .usd),
                startDate: startDate,
                confirmedNextRenewal: renewalDate,
                managementURL: nil,
                notes: ""
            )
        )

        #expect(workspace.syncStatus == .signedOut)
        #expect(try repository.listSubscriptions().count == 1)
    }

    @Test("A saved local subscription becomes pending for an available account")
    @MainActor
    func availableSyncStatusBecomesSynchronizingAfterCreation() async {
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(),
            syncMonitor: SyncMonitorFixture(result: .current)
        )

        await workspace.refreshSyncStatus()
        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Beacon",
                plan: "Monthly",
                category: "Music",
                originalAmount: Money(minorUnits: 1_200, currency: .usd),
                startDate: startDate,
                confirmedNextRenewal: renewalDate,
                managementURL: nil,
                notes: ""
            )
        )

        #expect(workspace.syncStatus == .synchronizing)
    }

    @Test("Table query searches visible fields and keeps sorting stable")
    func tableQueryFiltersAndSortsSummaries() {
        let firstID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let secondID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        let thirdID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let renewal = Date(timeIntervalSince1970: 1_769_356_800)
        let summaries = [
            SubscriptionSummary(
                subscription: makeSubscription(
                    id: firstID,
                    confirmedNextRenewal: renewal,
                    originalAmount: Money(minorUnits: 1_200, currency: .usd),
                    category: "Cloud",
                    serviceName: "Atlas Cloud",
                    plan: "Pro"
                ),
                status: .active,
                nextExpectedCharge: nil
            ),
            SubscriptionSummary(
                subscription: makeSubscription(
                    id: secondID,
                    confirmedNextRenewal: renewal,
                    originalAmount: Money(minorUnits: 900, currency: .usd),
                    category: "Music",
                    serviceName: "Beacon Music",
                    plan: "Family"
                ),
                status: .active,
                nextExpectedCharge: nil
            ),
            SubscriptionSummary(
                subscription: makeSubscription(
                    id: thirdID,
                    confirmedNextRenewal: renewal,
                    originalAmount: Money(minorUnits: 500, currency: .usd),
                    category: "Productivity",
                    serviceName: "Atlas Notes",
                    plan: "Free"
                ),
                status: .active,
                nextExpectedCharge: nil
            ),
        ]

        let result = SubscriptionTableQuery(
            searchText: "atlas",
            sort: .amount,
            ascending: false
        )
        .apply(to: summaries)

        #expect(result.map(\.id) == [firstID, thirdID])
    }

    @Test("EUR snapshot converts source money through its base rate")
    func exchangeRateSnapshotConvertsThroughEUR() throws {
        let now = Date(timeIntervalSince1970: 1_769_356_800)
        let snapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [
                .eur: 1,
                .usd: 1.2,
                .cny: 8.4,
            ]
        )

        let converted = try snapshot.convert(
            Money(minorUnits: 840, currency: .cny),
            to: .usd
        )

        #expect(converted == Money(minorUnits: 120, currency: .usd))
    }

    @Test("Today's rate cache is reused without requesting the network")
    @MainActor
    func rateRefreshReusesTodaysCache() async {
        let now = Date(timeIntervalSince1970: 1_769_356_800)
        let snapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2]
        )
        let source = RecordingExchangeRateSource(snapshot: snapshot)
        let cache = InMemoryExchangeRateCache(
            state: ExchangeRateCacheState(
                snapshot: snapshot,
                lastAttemptAt: now
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(),
            exchangeRateSource: source,
            exchangeRateCache: cache,
            now: { now }
        )

        await workspace.refreshExchangeRates()

        #expect(source.requests.isEmpty)
        #expect(workspace.exchangeRateStatus == .fresh(snapshot))
    }

    @Test("Stale rates refresh only library and display currencies")
    @MainActor
    func rateRefreshRequestsOnlyNeededCurrencies() async {
        let yesterday = Date(timeIntervalSince1970: 1_769_270_400)
        let now = Date(timeIntervalSince1970: 1_769_356_800)
        let refreshed = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2]
        )
        let source = RecordingExchangeRateSource(snapshot: refreshed)
        let cache = InMemoryExchangeRateCache(
            state: ExchangeRateCacheState(
                snapshot: ExchangeRateSnapshot(
                    base: .eur,
                    providerDate: yesterday,
                    fetchedAt: yesterday,
                    source: "fixture",
                    rates: [.eur: 1, .usd: 1.2]
                ),
                lastAttemptAt: yesterday
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(subscriptions: [
                makeSubscription(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    originalAmount: Money(minorUnits: 999, currency: .usd)
                ),
            ]),
            exchangeRateSource: source,
            exchangeRateCache: cache,
            now: { now }
        )

        await workspace.refreshExchangeRates()

        #expect(source.requests.count == 1)
        #expect(source.requests.first?.base == .eur)
        #expect(source.requests.first?.quotes == [.cny, .usd])
        #expect(cache.state == ExchangeRateCacheState(
            snapshot: refreshed,
            lastAttemptAt: now
        ))
        #expect(workspace.exchangeRateStatus == ExchangeRateStatus.fresh(refreshed))
    }

    @Test("A failed refresh keeps stale rates and is not retried today")
    @MainActor
    func failedRateRefreshKeepsStaleSnapshot() async {
        let yesterday = Date(timeIntervalSince1970: 1_769_270_400)
        let now = Date(timeIntervalSince1970: 1_769_356_800)
        let stale = ExchangeRateSnapshot(
            base: .eur,
            providerDate: yesterday,
            fetchedAt: yesterday,
            source: "fixture",
            rates: [.eur: 1, .cny: 8.4]
        )
        let source = RecordingExchangeRateSource(error: ExchangeRateFixtureError.offline)
        let cache = InMemoryExchangeRateCache(
            state: ExchangeRateCacheState(
                snapshot: stale,
                lastAttemptAt: yesterday
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(),
            exchangeRateSource: source,
            exchangeRateCache: cache,
            now: { now }
        )

        await workspace.refreshExchangeRates()
        await workspace.refreshExchangeRates()

        #expect(source.requests.count == 1)
        #expect(workspace.exchangeRateStatus == ExchangeRateStatus.stale(stale))
        #expect(cache.state?.lastAttemptAt == now)
    }

    @Test("Expected insights convert charges into selected currency totals")
    @MainActor
    func expectedInsightsConvertRangeMonthlyAndCategoryTotals() async throws {
        let now = Date(timeIntervalSince1970: 1_769_356_800)
        let renewal = now.addingTimeInterval(86_400)
        let snapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(subscriptions: [
                makeSubscription(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    billingSchedule: FixedBillingSchedule(
                        interval: .monthly,
                        renewalAnchor: renewal,
                        timeZoneIdentifier: "UTC"
                    ),
                    confirmedNextRenewal: renewal,
                    originalAmount: Money(minorUnits: 120, currency: .usd),
                    category: "Video"
                ),
            ]),
            exchangeRateCache: InMemoryExchangeRateCache(
                state: ExchangeRateCacheState(
                    snapshot: snapshot,
                    lastAttemptAt: now
                )
            ),
            now: { now }
        )

        await workspace.refreshExchangeRates()
        workspace.loadInsights(
            mode: .expected,
            from: now,
            through: now.addingTimeInterval(172_800)
        )

        let insights = try #require(workspace.insightsState.availableValue)
        #expect(insights.selectedRangeTotal == Money(minorUnits: 840, currency: .cny))
        #expect(insights.monthlyTotals.map(\.amount) == [
            Money(minorUnits: 840, currency: .cny),
        ])
        #expect(insights.categoryTotals == [
            SpendingCategoryTotal(category: "Video", amount: Money(minorUnits: 840, currency: .cny)),
        ])

        workspace.updatePreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .twelveMonths
        )

        let recomputed = try #require(workspace.insightsState.availableValue)
        #expect(recomputed.selectedRangeTotal == Money(minorUnits: 120, currency: .usd))
    }

    @Test("Upcoming timeline orders expected and confirmed charges while excluding cancelled subscriptions")
    @MainActor
    func upcomingTimelineOrdersEligibleCharges() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let firstID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let secondID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        let cancelledID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let firstDate = now.addingTimeInterval(86_400)
        let confirmedDate = now.addingTimeInterval(172_800)
        let secondDate = now.addingTimeInterval(259_200)
        let repository = InMemorySubscriptionRepository(subscriptions: [
            makeSubscription(
                id: firstID,
                billingSchedule: FixedBillingSchedule(
                    interval: .weekly,
                    renewalAnchor: firstDate,
                    timeZoneIdentifier: "UTC"
                ),
                confirmedNextRenewal: firstDate,
                confirmedCharges: [ConfirmedCharge(
                    id: UUID(uuidString: "12121212-3434-5656-7878-909090909090")!,
                    chargedDate: confirmedDate,
                    amount: Money(minorUnits: 1_099, currency: .usd)
                )]
            ),
            makeSubscription(
                id: secondID,
                billingSchedule: FixedBillingSchedule(
                    interval: .weekly,
                    renewalAnchor: secondDate,
                    timeZoneIdentifier: "UTC"
                ),
                confirmedNextRenewal: secondDate
            ),
            makeSubscription(
                id: cancelledID,
                lifecycle: .cancelled(
                    cancelledAt: now,
                    accessUntil: now.addingTimeInterval(86_400)
                ),
                billingSchedule: FixedBillingSchedule(
                    interval: .weekly,
                    renewalAnchor: firstDate,
                    timeZoneIdentifier: "UTC"
                ),
                confirmedNextRenewal: firstDate
            ),
        ])
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now }
        )

        workspace.loadUpcomingTimeline(
            from: now,
            through: now.addingTimeInterval(604_800)
        )

        #expect(workspace.upcomingTimeline.map(\.subscriptionID) == [
            firstID,
            firstID,
            secondID,
        ])
        #expect(workspace.upcomingTimeline.map(\.kind) == [
            .expected,
            .confirmed,
            .expected,
        ])
    }

    @Test("A valid newer catalog becomes active without mutating subscriptions")
    @MainActor
    func newerCatalogActivatesWithoutMutatingSubscriptions() async throws {
        let bundled = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(
                en: "Example Music",
                zhHans: "示例音乐"
            ),
            category: CatalogLocalizedText(en: "Music", zhHans: "音乐"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .music
        )
        let newer = CatalogPreset(
            id: "video.example",
            serviceName: CatalogLocalizedText(
                en: "Example Video",
                zhHans: "示例视频"
            ),
            category: CatalogLocalizedText(en: "Video", zhHans: "视频"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .video
        )
        let update = try JSONEncoder().encode(
            CatalogSnapshot(
                schemaVersion: CatalogSnapshot.currentSchemaVersion,
                catalogVersion: 2,
                presets: [newer]
            )
        )
        let repository = InMemorySubscriptionRepository()
        let cache = InMemoryCatalogCache()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(
                catalogVersion: 1,
                presets: [bundled]
            ),
            catalogUpdateSource: StaticCatalogUpdateSource(data: update),
            catalogCache: cache
        )

        workspace.loadCatalog(locale: Locale(identifier: "en"))
        await workspace.refreshCatalog()

        #expect(workspace.catalogDiagnostics?.version == 2)
        #expect(workspace.catalogState == .loaded(
            categories: [CatalogCategory(
                id: "video",
                title: newer.category
            )],
            presets: [newer]
        ))
        #expect(cache.storedData == update)
        #expect(repository.updateAttemptCount == 0)
    }

    @Test("Stale and corrupt catalog updates preserve the active catalog")
    @MainActor
    func staleAndCorruptCatalogUpdatesPreserveActiveCatalog() async throws {
        let bundled = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(
                en: "Example Music",
                zhHans: "示例音乐"
            ),
            category: CatalogLocalizedText(en: "Music", zhHans: "音乐"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .music
        )
        let stale = try JSONEncoder().encode(
            CatalogSnapshot(
                schemaVersion: CatalogSnapshot.currentSchemaVersion,
                catalogVersion: 1,
                presets: [bundled]
            )
        )
        let repository = InMemorySubscriptionRepository()
        let cache = InMemoryCatalogCache()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [bundled]),
            catalogUpdateSource: StaticCatalogUpdateSource(data: stale),
            catalogCache: cache
        )

        workspace.loadCatalog(locale: Locale(identifier: "en"))
        await workspace.refreshCatalog()

        #expect(workspace.catalogDiagnostics?.refreshStatus == .alreadyCurrent)
        #expect(cache.storedData == nil)

        let corruptWorkspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [bundled]),
            catalogUpdateSource: StaticCatalogUpdateSource(
                data: Data("corrupt".utf8)
            ),
            catalogCache: cache
        )
        corruptWorkspace.loadCatalog(locale: Locale(identifier: "en"))
        await corruptWorkspace.refreshCatalog()

        #expect(corruptWorkspace.catalogDiagnostics?.refreshStatus == .failed)
        #expect(corruptWorkspace.catalogState == .loaded(
            categories: [CatalogCategory(id: "music", title: bundled.category)],
            presets: [bundled]
        ))
        #expect(cache.storedData == nil)
        #expect(repository.updateAttemptCount == 0)
    }

    @Test("Active creation stores an active lifecycle")
    @MainActor
    func activeCreationStoresActiveLifecycle() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let money = Money(minorUnits: 999, currency: .usd)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Standard",
                category: "Other",
                originalAmount: money,
                startDate: start,
                confirmedNextRenewal: start.addingTimeInterval(86_400),
                managementURL: nil,
                notes: "",
                initialStatus: .active
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.lifecycle == .active)
        #expect(stored.isArchived == false)
    }

    @Test("Catalog search and creation preserve the preset identity")
    @MainActor
    func catalogSearchAndCreationPreservePresetIdentity() throws {
        let preset = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(
                en: "Example Music",
                zhHans: "示例音乐"
            ),
            category: CatalogLocalizedText(en: "Music", zhHans: "音乐"),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://example.com/manage"),
            icon: .music
        )
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "ACACACAC-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            identifierGenerator: { subscriptionID }
        )

        workspace.loadCatalog(locale: Locale(identifier: "zh-Hans"))
        workspace.setCatalogSearchQuery("音乐")
        workspace.createCatalogSubscription(
            presetID: preset.id,
            input: SubscriptionCreationInput(
                serviceName: "Example Music",
                plan: "Family",
                category: "Music",
                originalAmount: Money(minorUnits: 1_299, currency: .usd),
                billingInterval: .monthly,
                startDate: start,
                confirmedNextRenewal: start.addingTimeInterval(86_400),
                managementURL: preset.managementURL,
                notes: ""
            )
        )

        guard case .loaded(let categories, let presets) = workspace.catalogState else {
            Issue.record("Expected loaded catalog state")
            return
        }
        #expect(categories.count == 1)
        #expect(presets == [preset])
        #expect(
            repository.storedSubscription(id: subscriptionID)?.serviceIdentity
                == ServiceIdentity(rawValue: "catalog:music.example")
        )
    }

    @Test("Trial creation snapshots next renewal as first paid charge")
    @MainActor
    func trialCreationSnapshotsNextRenewalAsFirstPaidCharge() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "11111111-AAAA-BBBB-CCCC-222222222222"
        )!
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let firstPaidCharge = start.addingTimeInterval(86_400)
        let money = Money(minorUnits: 999, currency: .usd)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                originalAmount: money,
                startDate: start,
                confirmedNextRenewal: firstPaidCharge,
                managementURL: nil,
                notes: "",
                initialStatus: .trial
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(
            stored.lifecycle == .trial(
                firstPaidChargeAt: firstPaidCharge
            )
        )
        #expect(stored.isArchived == false)
    }

    @Test("A non-positive amount is rejected as an invalid fixed charge")
    @MainActor
    func nonPositiveAmountIsRejected() {
        let repository = InMemorySubscriptionRepository()
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let workspace = SubscriptionWorkspace(repository: repository)
        let input = SubscriptionCreationInput(
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 0, currency: .usd),
            startDate: startDate,
            confirmedNextRenewal: startDate.addingTimeInterval(86_400),
            managementURL: nil,
            notes: ""
        )

        workspace.createSubscription(input)
        workspace.loadLibrary()

        #expect(
            workspace.creationValidationErrors[.originalAmount]
                == .mustBePositive
        )
        #expect(workspace.libraryState == .empty(.current))
    }

    @Test("Incomplete monthly input exposes field errors without creating a record")
    @MainActor
    func incompleteMonthlyInputExposesFieldErrors() {
        let repository = InMemorySubscriptionRepository()
        let startDate = Date(timeIntervalSince1970: 1_769_904_000)
        let workspace = SubscriptionWorkspace(repository: repository)
        let input = SubscriptionCreationInput(
            serviceName: "   ",
            plan: "",
            category: "\n",
            originalAmount: nil,
            startDate: startDate,
            confirmedNextRenewal: startDate.addingTimeInterval(-86_400),
            managementURL: nil,
            notes: ""
        )

        workspace.createSubscription(input)
        workspace.loadLibrary()

        #expect(
            workspace.creationValidationErrors == [
                .serviceName: .required,
                .plan: .required,
                .category: .required,
                .originalAmount: .required,
                .confirmedNextRenewal: .beforeStartDate,
            ]
        )
        #expect(workspace.libraryState == .empty(.current))
    }

    @Test("A monthly subscription remains inspectable after a workspace reload")
    @MainActor
    func monthlySubscriptionRemainsInspectableAfterWorkspaceReload() {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555555"
        )!
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let input = SubscriptionCreationInput(
            serviceName: "Example Cloud",
            plan: "Pro",
            category: "Cloud storage",
            originalAmount: Money(minorUnits: 1_999, currency: .cny),
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: URL(string: "https://example.com/account"),
            notes: "Work files"
        )
        let creationWorkspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )

        creationWorkspace.createSubscription(input)

        let reloadedWorkspace = SubscriptionWorkspace(repository: repository)
        reloadedWorkspace.loadLibrary()
        reloadedWorkspace.loadSubscription(id: subscriptionID)

        let expectedSubscription = Subscription(
            id: subscriptionID,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(subscriptionID.uuidString)"
            ),
            serviceName: "Example Cloud",
            plan: "Pro",
            category: "Cloud storage",
            originalAmount: Money(minorUnits: 1_999, currency: .cny),
            billingCycle: .monthly,
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: URL(string: "https://example.com/account"),
            notes: "Work files"
        )
        guard case .loaded(.current, let subscriptions) =
            reloadedWorkspace.libraryState
        else {
            Issue.record("Expected loaded current library")
            return
        }
        #expect(subscriptions.map(\.id) == [subscriptionID])
        guard case .loaded(let loaded, let status, let nextExpectedCharge) =
            reloadedWorkspace.detailState
        else {
            Issue.record("Expected loaded subscription detail")
            return
        }
        #expect(loaded == expectedSubscription)
        #expect(status == .active)
        #expect(nextExpectedCharge != nil)
    }

    @Test("Monthly subscription text is normalized before it is saved")
    @MainActor
    func monthlySubscriptionTextIsNormalizedBeforeItIsSaved() {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "22222222-3333-4444-5555-666666666666"
        )!
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )
        let input = SubscriptionCreationInput(
            serviceName: " \n Example Cloud \t",
            plan: "\t Pro \n",
            category: "\n Cloud storage ",
            originalAmount: Money(minorUnits: 1_999, currency: .cny),
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: nil,
            notes: ""
        )

        workspace.createSubscription(input)

        let expectedSubscription = Subscription(
            id: subscriptionID,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(subscriptionID.uuidString)"
            ),
            serviceName: "Example Cloud",
            plan: "Pro",
            category: "Cloud storage",
            originalAmount: Money(minorUnits: 1_999, currency: .cny),
            billingCycle: .monthly,
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: nil,
            notes: ""
        )
        guard case .loaded(let loaded, _, _) = workspace.detailState else {
            Issue.record("Expected loaded subscription detail")
            return
        }
        #expect(loaded == expectedSubscription)
        guard case .loaded(.current, let subscriptions) =
            workspace.libraryState
        else {
            Issue.record("Expected loaded current library")
            return
        }
        #expect(subscriptions.map(\.id) == [subscriptionID])
    }

    @Test("The in-memory repository lists subscriptions in stable identifier order")
    @MainActor
    func inMemoryRepositoryListsSubscriptionsInStableIdentifierOrder() throws {
        let repository = InMemorySubscriptionRepository()
        let firstID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let secondID = UUID(
            uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        )!

        try repository.createSubscription(makeSubscription(id: secondID))
        try repository.createSubscription(makeSubscription(id: firstID))

        #expect(
            try repository.listSubscriptions().map(\.id)
                == [firstID, secondID]
        )
    }

    @Test("A fresh workspace loads an empty subscription library")
    @MainActor
    func freshWorkspaceLoadsEmptyLibrary() {
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository()
        )

        workspace.loadLibrary()

        #expect(workspace.libraryState == .empty(.current))
    }

    @Test("A repository failure produces a recoverable library state")
    @MainActor
    func repositoryFailureProducesFailedState() {
        let workspace = SubscriptionWorkspace(
            repository: FailingSubscriptionRepository()
        )

        workspace.loadLibrary()

        #expect(workspace.libraryState == .failed(.current))
    }

    @Test("Existing subscriptions become observable library content")
    @MainActor
    func existingSubscriptionsBecomeLoadedState() {
        let subscription = makeSubscription(
            id: UUID(
                uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            )!
        )
        let workspace = SubscriptionWorkspace(
            repository: PopulatedSubscriptionRepository(
                subscriptions: [subscription]
            )
        )

        workspace.loadLibrary()

        guard case .loaded(.current, let subscriptions) =
            workspace.libraryState
        else {
            Issue.record("Expected loaded current library")
            return
        }
        #expect(subscriptions.map(\.id) == [subscription.id])
    }

    @Test("Current and archived scopes never mix records")
    @MainActor
    func libraryScopesRemainDisjoint() {
        let currentID = UUID(
            uuidString: "10000000-0000-0000-0000-000000000001"
        )!
        let archivedID = UUID(
            uuidString: "20000000-0000-0000-0000-000000000002"
        )!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cancelledAt = now.addingTimeInterval(-10 * 86_400)
        let accessUntil = now.addingTimeInterval(10 * 86_400)
        let calendar = utcCalendar()
        let repository = LifecycleRepository(
            subscriptions: [
                makeSubscription(id: currentID, lifecycle: .active),
                makeSubscription(
                    id: archivedID,
                    lifecycle: .cancelled(
                        cancelledAt: cancelledAt,
                        accessUntil: accessUntil
                    ),
                    isArchived: true
                ),
            ]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        workspace.loadLibrary(scope: .current)
        guard case .loaded(.current, let current) = workspace.libraryState else {
            Issue.record("Expected current scope")
            return
        }
        #expect(current.map(\.id) == [currentID])

        workspace.loadLibrary(scope: .archived)
        guard case .loaded(.archived, let archived) = workspace.libraryState else {
            Issue.record("Expected archived scope")
            return
        }
        #expect(archived.map(\.id) == [archivedID])
        #expect(archived.first?.nextExpectedCharge == nil)
    }

    @Test("Archiving refreshes the currently selected library scope")
    @MainActor
    func archivingRefreshesCurrentScopeAfterScopeChanges() throws {
        let currentID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000003"
        )!
        let archivedID = UUID(
            uuidString: "40000000-0000-0000-0000-000000000004"
        )!
        let repository = InMemorySubscriptionRepository(
            subscriptions: [
                makeSubscription(id: currentID),
                makeSubscription(id: archivedID, isArchived: true),
            ]
        )
        let workspace = SubscriptionWorkspace(repository: repository)

        workspace.loadLibrary(scope: .archived)
        workspace.loadLibrary(scope: .current)

        guard case .loaded(.current, let current) = workspace.libraryState else {
            Issue.record("Expected current scope after switching scopes")
            return
        }
        #expect(current.map(\.id) == [currentID])
        #expect(!current.map(\.id).contains(archivedID))

        workspace.loadSubscription(id: currentID)
        workspace.archive(id: currentID)

        #expect(workspace.libraryState == .empty(.current))
        #expect(
            try #require(repository.storedSubscription(id: currentID))
                .isArchived
        )
    }

    @Test("Cancelled detail has access status without a next expected charge")
    @MainActor
    func cancelledDetailOmitsNextExpectedCharge() {
        let subscriptionID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000003"
        )!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let subscription = makeSubscription(
            id: subscriptionID,
            lifecycle: .cancelled(
                cancelledAt: now.addingTimeInterval(-10 * 86_400),
                accessUntil: now.addingTimeInterval(10 * 86_400)
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: LifecycleRepository(subscriptions: [subscription]),
            now: { now },
            calendar: utcCalendar()
        )

        workspace.loadSubscription(id: subscriptionID)

        guard case .loaded(
            let loaded,
            let status,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected loaded detail")
            return
        }
        #expect(loaded == subscription)
        #expect(status == .cancelledWithAccess)
        #expect(nextExpectedCharge == nil)
    }

    @Test("Active detail includes a next expected charge")
    @MainActor
    func activeDetailIncludesNextExpectedCharge() {
        let subscriptionID = UUID(
            uuidString: "40000000-0000-0000-0000-000000000004"
        )!
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let subscription = makeSubscription(
            id: subscriptionID,
            lifecycle: .active
        )
        let workspace = SubscriptionWorkspace(
            repository: LifecycleRepository(subscriptions: [subscription]),
            now: { now },
            calendar: utcCalendar()
        )

        workspace.loadSubscription(id: subscriptionID)

        guard case .loaded(
            let loaded,
            let status,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected loaded detail")
            return
        }
        #expect(loaded == subscription)
        #expect(status == .active)
        #expect(nextExpectedCharge != nil)
    }

    @Test(
        "Trial and active subscriptions can record billing-local cancellation",
        arguments: [
            LifecycleFixture.trial,
            LifecycleFixture.active,
        ]
    )
    @MainActor
    func trialAndActiveCanRecordCancellation(
        fixture: LifecycleFixture
    ) throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 8,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: fixture,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )
        let cancelledAt = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 23,
            calendar: calendar
        )
        let accessUntil = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 1,
            calendar: calendar
        )
        let normalizedDay = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 12,
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        #expect(workspace.expectedCharges?.isEmpty == false)
        workspace.recordCancellation(
            id: subscription.id,
            cancelledAt: cancelledAt,
            accessUntil: accessUntil
        )

        let stored = try #require(
            repository.storedSubscription(id: subscription.id)
        )
        #expect(
            stored.lifecycle == .cancelled(
                cancelledAt: normalizedDay,
                accessUntil: normalizedDay
            )
        )
        #expect(stored.billingSchedule == subscription.billingSchedule)
        #expect(stored.confirmedNextRenewal == subscription.confirmedNextRenewal)
        #expect(stored.confirmedCharges == subscription.confirmedCharges)
        #expect(workspace.expectedCharges == [])
        #expect(workspace.lifecycleActionError == nil)
        #expect(repository.updateAttemptCount == 1)
        guard case .loaded(
            let detail,
            .expired,
            nil
        ) = workspace.detailState else {
            Issue.record("Expected refreshed expired detail")
            return
        }
        #expect(detail == stored)
        guard case .loaded(.current, let summaries) = workspace.libraryState else {
            Issue.record("Expected refreshed current library")
            return
        }
        #expect(summaries.map(\.id) == [subscription.id])
        #expect(summaries.first?.status == .expired)
        #expect(summaries.first?.nextExpectedCharge == nil)
    }

    @Test("A cancellation on a future billing-local day is rejected")
    @MainActor
    func futureCancellationDayIsRejected() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 23,
            minute: 30,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        let detailBefore = workspace.detailState
        let forecastBefore = workspace.expectedCharges
        let libraryBefore = workspace.libraryState

        workspace.recordCancellation(
            id: subscription.id,
            cancelledAt: try actionDate(
                year: 2026,
                month: 7,
                day: 29,
                hour: 0,
                minute: 30,
                calendar: calendar
            ),
            accessUntil: try actionDate(
                year: 2026,
                month: 7,
                day: 29,
                hour: 23,
                calendar: calendar
            )
        )

        #expect(
            workspace.lifecycleActionError == .cancellationDateInFuture
        )
        #expect(
            repository.storedSubscription(id: subscription.id)
                == subscription
        )
        #expect(repository.updateAttemptCount == 0)
        #expect(workspace.detailState == detailBefore)
        #expect(workspace.expectedCharges == forecastBefore)
        #expect(workspace.libraryState == libraryBefore)
    }

    @Test("Access ending before the cancellation billing-local day is rejected")
    @MainActor
    func accessBeforeCancellationDayIsRejected() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 8,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        let detailBefore = workspace.detailState
        let forecastBefore = workspace.expectedCharges
        let libraryBefore = workspace.libraryState

        workspace.recordCancellation(
            id: subscription.id,
            cancelledAt: try actionDate(
                year: 2026,
                month: 7,
                day: 28,
                hour: 1,
                calendar: calendar
            ),
            accessUntil: try actionDate(
                year: 2026,
                month: 7,
                day: 27,
                hour: 23,
                calendar: calendar
            )
        )

        #expect(
            workspace.lifecycleActionError
                == .accessEndsBeforeCancellation
        )
        #expect(
            repository.storedSubscription(id: subscription.id)
                == subscription
        )
        #expect(repository.updateAttemptCount == 0)
        #expect(workspace.detailState == detailBefore)
        #expect(workspace.expectedCharges == forecastBefore)
        #expect(workspace.libraryState == libraryBefore)
    }

    @Test(
        "Cancelled and expired subscriptions can reactivate on the current local day",
        arguments: [
            LifecycleFixture.cancelledWithAccess,
            LifecycleFixture.expired,
        ]
    )
    @MainActor
    func cancelledAndExpiredCanReactivate(
        fixture: LifecycleFixture
    ) throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: fixture,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )
        let normalizedRenewal = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 12,
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        #expect(workspace.expectedCharges == [])

        workspace.reactivate(
            id: subscription.id,
            nextRenewal: try actionDate(
                year: 2026,
                month: 7,
                day: 28,
                hour: 1,
                calendar: calendar
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscription.id)
        )
        #expect(stored.lifecycle == .active)
        #expect(stored.billingSchedule == subscription.billingSchedule)
        #expect(
            stored.billingSchedule.renewalAnchor
                == subscription.billingSchedule.renewalAnchor
        )
        #expect(stored.confirmedNextRenewal == normalizedRenewal)
        #expect(stored.confirmedCharges == subscription.confirmedCharges)
        #expect(workspace.expectedCharges?.isEmpty == false)
        #expect(workspace.lifecycleActionError == nil)
        guard case .loaded(
            let detail,
            .active,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected refreshed active detail")
            return
        }
        #expect(detail == stored)
        #expect(nextExpectedCharge != nil)
        guard case .loaded(.current, let summaries) = workspace.libraryState else {
            Issue.record("Expected refreshed current library")
            return
        }
        #expect(summaries.map(\.id) == [subscription.id])
        #expect(summaries.first?.status == .active)
    }

    @Test("Reactivation before the current billing-local day is rejected")
    @MainActor
    func pastReactivationDayIsRejected() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 0,
            minute: 30,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .cancelledWithAccess,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        let detailBefore = workspace.detailState
        let forecastBefore = workspace.expectedCharges
        let libraryBefore = workspace.libraryState

        workspace.reactivate(
            id: subscription.id,
            nextRenewal: try actionDate(
                year: 2026,
                month: 7,
                day: 27,
                hour: 23,
                minute: 59,
                calendar: calendar
            )
        )

        #expect(workspace.lifecycleActionError == .nextRenewalInPast)
        #expect(
            repository.storedSubscription(id: subscription.id)
                == subscription
        )
        #expect(repository.updateAttemptCount == 0)
        #expect(workspace.detailState == detailBefore)
        #expect(workspace.expectedCharges == forecastBefore)
        #expect(workspace.libraryState == libraryBefore)
    }

    @Test(
        "Every current lifecycle can be archived without changing its facts",
        arguments: LifecycleFixture.allCases
    )
    @MainActor
    func everyCurrentLifecycleCanBeArchived(
        fixture: LifecycleFixture
    ) throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: fixture,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )

        workspace.archive(id: subscription.id)

        let stored = try #require(
            repository.storedSubscription(id: subscription.id)
        )
        #expect(stored.isArchived)
        #expect(stored.lifecycle == subscription.lifecycle)
        #expect(stored.confirmedCharges == subscription.confirmedCharges)
        #expect(workspace.expectedCharges == [])
        #expect(workspace.lifecycleActionError == nil)
        #expect(workspace.libraryState == .empty(.current))
        guard case .loaded(
            let detail,
            let status,
            nil
        ) = workspace.detailState else {
            Issue.record("Expected refreshed archived detail")
            return
        }
        #expect(detail == stored)
        #expect(status == fixture.status)
    }

    @Test(
        "Every archived lifecycle can be restored without changing its facts",
        arguments: LifecycleFixture.allCases
    )
    @MainActor
    func everyArchivedLifecycleCanBeRestored(
        fixture: LifecycleFixture
    ) throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: fixture,
            isArchived: true,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .archived,
            calendar: calendar
        )
        #expect(workspace.expectedCharges == [])

        workspace.restore(id: subscription.id)

        let stored = try #require(
            repository.storedSubscription(id: subscription.id)
        )
        #expect(!stored.isArchived)
        #expect(stored.lifecycle == subscription.lifecycle)
        #expect(stored.confirmedCharges == subscription.confirmedCharges)
        #expect(workspace.lifecycleActionError == nil)
        #expect(workspace.libraryState == .empty(.archived))
        guard case .loaded(
            let detail,
            let status,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected refreshed restored detail")
            return
        }
        #expect(detail == stored)
        #expect(status == fixture.status)
        #expect(
            (nextExpectedCharge != nil)
                == fixture.isEligibleForExpectedCharges
        )
        #expect(
            (workspace.expectedCharges?.isEmpty == false)
                == fixture.isEligibleForExpectedCharges
        )
    }

    @Test(
        "Cancelled current subscriptions cannot record cancellation again",
        arguments: [
            LifecycleFixture.cancelledWithAccess,
            LifecycleFixture.expired,
        ]
    )
    @MainActor
    func cancelledCurrentSubscriptionsRejectCancellation(
        fixture: LifecycleFixture
    ) throws {
        try expectInvalidTransition(
            .recordCancellation,
            fixture: fixture,
            isArchived: false
        )
    }

    @Test(
        "Trial and active current subscriptions cannot reactivate",
        arguments: [
            LifecycleFixture.trial,
            LifecycleFixture.active,
        ]
    )
    @MainActor
    func trialAndActiveCurrentSubscriptionsRejectReactivation(
        fixture: LifecycleFixture
    ) throws {
        try expectInvalidTransition(
            .reactivate,
            fixture: fixture,
            isArchived: false
        )
    }

    @Test(
        "Archived subscriptions cannot record cancellation",
        arguments: LifecycleFixture.allCases
    )
    @MainActor
    func archivedSubscriptionsRejectCancellation(
        fixture: LifecycleFixture
    ) throws {
        try expectInvalidTransition(
            .recordCancellation,
            fixture: fixture,
            isArchived: true
        )
    }

    @Test(
        "Archived subscriptions cannot reactivate",
        arguments: LifecycleFixture.allCases
    )
    @MainActor
    func archivedSubscriptionsRejectReactivation(
        fixture: LifecycleFixture
    ) throws {
        try expectInvalidTransition(
            .reactivate,
            fixture: fixture,
            isArchived: true
        )
    }

    @Test(
        "Archived subscriptions cannot be archived again",
        arguments: LifecycleFixture.allCases
    )
    @MainActor
    func archivedSubscriptionsRejectArchive(
        fixture: LifecycleFixture
    ) throws {
        try expectInvalidTransition(
            .archive,
            fixture: fixture,
            isArchived: true
        )
    }

    @Test(
        "Current subscriptions cannot be restored",
        arguments: LifecycleFixture.allCases
    )
    @MainActor
    func currentSubscriptionsRejectRestore(
        fixture: LifecycleFixture
    ) throws {
        try expectInvalidTransition(
            .restore,
            fixture: fixture,
            isArchived: false
        )
    }

    @Test(
        "Permanent deletion removes only its UUID in every lifecycle and scope"
    )
    @MainActor
    func permanentDeletionRemovesOnlyRequestedUUID() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )

        for fixture in LifecycleFixture.allCases {
            for isArchived in [false, true] {
                let target = try makeActionSubscription(
                    id: actionTargetID,
                    fixture: fixture,
                    isArchived: isArchived,
                    calendar: calendar
                )
                let unrelated = try makeActionSubscription(
                    id: unrelatedActionID,
                    fixture: .active,
                    isArchived: isArchived,
                    calendar: calendar
                )
                let repository = InMemorySubscriptionRepository(
                    subscriptions: [target, unrelated]
                )
                let workspace = SubscriptionWorkspace(
                    repository: repository,
                    now: { now },
                    calendar: calendar
                )
                let scope: SubscriptionLibraryScope =
                    isArchived ? .archived : .current

                loadActionPresentation(
                    workspace,
                    subscription: target,
                    scope: scope,
                    calendar: calendar
                )

                workspace.deletePermanently(id: target.id)

                #expect(
                    repository.storedSubscription(id: target.id) == nil
                )
                #expect(
                    repository.storedSubscription(id: unrelated.id)
                        == unrelated
                )
                #expect(repository.deletedIDs == [target.id])
                #expect(workspace.lifecycleActionError == nil)
                #expect(workspace.detailState == .notFound)
                #expect(workspace.expectedCharges == nil)
                guard case .loaded(
                    let loadedScope,
                    let summaries
                ) = workspace.libraryState else {
                    Issue.record("Expected refreshed library after deletion")
                    continue
                }
                #expect(loadedScope == scope)
                #expect(summaries.map(\.id) == [unrelated.id])
            }
        }
    }

    @Test(
        "Action repository failures preserve loaded detail and forecasts",
        arguments: [
            RepositoryFailure.lookup,
            RepositoryFailure.update,
            RepositoryFailure.delete,
        ]
    )
    @MainActor
    func actionRepositoryFailurePreservesPresentation(
        failure: RepositoryFailure
    ) throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        let detailBefore = workspace.detailState
        let forecastBefore = workspace.expectedCharges
        let libraryBefore = workspace.libraryState
        #expect(forecastBefore?.isEmpty == false)
        repository.failure = failure

        if failure == .delete {
            workspace.deletePermanently(id: subscription.id)
        } else {
            workspace.archive(id: subscription.id)
        }

        #expect(workspace.lifecycleActionError == .persistenceFailed)
        #expect(
            repository.storedSubscription(id: subscription.id)
                == subscription
        )
        #expect(workspace.detailState == detailBefore)
        #expect(workspace.expectedCharges == forecastBefore)
        #expect(workspace.libraryState == libraryBefore)
    }

    @Test(
        "A successful update publishes persisted truth before a failed refresh"
    )
    @MainActor
    func successfulUpdatePublishesTruthBeforeFailedRefresh() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        #expect(workspace.expectedCharges?.isEmpty == false)
        repository.failure = .list

        workspace.archive(id: subscription.id)

        #expect(
            repository.storedSubscription(id: subscription.id)?
                .isArchived == true
        )
        guard case .loaded(
            let updated,
            let status,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected the persisted archived detail")
            return
        }
        #expect(updated.id == subscription.id)
        #expect(updated.isArchived == true)
        #expect(status == .active)
        #expect(nextExpectedCharge == nil)
        #expect(workspace.expectedCharges == [])
        #expect(workspace.libraryState == .failed(.current))
        #expect(workspace.lifecycleActionError == nil)
    }

    @Test(
        "A successful delete publishes not found before a failed refresh"
    )
    @MainActor
    func successfulDeletePublishesNotFoundBeforeFailedRefresh() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        #expect(workspace.expectedCharges?.isEmpty == false)
        repository.failure = .list

        workspace.deletePermanently(id: subscription.id)

        #expect(repository.storedSubscription(id: subscription.id) == nil)
        #expect(workspace.detailState == .notFound)
        #expect(workspace.expectedCharges == nil)
        #expect(workspace.libraryState == .failed(.current))
        #expect(workspace.lifecycleActionError == nil)
    }

    @Test("Dismissing an action error clears it without changing content")
    @MainActor
    func dismissingActionErrorClearsItWithoutChangingContent() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )
        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: .current,
            calendar: calendar
        )
        let detailBefore = workspace.detailState
        let forecastBefore = workspace.expectedCharges
        let libraryBefore = workspace.libraryState
        repository.failure = .update
        workspace.archive(id: subscription.id)
        #expect(workspace.lifecycleActionError == .persistenceFailed)

        workspace.clearLifecycleActionError()

        #expect(workspace.lifecycleActionError == nil)
        #expect(workspace.detailState == detailBefore)
        #expect(workspace.expectedCharges == forecastBefore)
        #expect(workspace.libraryState == libraryBefore)
    }

    @Test("Every lifecycle command uses existing not-found behavior")
    @MainActor
    func lifecycleCommandsUseExistingNotFoundBehavior() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )

        for action in WorkspaceLifecycleAction.allCases {
            let repository = InMemorySubscriptionRepository()
            let workspace = SubscriptionWorkspace(
                repository: repository,
                now: { now },
                calendar: calendar
            )
            workspace.loadLibrary(
                scope: action == .restore ? .archived : .current
            )

            try perform(
                action,
                on: workspace,
                subscriptionID: actionTargetID,
                calendar: calendar
            )

            #expect(workspace.detailState == .notFound)
            #expect(workspace.lifecycleActionError == nil)
            #expect(repository.updateAttemptCount == 0)
            #expect(repository.deletedIDs.isEmpty)
        }
    }

    @MainActor
    private func expectInvalidTransition(
        _ action: WorkspaceLifecycleAction,
        fixture: LifecycleFixture,
        isArchived: Bool
    ) throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: fixture,
            isArchived: isArchived,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )
        let scope: SubscriptionLibraryScope =
            isArchived ? .archived : .current

        loadActionPresentation(
            workspace,
            subscription: subscription,
            scope: scope,
            calendar: calendar
        )
        let detailBefore = workspace.detailState
        let forecastBefore = workspace.expectedCharges
        let libraryBefore = workspace.libraryState

        try perform(
            action,
            on: workspace,
            subscriptionID: subscription.id,
            calendar: calendar
        )

        #expect(
            workspace.lifecycleActionError == .invalidLifecycleTransition
        )
        #expect(
            repository.storedSubscription(id: subscription.id)
                == subscription
        )
        #expect(repository.updateAttemptCount == 0)
        #expect(repository.deletedIDs.isEmpty)
        #expect(workspace.detailState == detailBefore)
        #expect(workspace.expectedCharges == forecastBefore)
        #expect(workspace.libraryState == libraryBefore)
    }
}

@MainActor
private struct EmptySubscriptionRepository: SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws {}

    func updateSubscription(_ subscription: Subscription) throws {}

    func deleteSubscription(id: UUID) throws {}

    func listSubscriptions() throws -> [Subscription] {
        []
    }

    func subscription(id: UUID) throws -> Subscription? {
        nil
    }
}

@MainActor
private struct StaticCatalogRepository: CatalogRepository {
    let catalogVersion: Int
    let presets: [CatalogPreset]

    init(catalogVersion: Int = 1, presets: [CatalogPreset]) {
        self.catalogVersion = catalogVersion
        self.presets = presets
    }

    func loadSnapshot() throws -> CatalogSnapshot {
        try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            catalogVersion: catalogVersion,
            presets: presets
        )
    }
}

@MainActor
private struct StaticCatalogUpdateSource: CatalogUpdateSource {
    let data: Data

    func fetchCatalogData() async throws -> Data {
        data
    }
}

@MainActor
private final class InMemoryCatalogCache: CatalogCache {
    private(set) var storedData: Data?

    func storeCatalogData(_ data: Data) throws {
        storedData = data
    }
}

@MainActor
private final class RecordingExchangeRateSource: ExchangeRateSource {
    private(set) var requests: [(base: Currency, quotes: Set<Currency>)] = []
    private let result: Result<ExchangeRateSnapshot, ExchangeRateFixtureError>

    init(snapshot: ExchangeRateSnapshot) {
        result = .success(snapshot)
    }

    init(error: ExchangeRateFixtureError) {
        result = .failure(error)
    }

    func fetchRates(
        base: Currency,
        quotes: Set<Currency>
    ) async throws -> ExchangeRateSnapshot {
        requests.append((base: base, quotes: quotes))
        return try result.get()
    }
}

private enum ExchangeRateFixtureError: Error {
    case offline
}

@MainActor
private final class CalendarPreferencesFixture: UserPreferencesRepository {
    private var preferences: UserPreferences

    init(preferences: UserPreferences) {
        self.preferences = preferences
    }

    func loadPreferences() throws -> UserPreferences? {
        preferences
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        self.preferences = preferences
    }
}

@MainActor
private final class CalendarImporterFixture: CalendarProjectionImporter {
    private let result: CalendarProjectionImportResult
    private var events: [CalendarProjectionEvent]?

    init(result: CalendarProjectionImportResult) {
        self.result = result
    }

    func importProjection(
        events: [CalendarProjectionEvent]
    ) async -> CalendarProjectionImportResult {
        self.events = events
        return result
    }

    func importedEvents() -> [CalendarProjectionEvent]? { events }
}

private struct SyncMonitorFixture: LibrarySyncMonitor {
    let result: LibrarySyncStatus

    func refreshStatus() async -> LibrarySyncStatus {
        result
    }
}

@MainActor
private final class InMemoryExchangeRateCache: ExchangeRateCache {
    private(set) var state: ExchangeRateCacheState?

    init(state: ExchangeRateCacheState?) {
        self.state = state
    }

    func loadState() throws -> ExchangeRateCacheState? {
        state
    }

    func saveState(_ state: ExchangeRateCacheState) throws {
        self.state = state
    }
}

@MainActor
private struct FailingSubscriptionRepository: SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws {
        throw RepositoryError.unavailable
    }

    func updateSubscription(_ subscription: Subscription) throws {
        throw RepositoryError.unavailable
    }

    func deleteSubscription(id: UUID) throws {
        throw RepositoryError.unavailable
    }

    func listSubscriptions() throws -> [Subscription] {
        throw RepositoryError.unavailable
    }

    func subscription(id: UUID) throws -> Subscription? {
        throw RepositoryError.unavailable
    }

    private enum RepositoryError: Error {
        case unavailable
    }
    @Test("Confirming a passed scheduled charge is idempotent")
    @MainActor
    func confirmingPassedScheduledChargeIsIdempotent() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 29,
            hour: 12,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )
        let scheduledDate = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 12,
            calendar: calendar
        )
        let actualAmount = Money(minorUnits: 1_299, currency: .usd)

        workspace.confirmCharge(
            id: subscription.id,
            scheduledDate: scheduledDate,
            chargedDate: scheduledDate,
            amount: actualAmount
        )
        workspace.confirmCharge(
            id: subscription.id,
            scheduledDate: scheduledDate,
            chargedDate: scheduledDate,
            amount: actualAmount
        )

        let stored = try #require(
            repository.storedSubscription(id: subscription.id)
        )
        #expect(stored.confirmedCharges.count == 2)
        #expect(stored.confirmedCharges.last?.amount == actualAmount)
    }

    @Test("A scheduled charge on the current billing day can be confirmed")
    @MainActor
    func confirmingCurrentBillingDayCharge() throws {
        let calendar = actionCalendar()
        let scheduledDate = try actionDate(
            year: 2026, month: 7, day: 29, hour: 12, calendar: calendar
        )
        let now = try actionDate(
            year: 2026, month: 7, day: 29, hour: 14, calendar: calendar
        )
        let nextRenewal = try actionDate(
            year: 2026, month: 8, day: 29, hour: 12, calendar: calendar
        )
        let subscription = Subscription(
            id: actionTargetID,
            serviceIdentity: ServiceIdentity(rawValue: "manual:current-day"),
            serviceName: "Current Day",
            plan: "Monthly",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: scheduledDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            startDate: scheduledDate,
            confirmedNextRenewal: nextRenewal,
            managementURL: nil,
            notes: ""
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository, now: { now }, calendar: calendar
        )

        workspace.confirmCharge(
            id: subscription.id,
            scheduledDate: scheduledDate,
            chargedDate: scheduledDate,
            amount: Money(minorUnits: 999, currency: .usd)
        )

        #expect(
            repository.storedSubscription(id: subscription.id)?
                .confirmedCharges.count == 1
        )
        #expect(workspace.paymentHistoryActionError == nil)
    }

    @Test("Price changes apply on their effective billing day without rewriting facts")
    @MainActor
    func priceChangesResolveFutureForecastWithoutRewritingFacts() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026, month: 7, day: 29, hour: 12, calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .active, calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository, now: { now }, calendar: calendar
        )
        let effectiveDate = try actionDate(
            year: 2026, month: 7, day: 28, hour: 12, calendar: calendar
        )
        let changedAmount = Money(minorUnits: 1_499, currency: .usd)
        let forecastHorizon = try actionDate(
            year: 2026, month: 8, day: 29, hour: 12, calendar: calendar
        )

        workspace.recordPriceChange(
            id: subscription.id,
            effectiveDate: effectiveDate,
            amount: changedAmount
        )
        workspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: forecastHorizon,
            maximumCount: 3
        )

        let stored = try #require(
            repository.storedSubscription(id: subscription.id)
        )
        #expect(stored.originalAmount == Money(minorUnits: 999, currency: .usd))
        #expect(stored.confirmedCharges.first?.amount == Money(
            minorUnits: 999, currency: .usd
        ))
        #expect(stored.priceChanges.map(\.amount) == [changedAmount])
        #expect(workspace.expectedCharges?.first?.amount == changedAmount)
        #expect(workspace.paymentHistory.contains(.priceChange(
            try #require(stored.priceChanges.first)
        )))
    }
}

@MainActor
private struct PopulatedSubscriptionRepository: SubscriptionRepository {
    let subscriptions: [Subscription]

    func createSubscription(_ subscription: Subscription) throws {}

    func updateSubscription(_ subscription: Subscription) throws {}

    func deleteSubscription(id: UUID) throws {}

    func listSubscriptions() throws -> [Subscription] {
        subscriptions
    }

    func subscription(id: UUID) throws -> Subscription? {
        nil
    }
}

@MainActor
private final class InMemorySubscriptionRepository: SubscriptionRepository {
    private var subscriptions: [UUID: Subscription] = [:]
    var failure: RepositoryFailure?
    private(set) var updateAttemptCount = 0
    private(set) var deletedIDs: [UUID] = []

    init(subscriptions: [Subscription] = []) {
        self.subscriptions = Dictionary(
            uniqueKeysWithValues: subscriptions.map { ($0.id, $0) }
        )
    }

    func createSubscription(_ subscription: Subscription) throws {
        subscriptions[subscription.id] = subscription
    }

    func updateSubscription(_ subscription: Subscription) throws {
        updateAttemptCount += 1
        if failure == .update {
            throw RepositoryFailureError.unavailable
        }
        subscriptions[subscription.id] = subscription
    }

    func deleteSubscription(id: UUID) throws {
        if failure == .delete {
            throw RepositoryFailureError.unavailable
        }
        deletedIDs.append(id)
        subscriptions[id] = nil
    }

    func listSubscriptions() throws -> [Subscription] {
        if failure == .list {
            throw RepositoryFailureError.unavailable
        }
        return subscriptions.values
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func subscription(id: UUID) throws -> Subscription? {
        if failure == .lookup {
            throw RepositoryFailureError.unavailable
        }
        return subscriptions[id]
    }

    func storedSubscription(id: UUID) -> Subscription? {
        subscriptions[id]
    }

    private enum RepositoryFailureError: Error {
        case unavailable
    }
}

@MainActor
private struct LifecycleRepository: SubscriptionRepository {
    let subscriptions: [Subscription]

    func createSubscription(_ subscription: Subscription) throws {}

    func updateSubscription(_ subscription: Subscription) throws {}

    func deleteSubscription(id: UUID) throws {}

    func listSubscriptions() throws -> [Subscription] {
        subscriptions
    }

    func subscription(id: UUID) throws -> Subscription? {
        subscriptions.first { $0.id == id }
    }
}

private func makeSubscription(
    id: UUID,
    lifecycle: SubscriptionLifecycle = .active,
    isArchived: Bool = false,
    billingSchedule: FixedBillingSchedule? = nil,
    confirmedNextRenewal: Date? = nil,
    confirmedCharges: [ConfirmedCharge] = [],
    originalAmount: Money = Money(minorUnits: 999, currency: .usd),
    category: String = "Other",
    serviceName: String = "Example",
    plan: String = "Standard",
    notes: String = ""
) -> Subscription {
    let startDate = Date(timeIntervalSince1970: 1_767_225_600)
    let schedule = billingSchedule ?? FixedBillingSchedule(
        interval: .monthly,
        renewalAnchor: startDate,
        timeZoneIdentifier: "UTC"
    )
    let renewalDate =
        confirmedNextRenewal
        ?? Date(timeIntervalSince1970: 1_769_904_000)
    return Subscription(
        id: id,
        serviceIdentity: ServiceIdentity(rawValue: "manual:\(id.uuidString)"),
        serviceName: serviceName,
        plan: plan,
        category: category,
        originalAmount: originalAmount,
        billingSchedule: schedule,
        startDate: schedule.renewalAnchor,
        confirmedNextRenewal: renewalDate,
        managementURL: nil,
        notes: notes,
        confirmedCharges: confirmedCharges,
        lifecycle: lifecycle,
        isArchived: isArchived
    )
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

enum LifecycleFixture: String, CaseIterable, Equatable, Sendable {
    case trial
    case active
    case cancelledWithAccess
    case expired

    var status: SubscriptionStatus {
        switch self {
        case .trial:
            .trial
        case .active:
            .active
        case .cancelledWithAccess:
            .cancelledWithAccess
        case .expired:
            .expired
        }
    }

    var isEligibleForExpectedCharges: Bool {
        switch self {
        case .trial, .active:
            true
        case .cancelledWithAccess, .expired:
            false
        }
    }
}

private enum WorkspaceLifecycleAction: CaseIterable, Equatable, Sendable {
    case recordCancellation
    case reactivate
    case archive
    case restore
    case deletePermanently
}

enum RepositoryFailure: Equatable, Sendable {
    case lookup
    case update
    case delete
    case list
}

private let actionTargetID = UUID(
    uuidString: "50000000-0000-0000-0000-000000000005"
)!

private let unrelatedActionID = UUID(
    uuidString: "60000000-0000-0000-0000-000000000006"
)!

@MainActor
private func loadActionPresentation(
    _ workspace: SubscriptionWorkspace,
    subscription: Subscription,
    scope: SubscriptionLibraryScope,
    calendar: Calendar
) {
    workspace.loadLibrary(scope: scope)
    workspace.loadSubscription(id: subscription.id)
    workspace.loadExpectedCharges(
        subscriptionID: subscription.id,
        through: calendar.date(
            from: DateComponents(
                year: 2026,
                month: 9,
                day: 1,
                hour: 12
            )
        )!
    )
}

@MainActor
private func perform(
    _ action: WorkspaceLifecycleAction,
    on workspace: SubscriptionWorkspace,
    subscriptionID: UUID,
    calendar: Calendar
) throws {
    switch action {
    case .recordCancellation:
        workspace.recordCancellation(
            id: subscriptionID,
            cancelledAt: try actionDate(
                year: 2026,
                month: 7,
                day: 28,
                hour: 12,
                calendar: calendar
            ),
            accessUntil: try actionDate(
                year: 2026,
                month: 7,
                day: 29,
                hour: 12,
                calendar: calendar
            )
        )
    case .reactivate:
        workspace.reactivate(
            id: subscriptionID,
            nextRenewal: try actionDate(
                year: 2026,
                month: 7,
                day: 28,
                hour: 12,
                calendar: calendar
            )
        )
    case .archive:
        workspace.archive(id: subscriptionID)
    case .restore:
        workspace.restore(id: subscriptionID)
    case .deletePermanently:
        workspace.deletePermanently(id: subscriptionID)
    }
}

private func makeActionSubscription(
    id: UUID = actionTargetID,
    fixture: LifecycleFixture,
    isArchived: Bool = false,
    calendar: Calendar
) throws -> Subscription {
    let renewalAnchor = try actionDate(
        year: 2026,
        month: 6,
        day: 28,
        hour: 12,
        calendar: calendar
    )
    let confirmedNextRenewal = try actionDate(
        year: 2026,
        month: 7,
        day: 28,
        hour: 12,
        calendar: calendar
    )
    let lifecycle: SubscriptionLifecycle
    switch fixture {
    case .trial:
        lifecycle = .trial(
            firstPaidChargeAt: try actionDate(
                year: 2026,
                month: 7,
                day: 30,
                hour: 12,
                calendar: calendar
            )
        )
    case .active:
        lifecycle = .active
    case .cancelledWithAccess:
        lifecycle = .cancelled(
            cancelledAt: try actionDate(
                year: 2026,
                month: 7,
                day: 20,
                hour: 12,
                calendar: calendar
            ),
            accessUntil: try actionDate(
                year: 2026,
                month: 7,
                day: 29,
                hour: 12,
                calendar: calendar
            )
        )
    case .expired:
        lifecycle = .cancelled(
            cancelledAt: try actionDate(
                year: 2026,
                month: 7,
                day: 20,
                hour: 12,
                calendar: calendar
            ),
            accessUntil: try actionDate(
                year: 2026,
                month: 7,
                day: 28,
                hour: 12,
                calendar: calendar
            )
        )
    }
    let confirmedCharge = ConfirmedCharge(
        id: UUID(uuidString: "70000000-0000-0000-0000-000000000007")!,
        chargedDate: renewalAnchor,
        amount: Money(minorUnits: 999, currency: .usd)
    )
    return makeSubscription(
        id: id,
        lifecycle: lifecycle,
        isArchived: isArchived,
        billingSchedule: FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: renewalAnchor,
            timeZoneIdentifier: calendar.timeZone.identifier
        ),
        confirmedNextRenewal: confirmedNextRenewal,
        confirmedCharges: [confirmedCharge]
    )
}

private func actionCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func actionDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int = 0,
    calendar: Calendar
) throws -> Date {
    try #require(
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )
    )
}
