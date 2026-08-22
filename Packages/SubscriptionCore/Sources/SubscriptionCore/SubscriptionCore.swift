import Foundation
import Observation

@MainActor
@Observable
public final class SubscriptionWorkspace {
    public internal(set) var libraryState: SubscriptionLibraryState =
        .loading(.current)
    public internal(set) var detailState: SubscriptionDetailState = .notLoaded
    public internal(set) var creationValidationErrors:
        [SubscriptionCreationField: SubscriptionCreationValidationError] = [:]
    public internal(set) var editingValidationErrors:
        [SubscriptionCreationField: SubscriptionCreationValidationError] = [:]
    public internal(set) var expectedCharges: [ExpectedCharge]?
    public internal(set) var upcomingTimeline: [UpcomingTimelineItem] = []
    public internal(set) var upcomingTimelineState: UpcomingTimelineState =
        .notLoaded
    public internal(set) var calendarProjection: [CalendarProjectionEvent] = []
    public internal(set) var calendarImportState: CalendarImportState =
        .notRequested
    public internal(set) var calendarReconciliationState:
        CalendarReconciliationState = .notConfigured
    public internal(set) var lifecycleActionError:
        SubscriptionLifecycleActionError?
    public internal(set) var paymentHistoryActionError:
        PaymentHistoryActionError?
    public internal(set) var paymentHistory: [SubscriptionHistoryEntry] = []
    public internal(set) var catalogState: CatalogState = .notLoaded
    public internal(set) var catalogDiagnostics: CatalogDiagnostics?
    public internal(set) var catalogReconciliationError:
        CatalogAssociationReconciliationError? = nil
    public internal(set) var setupState: SetupState = .notLoaded
    public internal(set) var setupRevision: UInt64 = 0
    public internal(set) var exchangeRateStatus: ExchangeRateStatus = .notLoaded
    public internal(set) var insightsState: SpendingInsightsState = .notLoaded
    public internal(set) var syncStatus: LibrarySyncStatus = .notLoaded

    let repository: any SubscriptionRepository
    let preferencesRepository: (any UserPreferencesRepository)?
    let portableBackupImportRepository:
        (any PortableBackupImportRepository)?
    let widgetSnapshotPublisher: (any WidgetSnapshotPublishing)?
    let catalogRepository: (any CatalogRepository)?
    let catalogUpdateSource: (any CatalogUpdateSource)?
    let catalogCache: (any CatalogCache)?
    let exchangeRateSource: (any ExchangeRateSource)?
    let exchangeRateCache: (any ExchangeRateCache)?
    let syncMonitor: (any LibrarySyncMonitor)?
    let calendarProjectionImporter: (any CalendarProjectionImporter)?
    let calendarProjectionReconciler:
        (any CalendarProjectionReconciler)?
    let identifierGenerator: () -> UUID
    let now: () -> Date
    let calendar: Calendar
    enum SetupPreferencesLoadResult {
        case unknown
        case missing
        case stored
        case failed
    }
    var setupPreferencesLoadResult: SetupPreferencesLoadResult =
        .unknown
    enum CalendarReconciliationRequest {
        case reconcile(Locale)
        case rebuild(Locale)
        case disable

        var priority: Int {
            switch self {
            case .reconcile:
                1
            case .rebuild:
                2
            case .disable:
                3
            }
        }
    }
    var expectedChargesRequest: ExpectedChargesRequest?
    var insightsRequest: InsightsRequest?
    var upcomingTimelineRequest: UpcomingTimelineRequest?
    var calendarProjectionLocale: Locale?
    var pendingCalendarReconciliationRequest:
        CalendarReconciliationRequest?
    var catalogSnapshot: CatalogSnapshot?
    var catalogRefreshGeneration: UInt64 = 0
    var catalogLocale = Locale.current
    var catalogSearchQuery = ""
    var catalogCategoryID: String?
    struct ExchangeRateAttemptKey: Hashable {
        let day: Date
        let quotes: Set<Currency>
    }
    enum ExchangeRateRefreshError: Error {
        case incompleteSnapshot
    }
    var exchangeRateRefreshGeneration: UInt64 = 0
    var exchangeRateAttempts: Set<ExchangeRateAttemptKey> = []

    public init(
        repository: any SubscriptionRepository,
        preferencesRepository: (any UserPreferencesRepository)? = nil,
        portableBackupImportRepository:
            (any PortableBackupImportRepository)? = nil,
        widgetSnapshotPublisher: (any WidgetSnapshotPublishing)? = nil,
        catalogRepository: (any CatalogRepository)? = nil,
        catalogUpdateSource: (any CatalogUpdateSource)? = nil,
        catalogCache: (any CatalogCache)? = nil,
        exchangeRateSource: (any ExchangeRateSource)? = nil,
        exchangeRateCache: (any ExchangeRateCache)? = nil,
        syncMonitor: (any LibrarySyncMonitor)? = nil,
        calendarProjectionImporter: (any CalendarProjectionImporter)? = nil,
        calendarProjectionReconciler:
            (any CalendarProjectionReconciler)? = nil,
        identifierGenerator: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar? = nil
    ) {
        self.repository = repository
        self.preferencesRepository = preferencesRepository
        self.portableBackupImportRepository = portableBackupImportRepository
        self.widgetSnapshotPublisher = widgetSnapshotPublisher
        self.catalogRepository = catalogRepository
        self.catalogUpdateSource = catalogUpdateSource
        self.catalogCache = catalogCache
        self.exchangeRateSource = exchangeRateSource
        self.exchangeRateCache = exchangeRateCache
        self.syncMonitor = syncMonitor
        self.calendarProjectionImporter = calendarProjectionImporter
        self.calendarProjectionReconciler = calendarProjectionReconciler
        self.identifierGenerator = identifierGenerator
        self.now = now
        self.calendar = calendar ?? Self.defaultRenewalCalendar()
    }

    public func refreshSyncStatus() async {
        syncStatus = await syncMonitor?.refreshStatus() ?? .localOnly
    }

    func markLocalChangesForSync() {
        switch syncStatus {
        case .current, .synchronizing:
            syncStatus = .synchronizing
        case .notLoaded, .localOnly, .signedOut, .requiresAttention:
            break
        }
        Task { [weak self] in
            await self?.reconcileCalendarProjection(locale: .current)
        }
    }

    public func loadSetup(libraryIsEmpty: Bool) {
        loadSetup(
            libraryIsEmptyWhenPreferencesAreMissing: libraryIsEmpty
        )
    }

    func loadSetup(
        libraryIsEmptyWhenPreferencesAreMissing: Bool?
    ) {
        let fallback = UserPreferences.default
        for attempt in 0..<2 {
            do {
                let storedPreferences = try preferencesRepository?.loadPreferences()
                guard let preferences = storedPreferences else {
                    setupPreferencesLoadResult = .missing
                    guard let libraryIsEmptyWhenPreferencesAreMissing else {
                        setupState = .loadFailed
                        return
                    }
                    setupState = libraryIsEmptyWhenPreferencesAreMissing
                        ? .needsSetup(fallback)
                        : .completed(fallback)
                    return
                }
                setupPreferencesLoadResult = .stored
                switch preferences.setupStatus {
                case .notCompleted:
                    setupState = .needsSetup(preferences)
                case .completed:
                    setupState = .completed(preferences)
                case .skipped:
                    setupState = .skipped(preferences)
                }
                return
            } catch {
                if attempt == 1 {
                    setupPreferencesLoadResult = .failed
                    setupState = .loadFailed
                }
            }
        }
    }

    func markSetupLoadFailed() {
        setupState = .loadFailed
    }

    public func updatePreferences(
        primaryCurrency: Currency,
        calendarProjectionHorizon: CalendarProjectionHorizon,
        hideAmountsInCalendar: Bool? = nil,
        menuBarModeEnabled: Bool? = nil,
        appearanceMode: AppearanceMode? = nil
    ) {
        let previousPreferences = currentPreferences
        let retainsExistingLibraryConfigurationFailure: Bool
        if case .configurationSaveFailed = setupState {
            retainsExistingLibraryConfigurationFailure = true
        } else {
            retainsExistingLibraryConfigurationFailure = false
        }
        persistPreferences(
            UserPreferences(
                primaryCurrency: primaryCurrency,
                calendarProjectionHorizon: calendarProjectionHorizon,
                hideAmountsInCalendar: hideAmountsInCalendar
                    ?? currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: menuBarModeEnabled
                    ?? currentPreferences.menuBarModeEnabled,
                appearanceMode: appearanceMode
                    ?? currentPreferences.appearanceMode,
                setupStatus: currentPreferences.setupStatus
            ),
            stateOnFailure: { _ in
                retainsExistingLibraryConfigurationFailure
                    ? .configurationSaveFailed(previousPreferences)
                    : .failed(previousPreferences)
            }
        )
        reloadInsightsIfNeeded()
    }

    public func completeSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .completed
            )
        )
    }

    /// Marks setup complete when existing subscriptions prove this is not a
    /// first-run library. A failed persistence attempt remains observable,
    /// but must not send that existing library through onboarding.
    func completeExistingLibrarySetup() {
        guard case .missing = setupPreferencesLoadResult else { return }
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .completed
            ),
            stateOnFailure: { .configurationSaveFailed($0) }
        )
    }

    public func skipSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .skipped
            )
        )
    }

    public func resumeSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .notCompleted
            ),
            stateOnSuccess: { .needsSetup($0) }
        )
    }

    var currentPreferences: UserPreferences {
        switch setupState {
        case .notLoaded, .loadFailed:
            .default
        case .needsSetup(let preferences),
             .completed(let preferences),
             .skipped(let preferences),
             .failed(let preferences),
             .configurationSaveFailed(let preferences):
            preferences
        }
    }

    func persistPreferences(
        _ preferences: UserPreferences,
        stateOnSuccess: ((UserPreferences) -> SetupState)? = nil,
        stateOnFailure: ((UserPreferences) -> SetupState)? = nil
    ) {
        if preferencesRepository != nil {
            switch setupState {
            case .notLoaded, .loadFailed:
                return
            case .needsSetup,
                 .completed,
                 .skipped,
                 .failed,
                 .configurationSaveFailed:
                break
            }
        }
        do {
            try preferencesRepository?.savePreferences(preferences)
            if preferencesRepository != nil {
                markLocalChangesForSync()
                setupPreferencesLoadResult = .stored
            }
            setupState = stateOnSuccess?(preferences)
                ?? setupState(for: preferences)
            setupRevision &+= 1
        } catch {
            setupState = stateOnFailure?(preferences)
                ?? .failed(currentPreferences)
        }
    }

    func setupState(for preferences: UserPreferences) -> SetupState {
        switch preferences.setupStatus {
        case .notCompleted:
            .needsSetup(preferences)
        case .completed:
            .completed(preferences)
        case .skipped:
            .skipped(preferences)
        }
    }

    nonisolated static func defaultRenewalCalendar() -> Calendar {
        BillingCalendar.calendar(timeZone: .autoupdatingCurrent)
    }

    public func refreshExchangeRates() async {
        exchangeRateRefreshGeneration &+= 1
        let refreshGeneration = exchangeRateRefreshGeneration
        let cachedState = try? exchangeRateCache?.loadState()
        guard let subscriptions = try? repository.listSubscriptions() else {
            exchangeRateStatus = .unavailable
            return
        }
        let requiredCurrencies = Set(
            subscriptions.flatMap { subscription in
                [subscription.originalAmount.currency]
                    + subscription.priceChanges.map(\.amount.currency)
                    + subscription.confirmedCharges.map(\.amount.currency)
            }
        )
            .union([currentPreferences.primaryCurrency])
        let requiredQuotes = requiredCurrencies.subtracting([.eur])
        let cacheIsComplete = cachedState?.snapshot.map {
            snapshotContainsRequiredCurrencies(
                $0,
                requiredCurrencies: requiredCurrencies
            )
        } ?? false
        if let cachedState,
           cacheIsComplete,
           calendar.isDate(
               cachedState.lastAttemptAt
                   ?? cachedState.snapshot?.fetchedAt
                   ?? .distantPast,
               inSameDayAs: now()
           )
        {
            exchangeRateStatus = cachedState.snapshot.map { snapshot in
                calendar.isDate(snapshot.fetchedAt, inSameDayAs: now())
                    ? .fresh(snapshot)
                    : .stale(snapshot)
            } ?? .unavailable
            return
        }

        let attemptKey = ExchangeRateAttemptKey(
            day: calendar.startOfDay(for: now()),
            quotes: requiredQuotes
        )
        if exchangeRateAttempts.contains(attemptKey) {
            return
        }

        guard let exchangeRateSource else {
            exchangeRateStatus = cacheIsComplete
                ? cachedState?.snapshot.map(ExchangeRateStatus.stale)
                    ?? .unavailable
                : .unavailable
            return
        }

        let attemptedAt = now()
        do {
            let snapshot = try await exchangeRateSource.fetchRates(
                base: .eur,
                quotes: requiredQuotes
            )
            guard refreshGeneration == exchangeRateRefreshGeneration else {
                return
            }
            guard snapshotContainsRequiredCurrencies(
                snapshot,
                requiredCurrencies: requiredCurrencies
            ) else {
                throw ExchangeRateRefreshError.incompleteSnapshot
            }
            let state = ExchangeRateCacheState(
                snapshot: snapshot,
                lastAttemptAt: attemptedAt
            )
            do {
                try exchangeRateCache?.saveState(state)
            } catch {
                exchangeRateAttempts.insert(attemptKey)
            }
            exchangeRateStatus = .fresh(snapshot)
        } catch is CancellationError {
            guard refreshGeneration == exchangeRateRefreshGeneration else {
                return
            }
            exchangeRateStatus = cacheIsComplete
                ? cachedState?.snapshot.map(ExchangeRateStatus.stale)
                    ?? .unavailable
                : .unavailable
        } catch {
            guard refreshGeneration == exchangeRateRefreshGeneration else {
                return
            }
            exchangeRateAttempts.insert(attemptKey)
            let state = ExchangeRateCacheState(
                snapshot: cachedState?.snapshot,
                lastAttemptAt: attemptedAt
            )
            try? exchangeRateCache?.saveState(state)
            exchangeRateStatus = cacheIsComplete
                ? cachedState?.snapshot.map(ExchangeRateStatus.stale)
                    ?? .unavailable
                : .unavailable
        }
    }

    func snapshotContainsRequiredCurrencies(
        _ snapshot: ExchangeRateSnapshot,
        requiredCurrencies: Set<Currency>
    ) -> Bool {
        requiredCurrencies.allSatisfy { currency in
            currency == snapshot.base || snapshot.rates[currency] != nil
        }
    }

    public func loadInsights(
        mode: SpendingReportMode,
        from: Date,
        through: Date
    ) {
        insightsRequest = InsightsRequest(mode: mode, from: from, through: through)
        guard from <= through,
              let snapshot = currentExchangeRateSnapshot
        else {
            insightsState = .unavailable
            return
        }

        let displayCurrency = currentPreferences.primaryCurrency
        do {
            let subscriptions = try repository.listSubscriptions()
            let rawItems = subscriptions.flatMap { subscription in
                makeSpendingInsightItems(
                    for: subscription,
                    mode: mode,
                    from: from,
                    through: through
                )
            }
            let items = try rawItems.map { item in
                SpendingInsightItem(
                    id: item.id,
                    subscriptionID: item.subscriptionID,
                    serviceName: item.serviceName,
                    category: item.category,
                    date: item.date,
                    originalAmount: item.amount,
                    convertedAmount: try snapshot.convert(
                        item.amount,
                        to: displayCurrency
                    )
                )
            }
            let sortedItems = items.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
            insightsState = .available(
                makeInsights(
                    mode: mode,
                    displayCurrency: displayCurrency,
                    from: from,
                    through: through,
                    items: sortedItems
                )
            )
        } catch {
            insightsState = .unavailable
        }
    }

    var currentExchangeRateSnapshot: ExchangeRateSnapshot? {
        switch exchangeRateStatus {
        case .fresh(let snapshot), .stale(let snapshot): snapshot
        case .notLoaded, .unavailable: nil
        }
    }

    func reloadInsightsIfNeeded() {
        guard let insightsRequest else { return }
        loadInsights(
            mode: insightsRequest.mode,
            from: insightsRequest.from,
            through: insightsRequest.through
        )
    }

    func makeInsights(
        mode: SpendingReportMode,
        displayCurrency: Currency,
        from: Date,
        through: Date,
        items: [SpendingInsightItem]
    ) -> SpendingInsights {
        let totalMinorUnits = items.reduce(Int64.zero) {
            $0 + $1.convertedAmount.minorUnits
        }
        let total = Money(
            minorUnits: totalMinorUnits,
            currency: displayCurrency
        )
        let monthTotals = Dictionary(grouping: items) { item in
            calendar.date(
                from: calendar.dateComponents([.year, .month], from: item.date)
            ) ?? item.date
        }
        .map { month, items in
            SpendingMonthlyTotal(
                month: month,
                amount: Money(
                    minorUnits: items.reduce(Int64.zero) {
                        $0 + $1.convertedAmount.minorUnits
                    },
                    currency: displayCurrency
                )
            )
        }
        .sorted { $0.month < $1.month }
        let categoryTotals = Dictionary(grouping: items, by: \.category)
            .map { category, items in
                SpendingCategoryTotal(
                    category: category,
                    amount: Money(
                        minorUnits: items.reduce(Int64.zero) {
                            $0 + $1.convertedAmount.minorUnits
                        },
                        currency: displayCurrency
                    )
                )
            }
            .sorted { $0.category.localizedCompare($1.category) == .orderedAscending }
        let dayCount = max(
            1,
            (calendar.dateComponents([.day], from: from, to: through).day ?? 0)
                + 1
        )
        let annualizedMinorUnits = NSDecimalNumber(
            decimal: Decimal(totalMinorUnits) / Decimal(dayCount) * 365
        ).int64Value
        return SpendingInsights(
            mode: mode,
            displayCurrency: displayCurrency,
            selectedRangeTotal: total,
            annualizedTotal: Money(
                minorUnits: annualizedMinorUnits,
                currency: displayCurrency
            ),
            monthlyTotals: monthTotals,
            categoryTotals: categoryTotals,
            items: items
        )
    }

    func makeSpendingInsightItems(
        for subscription: Subscription,
        mode: SpendingReportMode,
        from: Date,
        through: Date
    ) -> [RawSpendingInsightItem] {
        guard !subscription.isArchived else { return [] }
        switch mode {
        case .expected:
            guard isEligibleForExpectedCharges(subscription) else { return [] }
            return makeExpectedCharges(
                for: subscription,
                from: from,
                through: through,
                maximumCount: .max
            )
            .filter { $0.scheduledDate >= from }
            .map { charge in
                RawSpendingInsightItem(
                    id: "expected:\(charge.id.subscriptionID.uuidString)-"
                        + "\(charge.id.year)-\(charge.id.month)-\(charge.id.day)",
                    subscriptionID: subscription.id,
                    serviceName: subscription.serviceName,
                    category: subscription.category,
                    date: charge.scheduledDate,
                    amount: charge.amount
                )
            }
        case .confirmed:
            return subscription.confirmedCharges
                .filter { $0.chargedDate >= from && $0.chargedDate <= through }
                .map { charge in
                    RawSpendingInsightItem(
                        id: "confirmed:\(charge.id.uuidString)",
                        subscriptionID: subscription.id,
                        serviceName: subscription.serviceName,
                        category: subscription.category,
                        date: charge.chargedDate,
                        amount: charge.amount
                    )
                }
        }
    }

    @discardableResult
    public func createSubscription(
        _ input: SubscriptionCreationInput
    ) -> SubscriptionCreationResult {
        createSubscription(input) { id in
            ServiceIdentity(rawValue: "manual:\(id.uuidString)")
        }
    }

    public func loadCatalog(locale: Locale) {
        catalogSearchQuery = ""
        catalogCategoryID = nil
        guard let catalogRepository else {
            catalogState = .failed
            return
        }
        do {
            catalogSnapshot = try catalogRepository.loadSnapshot()
            catalogLocale = locale
            catalogDiagnostics = CatalogDiagnostics(
                source: catalogRepository.catalogSource,
                version: catalogSnapshot?.catalogVersion ?? 0,
                refreshStatus: .idle
            )
            refreshCatalogState()
        } catch {
            catalogSnapshot = nil
            catalogState = .failed
        }
    }

    public func catalogMatches(
        query: String,
        locale: Locale
    ) -> [CatalogPreset] {
        let snapshot = catalogSnapshot ?? (try? catalogRepository?.loadSnapshot())
        return snapshot?.search(query: query, locale: locale) ?? []
    }

    public func catalogOfferAdjustment(
        for subscription: Subscription
    ) -> CatalogOfferAdjustment? {
        guard let snapshot = matchingCatalogSnapshot() else { return nil }
        return CatalogOfferMatcher().adjustment(
            for: subscription,
            in: snapshot,
            onBillingDay: subscription.confirmedNextRenewal
        )
    }

    @discardableResult
    public func reconcileCatalogAssociations(
        locale: Locale
    ) -> CatalogAssociationReconciliationSummary {
        catalogReconciliationError = nil
        catalogLocale = locale
        guard let snapshot = matchingCatalogSnapshot() else {
            catalogReconciliationError = .catalogUnavailable
            return CatalogAssociationReconciliationSummary(
                commandError: .catalogUnavailable
            )
        }

        let subscriptions: [Subscription]
        do {
            subscriptions = try repository.listSubscriptions()
        } catch {
            catalogReconciliationError = .persistenceFailed
            return CatalogAssociationReconciliationSummary(
                commandError: .persistenceFailed
            )
        }

        var normalizedIDs: [UUID] = []
        var unchangedIDs: [UUID] = []
        var ambiguousIDs: [UUID] = []
        var failedIDs: [UUID] = []
        var normalizedByID: [UUID: Subscription] = [:]
        for subscription in subscriptions {
            switch CatalogOfferMatcher().match(
                subscription: subscription,
                in: snapshot,
                onBillingDay: subscription.confirmedNextRenewal
            ) {
            case .none:
                // Reuse the per-subscription reconcile contract so a stale
                // `catalog:` identity demotes to `manual:<uuid>` exactly as
                // the create and edit paths do.
                let reconciled = reconciledCatalogAssociation(
                    for: subscription,
                    locale: locale,
                    snapshot: snapshot
                )
                guard reconciled != subscription else {
                    unchangedIDs.append(subscription.id)
                    continue
                }
                do {
                    try repository.updateSubscription(reconciled)
                    normalizedIDs.append(subscription.id)
                    normalizedByID[subscription.id] = reconciled
                } catch {
                    failedIDs.append(subscription.id)
                    catalogReconciliationError = .persistenceFailed
                }
            case .ambiguous:
                ambiguousIDs.append(subscription.id)
            case .unique(let candidate):
                let normalized = normalizedCatalogAssociation(
                    for: subscription,
                    candidate: candidate,
                    locale: locale
                )
                guard normalized != subscription else {
                    unchangedIDs.append(subscription.id)
                    continue
                }
                do {
                    try repository.updateSubscription(normalized)
                    normalizedIDs.append(subscription.id)
                    normalizedByID[subscription.id] = normalized
                } catch {
                    failedIDs.append(subscription.id)
                    catalogReconciliationError = .persistenceFailed
                }
            }
        }

        if !normalizedIDs.isEmpty {
            markLocalChangesForSync()
            if case .loaded(let selected, _, _) = detailState,
               let normalized = normalizedByID[selected.id]
            {
                detailState = makeDetail(normalized)
            }
            loadLibrary(scope: carriedLibraryScope)
            reloadRequestedConsumers()
        }

        return CatalogAssociationReconciliationSummary(
            normalizedIDs: normalizedIDs,
            unchangedIDs: unchangedIDs,
            ambiguousIDs: ambiguousIDs,
            failedIDs: failedIDs,
            commandError: catalogReconciliationError
        )
    }

    public func clearCatalogReconciliationError() {
        catalogReconciliationError = nil
    }

    public func refreshCatalog() async {
        guard let catalogRepository,
              let catalogUpdateSource,
              let catalogCache
        else {
            return
        }
        catalogRefreshGeneration &+= 1
        let refreshGeneration = catalogRefreshGeneration

        do {
            let persistedSnapshot = try catalogSnapshot == nil
                ? catalogRepository.loadSnapshot()
                : nil
            let data = try await catalogUpdateSource.fetchCatalogData()
            let candidate = try JSONDecoder().decode(
                CatalogSnapshot.self,
                from: data
            )
            let latestActiveSnapshot: CatalogSnapshot
            if let catalogSnapshot {
                latestActiveSnapshot = catalogSnapshot
            } else if let persistedSnapshot {
                latestActiveSnapshot = persistedSnapshot
            } else {
                latestActiveSnapshot = try catalogRepository.loadSnapshot()
            }
            guard candidate.catalogVersion > latestActiveSnapshot.catalogVersion else {
                catalogDiagnostics = CatalogDiagnostics(
                    source: catalogDiagnostics?.source
                        ?? catalogRepository.catalogSource,
                    version: latestActiveSnapshot.catalogVersion,
                    refreshStatus: .alreadyCurrent
                )
                return
            }

            try catalogCache.storeCatalogData(data)
            catalogSnapshot = candidate
            catalogDiagnostics = CatalogDiagnostics(
                source: .cached,
                version: candidate.catalogVersion,
                refreshStatus: .updated
            )
            refreshCatalogState()
        } catch {
            guard refreshGeneration == catalogRefreshGeneration else {
                return
            }
            if let catalogSnapshot {
                catalogDiagnostics = CatalogDiagnostics(
                    source: catalogDiagnostics?.source
                        ?? catalogRepository.catalogSource,
                    version: catalogSnapshot.catalogVersion,
                    refreshStatus: .failed
                )
            }
        }
    }

    public func setCatalogSearchQuery(_ query: String) {
        catalogSearchQuery = query
        refreshCatalogState()
    }

    public func setCatalogCategory(_ categoryID: String?) {
        catalogCategoryID = categoryID
        refreshCatalogState()
    }

    @discardableResult
    public func createCatalogSubscription(
        presetID: String,
        command: CatalogSubscriptionCreationCommand
    ) -> CatalogSubscriptionCreationResult {
        guard let preset = catalogSnapshot?.presets.first(where: {
            $0.id == presetID
        }) else {
            creationValidationErrors = [:]
            return .rejected(.presetNotFound)
        }

        let input: SubscriptionCreationInput
        switch command {
        case .verifiedOffer(let offerInput):
            guard let offer = preset.offers.first(where: {
                $0.id == offerInput.offerID
            }) else {
                creationValidationErrors = [:]
                return .rejected(.offerNotFound)
            }
            guard offer.reviewStatus == .verified else {
                creationValidationErrors = [:]
                return .rejected(.offerRequiresReview)
            }
            let billingInterval = switch
                offerInput.billingIntervalSelection
            {
            case .official:
                offer.billingInterval
            case .override(let interval):
                interval
            }
            input = SubscriptionCreationInput(
                serviceName: preset.serviceName.value(for: catalogLocale),
                plan: offer.planName.value(for: catalogLocale),
                category: preset.category.value(for: catalogLocale),
                originalAmount:
                    offerInput.actualChargeOverride ?? offer.price,
                billingInterval: billingInterval,
                startDate: offerInput.startDate,
                renewalAnchor: offerInput.renewalAnchor,
                confirmedNextRenewal: offerInput.confirmedNextRenewal,
                billingTimeZoneIdentifier:
                    offerInput.billingTimeZoneIdentifier,
                managementURL: preset.managementURL,
                notes: offerInput.notes,
                initialStatus: offerInput.initialStatus
            )
        case .legacy(let legacyInput):
            guard !preset.offers.contains(where: {
                $0.reviewStatus == .verified
            }) else {
                creationValidationErrors = [:]
                return .rejected(.verifiedOfferRequired)
            }
            input = legacyInput
        }

        let result = createSubscription(input) { _ in
            ServiceIdentity(rawValue: "catalog:\(preset.id)")
        }
        switch result {
        case .created(let subscription):
            return .created(subscription)
        case .validationFailed:
            return .validationFailed
        case .persistenceFailed:
            return .persistenceFailed
        }
    }

    @discardableResult
    func createSubscription(
        _ input: SubscriptionCreationInput,
        serviceIdentity: (UUID) -> ServiceIdentity
    ) -> SubscriptionCreationResult {
        creationValidationErrors = validate(input)
        guard creationValidationErrors.isEmpty,
              let originalAmount = input.originalAmount
        else {
            return .validationFailed
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        let id = identifierGenerator()
        let confirmedNextRenewal: Date
        switch input.initialStatus {
        case .active:
            guard let timeZone = TimeZone(
                identifier: input.billingTimeZoneIdentifier
            ),
            let resolvedRenewal = BillingDateResolver().nextRenewal(
                afterStart: input.startDate,
                interval: input.billingInterval,
                asOf: now(),
                timeZone: timeZone
            ) else {
                creationValidationErrors[.confirmedNextRenewal] = .required
                return .validationFailed
            }
            confirmedNextRenewal = resolvedRenewal
        case .trial:
            confirmedNextRenewal = input.confirmedNextRenewal
        }
        let lifecycle: SubscriptionLifecycle =
            input.initialStatus == .trial
                ? .trial(firstPaidChargeAt: confirmedNextRenewal)
                : .active
        let renewalAnchor = input.initialStatus == .trial
            ? confirmedNextRenewal
            : input.startDate
        let subscription = Subscription(
            id: id,
            serviceIdentity: serviceIdentity(id),
            serviceName: input.serviceName.trimmingCharacters(in: whitespace),
            plan: input.plan.trimmingCharacters(in: whitespace),
            category: input.category.trimmingCharacters(in: whitespace),
            originalAmount: originalAmount,
            billingSchedule: FixedBillingSchedule(
                interval: input.billingInterval,
                renewalAnchor: renewalAnchor,
                timeZoneIdentifier: input.billingTimeZoneIdentifier
            ),
            startDate: input.startDate,
            confirmedNextRenewal: confirmedNextRenewal,
            managementURL: input.managementURL,
            notes: input.notes,
            lifecycle: lifecycle,
            isArchived: false
        )
        let subscriptionToPersist = reconciledCatalogAssociation(
            for: subscription,
            locale: catalogLocale
        )

        do {
            try repository.createSubscription(subscriptionToPersist)
            markLocalChangesForSync()
            detailState = makeDetail(subscriptionToPersist)
            loadLibrary()
            reloadRequestedConsumers()
            return .created(subscriptionToPersist)
        } catch {
            detailState = .failed
            return .persistenceFailed
        }
    }

    @available(*, deprecated, renamed: "createSubscription")
    public func createMonthlySubscription(
        _ input: SubscriptionCreationInput
    ) {
        createSubscription(input)
    }

    @discardableResult









    public func loadLibrary(
        scope: SubscriptionLibraryScope = .current
    ) {
        libraryState = .loading(scope)
        do {
            libraryState = try makeLibraryState(scope: scope)
            publishWidgetSnapshot()
        } catch {
            libraryState = .failed(scope)
        }
    }

    public func reloadLibrary() {
        loadLibrary(scope: carriedLibraryScope)
    }

    public func reloadAfterRemoteImport() async {
        let scope = carriedLibraryScope
        loadLibrary(scope: scope)
        reloadPreferencesAfterRemoteImport()
        if insightsRequest != nil {
            await refreshExchangeRates()
        }
        reloadRequestedConsumers()
    }

    func reloadPreferencesAfterRemoteImport() {
        guard preferencesRepository != nil else { return }
        let previousState = setupState
        loadSetup(
            libraryIsEmptyWhenPreferencesAreMissing:
                libraryIsEmptyAfterRemoteImport
        )
        if setupState != previousState {
            setupRevision &+= 1
        }
    }

    var libraryIsEmptyAfterRemoteImport: Bool? {
        switch libraryState {
        case .loaded:
            false
        case .empty:
            try? repository.listSubscriptions().isEmpty
        case .loading, .failed:
            nil
        }
    }

    public func makeWidgetSnapshot() -> WidgetSnapshot? {
        do {
            let nextRenewal = try repository.listSubscriptions()
                .compactMap { subscription -> WidgetRenewalSnapshot? in
                    guard let charge = makePresentationNextExpectedCharge(
                        for: subscription
                    ) else {
                        return nil
                    }
                    return WidgetRenewalSnapshot(
                        subscriptionID: subscription.id,
                        serviceName: subscription.serviceName,
                        renewalDate: charge.scheduledDate,
                        amountDescription: formattedWidgetAmount(charge.amount),
                        isRateStale: false
                    )
                }
                .min { lhs, rhs in
                    if lhs.renewalDate != rhs.renewalDate {
                        return lhs.renewalDate < rhs.renewalDate
                    }
                    return lhs.subscriptionID.uuidString < rhs.subscriptionID.uuidString
                }
            return WidgetSnapshot(generatedAt: now(), nextRenewal: nextRenewal)
        } catch {
            return nil
        }
    }


    public func beginEditing() {
        editingValidationErrors = [:]
    }

    public func loadSubscription(id: UUID) {
        do {
            if let subscription = try repository.subscription(id: id) {
                detailState = makeDetail(subscription)
            } else {
                detailState = .notFound
                paymentHistory = []
            }
        } catch {
            detailState = .failed
            paymentHistory = []
        }
    }

    public func subscriptions() throws -> [Subscription] {
        try repository.listSubscriptions()
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func subscription(for id: UUID) throws -> Subscription? {
        try repository.subscription(id: id)
    }

    public func loadExpectedCharges(
        subscriptionID: UUID,
        through horizon: Date,
        maximumCount: Int = .max
    ) {
        expectedChargesRequest = ExpectedChargesRequest(
            subscriptionID: subscriptionID,
            horizon: horizon,
            maximumCount: maximumCount
        )
        do {
            guard let subscription = try repository.subscription(
                id: subscriptionID
            ) else {
                expectedCharges = nil
                return
            }
            expectedCharges = makeExpectedCharges(
                for: subscription,
                through: horizon,
                maximumCount: maximumCount
            )
        } catch {
            expectedCharges = nil
        }
    }

    public func loadUpcomingTimeline(from: Date, through: Date) {
        upcomingTimelineRequest = UpcomingTimelineRequest(
            from: from,
            through: through
        )
        do {
            let timeline = try upcomingRenewals(from: from, through: through)
            upcomingTimeline = timeline
            upcomingTimelineState = timeline.isEmpty ? .empty : .loaded(timeline)
        } catch {
            upcomingTimeline = []
            upcomingTimelineState = .failed
        }
    }

    public func upcomingRenewals(
        from: Date,
        through: Date
    ) throws -> [UpcomingTimelineItem] {
        guard from <= through else { return [] }
        return try subscriptions()
            .flatMap { subscription in
                makeUpcomingTimelineItems(
                    for: subscription,
                    from: from,
                    through: through
                )
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
    }

    @discardableResult


    /// Exports a portable backup and reports how many unreadable local
    /// records the repository skipped during that load, so callers can
    /// surface incomplete exports instead of failing silently.










    func validate(
        _ input: SubscriptionCreationInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if let originalAmount = input.originalAmount {
            if originalAmount.minorUnits <= 0 {
                errors[.originalAmount] = .mustBePositive
            }
        } else {
            errors[.originalAmount] = .required
        }
        if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
            errors[.billingSchedule] = .required
        }
        if input.initialStatus == .trial {
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        }
        if !input.billingInterval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingTimeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }

    func validate(
        _ input: SubscriptionEditInput,
        lifecycle: SubscriptionLifecycle
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.amount.minorUnits <= 0 {
            errors[.originalAmount] = .mustBePositive
        }
        switch lifecycle {
        case .active:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
                errors[.billingSchedule] = .required
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            }
        case .trial:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
                errors[.billingSchedule] = .required
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        case .cancelled:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite
                || !input.billingSchedule.renewalAnchor
                    .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.billingSchedule] = .required
            } else if input.billingSchedule.renewalAnchor < input.startDate {
                errors[.renewalAnchor] = .beforeStartDate
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        }
        if !input.billingSchedule.interval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingSchedule.timeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }

    func editedPriceChanges(
        for existing: Subscription,
        amount: Money,
        confirmedNextRenewal: Date,
        calendar: Calendar
    ) -> [PriceChange] {
        let currentAmount = existing.amount(
            onBillingDay: confirmedNextRenewal
        )
        guard amount != currentAmount else {
            return existing.priceChanges
        }

        let sameDayWinnerIndex = existing.priceChanges.indices
            .filter {
                calendar.isDate(
                    existing.priceChanges[$0].effectiveDate,
                    inSameDayAs: confirmedNextRenewal
                )
            }
            .max {
                existing.priceChanges[$0].id.uuidString
                    < existing.priceChanges[$1].id.uuidString
            }

        if let index = sameDayWinnerIndex {
            var corrected = existing.priceChanges
            let existingChange = corrected[index]
            corrected[index] = PriceChange(
                id: existingChange.id,
                effectiveDate: confirmedNextRenewal,
                amount: amount
            )
            return corrected
        }

        return existing.priceChanges + [
            PriceChange(
                id: identifierGenerator(),
                effectiveDate: confirmedNextRenewal,
                amount: amount
            ),
        ]
    }

    func billingTimeZone(
        for subscription: Subscription
    ) -> TimeZone {
        TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
    }

    func publishWidgetSnapshot() {
        guard let snapshot = makeWidgetSnapshot() else { return }
        widgetSnapshotPublisher?.publish(snapshot)
    }

    func formattedWidgetAmount(_ money: Money) -> String {
        (Decimal(money.minorUnits) / 100).formatted(
            .currency(code: money.currency.rawValue).locale(.current)
        )
    }

    func finishLifecycleUpdate(
        _ subscription: Subscription
    ) {
        markLocalChangesForSync()
        let scope = carriedLibraryScope
        let refreshedDetailState = makeDetail(subscription)

        detailState = refreshedDetailState
        loadLibrary(scope: scope)
        reloadRequestedConsumers()
    }

    func reloadRequestedConsumers() {
        if case .loaded(let subscription, _, _) = detailState {
            loadSubscription(id: subscription.id)
        }
        if let expectedChargesRequest {
            loadExpectedCharges(
                subscriptionID: expectedChargesRequest.subscriptionID,
                through: expectedChargesRequest.horizon,
                maximumCount: expectedChargesRequest.maximumCount
            )
        }
        if let upcomingTimelineRequest {
            loadUpcomingTimeline(
                from: upcomingTimelineRequest.from,
                through: upcomingTimelineRequest.through
            )
        }
        if let calendarProjectionLocale {
            loadCalendarProjection(locale: calendarProjectionLocale)
        }
        reloadInsightsIfNeeded()
    }

    func makeLibraryState(
        scope: SubscriptionLibraryScope
    ) throws -> SubscriptionLibraryState {
        let subscriptions = try repository.listSubscriptions()
            .filter { $0.isArchived == (scope == .archived) }
        let summaries = subscriptions.map(makeSummary)
        let orderedSummaries = scope == .current
            ? SubscriptionTableQuery().apply(to: summaries)
            : summaries
        return orderedSummaries.isEmpty
            ? .empty(scope)
            : .loaded(scope, orderedSummaries)
    }

    var carriedLibraryScope: SubscriptionLibraryScope {
        switch libraryState {
        case .loading(let scope),
             .empty(let scope),
             .loaded(let scope, _),
             .failed(let scope):
            scope
        }
    }

    func matchingCatalogSnapshot() -> CatalogSnapshot? {
        if let catalogSnapshot {
            return catalogSnapshot
        }
        return try? catalogRepository?.loadSnapshot()
    }

    func reconciledCatalogAssociation(
        for subscription: Subscription,
        locale: Locale,
        snapshot providedSnapshot: CatalogSnapshot? = nil
    ) -> Subscription {
        guard let snapshot = providedSnapshot ?? matchingCatalogSnapshot()
        else {
            return subscription
        }
        let matcher = CatalogOfferMatcher()
        let serviceNameMatch = matcher.matchesCatalogServiceName(
            subscription: subscription,
            in: snapshot
        )
        let hasCatalogIdentity = subscription.serviceIdentity.rawValue
            .hasPrefix("catalog:")
        guard !hasCatalogIdentity || serviceNameMatch != nil
        else {
            return subscription
        }
        switch matcher.match(
            subscription: subscription,
            in: snapshot,
            onBillingDay: subscription.confirmedNextRenewal
        ) {
        case .none:
            guard hasCatalogIdentity,
                  serviceNameMatch == false
            else {
                return subscription
            }
            return subscription.replacingCatalogAssociation(
                serviceIdentity: ServiceIdentity(
                    rawValue: "manual:\(subscription.id.uuidString)"
                ),
                serviceName: subscription.serviceName,
                plan: subscription.plan,
                category: subscription.category,
                managementURL: subscription.managementURL
            )
        case .ambiguous:
            return subscription
        case .unique(let candidate):
            return normalizedCatalogAssociation(
                for: subscription,
                candidate: candidate,
                locale: locale
            )
        }
    }

    func normalizedCatalogAssociation(
        for subscription: Subscription,
        candidate: CatalogOfferMatchCandidate,
        locale: Locale
    ) -> Subscription {
        subscription.replacingCatalogAssociation(
            serviceIdentity: ServiceIdentity(
                rawValue: "catalog:\(candidate.preset.id)"
            ),
            serviceName: candidate.preset.serviceName.value(for: locale),
            plan: candidate.offer.planName.value(for: locale),
            category: candidate.preset.category.value(for: locale),
            managementURL: candidate.preset.managementURL
        )
    }

    func refreshCatalogState() {
        guard let catalogSnapshot else {
            return
        }
        let presets = catalogSnapshot.search(
            query: catalogSearchQuery,
            locale: catalogLocale
        )
        .filter { preset in
            guard let catalogCategoryID else { return true }
            return preset.category.en.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en")
            ) == catalogCategoryID
        }
        catalogState = .loaded(
            categories: catalogSnapshot.categories(locale: catalogLocale),
            presets: presets
        )
    }

    func makeExpectedCharges(
        for subscription: Subscription,
        through horizon: Date,
        maximumCount: Int
    ) -> [ExpectedCharge] {
        guard maximumCount > 0,
              isEligibleForExpectedCharges(subscription),
              subscription.billingSchedule.interval.isValid,
              let timeZone = TimeZone(
                  identifier: subscription.billingSchedule.timeZoneIdentifier
              )
        else {
            return []
        }

        var renewalCalendar = calendar
        renewalCalendar.timeZone = timeZone
        let currentDate = renewalCalendar.startOfDay(for: now())
        let firstForecastDate = max(
            currentDate,
            subscription.confirmedNextRenewal
        )
        var charges: [ExpectedCharge] = []
        var occurrenceIndex = estimatedOccurrenceIndex(
            for: subscription.billingSchedule,
            onOrAfter: firstForecastDate,
            calendar: renewalCalendar
        )

        while charges.count < maximumCount {
            guard let scheduledDate = scheduledDate(
                for: subscription.billingSchedule,
                occurrenceIndex: occurrenceIndex,
                calendar: renewalCalendar
            ) else {
                break
            }
            if scheduledDate > horizon {
                break
            }
            if scheduledDate >= firstForecastDate {
                let charge = expectedCharge(
                    for: subscription,
                    scheduledDate: scheduledDate,
                    calendar: renewalCalendar
                )
                if !subscription.confirmedCharges.contains(where: {
                    $0.sourceScheduledChargeID == charge.id
                }) {
                    charges.append(charge)
                }
            }
            occurrenceIndex += 1
        }

        return charges
    }

    func makeUpcomingTimelineItems(
        for subscription: Subscription,
        from: Date,
        through: Date
    ) -> [UpcomingTimelineItem] {
        guard !subscription.isArchived,
              isEligibleForExpectedCharges(subscription)
        else {
            return []
        }

        let expectedItems = makeExpectedCharges(
            for: subscription,
            from: from,
            through: through,
            maximumCount: .max
        )
        .map { charge in
            UpcomingTimelineItem(
                id: "expected:\(charge.id.subscriptionID.uuidString)-"
                    + "\(charge.id.year)-\(charge.id.month)-\(charge.id.day)",
                kind: .expected,
                subscriptionID: subscription.id,
                serviceName: subscription.serviceName,
                date: charge.scheduledDate,
                amount: charge.amount
            )
        }
        let confirmedItems = subscription.confirmedCharges
            .filter { $0.chargedDate >= from && $0.chargedDate <= through }
            .map { charge in
                UpcomingTimelineItem(
                    id: "confirmed:\(charge.id.uuidString)",
                    kind: .confirmed,
                    subscriptionID: subscription.id,
                    serviceName: subscription.serviceName,
                    date: charge.chargedDate,
                    amount: charge.amount
                )
            }
        return expectedItems + confirmedItems
    }

    func makeExpectedCharges(
        for subscription: Subscription,
        from: Date,
        through: Date,
        maximumCount: Int
    ) -> [ExpectedCharge] {
        guard from <= through,
              maximumCount > 0,
              isEligibleForExpectedCharges(subscription),
              subscription.billingSchedule.interval.isValid,
              let timeZone = TimeZone(
                  identifier: subscription.billingSchedule.timeZoneIdentifier
              )
        else {
            return []
        }

        var renewalCalendar = calendar
        renewalCalendar.timeZone = timeZone
        let requestedStart = max(
            renewalCalendar.startOfDay(for: from),
            subscription.startDate
        )
        let currentBillingDay = renewalCalendar.startOfDay(for: now())
        // Historical month queries may surface an unconfirmed occurrence;
        // ranges containing today or the future remain forward-looking.
        let firstForecastDate = through < currentBillingDay
            ? requestedStart
            : max(
                requestedStart,
                max(currentBillingDay, subscription.confirmedNextRenewal)
            )
        var charges: [ExpectedCharge] = []
        var occurrenceIndex = estimatedOccurrenceIndex(
            for: subscription.billingSchedule,
            onOrAfter: firstForecastDate,
            calendar: renewalCalendar
        )

        while charges.count < maximumCount {
            guard let scheduledDate = scheduledDate(
                for: subscription.billingSchedule,
                occurrenceIndex: occurrenceIndex,
                calendar: renewalCalendar
            ) else {
                break
            }
            if scheduledDate > through {
                break
            }
            if scheduledDate >= firstForecastDate {
                let charge = expectedCharge(
                    for: subscription,
                    scheduledDate: scheduledDate,
                    calendar: renewalCalendar
                )
                if !subscription.confirmedCharges.contains(where: {
                    $0.sourceScheduledChargeID == charge.id
                }) {
                    charges.append(charge)
                }
            }
            occurrenceIndex += 1
        }

        return charges
    }

    func makeCalendarProjectionEvents(
        for subscription: Subscription,
        through horizon: Date,
        locale: Locale,
        hidesAmounts: Bool
    ) -> [CalendarProjectionEvent] {
        guard let timeZone = TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) else {
            return []
        }
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        return makeExpectedCharges(
            for: subscription,
            through: horizon,
            maximumCount: .max
        )
        .compactMap { charge in
            guard let endDate = localCalendar.date(
                byAdding: .day,
                value: 1,
                to: charge.scheduledDate
            ) else {
                return nil
            }
            let dateComponents = localCalendar.dateComponents(
                [.year, .month, .day],
                from: charge.scheduledDate
            )
            guard let year = dateComponents.year,
                  let month = dateComponents.month,
                  let day = dateComponents.day
            else {
                return nil
            }
            let amount = formattedCalendarAmount(charge.amount, locale: locale)
            let title = hidesAmounts
                ? subscription.serviceName
                : "\(subscription.serviceName) — \(amount)"
            var noteLines = [subscription.plan]
            if !hidesAmounts {
                noteLines.append(amount)
            }
            let subscriptionNotes = subscription.notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !subscriptionNotes.isEmpty {
                noteLines.append(subscriptionNotes)
            }
            let alarmOffsets: [Int]
            switch subscription.lifecycle {
            case .trial:
                alarmOffsets = [-3, -1]
            case .active, .cancelled:
                alarmOffsets = [-7, -1]
            }
            return CalendarProjectionEvent(
                uid: "\(subscription.id.uuidString.lowercased())-"
                    + "\(String(format: "%04d%02d%02d", year, month, day))"
                    + "@subscription-manager",
                startDate: charge.scheduledDate,
                endDate: endDate,
                title: title,
                notes: noteLines.joined(separator: "\n"),
                managementURL: subscription.managementURL,
                alarmOffsets: alarmOffsets,
                timeZoneIdentifier: timeZone.identifier
            )
        }
    }

    func formattedCalendarAmount(
        _ money: Money,
        locale: Locale
    ) -> String {
        (Decimal(money.minorUnits) / 100).formatted(
            .currency(code: money.currency.rawValue).locale(locale)
        )
    }

    func expectedCharge(
        for subscription: Subscription,
        scheduledDate: Date,
        calendar: Calendar
    ) -> ExpectedCharge {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: scheduledDate
        )
        let id = ScheduledChargeID(
            subscriptionID: subscription.id,
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
        let amount = subscription.amount(onBillingDay: scheduledDate)
        return ExpectedCharge(
            id: id,
            subscriptionID: subscription.id,
            scheduledDate: scheduledDate,
            amount: amount
        )
    }

    func isScheduledOccurrence(
        _ date: Date,
        for subscription: Subscription,
        calendar: Calendar
    ) -> Bool {
        guard date >= subscription.startDate else {
            return false
        }
        let firstCandidateIndex = estimatedOccurrenceIndex(
            for: subscription.billingSchedule,
            onOrAfter: date,
            calendar: calendar
        )
        // The estimate is deliberately conservative so forecasting can find
        // the first occurrence on or after a boundary. Check that candidate
        // and the immediately following one when validating a user-selected
        // past occurrence.
        for occurrenceIndex in firstCandidateIndex...(firstCandidateIndex + 1) {
            guard let occurrence = scheduledDate(
                for: subscription.billingSchedule,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            ) else {
                continue
            }
            if calendar.isDate(occurrence, inSameDayAs: date) {
                return true
            }
        }
        return false
    }

    func makeSummary(
        _ subscription: Subscription
    ) -> SubscriptionSummary {
        let presentation = makePresentation(for: subscription)
        return SubscriptionSummary(
            subscription: presentation.subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }

    func makeDetail(
        _ subscription: Subscription
    ) -> SubscriptionDetailState {
        let presentation = makePresentation(for: subscription)
        paymentHistory = makeHistory(for: subscription)
        return .loaded(
            subscription: presentation.subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }

    func makeHistory(
        for subscription: Subscription
    ) -> [SubscriptionHistoryEntry] {
        let timeZone = billingTimeZone(for: subscription)
        let localCalendar = billingLocalCalendar(timeZone: timeZone)
        var entries: [SubscriptionHistoryEntry] =
            subscription.confirmedCharges.map(SubscriptionHistoryEntry.confirmed)
            + subscription.priceChanges.map(SubscriptionHistoryEntry.priceChange)

        if !subscription.isArchived,
           isEligibleForExpectedCharges(subscription)
        {
            let today = localCalendar.startOfDay(for: now())
            let candidateIndex = estimatedOccurrenceIndex(
                for: subscription.billingSchedule,
                onOrAfter: today,
                calendar: localCalendar
            )
            let startDay = localCalendar.startOfDay(for: subscription.startDate)
            let confirmedNextRenewalDay = localCalendar.startOfDay(
                for: subscription.confirmedNextRenewal
            )
            let missedOccurrence =
                HistoryOccurrenceSearch.firstUnconfirmedPastOccurrence(
                    candidateIndex: candidateIndex,
                    lowerBoundDay: max(startDay, confirmedNextRenewalDay),
                    todayDay: today,
                    occurrenceAt: { occurrenceIndex in
                        self.scheduledDate(
                            for: subscription.billingSchedule,
                            occurrenceIndex: occurrenceIndex,
                            calendar: localCalendar
                        )
                    },
                    day: localCalendar.startOfDay(for:),
                    isConfirmed: { occurrence in
                        let charge = self.expectedCharge(
                            for: subscription,
                            scheduledDate: occurrence,
                            calendar: localCalendar
                        )
                        return subscription.confirmedCharges.contains {
                            $0.sourceScheduledChargeID == charge.id
                        }
                    }
                )
            if let missedOccurrence {
                let missed = expectedCharge(
                    for: subscription,
                    scheduledDate: missedOccurrence,
                    calendar: localCalendar
                )
                entries.append(.expected(missed))
            }

            let tomorrow = localCalendar.date(
                byAdding: .day,
                value: 1,
                to: today
            ) ?? today
            let nextLowerBound = max(tomorrow, confirmedNextRenewalDay)
            let nextIndex = estimatedOccurrenceIndex(
                for: subscription.billingSchedule,
                onOrAfter: nextLowerBound,
                calendar: localCalendar
            )
            let next = (nextIndex...(nextIndex + 2)).compactMap {
                scheduledDate(
                    for: subscription.billingSchedule,
                    occurrenceIndex: $0,
                    calendar: localCalendar
                )
            }
            .filter { $0 >= nextLowerBound }
            .map {
                expectedCharge(
                    for: subscription,
                    scheduledDate: $0,
                    calendar: localCalendar
                )
            }
            .first { charge in
                !subscription.confirmedCharges.contains {
                    $0.sourceScheduledChargeID == charge.id
                }
            }
            if let next {
                entries.append(.expected(next))
            }
        }

        return entries.sorted { lhs, rhs in
            let left = historySortKey(lhs)
            let right = historySortKey(rhs)
            let leftDay = localCalendar.startOfDay(for: left.date)
            let rightDay = localCalendar.startOfDay(for: right.date)
            if leftDay != rightDay {
                return leftDay < rightDay
            }
            if left.kindOrder != right.kindOrder {
                return left.kindOrder < right.kindOrder
            }
            return left.date < right.date
        }
    }

    func historySortKey(
        _ entry: SubscriptionHistoryEntry
    ) -> (date: Date, kindOrder: Int) {
        switch entry {
        case .priceChange(let change):
            (change.effectiveDate, 0)
        case .expected(let charge):
            (charge.scheduledDate, 1)
        case .confirmed(let charge):
            (charge.chargedDate, 2)
        }
    }

    func makePresentation(
        for subscription: Subscription
    ) -> (
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    ) {
        let timeZone = TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
        let status = subscription.lifecycle.status(
            asOf: now(),
            timeZone: timeZone
        )
        let nextExpectedCharge = makePresentationNextExpectedCharge(
            for: subscription
        )
        let presentedSubscription =
            if case .active = subscription.lifecycle,
               let nextExpectedCharge
            {
                subscription.replacingLifecycleFacts(
                    confirmedNextRenewal:
                        nextExpectedCharge.scheduledDate
                )
            } else {
                subscription
            }
        return (
            presentedSubscription,
            status,
            nextExpectedCharge
        )
    }

    func makePresentationNextExpectedCharge(
        for subscription: Subscription
    ) -> ExpectedCharge? {
        guard isEligibleForExpectedCharges(subscription),
              let timeZone = TimeZone(
                  identifier:
                      subscription.billingSchedule.timeZoneIdentifier
              )
        else {
            return nil
        }
        guard case .active = subscription.lifecycle else {
            return makeExpectedCharges(
                for: subscription,
                through: .distantFuture,
                maximumCount: 1
            ).first
        }

        let resolver = BillingDateResolver()
        var renewal = resolver.nextRenewal(
            afterStart: subscription.billingSchedule.renewalAnchor,
            interval: subscription.billingSchedule.interval,
            asOf: now(),
            timeZone: timeZone
        )
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        for _ in 0 ... subscription.confirmedCharges.count {
            guard let scheduledDate = renewal else { return nil }
            let charge = expectedCharge(
                for: subscription,
                scheduledDate: scheduledDate,
                calendar: localCalendar
            )
            if !subscription.confirmedCharges.contains(where: {
                $0.sourceScheduledChargeID == charge.id
            }) {
                return charge
            }
            renewal = resolver.nextRenewal(
                afterStart: scheduledDate,
                interval: subscription.billingSchedule.interval,
                asOf: scheduledDate,
                timeZone: timeZone
            )
        }
        return nil
    }

    func isEligibleForExpectedCharges(
        _ subscription: Subscription
    ) -> Bool {
        guard !subscription.isArchived else {
            return false
        }
        if case .cancelled = subscription.lifecycle {
            return false
        }
        return true
    }

    func estimatedOccurrenceIndex(
        for schedule: FixedBillingSchedule,
        onOrAfter targetDate: Date,
        calendar: Calendar
    ) -> Int {
        guard targetDate > schedule.renewalAnchor else {
            return 0
        }

        let estimate: Int
        switch schedule.interval {
        case .weekly:
            estimate = estimatedDayOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalDays: 7,
                calendar: calendar
            )
        case .monthly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 1,
                calendar: calendar
            )
        case .quarterly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 3,
                calendar: calendar
            )
        case .halfYearly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 6,
                calendar: calendar
            )
        case .yearly:
            estimate = estimatedMonthOccurrenceIndex(
                anchor: schedule.renewalAnchor,
                targetDate: targetDate,
                intervalMonths: 12,
                calendar: calendar
            )
        case .custom(let value, let unit):
            switch unit {
            case .day:
                estimate = estimatedDayOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalDays: value,
                    calendar: calendar
                )
            case .week:
                let (days, overflow) = value.multipliedReportingOverflow(
                    by: 7
                )
                guard !overflow else {
                    return 0
                }
                estimate = estimatedDayOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalDays: days,
                    calendar: calendar
                )
            case .month:
                estimate = estimatedMonthOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalMonths: value,
                    calendar: calendar
                )
            case .year:
                let (months, overflow) = value.multipliedReportingOverflow(
                    by: 12
                )
                guard !overflow else {
                    return 0
                }
                estimate = estimatedMonthOccurrenceIndex(
                    anchor: schedule.renewalAnchor,
                    targetDate: targetDate,
                    intervalMonths: months,
                    calendar: calendar
                )
            }
        }

        return max(0, estimate - 1)
    }

    func estimatedDayOccurrenceIndex(
        anchor: Date,
        targetDate: Date,
        intervalDays: Int,
        calendar: Calendar
    ) -> Int {
        guard intervalDays > 0 else {
            return 0
        }
        let dayDistance = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchor),
            to: calendar.startOfDay(for: targetDate)
        ).day ?? 0
        return max(0, dayDistance / intervalDays)
    }

    func estimatedMonthOccurrenceIndex(
        anchor: Date,
        targetDate: Date,
        intervalMonths: Int,
        calendar: Calendar
    ) -> Int {
        guard intervalMonths > 0 else {
            return 0
        }
        let anchorComponents = calendar.dateComponents(
            [.year, .month],
            from: anchor
        )
        let targetComponents = calendar.dateComponents(
            [.year, .month],
            from: targetDate
        )
        guard let anchorYear = anchorComponents.year,
              let anchorMonth = anchorComponents.month,
              let targetYear = targetComponents.year,
              let targetMonth = targetComponents.month
        else {
            return 0
        }
        let monthDistance =
            (targetYear - anchorYear) * 12 + targetMonth - anchorMonth
        return max(0, monthDistance / intervalMonths)
    }

    func scheduledDate(
        for schedule: FixedBillingSchedule,
        occurrenceIndex: Int,
        calendar: Calendar
    ) -> Date? {
        guard occurrenceIndex >= 0 else {
            return nil
        }

        switch schedule.interval {
        case .weekly:
            return dayBasedDate(
                anchor: schedule.renewalAnchor,
                intervalDays: 7,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .monthly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 1,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .quarterly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 3,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .halfYearly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 6,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .yearly:
            return monthBasedDate(
                anchor: schedule.renewalAnchor,
                intervalMonths: 12,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            )
        case .custom(let value, let unit):
            guard value > 0 else {
                return nil
            }
            switch unit {
            case .day:
                return dayBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalDays: value,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            case .week:
                let (days, overflow) = value.multipliedReportingOverflow(by: 7)
                guard !overflow else {
                    return nil
                }
                return dayBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalDays: days,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            case .month:
                return monthBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalMonths: value,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            case .year:
                let (months, overflow) = value.multipliedReportingOverflow(
                    by: 12
                )
                guard !overflow else {
                    return nil
                }
                return monthBasedDate(
                    anchor: schedule.renewalAnchor,
                    intervalMonths: months,
                    occurrenceIndex: occurrenceIndex,
                    calendar: calendar
                )
            }
        }
    }

    func dayBasedDate(
        anchor: Date,
        intervalDays: Int,
        occurrenceIndex: Int,
        calendar: Calendar
    ) -> Date? {
        let (days, overflow) = intervalDays.multipliedReportingOverflow(
            by: occurrenceIndex
        )
        guard !overflow else {
            return nil
        }
        return calendar.date(byAdding: .day, value: days, to: anchor)
    }

    func monthBasedDate(
        anchor: Date,
        intervalMonths: Int,
        occurrenceIndex: Int,
        calendar: Calendar
    ) -> Date? {
        let (monthOffset, offsetOverflow) =
            intervalMonths.multipliedReportingOverflow(by: occurrenceIndex)
        guard !offsetOverflow else {
            return nil
        }
        var anchorComponents = calendar.dateComponents(
            [
                .era,
                .year,
                .month,
                .day,
                .hour,
                .minute,
                .second,
                .nanosecond,
            ],
            from: anchor
        )
        guard let anchorYear = anchorComponents.year,
              let anchorMonth = anchorComponents.month,
              let anchorDay = anchorComponents.day
        else {
            return nil
        }
        let (monthIndex, indexOverflow) = (anchorMonth - 1)
            .addingReportingOverflow(monthOffset)
        guard !indexOverflow else {
            return nil
        }
        let targetYearOffset = monthIndex / 12
        let (targetYear, yearOverflow) = anchorYear.addingReportingOverflow(
            targetYearOffset
        )
        guard !yearOverflow else {
            return nil
        }
        let targetMonth = monthIndex % 12 + 1
        anchorComponents.year = targetYear
        anchorComponents.month = targetMonth
        anchorComponents.day = 1
        guard let firstOfTargetMonth = calendar.date(from: anchorComponents),
              let dayRange = calendar.range(
                  of: .day,
                  in: .month,
                  for: firstOfTargetMonth
              )
        else {
            return nil
        }
        anchorComponents.day = min(anchorDay, dayRange.count)
        return calendar.date(from: anchorComponents)
    }

    struct RawSpendingInsightItem {
        let id: String
        let subscriptionID: UUID
        let serviceName: String
        let category: String
        let date: Date
        let amount: Money
    }

    struct InsightsRequest {
        let mode: SpendingReportMode
        let from: Date
        let through: Date
    }

    struct ExpectedChargesRequest {
        let subscriptionID: UUID
        let horizon: Date
        let maximumCount: Int
    }

    struct UpcomingTimelineRequest {
        let from: Date
        let through: Date
    }
}
