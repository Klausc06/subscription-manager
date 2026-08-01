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

    @Test("Calendar reconciliation surfaces an external calendar deletion without recreating it")
    @MainActor
    func calendarReconciliationRequiresDecisionForMissingCalendar() async throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let reconciler = CalendarReconcilerFixture(
            result: .needsDecision(.calendarMissing)
        )
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
            calendarProjectionReconciler: reconciler,
            now: { now },
            calendar: calendar
        )

        await workspace.reconcileCalendarProjection(
            locale: Locale(identifier: "en_US")
        )

        #expect(
            reconciler.commands == [.reconcile(workspace.calendarProjection)]
        )
        #expect(
            workspace.calendarReconciliationState
                == .needsDecision(.calendarMissing)
        )
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

    @Test(
        "Active presentations advance stale renewals before detail and sorting"
    )
    @MainActor
    func activePresentationsAdvanceStaleRenewals() throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 3,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let firstID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555551"
        )!
        let secondID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555552"
        )!
        let firstStart = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let secondStart = try actionDate(
            year: 2026,
            month: 1,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let staleFirstRenewal = try actionDate(
            year: 2026,
            month: 2,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let staleSecondRenewal = try actionDate(
            year: 2026,
            month: 2,
            day: 20,
            hour: 12,
            calendar: calendar
        )
        let expectedFirstRenewal = try actionDate(
            year: 2026,
            month: 3,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let expectedSecondRenewal = try actionDate(
            year: 2026,
            month: 3,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let first = makeSubscription(
            id: firstID,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: firstStart,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            confirmedNextRenewal: staleFirstRenewal,
            serviceName: "First"
        )
        let second = makeSubscription(
            id: secondID,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: secondStart,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            confirmedNextRenewal: staleSecondRenewal,
            serviceName: "Second"
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [first, second]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        workspace.loadLibrary()
        guard case .loaded(.current, let summaries) = workspace.libraryState else {
            Issue.record("Expected a loaded current library.")
            return
        }
        let firstSummary = try #require(
            summaries.first { $0.id == firstID }
        )
        let secondSummary = try #require(
            summaries.first { $0.id == secondID }
        )
        #expect(firstSummary.confirmedNextRenewal == expectedFirstRenewal)
        #expect(secondSummary.confirmedNextRenewal == expectedSecondRenewal)
        #expect(
            SubscriptionTableQuery(
                sort: .nextRenewal,
                ascending: true
            ).apply(to: summaries).map(\.id) == [secondID, firstID]
        )

        workspace.loadSubscription(id: firstID)
        guard case .loaded(let detail, _, _) = workspace.detailState else {
            Issue.record("Expected a loaded detail.")
            return
        }
        #expect(detail.confirmedNextRenewal == expectedFirstRenewal)
        #expect(
            repository.storedSubscription(id: firstID)?
                .confirmedNextRenewal == staleFirstRenewal
        )
    }

    @Test(
        "Active presentations skip today's billing-local occurrence before noon"
    )
    @MainActor
    func activePresentationsSkipCurrentBillingDay() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 3,
            day: 15,
            hour: 8,
            calendar: calendar
        )
        let start = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let todayOccurrence = try actionDate(
            year: 2026,
            month: 3,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let expectedRenewal = try actionDate(
            year: 2026,
            month: 4,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let id = UUID(
            uuidString: "11111111-2222-3333-4444-555555555553"
        )!
        let subscription = makeSubscription(
            id: id,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: start,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            confirmedNextRenewal: todayOccurrence
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(
                subscriptions: [subscription]
            ),
            now: { now },
            calendar: calendar
        )

        workspace.loadLibrary()
        guard case .loaded(.current, let summaries) = workspace.libraryState,
              let summary = summaries.first
        else {
            Issue.record("Expected a loaded current library.")
            return
        }
        #expect(summary.confirmedNextRenewal == expectedRenewal)
        #expect(summary.nextExpectedCharge?.scheduledDate == expectedRenewal)

        workspace.loadSubscription(id: id)
        guard case .loaded(
            let detail,
            _,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected a loaded detail.")
            return
        }
        #expect(detail.confirmedNextRenewal == expectedRenewal)
        #expect(nextExpectedCharge?.scheduledDate == expectedRenewal)
        #expect(
            workspace.makeWidgetSnapshot()?.nextRenewal?.renewalDate
                == expectedRenewal
        )
    }

    @Test("Every table sort keeps pinned subscriptions first by recency")
    func tableQueryKeepsPinnedSummariesFirst() {
        let newestID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555555"
        )!
        let tiedFirstID = UUID(
            uuidString: "22222222-2222-3333-4444-555555555555"
        )!
        let tiedSecondID = UUID(
            uuidString: "33333333-2222-3333-4444-555555555555"
        )!
        let unpinnedID = UUID(
            uuidString: "44444444-2222-3333-4444-555555555555"
        )!
        let olderPin = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let newestPin = olderPin.addingTimeInterval(60)
        let summaries = [
            SubscriptionSummary(
                subscription: makeSubscription(
                    id: unpinnedID,
                    serviceName: "A Service"
                ),
                status: .active,
                nextExpectedCharge: nil
            ),
            SubscriptionSummary(
                subscription: makeSubscription(
                    id: tiedSecondID,
                    pinnedAt: olderPin,
                    serviceName: "Z Service"
                ),
                status: .active,
                nextExpectedCharge: nil
            ),
            SubscriptionSummary(
                subscription: makeSubscription(
                    id: newestID,
                    pinnedAt: newestPin,
                    serviceName: "M Service"
                ),
                status: .active,
                nextExpectedCharge: nil
            ),
            SubscriptionSummary(
                subscription: makeSubscription(
                    id: tiedFirstID,
                    pinnedAt: olderPin,
                    serviceName: "Y Service"
                ),
                status: .active,
                nextExpectedCharge: nil
            ),
        ]

        for sort in SubscriptionTableSort.allCases {
            for ascending in [true, false] {
                let result = SubscriptionTableQuery(
                    searchText: "service",
                    sort: sort,
                    ascending: ascending
                )
                .apply(to: summaries)

                #expect(
                    Array(result.prefix(3).map(\.id))
                        == [newestID, tiedFirstID, tiedSecondID]
                )
                #expect(result.last?.id == unpinnedID)
            }
        }
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

    @Test("A new catalog session clears search and category filters")
    @MainActor
    func newCatalogSessionClearsFilters() throws {
        let music = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(en: "Music", zhHans: "音乐"),
            category: CatalogLocalizedText(en: "Music", zhHans: "音乐"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .music
        )
        let video = CatalogPreset(
            id: "video.example",
            serviceName: CatalogLocalizedText(en: "Video", zhHans: "视频"),
            category: CatalogLocalizedText(en: "Video", zhHans: "视频"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .video
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(),
            catalogRepository: StaticCatalogRepository(
                presets: [music, video]
            )
        )

        workspace.loadCatalog(locale: Locale(identifier: "en"))
        workspace.setCatalogSearchQuery("Video")
        workspace.setCatalogCategory("video")
        #expect(workspace.catalogState == .loaded(
            categories: [
                CatalogCategory(id: "music", title: music.category),
                CatalogCategory(id: "video", title: video.category),
            ],
            presets: [video]
        ))

        workspace.loadCatalog(locale: Locale(identifier: "en"))

        #expect(workspace.catalogState == .loaded(
            categories: [
                CatalogCategory(id: "music", title: music.category),
                CatalogCategory(id: "video", title: video.category),
            ],
            presets: [music, video]
        ))
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

    @Test("Workspace persists linked active dates through create and edit")
    @MainActor
    func workspacePersistsLinkedActiveDates() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-FFFFFFFFFFFF"
        )!
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let resolver = BillingDateResolver()
        let today = try actionDate(
            year: 2026,
            month: 7,
            day: 30,
            hour: 12,
            calendar: calendar
        )
        let start = try actionDate(
            year: 2025,
            month: 9,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let nextRenewal = try #require(
            resolver.nextRenewal(
                afterStart: start,
                interval: .monthly,
                asOf: today,
                timeZone: timeZone
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID },
            now: { today },
            calendar: calendar
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Standard",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: start,
                confirmedNextRenewal: nextRenewal,
                billingTimeZoneIdentifier: timeZone.identifier,
                managementURL: nil,
                notes: ""
            )
        )

        let created = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(created.startDate == start)
        #expect(created.billingSchedule.renewalAnchor == start)
        #expect(created.confirmedNextRenewal == nextRenewal)

        let editedRenewal = try actionDate(
            year: 2026,
            month: 10,
            day: 28,
            hour: 12,
            calendar: calendar
        )
        let editedStart = try #require(
            resolver.previousCycleStart(
                before: editedRenewal,
                interval: .monthly,
                timeZone: timeZone
            )
        )
        workspace.editSubscription(
            id: subscriptionID,
            input: SubscriptionEditInput(
                serviceName: created.serviceName,
                plan: created.plan,
                category: created.category,
                amount: created.amount(
                    onBillingDay: created.confirmedNextRenewal
                ),
                billingSchedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: editedStart,
                    timeZoneIdentifier: timeZone.identifier
                ),
                startDate: editedStart,
                confirmedNextRenewal: editedRenewal,
                managementURL: nil,
                notes: ""
            )
        )

        let edited = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(edited.startDate == editedStart)
        #expect(edited.billingSchedule.renewalAnchor == editedStart)
        #expect(edited.confirmedNextRenewal == editedRenewal)
    }

    @Test("Workspace resolves conflicting active creation dates")
    @MainActor
    func workspaceResolvesConflictingActiveCreationDates() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-ABABABABABAB"
        )!
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let today = try actionDate(
            year: 2026,
            month: 7,
            day: 30,
            hour: 12,
            calendar: calendar
        )
        let start = try actionDate(
            year: 2026,
            month: 6,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let conflictingRenewal = try actionDate(
            year: 2026,
            month: 6,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let expectedRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID },
            now: { today },
            calendar: calendar
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Standard",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: start,
                renewalAnchor: conflictingRenewal,
                confirmedNextRenewal: conflictingRenewal,
                billingTimeZoneIdentifier: timeZone.identifier,
                managementURL: nil,
                notes: ""
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.startDate == start)
        #expect(stored.billingSchedule.renewalAnchor == start)
        #expect(stored.confirmedNextRenewal == expectedRenewal)
    }

    @Test("Workspace resolves conflicting active edit dates")
    @MainActor
    func workspaceResolvesConflictingActiveEditDates() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-CDCDCDCDCDCD"
        )!
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let today = try actionDate(
            year: 2026,
            month: 7,
            day: 30,
            hour: 12,
            calendar: calendar
        )
        let originalStart = try actionDate(
            year: 2026,
            month: 6,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let editedStart = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let conflictingRenewal = try actionDate(
            year: 2026,
            month: 6,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let initialRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let expectedRenewal = try actionDate(
            year: 2027,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID },
            now: { today },
            calendar: calendar
        )
        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Standard",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: originalStart,
                confirmedNextRenewal: initialRenewal,
                billingTimeZoneIdentifier: timeZone.identifier,
                managementURL: nil,
                notes: ""
            )
        )

        workspace.editSubscription(
            id: subscriptionID,
            input: SubscriptionEditInput(
                serviceName: "Example",
                plan: "Standard",
                category: "Other",
                amount: Money(minorUnits: 999, currency: .usd),
                billingSchedule: FixedBillingSchedule(
                    interval: .yearly,
                    renewalAnchor: conflictingRenewal,
                    timeZoneIdentifier: timeZone.identifier
                ),
                startDate: editedStart,
                confirmedNextRenewal: expectedRenewal,
                managementURL: nil,
                notes: ""
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.startDate == editedStart)
        #expect(stored.billingSchedule.renewalAnchor == editedStart)
        #expect(stored.billingSchedule.interval == .yearly)
        #expect(stored.confirmedNextRenewal == expectedRenewal)
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
        let result = workspace.createCatalogSubscription(
            presetID: preset.id,
            command: .legacy(
                SubscriptionCreationInput(
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
        guard case .created = result else {
            Issue.record("Expected offer-less legacy catalog creation")
            return
        }
    }

    @Test("Verified catalog creation derives provider fields and permits actual charge")
    @MainActor
    func verifiedCatalogCreationDerivesProviderFields() throws {
        let verifiedOffer = catalogOfferFixture(
            id: "plus-monthly-us-web",
            status: .verified
        )
        let preset = catalogPresetFixture(offers: [verifiedOffer])
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "ACACACAC-1111-2222-3333-EEEEEEEEEEEE"
        )!
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let nextRenewal = start.addingTimeInterval(86_400)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            identifierGenerator: { subscriptionID }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let result = workspace.createCatalogSubscription(
            presetID: preset.id,
            command: .verifiedOffer(
                CatalogOfferSubscriptionInput(
                    offerID: verifiedOffer.id,
                    actualChargeOverride: Money(
                        minorUnits: 2_199,
                        currency: .eur
                    ),
                    billingIntervalSelection: .official,
                    startDate: start,
                    renewalAnchor: start,
                    confirmedNextRenewal: nextRenewal,
                    billingTimeZoneIdentifier: "UTC",
                    notes: "Personal note",
                    initialStatus: .active
                )
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(result == .created(stored))
        #expect(stored.serviceName == preset.serviceName.en)
        #expect(stored.plan == verifiedOffer.planName.en)
        #expect(stored.category == preset.category.en)
        #expect(stored.originalAmount == Money(
            minorUnits: 2_199,
            currency: .eur
        ))
        #expect(stored.billingSchedule.interval == verifiedOffer.billingInterval)
        #expect(stored.managementURL == preset.managementURL)
        #expect(stored.serviceIdentity.rawValue == "catalog:\(preset.id)")
    }

    @Test("Verified catalog creation permits a valid billing interval override")
    @MainActor
    func verifiedCatalogCreationPermitsBillingIntervalOverride() throws {
        let verifiedOffer = catalogOfferFixture(
            id: "plus-monthly-us-web",
            status: .verified
        )
        let preset = catalogPresetFixture(offers: [verifiedOffer])
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "ACACACAC-1111-2222-3333-FFFFFFFFFFFF"
        )!
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            identifierGenerator: { subscriptionID }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let result = workspace.createCatalogSubscription(
            presetID: preset.id,
            command: .verifiedOffer(
                CatalogOfferSubscriptionInput(
                    offerID: verifiedOffer.id,
                    actualChargeOverride: nil,
                    billingIntervalSelection: .override(
                        .custom(value: 3, unit: .week)
                    ),
                    startDate: start,
                    renewalAnchor: start,
                    confirmedNextRenewal:
                        start.addingTimeInterval(86_400),
                    billingTimeZoneIdentifier: "UTC",
                    notes: "",
                    initialStatus: .active
                )
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(result == .created(stored))
        #expect(
            stored.billingSchedule.interval
                == .custom(value: 3, unit: .week)
        )
    }

    @Test("Verified catalog creation validates a billing interval override")
    @MainActor
    func verifiedCatalogCreationValidatesBillingIntervalOverride() {
        let verifiedOffer = catalogOfferFixture(
            id: "plus-monthly-us-web",
            status: .verified
        )
        let preset = catalogPresetFixture(offers: [verifiedOffer])
        let repository = InMemorySubscriptionRepository()
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset])
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let result = workspace.createCatalogSubscription(
            presetID: preset.id,
            command: .verifiedOffer(
                CatalogOfferSubscriptionInput(
                    offerID: verifiedOffer.id,
                    actualChargeOverride: nil,
                    billingIntervalSelection: .override(
                        .custom(value: 0, unit: .week)
                    ),
                    startDate: start,
                    renewalAnchor: start,
                    confirmedNextRenewal:
                        start.addingTimeInterval(86_400),
                    billingTimeZoneIdentifier: "UTC",
                    notes: "",
                    initialStatus: .active
                )
            )
        )

        #expect(result == .validationFailed)
        #expect(
            workspace.creationValidationErrors[.billingSchedule]
                == .mustBePositive
        )
        #expect((try? repository.listSubscriptions())?.isEmpty == true)
    }

    @Test("Catalog creation rejects an unknown offer identifier")
    @MainActor
    func catalogCreationRejectsUnknownOffer() {
        let preset = catalogPresetFixture(offers: [
            catalogOfferFixture(
                id: "plus-monthly-us-web",
                status: .verified
            )
        ])
        let repository = InMemorySubscriptionRepository()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset])
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let result = workspace.createCatalogSubscription(
            presetID: preset.id,
            command: .verifiedOffer(
                catalogOfferInputFixture(offerID: "unknown")
            )
        )

        #expect(result == .rejected(.offerNotFound))
        #expect((try? repository.listSubscriptions())?.isEmpty == true)
    }

    @Test("Catalog creation rejects an offer that requires review")
    @MainActor
    func catalogCreationRejectsReviewRequiredOffer() {
        let offer = catalogOfferFixture(
            id: "research-only",
            status: .reviewRequired
        )
        let preset = catalogPresetFixture(offers: [offer])
        let repository = InMemorySubscriptionRepository()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset])
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let result = workspace.createCatalogSubscription(
            presetID: preset.id,
            command: .verifiedOffer(
                catalogOfferInputFixture(offerID: offer.id)
            )
        )

        #expect(result == .rejected(.offerRequiresReview))
        #expect((try? repository.listSubscriptions())?.isEmpty == true)
    }

    @Test("Catalog creation rejects legacy input when a verified offer exists")
    @MainActor
    func catalogCreationRequiresVerifiedOfferSelection() {
        let preset = catalogPresetFixture(offers: [
            catalogOfferFixture(
                id: "plus-monthly-us-web",
                status: .verified
            )
        ])
        let repository = InMemorySubscriptionRepository()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset])
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let result = workspace.createCatalogSubscription(
            presetID: preset.id,
            command: .legacy(
                SubscriptionCreationInput(
                    serviceName: "Forged",
                    plan: "Forged",
                    category: "Forged",
                    originalAmount: Money(minorUnits: 1, currency: .cny),
                    startDate: .distantPast,
                    confirmedNextRenewal: .distantFuture,
                    managementURL: nil,
                    notes: ""
                )
            )
        )

        #expect(result == .rejected(.verifiedOfferRequired))
        #expect((try? repository.listSubscriptions())?.isEmpty == true)
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
        #expect(
            stored.billingSchedule.renewalAnchor == firstPaidCharge
        )
        #expect(stored.startDate == start)
        #expect(stored.confirmedNextRenewal == firstPaidCharge)
        #expect(stored.isArchived == false)
    }

    @Test("Editing Trial Start and paid interval keeps First Paid Charge fixed")
    @MainActor
    func trialEditKeepsFirstPaidChargeIndependent() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "11111111-AAAA-BBBB-CCCC-333333333333"
        )!
        let calendar = utcCalendar()
        let trialStart = try actionDate(
            year: 2026,
            month: 1,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let firstPaidCharge = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let editedTrialStart = try actionDate(
            year: 2026,
            month: 1,
            day: 5,
            hour: 12,
            calendar: calendar
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID },
            calendar: calendar
        )
        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: trialStart,
                confirmedNextRenewal: firstPaidCharge,
                billingTimeZoneIdentifier: "UTC",
                managementURL: nil,
                notes: "",
                initialStatus: .trial
            )
        )

        workspace.editSubscription(
            id: subscriptionID,
            input: SubscriptionEditInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                amount: Money(minorUnits: 999, currency: .usd),
                billingSchedule: FixedBillingSchedule(
                    interval: .yearly,
                    renewalAnchor: editedTrialStart,
                    timeZoneIdentifier: "UTC"
                ),
                startDate: editedTrialStart,
                confirmedNextRenewal: firstPaidCharge,
                managementURL: nil,
                notes: ""
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.startDate == editedTrialStart)
        #expect(stored.confirmedNextRenewal == firstPaidCharge)
        #expect(
            stored.lifecycle == .trial(
                firstPaidChargeAt: firstPaidCharge
            )
        )
        #expect(stored.billingSchedule.interval == .yearly)
        #expect(
            stored.billingSchedule.renewalAnchor == firstPaidCharge
        )
    }

    @Test("Editing First Paid Charge updates the lifecycle boundary")
    @MainActor
    func editingFirstPaidChargeUpdatesLifecycleBoundary() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "11111111-AAAA-BBBB-CCCC-555555555555"
        )!
        let calendar = utcCalendar()
        let trialStart = try actionDate(
            year: 2026,
            month: 1,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let originalFirstPaidCharge = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let editedFirstPaidCharge = try actionDate(
            year: 2026,
            month: 1,
            day: 20,
            hour: 12,
            calendar: calendar
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID },
            calendar: calendar
        )
        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: trialStart,
                confirmedNextRenewal: originalFirstPaidCharge,
                billingTimeZoneIdentifier: "UTC",
                managementURL: nil,
                notes: "",
                initialStatus: .trial
            )
        )

        workspace.editSubscription(
            id: subscriptionID,
            input: SubscriptionEditInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                amount: Money(minorUnits: 999, currency: .usd),
                billingSchedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: originalFirstPaidCharge,
                    timeZoneIdentifier: "UTC"
                ),
                startDate: trialStart,
                confirmedNextRenewal: editedFirstPaidCharge,
                managementURL: nil,
                notes: ""
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(
            stored.lifecycle == .trial(
                firstPaidChargeAt: editedFirstPaidCharge
            )
        )
        #expect(
            stored.billingSchedule.renewalAnchor == editedFirstPaidCharge
        )
        #expect(stored.confirmedNextRenewal == editedFirstPaidCharge)
        #expect(
            stored.lifecycle.status(
                asOf: try actionDate(
                    year: 2026,
                    month: 1,
                    day: 16,
                    hour: 12,
                    calendar: calendar
                ),
                timeZone: try #require(TimeZone(identifier: "UTC"))
            ) == .trial
        )
        #expect(
            stored.lifecycle.status(
                asOf: editedFirstPaidCharge,
                timeZone: try #require(TimeZone(identifier: "UTC"))
            ) == .active
        )
    }

    @Test("Trial commands reject non-finite dates")
    @MainActor
    func trialCommandsRejectNonFiniteDates() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "11111111-AAAA-BBBB-CCCC-666666666666"
        )!
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let firstPaidCharge = start.addingTimeInterval(86_400)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                startDate: Date(timeIntervalSinceReferenceDate: .nan),
                confirmedNextRenewal: firstPaidCharge,
                managementURL: nil,
                notes: "",
                initialStatus: .trial
            )
        )
        #expect(
            repository.storedSubscription(id: subscriptionID) == nil
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                startDate: start,
                confirmedNextRenewal:
                    Date(timeIntervalSinceReferenceDate: .infinity),
                managementURL: nil,
                notes: "",
                initialStatus: .trial
            )
        )
        #expect(
            repository.storedSubscription(id: subscriptionID) == nil
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                startDate: start,
                confirmedNextRenewal: firstPaidCharge,
                managementURL: nil,
                notes: "",
                initialStatus: .trial
            )
        )
        workspace.editSubscription(
            id: subscriptionID,
            input: SubscriptionEditInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                amount: Money(minorUnits: 999, currency: .usd),
                billingSchedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: firstPaidCharge,
                    timeZoneIdentifier: "UTC"
                ),
                startDate: start,
                confirmedNextRenewal:
                    Date(timeIntervalSinceReferenceDate: .nan),
                managementURL: nil,
                notes: ""
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.confirmedNextRenewal == firstPaidCharge)
        #expect(
            workspace.editingValidationErrors[
                .confirmedNextRenewal
            ] == .required
        )
    }

    @Test("Trial forecast starts on First Paid Charge")
    @MainActor
    func trialForecastStartsOnFirstPaidCharge() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "11111111-AAAA-BBBB-CCCC-444444444444"
        )!
        let calendar = utcCalendar()
        let trialStart = try actionDate(
            year: 2026,
            month: 1,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let now = try actionDate(
            year: 2026,
            month: 1,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let firstPaidCharge = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let horizon = try actionDate(
            year: 2026,
            month: 3,
            day: 31,
            hour: 12,
            calendar: calendar
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID },
            now: { now },
            calendar: calendar
        )

        workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "Trial",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 999,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: trialStart,
                confirmedNextRenewal: firstPaidCharge,
                billingTimeZoneIdentifier: "UTC",
                managementURL: nil,
                notes: "",
                initialStatus: .trial
            )
        )
        workspace.loadExpectedCharges(
            subscriptionID: subscriptionID,
            through: horizon
        )

        let charges = try #require(workspace.expectedCharges)
        #expect(charges.map(\.scheduledDate) == [
            firstPaidCharge,
            try actionDate(
                year: 2026,
                month: 2,
                day: 15,
                hour: 12,
                calendar: calendar
            ),
            try actionDate(
                year: 2026,
                month: 3,
                day: 15,
                hour: 12,
                calendar: calendar
            ),
        ])
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

    @Test("Creation allows empty optional metadata")
    @MainActor
    func creationAllowsEmptyOptionalMetadata() throws {
        let repository = InMemorySubscriptionRepository()
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_769_904_000) }
        )
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)

        let result = workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "Example",
                plan: "",
                category: "\n",
                originalAmount: Money(minorUnits: 999, currency: .usd),
                billingInterval: .monthly,
                startDate: startDate,
                confirmedNextRenewal: startDate,
                billingTimeZoneIdentifier: "UTC",
                managementURL: nil,
                notes: ""
            )
        )

        guard case .created(let created) = result else {
            Issue.record("Expected creation to accept optional metadata.")
            return
        }
        #expect(created.plan.isEmpty)
        #expect(created.category.isEmpty)
        #expect(workspace.creationValidationErrors.isEmpty)
    }

    @Test("Editing allows empty optional metadata")
    @MainActor
    func editingAllowsEmptyOptionalMetadata() throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 30,
            hour: 12,
            calendar: calendar
        )
        let startDate = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let nextRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let existing = makeSubscription(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: startDate,
                timeZoneIdentifier: "UTC"
            ),
            confirmedNextRenewal: nextRenewal
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        workspace.editSubscription(
            id: existing.id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: "",
                category: "\t",
                amount: existing.amount(
                    onBillingDay: existing.confirmedNextRenewal
                ),
                billingSchedule: existing.billingSchedule,
                startDate: existing.startDate,
                confirmedNextRenewal: existing.confirmedNextRenewal,
                managementURL: nil,
                notes: existing.notes
            )
        )

        #expect(workspace.editingValidationErrors.isEmpty)
        #expect(
            repository.storedSubscription(id: existing.id)?.plan.isEmpty == true
        )
        #expect(
            repository.storedSubscription(id: existing.id)?.category.isEmpty
                == true
        )
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
                .originalAmount: .required,
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
            identifierGenerator: { subscriptionID },
            now: { startDate }
        )

        creationWorkspace.createSubscription(input)

        let reloadedWorkspace = SubscriptionWorkspace(
            repository: repository,
            now: { startDate }
        )
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
            identifierGenerator: { subscriptionID },
            now: { startDate }
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

    @Test("Creation reports the one normalized record persisted by the workspace")
    @MainActor
    func creationReportsExactlyOnePersistedSubscription() throws {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "33333333-4444-5555-6666-777777777777"
        )!
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )

        let result = workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: " Atlas ",
                plan: "Pro",
                category: "Productivity",
                originalAmount: Money(minorUnits: 1_299, currency: .usd),
                startDate: Date(timeIntervalSince1970: 1_767_225_600),
                confirmedNextRenewal: Date(timeIntervalSince1970: 1_769_904_000),
                managementURL: nil,
                notes: ""
            )
        )

        guard case .created(let created) = result else {
            Issue.record("Expected a persisted subscription result")
            return
        }
        #expect(created.id == subscriptionID)
        #expect(created.serviceName == "Atlas")
        #expect(try repository.listSubscriptions() == [created])
    }

    @Test("Intent-facing queries keep stable records but exclude archived renewals")
    @MainActor
    func intentFacingQueriesUseTheSameWorkspaceRules() throws {
        let currentID = UUID(
            uuidString: "44444444-5555-6666-7777-888888888888"
        )!
        let archivedID = UUID(
            uuidString: "55555555-6666-7777-8888-999999999999"
        )!
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let current = makeSubscription(
            id: currentID,
            confirmedNextRenewal: now.addingTimeInterval(86_400),
            serviceName: "Atlas"
        )
        let archived = makeSubscription(
            id: archivedID,
            isArchived: true,
            confirmedNextRenewal: now.addingTimeInterval(43_200),
            serviceName: "Beacon"
        )
        let workspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository(
                subscriptions: [archived, current]
            ),
            now: { now }
        )

        #expect(try workspace.subscriptions().map(\.id) == [currentID, archivedID])
        #expect(try workspace.subscription(for: archivedID) == archived)
        #expect(try workspace.subscription(for: UUID()) == nil)
        #expect(
            try workspace.upcomingRenewals(
                from: now,
                through: now.addingTimeInterval(40 * 86_400)
            ).map(\.subscriptionID) == [currentID]
        )
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
        "Cancelled and expired subscriptions can reactivate with a future renewal",
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
            month: 8,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let expectedStart = try actionDate(
            year: 2026,
            month: 7,
            day: 10,
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
                month: 8,
                day: 10,
                hour: 1,
                calendar: calendar
            )
        )

        let stored = try #require(
            repository.storedSubscription(id: subscription.id)
        )
        #expect(stored.lifecycle == .active)
        #expect(stored.startDate == expectedStart)
        #expect(
            stored.billingSchedule.interval
                == subscription.billingSchedule.interval
        )
        #expect(
            stored.billingSchedule.renewalAnchor
                == expectedStart
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

    @Test("Reactivation refreshes every loaded schedule consumer")
    @MainActor
    func reactivationRefreshesLoadedConsumers() async throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
            calendar: calendar
        )
        let nextRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let through = try actionDate(
            year: 2026,
            month: 9,
            day: 30,
            hour: 12,
            calendar: calendar
        )
        let subscription = try makeActionSubscription(
            fixture: .cancelledWithAccess,
            calendar: calendar
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let rateSnapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            exchangeRateCache: InMemoryExchangeRateCache(
                state: ExchangeRateCacheState(
                    snapshot: rateSnapshot,
                    lastAttemptAt: now
                )
            ),
            now: { now },
            calendar: calendar
        )

        await workspace.refreshExchangeRates()
        workspace.loadLibrary()
        workspace.loadSubscription(id: subscription.id)
        workspace.loadUpcomingTimeline(from: now, through: through)
        workspace.loadCalendarProjection(locale: Locale(identifier: "en"))
        workspace.loadInsights(
            mode: .expected,
            from: now,
            through: through
        )
        #expect(workspace.upcomingTimeline.isEmpty)
        #expect(workspace.calendarProjection.isEmpty)
        #expect(
            workspace.insightsState.availableValue?.items.isEmpty == true
        )

        workspace.reactivate(
            id: subscription.id,
            nextRenewal: nextRenewal
        )

        #expect(workspace.upcomingTimeline.first?.date == nextRenewal)
        #expect(workspace.calendarProjection.first?.startDate == nextRenewal)
        #expect(
            workspace.insightsState.availableValue?.items.first?.date
                == nextRenewal
        )
        #expect(
            workspace.makeWidgetSnapshot()?.nextRenewal?.renewalDate
                == nextRenewal
        )
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

    @Test("Reactivation on the current billing-local day is rejected")
    @MainActor
    func currentDayReactivationIsRejected() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 18,
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
                day: 28,
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

    @Test("Pin commands persist recency and preserve it through archive")
    @MainActor
    func pinCommandsPersistRecencyAndPreserveArchive() throws {
        let subscriptionID = UUID(
            uuidString: "70000000-0000-0000-0000-000000000007"
        )!
        let now = Date(timeIntervalSinceReferenceDate: 810_000_000)
        let subscription = makeSubscription(id: subscriptionID)
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now }
        )

        workspace.loadLibrary(scope: .current)
        workspace.setPinned(id: subscriptionID, pinned: true)

        var stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.pinnedAt == now)
        #expect(repository.updateAttemptCount == 1)
        guard case .loaded(.current, let pinnedSummaries) =
            workspace.libraryState
        else {
            Issue.record("Expected refreshed current library")
            return
        }
        #expect(pinnedSummaries.first?.pinnedAt == now)

        workspace.setPinned(id: subscriptionID, pinned: true)
        #expect(repository.updateAttemptCount == 1)

        workspace.archive(id: subscriptionID)
        stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.isArchived)
        #expect(stored.pinnedAt == now)

        workspace.restore(id: subscriptionID)
        stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(!stored.isArchived)
        #expect(stored.pinnedAt == now)

        workspace.setPinned(id: subscriptionID, pinned: false)
        stored = try #require(
            repository.storedSubscription(id: subscriptionID)
        )
        #expect(stored.pinnedAt == nil)
        #expect(repository.updateAttemptCount == 4)

        workspace.setPinned(id: subscriptionID, pinned: false)
        #expect(repository.updateAttemptCount == 4)
    }

    @Test("Archived subscriptions cannot be newly pinned")
    @MainActor
    func archivedSubscriptionsCannotBeNewlyPinned() throws {
        let subscription = makeSubscription(
            id: UUID(
                uuidString: "80000000-0000-0000-0000-000000000008"
            )!,
            isArchived: true
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(repository: repository)

        workspace.setPinned(id: subscription.id, pinned: true)

        #expect(
            repository.storedSubscription(id: subscription.id)
                == subscription
        )
        #expect(repository.updateAttemptCount == 0)
        #expect(
            workspace.lifecycleActionError == .invalidLifecycleTransition
        )
    }

    @Test("A failed pin keeps persisted and presented state unchanged")
    @MainActor
    func failedPinKeepsStateUnchanged() {
        let subscription = makeSubscription(
            id: UUID(
                uuidString: "90000000-0000-0000-0000-000000000009"
            )!
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(repository: repository)
        workspace.loadLibrary(scope: .current)
        let libraryBefore = workspace.libraryState
        repository.failure = .update

        workspace.setPinned(id: subscription.id, pinned: true)

        #expect(
            repository.storedSubscription(id: subscription.id)
                == subscription
        )
        #expect(workspace.libraryState == libraryBefore)
        #expect(
            workspace.lifecycleActionError == .persistenceFailed
        )
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
        #expect(
            replacingConfirmedNextRenewal(
                in: detail,
                with: stored.confirmedNextRenewal
            ) == stored
        )
        #expect(status == fixture.status)
        #expect(
            (nextExpectedCharge != nil)
                == fixture.isEligibleForExpectedCharges
        )
        if case .active = fixture {
            #expect(
                detail.confirmedNextRenewal
                    == nextExpectedCharge?.scheduledDate
            )
        } else {
            #expect(
                detail.confirmedNextRenewal
                    == stored.confirmedNextRenewal
            )
        }
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

    @Test("Manual ChatGPT Plus creation adopts the verified catalog offer")
    @MainActor
    func manualCreationReconcilesUniqueCatalogOffer() throws {
        let repository = InMemorySubscriptionRepository()
        let preset = catalogPresetFixture(
            offers: [catalogOfferFixture(id: "plus", status: .verified)],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            ),
            matchAliases: ["ChatGPT Plus"]
        )
        let now = Date(timeIntervalSince1970: 1_769_731_200)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            now: { now }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let result = workspace.createSubscription(
            SubscriptionCreationInput(
                serviceName: "ChatGPT Plus",
                plan: "Anything",
                category: "Other",
                originalAmount: Money(
                    minorUnits: 2_000,
                    currency: .usd
                ),
                billingInterval: .monthly,
                startDate: now,
                confirmedNextRenewal: now,
                billingTimeZoneIdentifier: "UTC",
                managementURL: nil,
                notes: "Keep this",
                initialStatus: .active
            )
        )

        let created: Subscription
        switch result {
        case .created(let subscription):
            created = subscription
        case .validationFailed, .persistenceFailed:
            Issue.record("Expected a reconciled subscription.")
            return
        }
        #expect(created.serviceIdentity.rawValue == "catalog:chatgpt")
        #expect(created.serviceName == "ChatGPT")
        #expect(created.plan == "Plus")
        #expect(created.category == "Productivity")
        #expect(created.managementURL == preset.managementURL)
        #expect(created.originalAmount.minorUnits == 2_000)
        #expect(created.notes == "Keep this")
    }

    @Test("Manual editing uses the same catalog reconciliation seam")
    @MainActor
    func manualEditReconcilesUniqueCatalogOffer() throws {
        let id = UUID(
            uuidString: "90000000-0000-0000-0000-000000000047"
        )!
        let pinnedAt = Date(timeIntervalSince1970: 1_769_700_000)
        let existing = makeSubscription(
            id: id,
            pinnedAt: pinnedAt,
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "Before Edit",
            notes: "Original notes"
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let preset = catalogPresetFixture(
            offers: [catalogOfferFixture(id: "plus", status: .verified)],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            ),
            matchAliases: ["ChatGPT Plus"]
        )
        let now = Date(timeIntervalSince1970: 1_769_731_200)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            now: { now }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: "ChatGPT Plus",
                plan: "Ignored Plan",
                category: "Ignored Category",
                amount: existing.amount(
                    onBillingDay: existing.confirmedNextRenewal
                ),
                billingSchedule: existing.billingSchedule,
                startDate: existing.startDate,
                confirmedNextRenewal: existing.confirmedNextRenewal,
                managementURL: nil,
                notes: "Edited notes"
            )
        )

        let edited = try #require(
            repository.storedSubscription(id: id)
        )
        #expect(edited.serviceIdentity.rawValue == "catalog:chatgpt")
        #expect(edited.serviceName == "ChatGPT")
        #expect(edited.plan == "Plus")
        #expect(edited.category == "Productivity")
        #expect(edited.managementURL == preset.managementURL)
        #expect(edited.notes == "Edited notes")
        #expect(edited.pinnedAt == pinnedAt)
    }

    @Test("Renaming a catalog subscription clears its stale identity atomically")
    @MainActor
    func catalogRenameClearsStaleIdentityDuringAtomicEdit() throws {
        let id = UUID(
            uuidString: "91000000-0000-0000-0000-000000000047"
        )!
        let existing = makeSubscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "catalog:chatgpt"),
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "ChatGPT",
            plan: "Plus"
        )
        let preset = catalogPresetFixture(
            offers: [catalogOfferFixture(id: "plus", status: .verified)],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            ),
            matchAliases: ["ChatGPT Plus"]
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            now: { Date(timeIntervalSince1970: 1_769_731_200) }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: "Renamed Service",
                plan: existing.plan,
                category: existing.category,
                amount: existing.amount(
                    onBillingDay: existing.confirmedNextRenewal
                ),
                billingSchedule: existing.billingSchedule,
                startDate: existing.startDate,
                confirmedNextRenewal: existing.confirmedNextRenewal,
                managementURL: existing.managementURL,
                notes: existing.notes
            )
        )

        let edited = try #require(repository.storedSubscription(id: id))
        #expect(
            edited.serviceIdentity
                == ServiceIdentity(rawValue: "manual:\(id.uuidString)")
        )
        #expect(edited.serviceName == "Renamed Service")
        #expect(repository.updateAttemptCount == 1)
    }

    @Test("A price-only catalog override retains catalog identity atomically")
    @MainActor
    func catalogPriceOnlyOverrideRetainsIdentityDuringAtomicEdit() throws {
        let id = UUID(
            uuidString: "92000000-0000-0000-0000-000000000047"
        )!
        let existing = makeSubscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "catalog:chatgpt"),
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "ChatGPT",
            plan: "Plus"
        )
        let preset = catalogPresetFixture(
            offers: [catalogOfferFixture(id: "plus", status: .verified)],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            )
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            now: { Date(timeIntervalSince1970: 1_769_731_200) }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: existing.plan,
                category: existing.category,
                amount: Money(minorUnits: 3_000, currency: .usd),
                billingSchedule: existing.billingSchedule,
                startDate: existing.startDate,
                confirmedNextRenewal: existing.confirmedNextRenewal,
                managementURL: existing.managementURL,
                notes: existing.notes
            )
        )

        let edited = try #require(repository.storedSubscription(id: id))
        #expect(
            edited.serviceIdentity
                == ServiceIdentity(rawValue: "catalog:chatgpt")
        )
        #expect(
            edited.amount(onBillingDay: edited.confirmedNextRenewal)
                == Money(minorUnits: 3_000, currency: .usd)
        )
        #expect(
            workspace.catalogOfferAdjustment(for: edited)
                == CatalogOfferAdjustment(
                    isPriceAdjusted: true,
                    isScheduleAdjusted: false
                )
        )
        #expect(repository.updateAttemptCount == 1)
    }

    @Test("An interval-only catalog override retains catalog identity atomically")
    @MainActor
    func catalogIntervalOnlyOverrideRetainsIdentityDuringAtomicEdit() throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 15,
            hour: 18,
            calendar: calendar
        )
        let startDate = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let yearlyRenewal = try actionDate(
            year: 2027,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let id = UUID(
            uuidString: "93000000-0000-0000-0000-000000000047"
        )!
        let existing = makeSubscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "catalog:chatgpt"),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: startDate,
                timeZoneIdentifier: "UTC"
            ),
            confirmedNextRenewal: try actionDate(
                year: 2026,
                month: 8,
                day: 1,
                hour: 12,
                calendar: calendar
            ),
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "ChatGPT",
            plan: "Plus"
        )
        let preset = catalogPresetFixture(
            offers: [catalogOfferFixture(id: "plus", status: .verified)],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            )
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            now: { now },
            calendar: calendar
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: existing.plan,
                category: existing.category,
                amount: existing.amount(
                    onBillingDay: existing.confirmedNextRenewal
                ),
                billingSchedule: FixedBillingSchedule(
                    interval: .yearly,
                    renewalAnchor: startDate,
                    timeZoneIdentifier: "UTC"
                ),
                startDate: startDate,
                confirmedNextRenewal: yearlyRenewal,
                managementURL: existing.managementURL,
                notes: existing.notes
            )
        )

        let edited = try #require(repository.storedSubscription(id: id))
        #expect(
            edited.serviceIdentity
                == ServiceIdentity(rawValue: "catalog:chatgpt")
        )
        #expect(
            edited.billingSchedule.interval == BillingInterval.yearly
        )
        #expect(
            workspace.catalogOfferAdjustment(for: edited)
                == CatalogOfferAdjustment(
                    isPriceAdjusted: false,
                    isScheduleAdjusted: true
                )
        )
        #expect(repository.updateAttemptCount == 1)
    }

    @Test("An empty catalog does not clear a catalog identity on edit")
    @MainActor
    func catalogEditWithEmptyCatalogRetainsIdentity() throws {
        let id = UUID(
            uuidString: "94000000-0000-0000-0000-000000000047"
        )!
        let existing = makeSubscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "catalog:chatgpt"),
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "ChatGPT"
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: []),
            now: { Date(timeIntervalSince1970: 1_769_731_200) }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: existing.plan,
                category: existing.category,
                amount: existing.amount(
                    onBillingDay: existing.confirmedNextRenewal
                ),
                billingSchedule: existing.billingSchedule,
                startDate: existing.startDate,
                confirmedNextRenewal: existing.confirmedNextRenewal,
                managementURL: existing.managementURL,
                notes: "Edited while catalog unavailable"
            )
        )

        let edited = try #require(repository.storedSubscription(id: id))
        #expect(
            edited.serviceIdentity
                == ServiceIdentity(rawValue: "catalog:chatgpt")
        )
        #expect(edited.notes == "Edited while catalog unavailable")
        #expect(repository.updateAttemptCount == 1)
    }

    @Test(
        "Explicit reconciliation preserves every non-catalog fact and is idempotent"
    )
    @MainActor
    func explicitCatalogReconciliationPreservesFacts() throws {
        let id = UUID(
            uuidString: "A0000000-0000-0000-0000-000000000047"
        )!
        let now = Date(timeIntervalSince1970: 1_769_731_200)
        let pinnedAt = now.addingTimeInterval(-300)
        let existing = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "manual:\(id)"),
            serviceName: "ChatGPT Plus",
            plan: "User Plan",
            category: "Other",
            originalAmount: Money(minorUnits: 1_500, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: now,
                timeZoneIdentifier: "UTC"
            ),
            startDate: now,
            confirmedNextRenewal: now.addingTimeInterval(86_400),
            managementURL: URL(string: "https://old.example.com"),
            notes: "Preserved notes",
            confirmedCharges: [
                ConfirmedCharge(
                    id: UUID(
                        uuidString:
                            "A0000000-0000-0000-0000-000000000048"
                    )!,
                    chargedDate: now.addingTimeInterval(-86_400),
                    amount: Money(minorUnits: 1_500, currency: .usd)
                ),
            ],
            priceChanges: [
                PriceChange(
                    id: UUID(
                        uuidString:
                            "A0000000-0000-0000-0000-000000000049"
                    )!,
                    effectiveDate: now.addingTimeInterval(-3_600),
                    amount: Money(minorUnits: 2_000, currency: .usd)
                ),
            ],
            lifecycle: .cancelled(
                cancelledAt: now.addingTimeInterval(-1_800),
                accessUntil: now.addingTimeInterval(86_400)
            ),
            isArchived: true,
            pinnedAt: pinnedAt
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let preset = catalogPresetFixture(
            offers: [catalogOfferFixture(id: "plus", status: .verified)],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            ),
            matchAliases: ["ChatGPT Plus"]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            now: { now }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let first = workspace.reconcileCatalogAssociations(
            locale: Locale(identifier: "en")
        )
        let normalized = try #require(
            repository.storedSubscription(id: id)
        )

        #expect(first.normalizedIDs == [id])
        #expect(first.unchangedIDs.isEmpty)
        #expect(first.ambiguousIDs.isEmpty)
        #expect(first.failedIDs.isEmpty)
        #expect(first.commandError == nil)
        #expect(normalized.serviceIdentity.rawValue == "catalog:chatgpt")
        #expect(normalized.serviceName == "ChatGPT")
        #expect(normalized.plan == "Plus")
        #expect(normalized.category == "Productivity")
        #expect(normalized.managementURL == preset.managementURL)
        #expect(normalized.originalAmount == existing.originalAmount)
        #expect(normalized.billingSchedule == existing.billingSchedule)
        #expect(normalized.startDate == existing.startDate)
        #expect(
            normalized.confirmedNextRenewal
                == existing.confirmedNextRenewal
        )
        #expect(normalized.notes == existing.notes)
        #expect(normalized.confirmedCharges == existing.confirmedCharges)
        #expect(normalized.priceChanges == existing.priceChanges)
        #expect(normalized.lifecycle == existing.lifecycle)
        #expect(normalized.isArchived == existing.isArchived)
        #expect(normalized.pinnedAt == existing.pinnedAt)

        let second = workspace.reconcileCatalogAssociations(
            locale: Locale(identifier: "en")
        )
        #expect(second.normalizedIDs.isEmpty)
        #expect(second.unchangedIDs == [id])
        #expect(repository.updateAttemptCount == 1)
    }

    @Test("Reconciliation refreshes loaded consumers from persisted truth")
    @MainActor
    func reconciliationRefreshesLoadedConsumers() throws {
        let id = UUID(
            uuidString: "A1000000-0000-0000-0000-000000000047"
        )!
        let now = Date(timeIntervalSince1970: 1_768_521_600)
        let existing = makeSubscription(
            id: id,
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "ChatGPT Plus"
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let preset = catalogPresetFixture(
            offers: [catalogOfferFixture(id: "plus", status: .verified)],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            ),
            matchAliases: ["ChatGPT Plus"]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            now: { now }
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))
        workspace.loadLibrary()
        workspace.loadSubscription(id: id)
        workspace.loadUpcomingTimeline(
            from: existing.startDate,
            through: existing.confirmedNextRenewal.addingTimeInterval(
                62 * 86_400
            )
        )
        workspace.loadCalendarProjection(
            locale: Locale(identifier: "en")
        )
        #expect(
            workspace.upcomingTimeline.contains {
                $0.serviceName == "ChatGPT Plus"
            }
        )
        #expect(
            workspace.calendarProjection.contains {
                $0.title.contains("ChatGPT Plus")
            }
        )

        workspace.reconcileCatalogAssociations(
            locale: Locale(identifier: "en")
        )

        guard case .loaded(let detail, _, _) = workspace.detailState else {
            Issue.record("Expected refreshed detail.")
            return
        }
        #expect(detail.serviceName == "ChatGPT")
        #expect(
            workspace.upcomingTimeline.allSatisfy {
                $0.serviceName == "ChatGPT"
            }
        )
        #expect(
            workspace.calendarProjection.allSatisfy {
                !$0.title.contains("ChatGPT Plus")
                    && $0.title.contains("ChatGPT")
            }
        )
        #expect(
            workspace.makeWidgetSnapshot()?.nextRenewal?.serviceName
                == "ChatGPT"
        )
    }

    @Test("Editing billing dates refreshes every loaded schedule consumer")
    @MainActor
    func editingBillingDatesRefreshesLoadedConsumers() async throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let oldStart = try actionDate(
            year: 2025,
            month: 12,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let oldRenewal = try actionDate(
            year: 2026,
            month: 2,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let editedStart = try actionDate(
            year: 2025,
            month: 12,
            day: 20,
            hour: 12,
            calendar: calendar
        )
        let editedRenewal = try actionDate(
            year: 2026,
            month: 1,
            day: 20,
            hour: 12,
            calendar: calendar
        )
        let through = try actionDate(
            year: 2026,
            month: 3,
            day: 31,
            hour: 12,
            calendar: calendar
        )
        let id = UUID(
            uuidString: "A2000000-0000-0000-0000-000000000048"
        )!
        let existing = makeSubscription(
            id: id,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: oldStart,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            confirmedNextRenewal: oldRenewal,
            serviceName: "Schedule Consumer"
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let rateSnapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            exchangeRateCache: InMemoryExchangeRateCache(
                state: ExchangeRateCacheState(
                    snapshot: rateSnapshot,
                    lastAttemptAt: now
                )
            ),
            now: { now },
            calendar: calendar
        )

        await workspace.refreshExchangeRates()
        workspace.loadLibrary()
        workspace.loadSubscription(id: id)
        workspace.loadUpcomingTimeline(
            from: now.addingTimeInterval(1),
            through: through
        )
        workspace.loadCalendarProjection(locale: Locale(identifier: "en"))
        workspace.loadInsights(
            mode: .expected,
            from: now.addingTimeInterval(1),
            through: through
        )
        #expect(workspace.upcomingTimeline.first?.date == oldRenewal)
        #expect(
            workspace.calendarProjection.first?.startDate
                == oldRenewal
        )
        #expect(
            workspace.insightsState.availableValue?.items.first?.date
                == oldRenewal
        )

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: existing.plan,
                category: existing.category,
                amount: existing.amount(
                    onBillingDay: existing.confirmedNextRenewal
                ),
                billingSchedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: editedStart,
                    timeZoneIdentifier: calendar.timeZone.identifier
                ),
                startDate: editedStart,
                confirmedNextRenewal: editedRenewal,
                managementURL: existing.managementURL,
                notes: existing.notes
            )
        )

        #expect(
            repository.storedSubscription(id: id)?
                .confirmedNextRenewal == editedRenewal
        )
        #expect(workspace.upcomingTimeline.first?.date == editedRenewal)
        #expect(
            workspace.calendarProjection.first?.startDate
                == editedRenewal
        )
        #expect(
            workspace.insightsState.availableValue?.items.first?.date
                == editedRenewal
        )
        #expect(
            workspace.makeWidgetSnapshot()?.nextRenewal?.renewalDate
                == editedRenewal
        )
        guard case .loaded(let detail, _, _) = workspace.detailState else {
            Issue.record("Expected refreshed detail.")
            return
        }
        #expect(detail.confirmedNextRenewal == editedRenewal)
    }

    @Test("Ordinary edits correct effective amount and metadata atomically")
    @MainActor
    func editAtomicallyCorrectsEffectiveAmount() async throws {
        let calendar = actionCalendar()
        let timeZoneIdentifier = calendar.timeZone.identifier
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 15,
            hour: 18,
            calendar: calendar
        )
        let startDate = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 4,
            calendar: calendar
        )
        let confirmedNextRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 20,
            calendar: calendar
        )
        let existingChangeID = UUID(
            uuidString: "A4000000-0000-0000-0000-000000000048"
        )!
        let id = UUID(
            uuidString: "A4000000-0000-0000-0000-000000000049"
        )!
        let existing = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "manual:\(id)"),
            serviceName: "Original Service",
            plan: "Original Plan",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: startDate,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            startDate: startDate,
            confirmedNextRenewal: confirmedNextRenewal,
            managementURL: nil,
            notes: "Original notes",
            priceChanges: [
                PriceChange(
                    id: existingChangeID,
                    effectiveDate: try actionDate(
                        year: 2026,
                        month: 8,
                        day: 1,
                        hour: 2,
                        calendar: calendar
                    ),
                    amount: Money(minorUnits: 1_299, currency: .usd)
                ),
            ]
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let preset = catalogPresetFixture(
            offers: [
                catalogOfferFixture(
                    id: "edited-monthly",
                    status: .verified,
                    price: Money(minorUnits: 6_800, currency: .cny)
                ),
            ],
            id: "edited.example",
            serviceName: CatalogLocalizedText(
                en: "Edited Service",
                zhHans: "Edited Service"
            )
        )
        let rateSnapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(presets: [preset]),
            exchangeRateCache: InMemoryExchangeRateCache(
                state: ExchangeRateCacheState(
                    snapshot: rateSnapshot,
                    lastAttemptAt: now
                )
            ),
            syncMonitor: SyncMonitorFixture(result: .current),
            now: { now },
            calendar: calendar
        )

        workspace.loadCatalog(locale: Locale(identifier: "en"))
        await workspace.refreshSyncStatus()
        await workspace.refreshExchangeRates()
        workspace.loadLibrary()
        workspace.loadSubscription(id: id)
        let horizon = try actionDate(
            year: 2026,
            month: 10,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        workspace.loadExpectedCharges(
            subscriptionID: id,
            through: horizon,
            maximumCount: 2
        )
        workspace.loadUpcomingTimeline(from: now, through: horizon)
        workspace.loadCalendarProjection(locale: Locale(identifier: "en"))
        workspace.loadInsights(mode: .expected, from: now, through: horizon)

        let inputStartDate = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 6,
            calendar: calendar
        )
        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: "Edited Service",
                plan: "Edited Plan",
                category: "Edited Category",
                amount: Money(minorUnits: 6_800, currency: .cny),
                billingSchedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: inputStartDate,
                    timeZoneIdentifier: timeZoneIdentifier
                ),
                startDate: inputStartDate,
                confirmedNextRenewal: confirmedNextRenewal,
                managementURL: nil,
                notes: "Edited notes"
            )
        )

        let stored = try #require(repository.storedSubscription(id: id))
        let normalizedRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let normalizedStart = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        #expect(stored.id == id)
        #expect(stored.originalAmount == Money(minorUnits: 999, currency: .usd))
        #expect(stored.serviceName == "Edited Service")
        #expect(stored.serviceIdentity.rawValue == "catalog:edited.example")
        #expect(stored.confirmedNextRenewal == normalizedRenewal)
        #expect(stored.startDate == normalizedStart)
        #expect(stored.billingSchedule.renewalAnchor == normalizedStart)
        #expect(stored.priceChanges.count == 1)
        #expect(stored.priceChanges[0].id == existingChangeID)
        #expect(stored.priceChanges[0].effectiveDate == normalizedRenewal)
        #expect(
            stored.priceChanges[0].amount
                == Money(minorUnits: 6_800, currency: .cny)
        )
        #expect(repository.updateAttemptCount == 1)

        guard case .loaded(.current, let summaries) = workspace.libraryState,
              let summary = summaries.first
        else {
            Issue.record("Expected the edited subscription in the library.")
            return
        }
        #expect(summary.amount == Money(minorUnits: 6_800, currency: .cny))
        #expect(workspace.expectedCharges?.first?.amount == summary.amount)
        #expect(workspace.upcomingTimeline.first?.amount == summary.amount)
        #expect(
            workspace.insightsState.availableValue?.items.first?.originalAmount
                == summary.amount
        )
        #expect(workspace.calendarProjection.first?.startDate == normalizedRenewal)
        #expect(workspace.makeWidgetSnapshot()?.nextRenewal?.serviceName == "Edited Service")
        #expect(workspace.syncStatus == .synchronizing)
    }

    @Test("A failed ordinary edit does not partially record price history")
    @MainActor
    func editFailureDoesNotPartiallyRecordPrice() async throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 15,
            hour: 18,
            calendar: calendar
        )
        let startDate = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let renewal = try actionDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let id = UUID(
            uuidString: "A5000000-0000-0000-0000-000000000049"
        )!
        let existing = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "manual:\(id)"),
            serviceName: "Failure Service",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: startDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            startDate: startDate,
            confirmedNextRenewal: renewal,
            managementURL: nil,
            notes: "Before",
            priceChanges: [
                PriceChange(
                    id: UUID(
                        uuidString: "A5000000-0000-0000-0000-000000000048"
                    )!,
                    effectiveDate: renewal,
                    amount: Money(minorUnits: 1_299, currency: .usd)
                ),
            ]
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        repository.failure = .update
        let rateSnapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            exchangeRateCache: InMemoryExchangeRateCache(
                state: ExchangeRateCacheState(
                    snapshot: rateSnapshot,
                    lastAttemptAt: now
                )
            ),
            syncMonitor: SyncMonitorFixture(result: .current),
            now: { now },
            calendar: calendar
        )

        await workspace.refreshSyncStatus()
        await workspace.refreshExchangeRates()
        let horizon = try actionDate(
            year: 2026,
            month: 10,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        workspace.loadLibrary()
        workspace.loadSubscription(id: id)
        workspace.loadExpectedCharges(
            subscriptionID: id,
            through: horizon,
            maximumCount: 2
        )
        workspace.loadUpcomingTimeline(from: now, through: horizon)
        workspace.loadCalendarProjection(locale: Locale(identifier: "en"))
        workspace.loadInsights(mode: .expected, from: now, through: horizon)

        let libraryBefore = workspace.libraryState
        let expectedBefore = workspace.expectedCharges
        let upcomingBefore = workspace.upcomingTimeline
        let calendarBefore = workspace.calendarProjection
        let insightsBefore = workspace.insightsState
        let widgetBefore = workspace.makeWidgetSnapshot()
        let syncBefore = workspace.syncStatus
        let historyBefore = workspace.paymentHistory

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: "Edited Failure Service",
                plan: "Changed",
                category: "Changed",
                amount: Money(minorUnits: 6_800, currency: .cny),
                billingSchedule: existing.billingSchedule,
                startDate: existing.startDate,
                confirmedNextRenewal: existing.confirmedNextRenewal,
                managementURL: nil,
                notes: "After"
            )
        )

        #expect(repository.updateAttemptCount == 1)
        #expect(repository.storedSubscription(id: id) == existing)
        #expect(workspace.libraryState == libraryBefore)
        #expect(workspace.expectedCharges == expectedBefore)
        #expect(workspace.upcomingTimeline == upcomingBefore)
        #expect(workspace.calendarProjection == calendarBefore)
        #expect(workspace.insightsState == insightsBefore)
        #expect(workspace.makeWidgetSnapshot() == widgetBefore)
        #expect(workspace.syncStatus == syncBefore)
        #expect(workspace.paymentHistory == historyBefore)
        #expect(workspace.detailState == .failed)
    }

    @Test("Active edit validates the supplied renewal day and normalizes derived dates")
    @MainActor
    func activeEditValidatesRenewalDayAndNormalizesDerivedDates() throws {
        let calendar = actionCalendar()
        let now = try actionDate(
            year: 2026,
            month: 7,
            day: 15,
            hour: 18,
            calendar: calendar
        )
        let startDate = try actionDate(
            year: 2026,
            month: 6,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let renewal = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let id = UUID(
            uuidString: "A6000000-0000-0000-0000-000000000049"
        )!
        let existing = makeSubscription(
            id: id,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: startDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            confirmedNextRenewal: renewal
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )
        let amount = existing.amount(onBillingDay: existing.confirmedNextRenewal)

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: existing.plan,
                category: existing.category,
                amount: amount,
                billingSchedule: existing.billingSchedule,
                startDate: startDate,
                confirmedNextRenewal: try actionDate(
                    year: 2026,
                    month: 9,
                    day: 2,
                    hour: 12,
                    calendar: calendar
                ),
                managementURL: nil,
                notes: existing.notes
            )
        )
        #expect(repository.updateAttemptCount == 0)
        #expect(repository.storedSubscription(id: id) == existing)
        #expect(
            workspace.editingValidationErrors[.confirmedNextRenewal]
                == .required
        )

        let selectedRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 21,
            calendar: calendar
        )
        let selectedStart = try #require(
            BillingDateResolver().previousCycleStart(
                before: selectedRenewal,
                interval: .monthly,
                timeZone: calendar.timeZone
            )
        )
        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: existing.plan,
                category: existing.category,
                amount: amount,
                billingSchedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: selectedStart,
                    timeZoneIdentifier: calendar.timeZone.identifier
                ),
                startDate: selectedStart,
                confirmedNextRenewal: selectedRenewal,
                managementURL: nil,
                notes: existing.notes
            )
        )

        let stored = try #require(repository.storedSubscription(id: id))
        let expectedStart = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let expectedRenewal = try actionDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        #expect(repository.updateAttemptCount == 1)
        #expect(stored.startDate == expectedStart)
        #expect(stored.billingSchedule.renewalAnchor == expectedStart)
        #expect(stored.confirmedNextRenewal == expectedRenewal)
    }

    @Test("An ordinary edit rejects a non-positive amount without updating")
    @MainActor
    func editRejectsInvalidAmountWithoutUpdating() throws {
        let calendar = utcCalendar()
        let subscription = makeSubscription(
            id: UUID(uuidString: "A7000000-0000-0000-0000-000000000049")!,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: Date(timeIntervalSince1970: 1_767_225_600),
                timeZoneIdentifier: "UTC"
            )
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            calendar: calendar
        )

        workspace.editSubscription(
            id: subscription.id,
            input: SubscriptionEditInput(
                serviceName: subscription.serviceName,
                plan: subscription.plan,
                category: subscription.category,
                amount: Money(minorUnits: 0, currency: .usd),
                billingSchedule: subscription.billingSchedule,
                startDate: subscription.startDate,
                confirmedNextRenewal: subscription.confirmedNextRenewal,
                managementURL: subscription.managementURL,
                notes: subscription.notes
            )
        )

        #expect(repository.updateAttemptCount == 0)
        #expect(repository.storedSubscription(id: subscription.id) == subscription)
        #expect(workspace.editingValidationErrors[.originalAmount] == .mustBePositive)
    }

    @Test("An unchanged amount preserves the complete price history")
    @MainActor
    func editUnchangedAmountPreservesPriceHistory() throws {
        let calendar = utcCalendar()
        let id = UUID(
            uuidString: "A8000000-0000-0000-0000-000000000049"
        )!
        let renewal = try actionDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let first = PriceChange(
            id: UUID(uuidString: "A8000000-0000-0000-0000-000000000048")!,
            effectiveDate: try actionDate(
                year: 2026,
                month: 7,
                day: 1,
                hour: 12,
                calendar: calendar
            ),
            amount: Money(minorUnits: 1_099, currency: .usd)
        )
        let second = PriceChange(
            id: UUID(uuidString: "A8000000-0000-0000-0000-000000000047")!,
            effectiveDate: renewal,
            amount: Money(minorUnits: 1_299, currency: .usd)
        )
        let existing = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "manual:\(id)"),
            serviceName: "History Service",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: try actionDate(
                    year: 2026,
                    month: 7,
                    day: 1,
                    hour: 12,
                    calendar: calendar
                ),
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            startDate: try actionDate(
                year: 2026,
                month: 7,
                day: 1,
                hour: 12,
                calendar: calendar
            ),
            confirmedNextRenewal: renewal,
            managementURL: nil,
            notes: "Before",
            priceChanges: [first, second]
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: {
                try! actionDate(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12,
                    calendar: calendar
                )
            },
            calendar: calendar
        )
        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: "History Service",
                plan: "Changed Metadata",
                category: "Other",
                amount: Money(minorUnits: 1_299, currency: .usd),
                billingSchedule: existing.billingSchedule,
                startDate: existing.startDate,
                confirmedNextRenewal: existing.confirmedNextRenewal,
                managementURL: nil,
                notes: "After"
            )
        )

        let stored = try #require(repository.storedSubscription(id: id))
        #expect(stored.priceChanges == [first, second])
        #expect(stored.originalAmount == existing.originalAmount)
        #expect(stored.plan == "Changed Metadata")
        #expect(repository.updateAttemptCount == 1)
    }

    @Test("Editing an amount replaces the deterministic same-day winner")
    @MainActor
    func editReplacesDeterministicSameDayPriceChangeWinner() throws {
        let calendar = utcCalendar()
        let id = UUID(
            uuidString: "A9000000-0000-0000-0000-000000000049"
        )!
        let startDate = try actionDate(
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let renewal = try actionDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 12,
            calendar: calendar
        )
        let lowerID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let higherID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        )!
        let lower = PriceChange(
            id: lowerID,
            effectiveDate: try actionDate(
                year: 2026,
                month: 8,
                day: 1,
                hour: 2,
                calendar: calendar
            ),
            amount: Money(minorUnits: 1_100, currency: .usd)
        )
        let higher = PriceChange(
            id: higherID,
            effectiveDate: try actionDate(
                year: 2026,
                month: 8,
                day: 1,
                hour: 22,
                calendar: calendar
            ),
            amount: Money(minorUnits: 1_200, currency: .usd)
        )
        let importedHistory = PriceChange(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000003"
            )!,
            effectiveDate: try actionDate(
                year: 2026,
                month: 7,
                day: 10,
                hour: 12,
                calendar: calendar
            ),
            amount: Money(minorUnits: 1_050, currency: .usd)
        )
        let existing = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "manual:\(id)"),
            serviceName: "Imported History Service",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: startDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            startDate: startDate,
            confirmedNextRenewal: renewal,
            managementURL: nil,
            notes: "Before",
            priceChanges: [lower, higher, importedHistory]
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: {
                try! actionDate(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12,
                    calendar: calendar
                )
            },
            calendar: calendar
        )
        let editedAmount = Money(minorUnits: 1_500, currency: .usd)

        workspace.editSubscription(
            id: id,
            input: SubscriptionEditInput(
                serviceName: existing.serviceName,
                plan: existing.plan,
                category: existing.category,
                amount: editedAmount,
                billingSchedule: existing.billingSchedule,
                startDate: startDate,
                confirmedNextRenewal: renewal,
                managementURL: nil,
                notes: "After"
            )
        )

        let stored = try #require(repository.storedSubscription(id: id))
        let expectedWinner = PriceChange(
            id: higherID,
            effectiveDate: renewal,
            amount: editedAmount
        )
        #expect(stored.priceChanges[0] == lower)
        #expect(stored.priceChanges[1] == expectedWinner)
        #expect(stored.priceChanges[2] == importedHistory)
        #expect(stored.amount(onBillingDay: renewal) == editedAmount)
    }

    @Test("Price changes refresh every loaded amount consumer")
    @MainActor
    func priceChangesRefreshLoadedConsumers() async throws {
        let calendar = utcCalendar()
        let now = try actionDate(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            calendar: calendar
        )
        let start = try actionDate(
            year: 2025,
            month: 12,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let renewal = try actionDate(
            year: 2026,
            month: 2,
            day: 10,
            hour: 12,
            calendar: calendar
        )
        let effectiveDate = try actionDate(
            year: 2026,
            month: 1,
            day: 16,
            hour: 12,
            calendar: calendar
        )
        let through = try actionDate(
            year: 2026,
            month: 3,
            day: 31,
            hour: 12,
            calendar: calendar
        )
        let originalAmount = Money(minorUnits: 999, currency: .usd)
        let changedAmount = Money(minorUnits: 1_999, currency: .usd)
        let id = UUID(
            uuidString: "A3000000-0000-0000-0000-000000000048"
        )!
        let existing = makeSubscription(
            id: id,
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: start,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            confirmedNextRenewal: renewal,
            originalAmount: originalAmount,
            serviceName: "Amount Consumer"
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [existing]
        )
        let catalogPreset = catalogPresetFixture(
            offers: [
                catalogOfferFixture(
                    id: "amount-consumer",
                    status: .verified,
                    price: changedAmount
                ),
            ],
            id: "amount-consumer",
            serviceName: CatalogLocalizedText(
                en: "Amount Consumer",
                zhHans: "Amount Consumer"
            )
        )
        let rateSnapshot = ExchangeRateSnapshot(
            base: .eur,
            providerDate: now,
            fetchedAt: now,
            source: "fixture",
            rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(
                presets: [catalogPreset]
            ),
            exchangeRateCache: InMemoryExchangeRateCache(
                state: ExchangeRateCacheState(
                    snapshot: rateSnapshot,
                    lastAttemptAt: now
                )
            ),
            now: { now },
            calendar: calendar
        )

        await workspace.refreshExchangeRates()
        workspace.loadExpectedCharges(
            subscriptionID: id,
            through: through,
            maximumCount: 1
        )
        workspace.loadUpcomingTimeline(from: now, through: through)
        workspace.loadCalendarProjection(locale: Locale(identifier: "en_US"))
        workspace.loadInsights(
            mode: .expected,
            from: now,
            through: through
        )
        workspace.loadLibrary()
        guard case .loaded(.current, let summaries) = workspace.libraryState,
              let summary = summaries.first
        else {
            Issue.record("Expected the current library summary to load.")
            return
        }
        #expect(summary.amount == originalAmount)
        #expect(summary.originalAmount == originalAmount)
        #expect(
            SubscriptionTableQuery(sort: .amount).apply(to: summaries)
                .first?.amount == originalAmount
        )
        #expect(workspace.expectedCharges?.first?.amount == originalAmount)
        #expect(workspace.upcomingTimeline.first?.amount == originalAmount)
        #expect(
            workspace.insightsState.availableValue?
                .items.first?.originalAmount == originalAmount
        )

        workspace.recordPriceChange(
            id: id,
            effectiveDate: effectiveDate,
            amount: changedAmount
        )

        guard case .loaded(.current, let refreshedSummaries) = workspace.libraryState,
              let refreshedSummary = refreshedSummaries.first
        else {
            Issue.record("Expected the refreshed current library summary.")
            return
        }
        #expect(refreshedSummary.amount == changedAmount)
        #expect(refreshedSummary.originalAmount == originalAmount)
        #expect(
            SubscriptionTableQuery(sort: .amount).apply(to: refreshedSummaries)
                .first?.amount == changedAmount
        )
        #expect(repository.storedSubscription(id: id)?.originalAmount == originalAmount)

        let catalogSummary = workspace.reconcileCatalogAssociations(
            locale: Locale(identifier: "en")
        )
        #expect(catalogSummary.normalizedIDs == [id])
        #expect(
            repository.storedSubscription(id: id)?.amount(
                onBillingDay: renewal
            ) == changedAmount
        )

        #expect(workspace.expectedCharges?.first?.amount == changedAmount)
        #expect(workspace.upcomingTimeline.first?.amount == changedAmount)
        #expect(
            workspace.calendarProjection.first?.title.contains("19.99")
                == true
        )
        #expect(
            workspace.insightsState.availableValue?
                .items.first?.originalAmount == changedAmount
        )
        #expect(
            workspace.makeWidgetSnapshot()?.nextRenewal?
                .amountDescription?.contains("19.99") == true
        )
    }

    @Test("Reconciliation reports ambiguity and partial persistence failure")
    @MainActor
    func reconciliationReportsAmbiguityAndFailure() throws {
        let ambiguousID = UUID(
            uuidString: "B0000000-0000-0000-0000-000000000047"
        )!
        let failedID = UUID(
            uuidString: "B0000000-0000-0000-0000-000000000048"
        )!
        let successfulID = UUID(
            uuidString: "B0000000-0000-0000-0000-000000000049"
        )!
        let ambiguous = makeSubscription(
            id: ambiguousID,
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "Shared Alias"
        )
        let failed = makeSubscription(
            id: failedID,
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "ChatGPT Plus"
        )
        let successful = makeSubscription(
            id: successfulID,
            originalAmount: Money(minorUnits: 2_000, currency: .usd),
            serviceName: "ChatGPT Plus"
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [ambiguous, failed, successful]
        )
        repository.failingUpdateIDs = [failedID]
        let offer = catalogOfferFixture(id: "plus", status: .verified)
        let chatGPT = catalogPresetFixture(
            offers: [offer],
            id: "chatgpt",
            serviceName: CatalogLocalizedText(
                en: "ChatGPT",
                zhHans: "ChatGPT"
            ),
            matchAliases: ["ChatGPT Plus", "Shared Alias"]
        )
        let competing = catalogPresetFixture(
            offers: [
                CatalogOffer(
                    id: "shared",
                    planName: offer.planName,
                    price: offer.price,
                    billingInterval: offer.billingInterval,
                    market: offer.market,
                    purchaseChannel: offer.purchaseChannel,
                    sourceURL: offer.sourceURL,
                    verifiedOn: offer.verifiedOn,
                    reviewStatus: .verified
                ),
            ],
            id: "competing",
            serviceName: CatalogLocalizedText(
                en: "Competing",
                zhHans: "竞争者"
            ),
            matchAliases: ["Shared Alias"]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            catalogRepository: StaticCatalogRepository(
                presets: [chatGPT, competing]
            )
        )
        workspace.loadCatalog(locale: Locale(identifier: "en"))

        let summary = workspace.reconcileCatalogAssociations(
            locale: Locale(identifier: "en")
        )

        #expect(summary.normalizedIDs == [successfulID])
        #expect(summary.unchangedIDs.isEmpty)
        #expect(summary.ambiguousIDs == [ambiguousID])
        #expect(summary.failedIDs == [failedID])
        #expect(summary.commandError == .persistenceFailed)
        #expect(
            repository.storedSubscription(id: failedID) == failed
        )
        #expect(
            repository.storedSubscription(id: successfulID)?
                .serviceIdentity.rawValue == "catalog:chatgpt"
        )
    }

    @Test("Reconciliation distinguishes unavailable catalog and storage")
    @MainActor
    func reconciliationReportsCommandLevelFailures() {
        let unavailableCatalogWorkspace = SubscriptionWorkspace(
            repository: InMemorySubscriptionRepository()
        )

        let catalogSummary =
            unavailableCatalogWorkspace.reconcileCatalogAssociations(
                locale: Locale(identifier: "en")
            )

        #expect(catalogSummary.commandError == .catalogUnavailable)
        #expect(
            unavailableCatalogWorkspace.catalogReconciliationError
                == .catalogUnavailable
        )

        let failingRepository = InMemorySubscriptionRepository()
        failingRepository.failure = .list
        let storageWorkspace = SubscriptionWorkspace(
            repository: failingRepository,
            catalogRepository: StaticCatalogRepository(
                presets: [
                    catalogPresetFixture(
                        offers: [
                            catalogOfferFixture(
                                id: "plus",
                                status: .verified
                            ),
                        ]
                    ),
                ]
            )
        )

        let storageSummary = storageWorkspace
            .reconcileCatalogAssociations(
                locale: Locale(identifier: "en")
            )

        #expect(storageSummary.commandError == .persistenceFailed)
        #expect(
            storageWorkspace.catalogReconciliationError
                == .persistenceFailed
        )
    }
}

private func catalogPresetFixture(
    offers: [CatalogOffer],
    id: String = "provider.example",
    serviceName: CatalogLocalizedText = CatalogLocalizedText(
        en: "Provider",
        zhHans: "服务商"
    ),
    matchAliases: [String] = []
) -> CatalogPreset {
    CatalogPreset(
        id: id,
        serviceName: serviceName,
        category: CatalogLocalizedText(
            en: "Productivity",
            zhHans: "效率"
        ),
        suggestedInterval: .monthly,
        managementURL: URL(string: "https://example.com/account"),
        icon: .productivity,
        matchAliases: matchAliases,
        offers: offers
    )
}

private func catalogOfferFixture(
    id: String,
    status: CatalogOfferReviewStatus,
    price: Money = Money(minorUnits: 2_000, currency: .usd)
) -> CatalogOffer {
    CatalogOffer(
        id: id,
        planName: CatalogLocalizedText(en: "Plus", zhHans: "Plus"),
        price: price,
        billingInterval: .monthly,
        market: "US",
        purchaseChannel: .web,
        sourceURL: URL(string: "https://example.com/pricing")!,
        verifiedOn: "2026-07-30",
        reviewStatus: status
    )
}

private func catalogOfferInputFixture(
    offerID: String
) -> CatalogOfferSubscriptionInput {
    let start = Date(timeIntervalSince1970: 1_767_225_600)
    return CatalogOfferSubscriptionInput(
        offerID: offerID,
        actualChargeOverride: nil,
        startDate: start,
        renewalAnchor: start,
        confirmedNextRenewal: start.addingTimeInterval(86_400),
        billingTimeZoneIdentifier: "UTC",
        notes: "",
        initialStatus: .active
    )
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

@MainActor
private final class CalendarReconcilerFixture: CalendarProjectionReconciler {
    let result: CalendarReconciliationResult
    private(set) var commands: [CalendarReconciliationCommand] = []

    init(result: CalendarReconciliationResult) {
        self.result = result
    }

    func perform(
        _ command: CalendarReconciliationCommand
    ) async -> CalendarReconciliationResult {
        commands.append(command)
        return result
    }
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
            year: 2026, month: 7, day: 29, hour: 10, calendar: calendar
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
            confirmedNextRenewal: scheduledDate,
            managementURL: nil,
            notes: ""
        )
        let repository = InMemorySubscriptionRepository(
            subscriptions: [subscription]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository, now: { now }, calendar: calendar
        )

        workspace.loadExpectedCharges(
            subscriptionID: subscription.id,
            through: nextRenewal,
            maximumCount: 1
        )
        #expect(
            workspace.expectedCharges?.first?.scheduledDate == scheduledDate
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
        #expect(
            workspace.expectedCharges?.first?.scheduledDate == nextRenewal
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
    var failingUpdateIDs: Set<UUID> = []
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
        if failure == .update || failingUpdateIDs.contains(subscription.id) {
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
    pinnedAt: Date? = nil,
    serviceIdentity: ServiceIdentity? = nil,
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
        serviceIdentity: serviceIdentity
            ?? ServiceIdentity(rawValue: "manual:\(id.uuidString)"),
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
        isArchived: isArchived,
        pinnedAt: pinnedAt
    )
}

private func replacingConfirmedNextRenewal(
    in subscription: Subscription,
    with confirmedNextRenewal: Date
) -> Subscription {
    Subscription(
        id: subscription.id,
        serviceIdentity: subscription.serviceIdentity,
        serviceName: subscription.serviceName,
        plan: subscription.plan,
        category: subscription.category,
        originalAmount: subscription.originalAmount,
        billingSchedule: subscription.billingSchedule,
        startDate: subscription.startDate,
        confirmedNextRenewal: confirmedNextRenewal,
        managementURL: subscription.managementURL,
        notes: subscription.notes,
        confirmedCharges: subscription.confirmedCharges,
        priceChanges: subscription.priceChanges,
        lifecycle: subscription.lifecycle,
        isArchived: subscription.isArchived,
        pinnedAt: subscription.pinnedAt
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
