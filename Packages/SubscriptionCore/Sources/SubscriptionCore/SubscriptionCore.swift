import Foundation
import Observation

public enum Currency: String, CaseIterable, Codable, Hashable, Sendable {
    case cny = "CNY"
    case usd = "USD"
    case eur = "EUR"
}

public struct Money: Codable, Equatable, Sendable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }
}

public struct ServiceIdentity: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ExpectedCharge: Codable, Equatable, Sendable {
    public let id: ScheduledChargeID
    public let subscriptionID: UUID
    public let scheduledDate: Date
    public let amount: Money

    public init(
        id: ScheduledChargeID,
        subscriptionID: UUID,
        scheduledDate: Date,
        amount: Money
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.scheduledDate = scheduledDate
        self.amount = amount
    }
}

public struct UpcomingTimelineItem: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case expected
        case confirmed
    }

    public let id: String
    public let kind: Kind
    public let subscriptionID: UUID
    public let serviceName: String
    public let date: Date
    public let amount: Money

    public init(
        id: String,
        kind: Kind,
        subscriptionID: UUID,
        serviceName: String,
        date: Date,
        amount: Money
    ) {
        self.id = id
        self.kind = kind
        self.subscriptionID = subscriptionID
        self.serviceName = serviceName
        self.date = date
        self.amount = amount
    }
}

public enum SubscriptionHistoryEntry: Equatable, Sendable {
    case expected(ExpectedCharge)
    case confirmed(ConfirmedCharge)
    case priceChange(PriceChange)
}

public enum PaymentHistoryActionError: Equatable, Sendable {
    case archivedSubscription
    case invalidScheduledOccurrence
    case scheduledDateInFuture
    case chargedDateInFuture
    case effectiveDateBeforeStart
    case duplicatePriceChangeDay
    case mustBePositive
    case persistenceFailed
}

public struct Subscription: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let serviceIdentity: ServiceIdentity
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money
    public let billingSchedule: FixedBillingSchedule
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String
    public let confirmedCharges: [ConfirmedCharge]
    public let priceChanges: [PriceChange]
    public let lifecycle: SubscriptionLifecycle
    public let isArchived: Bool

    public var billingCycle: BillingInterval {
        billingSchedule.interval
    }

    public init(
        id: UUID,
        serviceIdentity: ServiceIdentity,
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money,
        billingSchedule: FixedBillingSchedule,
        startDate: Date,
        confirmedNextRenewal: Date? = nil,
        managementURL: URL?,
        notes: String,
        confirmedCharges: [ConfirmedCharge] = [],
        priceChanges: [PriceChange] = [],
        lifecycle: SubscriptionLifecycle = .active,
        isArchived: Bool = false
    ) {
        self.id = id
        self.serviceIdentity = serviceIdentity
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.billingSchedule = billingSchedule
        self.startDate = startDate
        self.confirmedNextRenewal =
            confirmedNextRenewal ?? billingSchedule.renewalAnchor
        self.managementURL = managementURL
        self.notes = notes
        self.confirmedCharges = confirmedCharges
        self.priceChanges = priceChanges
        self.lifecycle = lifecycle
        self.isArchived = isArchived
    }

    public init(
        id: UUID,
        serviceIdentity: ServiceIdentity,
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money,
        billingCycle: BillingInterval,
        startDate: Date,
        confirmedNextRenewal: Date,
        billingTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        managementURL: URL?,
        notes: String,
        confirmedCharges: [ConfirmedCharge] = [],
        priceChanges: [PriceChange] = [],
        lifecycle: SubscriptionLifecycle = .active,
        isArchived: Bool = false
    ) {
        self.init(
            id: id,
            serviceIdentity: serviceIdentity,
            serviceName: serviceName,
            plan: plan,
            category: category,
            originalAmount: originalAmount,
            billingSchedule: FixedBillingSchedule(
                interval: billingCycle,
                renewalAnchor: startDate,
                timeZoneIdentifier: billingTimeZoneIdentifier
            ),
            startDate: startDate,
            confirmedNextRenewal: confirmedNextRenewal,
            managementURL: managementURL,
            notes: notes,
            confirmedCharges: confirmedCharges,
            priceChanges: priceChanges,
            lifecycle: lifecycle,
            isArchived: isArchived
        )
    }
}

public struct SubscriptionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let serviceIdentity: ServiceIdentity
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money
    public let billingSchedule: FixedBillingSchedule
    public let confirmedNextRenewal: Date
    public let status: SubscriptionStatus
    public let nextExpectedCharge: ExpectedCharge?

    public init(
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    ) {
        id = subscription.id
        serviceIdentity = subscription.serviceIdentity
        serviceName = subscription.serviceName
        plan = subscription.plan
        category = subscription.category
        originalAmount = subscription.originalAmount
        billingSchedule = subscription.billingSchedule
        confirmedNextRenewal = subscription.confirmedNextRenewal
        self.status = status
        self.nextExpectedCharge = nextExpectedCharge
    }
}

public struct SubscriptionCreationInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money?
    public let billingInterval: BillingInterval
    public let startDate: Date
    public let renewalAnchor: Date
    public let confirmedNextRenewal: Date
    public let billingTimeZoneIdentifier: String
    public let managementURL: URL?
    public let notes: String
    public let initialStatus: SubscriptionInitialStatus

    public init(
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money?,
        billingInterval: BillingInterval = .monthly,
        startDate: Date,
        renewalAnchor: Date? = nil,
        confirmedNextRenewal: Date,
        billingTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        managementURL: URL?,
        notes: String,
        initialStatus: SubscriptionInitialStatus = .active
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.billingInterval = billingInterval
        self.startDate = startDate
        self.renewalAnchor = renewalAnchor ?? startDate
        self.confirmedNextRenewal = confirmedNextRenewal
        self.billingTimeZoneIdentifier = billingTimeZoneIdentifier
        self.managementURL = managementURL
        self.notes = notes
        self.initialStatus = initialStatus
    }
}

@available(*, deprecated, renamed: "SubscriptionCreationInput")
public typealias MonthlySubscriptionCreationInput = SubscriptionCreationInput

public struct SubscriptionEditInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let billingSchedule: FixedBillingSchedule
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String

    public init(
        serviceName: String,
        plan: String,
        category: String,
        billingSchedule: FixedBillingSchedule,
        startDate: Date,
        confirmedNextRenewal: Date? = nil,
        managementURL: URL?,
        notes: String
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.billingSchedule = billingSchedule
        self.startDate = startDate
        self.confirmedNextRenewal =
            confirmedNextRenewal ?? billingSchedule.renewalAnchor
        self.managementURL = managementURL
        self.notes = notes
    }

    @available(*, deprecated, message: "Use recordPriceChange to change money")
    public init(
        serviceName: String,
        plan: String,
        category: String,
        originalAmount _: Money?,
        billingSchedule: FixedBillingSchedule,
        startDate: Date,
        confirmedNextRenewal: Date? = nil,
        managementURL: URL?,
        notes: String
    ) {
        self.init(
            serviceName: serviceName,
            plan: plan,
            category: category,
            billingSchedule: billingSchedule,
            startDate: startDate,
            confirmedNextRenewal: confirmedNextRenewal,
            managementURL: managementURL,
            notes: notes
        )
    }

    public init(
        subscription: Subscription,
        billingSchedule: FixedBillingSchedule
    ) {
        self.init(
            serviceName: subscription.serviceName,
            plan: subscription.plan,
            category: subscription.category,
            billingSchedule: billingSchedule,
            startDate: subscription.startDate,
            confirmedNextRenewal: subscription.confirmedNextRenewal,
            managementURL: subscription.managementURL,
            notes: subscription.notes
        )
    }
}

public enum SubscriptionCreationField: Hashable, Sendable {
    case serviceName
    case plan
    case category
    case originalAmount
    case renewalAnchor
    case confirmedNextRenewal
    case billingSchedule
}

public enum SubscriptionCreationValidationError: Equatable, Sendable {
    case required
    case mustBePositive
    case beforeStartDate
}

public enum SubscriptionLibraryScope: Hashable, Sendable {
    case current
    case archived
}

public enum SubscriptionLibraryState: Equatable, Sendable {
    case loading(SubscriptionLibraryScope)
    case empty(SubscriptionLibraryScope)
    case loaded(SubscriptionLibraryScope, [SubscriptionSummary])
    case failed(SubscriptionLibraryScope)
}

public enum SubscriptionTableSort: String, CaseIterable, Codable, Sendable {
    case serviceName
    case plan
    case category
    case nextRenewal
    case amount
}

public struct SubscriptionTableQuery: Equatable, Sendable {
    public let searchText: String
    public let sort: SubscriptionTableSort
    public let ascending: Bool

    public init(
        searchText: String = "",
        sort: SubscriptionTableSort = .serviceName,
        ascending: Bool = true
    ) {
        self.searchText = searchText
        self.sort = sort
        self.ascending = ascending
    }

    public func apply(
        to summaries: [SubscriptionSummary],
        locale: Locale = .current
    ) -> [SubscriptionSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return summaries
            .filter { summary in
                guard !query.isEmpty else { return true }
                return [summary.serviceName, summary.plan, summary.category]
                    .contains {
                        $0.range(
                            of: query,
                            options: [.caseInsensitive, .diacriticInsensitive],
                            range: nil,
                            locale: locale
                        ) != nil
                    }
            }
            .sorted { lhs, rhs in
                let order = comparison(of: lhs, and: rhs, locale: locale)
                if order == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return ascending
                    ? order == .orderedAscending
                    : order == .orderedDescending
            }
    }

    private func comparison(
        of lhs: SubscriptionSummary,
        and rhs: SubscriptionSummary,
        locale: Locale
    ) -> ComparisonResult {
        switch sort {
        case .serviceName:
            return lhs.serviceName.localizedCompare(rhs.serviceName)
        case .plan:
            return lhs.plan.localizedCompare(rhs.plan)
        case .category:
            return lhs.category.localizedCompare(rhs.category)
        case .nextRenewal:
            return lhs.confirmedNextRenewal.compare(rhs.confirmedNextRenewal)
        case .amount:
            let currencyOrder = lhs.originalAmount.currency.rawValue
                .localizedCompare(rhs.originalAmount.currency.rawValue)
            if currencyOrder != .orderedSame {
                return currencyOrder
            } else if lhs.originalAmount.minorUnits == rhs.originalAmount.minorUnits {
                return .orderedSame
            } else {
                return lhs.originalAmount.minorUnits < rhs.originalAmount.minorUnits
                    ? .orderedAscending
                    : .orderedDescending
            }
        }
    }
}

public enum SubscriptionDetailState: Equatable, Sendable {
    case notLoaded
    case loaded(
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    )
    case notFound
    case failed
}

@MainActor
public protocol SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws
    func updateSubscription(_ subscription: Subscription) throws
    func deleteSubscription(id: UUID) throws
    func listSubscriptions() throws -> [Subscription]
    func subscription(id: UUID) throws -> Subscription?
}

public enum LibrarySyncStatus: Equatable, Sendable {
    case notLoaded
    case localOnly
    case synchronizing
    case current
    case signedOut
    case requiresAttention
}

public protocol LibrarySyncMonitor: Sendable {
    func refreshStatus() async -> LibrarySyncStatus
}

@MainActor
@Observable
public final class SubscriptionWorkspace {
    public private(set) var libraryState: SubscriptionLibraryState =
        .loading(.current)
    public private(set) var detailState: SubscriptionDetailState = .notLoaded
    public private(set) var creationValidationErrors:
        [SubscriptionCreationField: SubscriptionCreationValidationError] = [:]
    public private(set) var editingValidationErrors:
        [SubscriptionCreationField: SubscriptionCreationValidationError] = [:]
    public private(set) var expectedCharges: [ExpectedCharge]?
    public private(set) var upcomingTimeline: [UpcomingTimelineItem] = []
    public private(set) var calendarProjection: [CalendarProjectionEvent] = []
    public private(set) var lifecycleActionError:
        SubscriptionLifecycleActionError?
    public private(set) var paymentHistoryActionError:
        PaymentHistoryActionError?
    public private(set) var paymentHistory: [SubscriptionHistoryEntry] = []
    public private(set) var catalogState: CatalogState = .notLoaded
    public private(set) var catalogDiagnostics: CatalogDiagnostics?
    public private(set) var setupState: SetupState = .notLoaded
    public private(set) var exchangeRateStatus: ExchangeRateStatus = .notLoaded
    public private(set) var insightsState: SpendingInsightsState = .notLoaded
    public private(set) var syncStatus: LibrarySyncStatus = .notLoaded

    private let repository: any SubscriptionRepository
    private let preferencesRepository: (any UserPreferencesRepository)?
    private let catalogRepository: (any CatalogRepository)?
    private let catalogUpdateSource: (any CatalogUpdateSource)?
    private let catalogCache: (any CatalogCache)?
    private let exchangeRateSource: (any ExchangeRateSource)?
    private let exchangeRateCache: (any ExchangeRateCache)?
    private let syncMonitor: (any LibrarySyncMonitor)?
    private let identifierGenerator: () -> UUID
    private let now: () -> Date
    private let calendar: Calendar
    private var expectedChargesRequest: ExpectedChargesRequest?
    private var insightsRequest: InsightsRequest?
    private var catalogSnapshot: CatalogSnapshot?
    private var catalogLocale = Locale.current
    private var catalogSearchQuery = ""
    private var catalogCategoryID: String?

    public init(
        repository: any SubscriptionRepository,
        preferencesRepository: (any UserPreferencesRepository)? = nil,
        catalogRepository: (any CatalogRepository)? = nil,
        catalogUpdateSource: (any CatalogUpdateSource)? = nil,
        catalogCache: (any CatalogCache)? = nil,
        exchangeRateSource: (any ExchangeRateSource)? = nil,
        exchangeRateCache: (any ExchangeRateCache)? = nil,
        syncMonitor: (any LibrarySyncMonitor)? = nil,
        identifierGenerator: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar? = nil
    ) {
        self.repository = repository
        self.preferencesRepository = preferencesRepository
        self.catalogRepository = catalogRepository
        self.catalogUpdateSource = catalogUpdateSource
        self.catalogCache = catalogCache
        self.exchangeRateSource = exchangeRateSource
        self.exchangeRateCache = exchangeRateCache
        self.syncMonitor = syncMonitor
        self.identifierGenerator = identifierGenerator
        self.now = now
        self.calendar = calendar ?? Self.defaultRenewalCalendar()
    }

    public func refreshSyncStatus() async {
        syncStatus = await syncMonitor?.refreshStatus() ?? .localOnly
    }

    private func markLocalChangesForSync() {
        switch syncStatus {
        case .current, .synchronizing:
            syncStatus = .synchronizing
        case .notLoaded, .localOnly, .signedOut, .requiresAttention:
            break
        }
    }

    public func loadSetup(libraryIsEmpty: Bool) {
        let fallback = UserPreferences.default
        do {
            let storedPreferences = try preferencesRepository?.loadPreferences()
            guard let preferences = storedPreferences else {
                setupState = libraryIsEmpty
                    ? .needsSetup(fallback)
                    : .completed(fallback)
                return
            }
            switch preferences.setupStatus {
            case .notCompleted:
                setupState = .needsSetup(preferences)
            case .completed:
                setupState = .completed(preferences)
            case .skipped:
                setupState = .skipped(preferences)
            }
        } catch {
            setupState = .failed(fallback)
        }
    }

    public func updatePreferences(
        primaryCurrency: Currency,
        calendarProjectionHorizon: CalendarProjectionHorizon,
        hideAmountsInCalendar: Bool? = nil
    ) {
        persistPreferences(
            UserPreferences(
                primaryCurrency: primaryCurrency,
                calendarProjectionHorizon: calendarProjectionHorizon,
                hideAmountsInCalendar: hideAmountsInCalendar
                    ?? currentPreferences.hideAmountsInCalendar,
                setupStatus: currentPreferences.setupStatus
            )
        )
        reloadInsightsIfNeeded()
    }

    public func completeSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                setupStatus: .completed
            )
        )
    }

    public func skipSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
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
                setupStatus: .notCompleted
            ),
            stateOnSuccess: { .needsSetup($0) }
        )
    }

    private var currentPreferences: UserPreferences {
        switch setupState {
        case .notLoaded:
            .default
        case .needsSetup(let preferences),
             .completed(let preferences),
             .skipped(let preferences),
             .failed(let preferences):
            preferences
        }
    }

    private func persistPreferences(
        _ preferences: UserPreferences,
        stateOnSuccess: ((UserPreferences) -> SetupState)? = nil
    ) {
        do {
            try preferencesRepository?.savePreferences(preferences)
            if preferencesRepository != nil {
                markLocalChangesForSync()
            }
            setupState = stateOnSuccess?(preferences)
                ?? setupState(for: preferences)
        } catch {
            setupState = .failed(currentPreferences)
        }
    }

    private func setupState(for preferences: UserPreferences) -> SetupState {
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    public func refreshExchangeRates() async {
        let cachedState = try? exchangeRateCache?.loadState()
        if let cachedState,
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

        guard let exchangeRateSource else {
            exchangeRateStatus = cachedState?.snapshot.map(
                ExchangeRateStatus.stale
            ) ?? .unavailable
            return
        }

        let subscriptions = (try? repository.listSubscriptions()) ?? []
        let quotes = Set(subscriptions.map(\.originalAmount.currency))
            .union([currentPreferences.primaryCurrency])
            .subtracting([.eur])
        let attemptedAt = now()
        do {
            let snapshot = try await exchangeRateSource.fetchRates(
                base: .eur,
                quotes: quotes
            )
            let state = ExchangeRateCacheState(
                snapshot: snapshot,
                lastAttemptAt: attemptedAt
            )
            try? exchangeRateCache?.saveState(state)
            exchangeRateStatus = .fresh(snapshot)
        } catch {
            let state = ExchangeRateCacheState(
                snapshot: cachedState?.snapshot,
                lastAttemptAt: attemptedAt
            )
            try? exchangeRateCache?.saveState(state)
            exchangeRateStatus = cachedState?.snapshot.map(
                ExchangeRateStatus.stale
            ) ?? .unavailable
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

    private var currentExchangeRateSnapshot: ExchangeRateSnapshot? {
        switch exchangeRateStatus {
        case .fresh(let snapshot), .stale(let snapshot): snapshot
        case .notLoaded, .unavailable: nil
        }
    }

    private func reloadInsightsIfNeeded() {
        guard let insightsRequest else { return }
        loadInsights(
            mode: insightsRequest.mode,
            from: insightsRequest.from,
            through: insightsRequest.through
        )
    }

    private func makeInsights(
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
            calendar.dateComponents([.day], from: from, to: through).day ?? 0
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

    private func makeSpendingInsightItems(
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

    public func createSubscription(
        _ input: SubscriptionCreationInput
    ) {
        createSubscription(input) { id in
            ServiceIdentity(rawValue: "manual:\(id.uuidString)")
        }
    }

    public func loadCatalog(locale: Locale) {
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

    public func refreshCatalog() async {
        guard let catalogRepository,
              let catalogUpdateSource,
              let catalogCache
        else {
            return
        }

        do {
            let activeSnapshot: CatalogSnapshot
            if let catalogSnapshot {
                activeSnapshot = catalogSnapshot
            } else {
                activeSnapshot = try catalogRepository.loadSnapshot()
            }
            let data = try await catalogUpdateSource.fetchCatalogData()
            let candidate = try JSONDecoder().decode(
                CatalogSnapshot.self,
                from: data
            )
            guard candidate.catalogVersion > activeSnapshot.catalogVersion else {
                catalogDiagnostics = CatalogDiagnostics(
                    source: catalogRepository.catalogSource,
                    version: activeSnapshot.catalogVersion,
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
            if let catalogSnapshot {
                catalogDiagnostics = CatalogDiagnostics(
                    source: catalogRepository.catalogSource,
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

    public func createCatalogSubscription(
        presetID: String,
        input: SubscriptionCreationInput
    ) {
        guard catalogSnapshot?.presets.contains(where: {
            $0.id == presetID
        }) == true else {
            return
        }
        createSubscription(input) { _ in
            ServiceIdentity(rawValue: "catalog:\(presetID)")
        }
    }

    private func createSubscription(
        _ input: SubscriptionCreationInput,
        serviceIdentity: (UUID) -> ServiceIdentity
    ) {
        creationValidationErrors = validate(input)
        guard creationValidationErrors.isEmpty,
              let originalAmount = input.originalAmount
        else {
            return
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        let id = identifierGenerator()
        let lifecycle: SubscriptionLifecycle =
            input.initialStatus == .trial
                ? .trial(firstPaidChargeAt: input.confirmedNextRenewal)
                : .active
        let subscription = Subscription(
            id: id,
            serviceIdentity: serviceIdentity(id),
            serviceName: input.serviceName.trimmingCharacters(in: whitespace),
            plan: input.plan.trimmingCharacters(in: whitespace),
            category: input.category.trimmingCharacters(in: whitespace),
            originalAmount: originalAmount,
            billingSchedule: FixedBillingSchedule(
                interval: input.billingInterval,
                renewalAnchor: input.renewalAnchor,
                timeZoneIdentifier: input.billingTimeZoneIdentifier
            ),
            startDate: input.startDate,
            confirmedNextRenewal: input.confirmedNextRenewal,
            managementURL: input.managementURL,
            notes: input.notes,
            lifecycle: lifecycle,
            isArchived: false
        )

        do {
            try repository.createSubscription(subscription)
            markLocalChangesForSync()
            detailState = makeDetail(subscription)
            loadLibrary()
        } catch {
            detailState = .failed
        }
    }

    @available(*, deprecated, renamed: "createSubscription")
    public func createMonthlySubscription(
        _ input: SubscriptionCreationInput
    ) {
        createSubscription(input)
    }

    public func editSubscription(
        id: UUID,
        input: SubscriptionEditInput,
        forecastThrough: Date? = nil
    ) {
        editingValidationErrors = validate(input)
        guard editingValidationErrors.isEmpty else {
            return
        }

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            let whitespace = CharacterSet.whitespacesAndNewlines
            let edited = Subscription(
                id: existing.id,
                serviceIdentity: existing.serviceIdentity,
                serviceName: input.serviceName.trimmingCharacters(
                    in: whitespace
                ),
                plan: input.plan.trimmingCharacters(in: whitespace),
                category: input.category.trimmingCharacters(in: whitespace),
                originalAmount: existing.originalAmount,
                billingSchedule: input.billingSchedule,
                startDate: input.startDate,
                confirmedNextRenewal: input.confirmedNextRenewal,
                managementURL: input.managementURL,
                notes: input.notes,
                confirmedCharges: existing.confirmedCharges,
                priceChanges: existing.priceChanges,
                lifecycle: existing.lifecycle,
                isArchived: existing.isArchived
            )
            try repository.updateSubscription(edited)
            markLocalChangesForSync()
            detailState = makeDetail(edited)
            loadLibrary()
            let forecastRequest = forecastThrough.map {
                ExpectedChargesRequest(
                    subscriptionID: id,
                    horizon: $0,
                    maximumCount: .max
                )
            } ?? expectedChargesRequest
            if let forecastRequest,
               forecastRequest.subscriptionID == id
            {
                expectedCharges = makeExpectedCharges(
                    for: edited,
                    through: forecastRequest.horizon,
                    maximumCount: forecastRequest.maximumCount
                )
                expectedChargesRequest = forecastRequest
            }
        } catch {
            detailState = .failed
        }
    }

    public func recordCancellation(
        id: UUID,
        cancelledAt: Date,
        accessUntil: Date
    ) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }
            switch existing.lifecycle {
            case .trial, .active:
                break
            case .cancelled:
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            let cancellationDay = localCalendar.startOfDay(for: cancelledAt)
            let accessUntilDay = localCalendar.startOfDay(for: accessUntil)
            let today = localCalendar.startOfDay(for: now())
            guard cancellationDay <= today else {
                lifecycleActionError = .cancellationDateInFuture
                return
            }
            guard accessUntilDay >= cancellationDay else {
                lifecycleActionError = .accessEndsBeforeCancellation
                return
            }
            guard let normalizedCancellation = normalizedBillingLocalNoon(
                cancelledAt,
                timeZone: timeZone
            ),
            let normalizedAccessUntil = normalizedBillingLocalNoon(
                accessUntil,
                timeZone: timeZone
            ) else {
                lifecycleActionError = .persistenceFailed
                return
            }

            let updated = existing.replacingLifecycleFacts(
                lifecycle: .cancelled(
                    cancelledAt: normalizedCancellation,
                    accessUntil: normalizedAccessUntil
                )
            )
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }

    public func confirmCharge(
        id: UUID,
        scheduledDate: Date,
        chargedDate: Date,
        amount: Money
    ) {
        paymentHistoryActionError = nil
        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                paymentHistoryActionError = .archivedSubscription
                return
            }
            switch existing.lifecycle {
            case .trial, .active:
                break
            case .cancelled:
                paymentHistoryActionError = .invalidScheduledOccurrence
                return
            }

            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            let today = localCalendar.startOfDay(for: now())
            guard amount.minorUnits > 0 else {
                paymentHistoryActionError = .mustBePositive
                return
            }
            guard let normalizedScheduledDate = normalizedBillingLocalNoon(
                      scheduledDate,
                      timeZone: timeZone
                  ),
                  let normalizedChargedDate = normalizedBillingLocalNoon(
                      chargedDate,
                      timeZone: timeZone
                  ),
                  localCalendar.startOfDay(for: normalizedScheduledDate)
                    <= today
            else {
                paymentHistoryActionError = .scheduledDateInFuture
                return
            }
            guard localCalendar.startOfDay(for: normalizedChargedDate)
                <= today
            else {
                paymentHistoryActionError = .chargedDateInFuture
                return
            }
            guard isScheduledOccurrence(
                normalizedScheduledDate,
                for: existing,
                calendar: localCalendar
            ) else {
                paymentHistoryActionError = .invalidScheduledOccurrence
                return
            }

            let components = localCalendar.dateComponents(
                [.year, .month, .day],
                from: normalizedScheduledDate
            )
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day
            else {
                return
            }
            let sourceScheduledChargeID = ScheduledChargeID(
                subscriptionID: existing.id,
                year: year,
                month: month,
                day: day
            )
            guard !existing.confirmedCharges.contains(where: {
                $0.sourceScheduledChargeID == sourceScheduledChargeID
            }) else {
                detailState = makeDetail(existing)
                return
            }

            let updated = existing.replacingPaymentHistory(
                confirmedCharges: existing.confirmedCharges + [
                    ConfirmedCharge(
                        id: identifierGenerator(),
                        chargedDate: normalizedChargedDate,
                        amount: amount,
                        sourceScheduledChargeID: sourceScheduledChargeID
                    )
                ]
            )
            try repository.updateSubscription(updated)
            markLocalChangesForSync()
            detailState = makeDetail(updated)
            loadLibrary()
        } catch {
            paymentHistoryActionError = .persistenceFailed
            detailState = .failed
        }
    }

    public func recordPriceChange(
        id: UUID,
        effectiveDate: Date,
        amount: Money
    ) {
        paymentHistoryActionError = nil
        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                paymentHistoryActionError = .archivedSubscription
                return
            }
            guard amount.minorUnits > 0 else {
                paymentHistoryActionError = .mustBePositive
                return
            }
            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            guard let normalizedEffectiveDate = normalizedBillingLocalNoon(
                effectiveDate,
                timeZone: timeZone
            ) else {
                paymentHistoryActionError = .persistenceFailed
                return
            }
            guard normalizedEffectiveDate >= localCalendar.startOfDay(
                for: existing.startDate
            ) else {
                paymentHistoryActionError = .effectiveDateBeforeStart
                return
            }
            guard !existing.priceChanges.contains(where: {
                localCalendar.isDate(
                    $0.effectiveDate,
                    inSameDayAs: normalizedEffectiveDate
                )
            }) else {
                paymentHistoryActionError = .duplicatePriceChangeDay
                return
            }
            let updated = existing.replacingPaymentHistory(
                priceChanges: existing.priceChanges + [
                    PriceChange(
                        id: identifierGenerator(),
                        effectiveDate: normalizedEffectiveDate,
                        amount: amount
                    )
                ]
            )
            try repository.updateSubscription(updated)
            markLocalChangesForSync()
            detailState = makeDetail(updated)
            loadLibrary()
        } catch {
            paymentHistoryActionError = .persistenceFailed
            detailState = .failed
        }
    }

    public func reactivate(id: UUID, nextRenewal: Date) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived,
                  case .cancelled = existing.lifecycle
            else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            let renewalDay = localCalendar.startOfDay(for: nextRenewal)
            let today = localCalendar.startOfDay(for: now())
            guard renewalDay >= today else {
                lifecycleActionError = .nextRenewalInPast
                return
            }
            guard let normalizedRenewal = normalizedBillingLocalNoon(
                nextRenewal,
                timeZone: timeZone
            ) else {
                lifecycleActionError = .persistenceFailed
                return
            }

            let updated = existing.replacingLifecycleFacts(
                lifecycle: .active,
                confirmedNextRenewal: normalizedRenewal
            )
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }

    public func archive(id: UUID) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let updated = existing.replacingLifecycleFacts(isArchived: true)
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }

    public func restore(id: UUID) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard existing.isArchived else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let updated = existing.replacingLifecycleFacts(isArchived: false)
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }

    public func deletePermanently(id: UUID) {
        lifecycleActionError = nil

        do {
            guard try repository.subscription(id: id) != nil else {
                detailState = .notFound
                return
            }

            let scope = carriedLibraryScope
            let clearsExpectedCharges =
                expectedChargesRequest?.subscriptionID == id
            let refreshedExpectedCharges: [ExpectedCharge]? =
                clearsExpectedCharges ? nil : expectedCharges
            try repository.deleteSubscription(id: id)
            markLocalChangesForSync()

            detailState = .notFound
            expectedCharges = refreshedExpectedCharges
            if clearsExpectedCharges {
                expectedChargesRequest = nil
            }
            loadLibrary(scope: scope)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }

    public func loadLibrary(
        scope: SubscriptionLibraryScope = .current
    ) {
        libraryState = .loading(scope)
        do {
            libraryState = try makeLibraryState(scope: scope)
        } catch {
            libraryState = .failed(scope)
        }
    }

    public func clearLifecycleActionError() {
        lifecycleActionError = nil
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
            }
        } catch {
            detailState = .failed
        }
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
        guard from <= through else {
            upcomingTimeline = []
            return
        }

        do {
            let subscriptions = try repository.listSubscriptions()
            upcomingTimeline = subscriptions.flatMap { subscription in
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
        } catch {
            upcomingTimeline = []
        }
    }

    public func loadCalendarProjection(locale: Locale) {
        let horizon = calendar.date(
            byAdding: .month,
            value: currentPreferences.calendarProjectionHorizon.rawValue,
            to: now()
        ) ?? now()
        do {
            calendarProjection = try repository.listSubscriptions()
                .flatMap { subscription in
                    makeCalendarProjectionEvents(
                        for: subscription,
                        through: horizon,
                        locale: locale,
                        hidesAmounts: currentPreferences.hideAmountsInCalendar
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.startDate != rhs.startDate {
                        return lhs.startDate < rhs.startDate
                    }
                    return lhs.uid < rhs.uid
                }
        } catch {
            calendarProjection = []
        }
    }

    private func validate(
        _ input: SubscriptionCreationInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.plan.trimmingCharacters(in: whitespace).isEmpty {
            errors[.plan] = .required
        }
        if input.category.trimmingCharacters(in: whitespace).isEmpty {
            errors[.category] = .required
        }
        if let originalAmount = input.originalAmount {
            if originalAmount.minorUnits <= 0 {
                errors[.originalAmount] = .mustBePositive
            }
        } else {
            errors[.originalAmount] = .required
        }
        if input.confirmedNextRenewal < input.startDate {
            errors[.confirmedNextRenewal] = .beforeStartDate
        }
        if input.renewalAnchor < input.startDate {
            errors[.renewalAnchor] = .beforeStartDate
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

    private func validate(
        _ input: SubscriptionEditInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.plan.trimmingCharacters(in: whitespace).isEmpty {
            errors[.plan] = .required
        }
        if input.category.trimmingCharacters(in: whitespace).isEmpty {
            errors[.category] = .required
        }
        if input.billingSchedule.renewalAnchor < input.startDate {
            errors[.renewalAnchor] = .beforeStartDate
        }
        if input.confirmedNextRenewal < input.startDate {
            errors[.confirmedNextRenewal] = .beforeStartDate
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

    private func billingTimeZone(
        for subscription: Subscription
    ) -> TimeZone {
        TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
    }

    private func finishLifecycleUpdate(
        _ subscription: Subscription
    ) {
        markLocalChangesForSync()
        let scope = carriedLibraryScope
        let refreshedDetailState = makeDetail(subscription)
        let refreshedExpectedCharges: [ExpectedCharge]? =
            if let request = expectedChargesRequest,
               request.subscriptionID == subscription.id
            {
                makeExpectedCharges(
                    for: subscription,
                    through: request.horizon,
                    maximumCount: request.maximumCount
                )
            } else {
                expectedCharges
            }

        detailState = refreshedDetailState
        expectedCharges = refreshedExpectedCharges
        loadLibrary(scope: scope)
    }

    private func makeLibraryState(
        scope: SubscriptionLibraryScope
    ) throws -> SubscriptionLibraryState {
        let subscriptions = try repository.listSubscriptions()
            .filter { $0.isArchived == (scope == .archived) }
        let summaries = subscriptions.map(makeSummary)
        return summaries.isEmpty
            ? .empty(scope)
            : .loaded(scope, summaries)
    }

    private var carriedLibraryScope: SubscriptionLibraryScope {
        switch libraryState {
        case .loading(let scope),
             .empty(let scope),
             .loaded(let scope, _),
             .failed(let scope):
            scope
        }
    }

    private func refreshCatalogState() {
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

    private func makeExpectedCharges(
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
        let currentDate = now()
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

    private func makeUpcomingTimelineItems(
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
            through: through,
            maximumCount: .max
        )
        .filter { $0.scheduledDate >= from }
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

    private func makeCalendarProjectionEvents(
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

    private func formattedCalendarAmount(
        _ money: Money,
        locale: Locale
    ) -> String {
        (Decimal(money.minorUnits) / 100).formatted(
            .currency(code: money.currency.rawValue).locale(locale)
        )
    }

    private func expectedCharge(
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
        let scheduledDay = calendar.startOfDay(for: scheduledDate)
        let amount = subscription.priceChanges
            .filter {
                calendar.startOfDay(for: $0.effectiveDate) <= scheduledDay
            }
            .max { $0.effectiveDate < $1.effectiveDate }?
            .amount ?? subscription.originalAmount
        return ExpectedCharge(
            id: id,
            subscriptionID: subscription.id,
            scheduledDate: scheduledDate,
            amount: amount
        )
    }

    private func isScheduledOccurrence(
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

    private func makeSummary(
        _ subscription: Subscription
    ) -> SubscriptionSummary {
        let presentation = makePresentation(for: subscription)
        return SubscriptionSummary(
            subscription: subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }

    private func makeDetail(
        _ subscription: Subscription
    ) -> SubscriptionDetailState {
        let presentation = makePresentation(for: subscription)
        paymentHistory = makeHistory(for: subscription)
        return .loaded(
            subscription: subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }

    private func makeHistory(
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
            let missed = (candidateIndex...(candidateIndex + 1)).compactMap {
                scheduledDate(
                    for: subscription.billingSchedule,
                    occurrenceIndex: $0,
                    calendar: localCalendar
                )
            }
            .filter {
                let occurrenceDay = localCalendar.startOfDay(for: $0)
                return occurrenceDay >= localCalendar.startOfDay(
                    for: subscription.startDate
                ) && occurrenceDay <= today
            }
            .map {
                expectedCharge(
                    for: subscription,
                    scheduledDate: $0,
                    calendar: localCalendar
                )
            }
            .filter { charge in
                !subscription.confirmedCharges.contains {
                    $0.sourceScheduledChargeID == charge.id
                }
            }
            .max { $0.scheduledDate < $1.scheduledDate }
            if let missed {
                entries.append(.expected(missed))
            }

            let tomorrow = localCalendar.date(
                byAdding: .day,
                value: 1,
                to: today
            ) ?? today
            let nextIndex = estimatedOccurrenceIndex(
                for: subscription.billingSchedule,
                onOrAfter: tomorrow,
                calendar: localCalendar
            )
            let next = (nextIndex...(nextIndex + 2)).compactMap {
                scheduledDate(
                    for: subscription.billingSchedule,
                    occurrenceIndex: $0,
                    calendar: localCalendar
                )
            }
            .filter { $0 >= tomorrow }
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
            return left.date == right.date
                ? left.kindOrder < right.kindOrder
                : left.date < right.date
        }
    }

    private func historySortKey(
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

    private func makePresentation(
        for subscription: Subscription
    ) -> (
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
        let nextExpectedCharge = makeExpectedCharges(
            for: subscription,
            through: .distantFuture,
            maximumCount: 1
        ).first
        return (status, nextExpectedCharge)
    }

    private func isEligibleForExpectedCharges(
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

    private func estimatedOccurrenceIndex(
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

    private func estimatedDayOccurrenceIndex(
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

    private func estimatedMonthOccurrenceIndex(
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

    private func scheduledDate(
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

    private func dayBasedDate(
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

    private func monthBasedDate(
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

    private struct RawSpendingInsightItem {
        let id: String
        let subscriptionID: UUID
        let serviceName: String
        let category: String
        let date: Date
        let amount: Money
    }

    private struct InsightsRequest {
        let mode: SpendingReportMode
        let from: Date
        let through: Date
    }

    private struct ExpectedChargesRequest {
        let subscriptionID: UUID
        let horizon: Date
        let maximumCount: Int
    }
}
