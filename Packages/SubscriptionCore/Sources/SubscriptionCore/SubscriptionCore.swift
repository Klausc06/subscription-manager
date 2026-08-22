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

public struct UpcomingCalendarDay: Equatable, Identifiable, Sendable {
    public let date: Date
    public let items: [UpcomingTimelineItem]

    public var id: Date { date }

    public init(date: Date, items: [UpcomingTimelineItem]) {
        self.date = date
        self.items = items
    }
}

/// A presentation-ready month slice of an existing Upcoming timeline. This
/// groups already-resolved charge facts; it does not query persistence or
/// generate billing recurrences.
public struct UpcomingCalendarProjection: Equatable, Sendable {
    public let monthStart: Date
    public let days: [UpcomingCalendarDay]

    public init(
        monthContaining date: Date,
        items: [UpcomingTimelineItem],
        calendar: Calendar
    ) {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date)
        else {
            monthStart = calendar.startOfDay(for: date)
            days = []
            return
        }

        monthStart = monthInterval.start
        let grouped = Dictionary(grouping: items.filter {
            monthInterval.contains($0.date)
        }) { item in
            calendar.startOfDay(for: item.date)
        }
        days = grouped
            .map { date, items in
                UpcomingCalendarDay(
                    date: date,
                    items: items.sorted { lhs, rhs in
                        if lhs.date != rhs.date { return lhs.date < rhs.date }
                        return lhs.id < rhs.id
                    }
                )
            }
            .sorted { $0.date < $1.date }
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

internal enum HistoryOccurrenceSearch {
    /// Returns the newest unconfirmed past occurrence without crossing the
    /// supplied lower bound. Occurrence dates must move earlier as indexes
    /// decrease so the lower-bound check can terminate the search.
    static func firstUnconfirmedPastOccurrence(
        candidateIndex: Int,
        lowerBoundDay: Date,
        todayDay: Date,
        occurrenceAt: (Int) -> Date?,
        day: (Date) -> Date,
        isConfirmed: (Date) -> Bool
    ) -> Date? {
        var nextIndex = candidateIndex == Int.max
            ? candidateIndex
            : candidateIndex + 1
        while nextIndex >= 0 {
            let occurrenceIndex = nextIndex
            nextIndex = occurrenceIndex == 0 ? -1 : occurrenceIndex - 1
            guard let occurrence = occurrenceAt(occurrenceIndex) else {
                continue
            }
            let occurrenceDay = day(occurrence)
            guard occurrenceDay >= lowerBoundDay else {
                return nil
            }
            guard occurrenceDay <= todayDay,
                  !isConfirmed(occurrence)
            else {
                continue
            }
            return occurrence
        }
        return nil
    }
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
    public let pinnedAt: Date?

    public var billingCycle: BillingInterval {
        billingSchedule.interval
    }

    /// Returns the amount due for the billing-local calendar day containing
    /// `date`, applying the latest applicable price change.
    public func amount(onBillingDay date: Date) -> Money {
        let timeZone = TimeZone(
            identifier: billingSchedule.timeZoneIdentifier
        ) ?? .gmt
        let calendar = billingLocalCalendar(timeZone: timeZone)
        let billingDay = calendar.startOfDay(for: date)
        return priceChanges
            .filter {
                calendar.startOfDay(for: $0.effectiveDate) <= billingDay
            }
            .max { left, right in
                let leftDay = calendar.startOfDay(for: left.effectiveDate)
                let rightDay = calendar.startOfDay(for: right.effectiveDate)
                if leftDay == rightDay {
                    return left.id.uuidString < right.id.uuidString
                }
                return leftDay < rightDay
            }?
            .amount ?? originalAmount
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
        isArchived: Bool = false,
        pinnedAt: Date? = nil
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
        self.pinnedAt = pinnedAt
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
        isArchived: Bool = false,
        pinnedAt: Date? = nil
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
            isArchived: isArchived,
            pinnedAt: pinnedAt
        )
    }
}

public struct SubscriptionSummary: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case serviceIdentity
        case serviceName
        case plan
        case category
        case originalAmount
        case amount
        case billingSchedule
        case confirmedNextRenewal
        case status
        case nextExpectedCharge
        case pinnedAt
    }

    public let id: UUID
    public let serviceIdentity: ServiceIdentity
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money
    public let amount: Money
    public let billingSchedule: FixedBillingSchedule
    public let confirmedNextRenewal: Date
    public let status: SubscriptionStatus
    public let nextExpectedCharge: ExpectedCharge?
    public let pinnedAt: Date?

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
        amount = nextExpectedCharge?.amount
            ?? subscription.amount(
                onBillingDay: subscription.confirmedNextRenewal
            )
        billingSchedule = subscription.billingSchedule
        confirmedNextRenewal = subscription.confirmedNextRenewal
        self.status = status
        self.nextExpectedCharge = nextExpectedCharge
        pinnedAt = subscription.pinnedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        serviceIdentity = try container.decode(
            ServiceIdentity.self,
            forKey: .serviceIdentity
        )
        serviceName = try container.decode(String.self, forKey: .serviceName)
        plan = try container.decode(String.self, forKey: .plan)
        category = try container.decode(String.self, forKey: .category)
        originalAmount = try container.decode(
            Money.self,
            forKey: .originalAmount
        )
        amount = try container.decodeIfPresent(Money.self, forKey: .amount)
            ?? originalAmount
        billingSchedule = try container.decode(
            FixedBillingSchedule.self,
            forKey: .billingSchedule
        )
        confirmedNextRenewal = try container.decode(
            Date.self,
            forKey: .confirmedNextRenewal
        )
        status = try container.decode(
            SubscriptionStatus.self,
            forKey: .status
        )
        nextExpectedCharge = try container.decodeIfPresent(
            ExpectedCharge.self,
            forKey: .nextExpectedCharge
        )
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(serviceIdentity, forKey: .serviceIdentity)
        try container.encode(serviceName, forKey: .serviceName)
        try container.encode(plan, forKey: .plan)
        try container.encode(category, forKey: .category)
        try container.encode(originalAmount, forKey: .originalAmount)
        try container.encode(amount, forKey: .amount)
        try container.encode(billingSchedule, forKey: .billingSchedule)
        try container.encode(
            confirmedNextRenewal,
            forKey: .confirmedNextRenewal
        )
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(
            nextExpectedCharge,
            forKey: .nextExpectedCharge
        )
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
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

public enum CatalogBillingIntervalSelection: Equatable, Sendable {
    case official
    case `override`(BillingInterval)
}

public struct CatalogOfferSubscriptionInput: Equatable, Sendable {
    public let offerID: String
    public let actualChargeOverride: Money?
    public let billingIntervalSelection: CatalogBillingIntervalSelection
    public let startDate: Date
    public let renewalAnchor: Date
    public let confirmedNextRenewal: Date
    public let billingTimeZoneIdentifier: String
    public let notes: String
    public let initialStatus: SubscriptionInitialStatus

    public init(
        offerID: String,
        actualChargeOverride: Money?,
        billingIntervalSelection: CatalogBillingIntervalSelection = .official,
        startDate: Date,
        renewalAnchor: Date,
        confirmedNextRenewal: Date,
        billingTimeZoneIdentifier: String,
        notes: String,
        initialStatus: SubscriptionInitialStatus
    ) {
        self.offerID = offerID
        self.actualChargeOverride = actualChargeOverride
        self.billingIntervalSelection = billingIntervalSelection
        self.startDate = startDate
        self.renewalAnchor = renewalAnchor
        self.confirmedNextRenewal = confirmedNextRenewal
        self.billingTimeZoneIdentifier = billingTimeZoneIdentifier
        self.notes = notes
        self.initialStatus = initialStatus
    }
}

public enum CatalogSubscriptionCreationCommand: Equatable, Sendable {
    case verifiedOffer(CatalogOfferSubscriptionInput)
    case legacy(SubscriptionCreationInput)
}

public enum CatalogSubscriptionCreationRejection: Equatable, Sendable {
    case presetNotFound
    case offerNotFound
    case offerRequiresReview
    case verifiedOfferRequired
}

public enum CatalogSubscriptionCreationResult: Equatable, Sendable {
    case created(Subscription)
    case rejected(CatalogSubscriptionCreationRejection)
    case validationFailed
    case persistenceFailed
}

@available(*, deprecated, renamed: "SubscriptionCreationInput")
public typealias MonthlySubscriptionCreationInput = SubscriptionCreationInput

public struct SubscriptionEditInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let amount: Money
    public let billingSchedule: FixedBillingSchedule
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String

    public init(
        serviceName: String,
        plan: String,
        category: String,
        amount: Money,
        billingSchedule: FixedBillingSchedule,
        startDate: Date,
        confirmedNextRenewal: Date? = nil,
        managementURL: URL?,
        notes: String
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.amount = amount
        self.billingSchedule = billingSchedule
        self.startDate = startDate
        self.confirmedNextRenewal =
            confirmedNextRenewal ?? billingSchedule.renewalAnchor
        self.managementURL = managementURL
        self.notes = notes
    }

    public init(
        subscription: Subscription,
        billingSchedule: FixedBillingSchedule
    ) {
        self.init(
            serviceName: subscription.serviceName,
            plan: subscription.plan,
            category: subscription.category,
            amount: subscription.amount(
                onBillingDay: subscription.confirmedNextRenewal
            ),
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

public enum SubscriptionCreationResult: Equatable, Sendable {
    case created(Subscription)
    case validationFailed
    case persistenceFailed
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

public enum UpcomingTimelineState: Equatable, Sendable {
    case notLoaded
    case empty
    case loaded([UpcomingTimelineItem])
    case failed
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
                switch (lhs.pinnedAt, rhs.pinnedAt) {
                case let (left?, right?):
                    if left != right {
                        return left > right
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
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
            let currencyOrder = lhs.amount.currency.rawValue
                .localizedCompare(rhs.amount.currency.rawValue)
            if currencyOrder != .orderedSame {
                return currencyOrder
            } else if lhs.amount.minorUnits == rhs.amount.minorUnits {
                return .orderedSame
            } else {
                return lhs.amount.minorUnits < rhs.amount.minorUnits
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
    public private(set) var upcomingTimelineState: UpcomingTimelineState =
        .notLoaded
    public private(set) var calendarProjection: [CalendarProjectionEvent] = []
    public private(set) var calendarImportState: CalendarImportState =
        .notRequested
    public private(set) var calendarReconciliationState:
        CalendarReconciliationState = .notConfigured
    public private(set) var lifecycleActionError:
        SubscriptionLifecycleActionError?
    public private(set) var paymentHistoryActionError:
        PaymentHistoryActionError?
    public private(set) var paymentHistory: [SubscriptionHistoryEntry] = []
    public private(set) var catalogState: CatalogState = .notLoaded
    public private(set) var catalogDiagnostics: CatalogDiagnostics?
    public private(set) var catalogReconciliationError:
        CatalogAssociationReconciliationError? = nil
    public private(set) var setupState: SetupState = .notLoaded
    public private(set) var setupRevision: UInt64 = 0
    public private(set) var exchangeRateStatus: ExchangeRateStatus = .notLoaded
    public private(set) var insightsState: SpendingInsightsState = .notLoaded
    public private(set) var syncStatus: LibrarySyncStatus = .notLoaded

    private let repository: any SubscriptionRepository
    private let preferencesRepository: (any UserPreferencesRepository)?
    private let portableBackupImportRepository:
        (any PortableBackupImportRepository)?
    private let widgetSnapshotPublisher: (any WidgetSnapshotPublishing)?
    private let catalogRepository: (any CatalogRepository)?
    private let catalogUpdateSource: (any CatalogUpdateSource)?
    private let catalogCache: (any CatalogCache)?
    private let exchangeRateSource: (any ExchangeRateSource)?
    private let exchangeRateCache: (any ExchangeRateCache)?
    private let syncMonitor: (any LibrarySyncMonitor)?
    private let calendarProjectionImporter: (any CalendarProjectionImporter)?
    private let calendarProjectionReconciler:
        (any CalendarProjectionReconciler)?
    private let identifierGenerator: () -> UUID
    private let now: () -> Date
    private let calendar: Calendar
    private enum SetupPreferencesLoadResult {
        case unknown
        case missing
        case stored
        case failed
    }
    private var setupPreferencesLoadResult: SetupPreferencesLoadResult =
        .unknown
    private enum CalendarReconciliationRequest {
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
    private var expectedChargesRequest: ExpectedChargesRequest?
    private var insightsRequest: InsightsRequest?
    private var upcomingTimelineRequest: UpcomingTimelineRequest?
    private var calendarProjectionLocale: Locale?
    private var pendingCalendarReconciliationRequest:
        CalendarReconciliationRequest?
    private var catalogSnapshot: CatalogSnapshot?
    private var catalogRefreshGeneration: UInt64 = 0
    private var catalogLocale = Locale.current
    private var catalogSearchQuery = ""
    private var catalogCategoryID: String?
    private struct ExchangeRateAttemptKey: Hashable {
        let day: Date
        let quotes: Set<Currency>
    }
    private enum ExchangeRateRefreshError: Error {
        case incompleteSnapshot
    }
    private var exchangeRateRefreshGeneration: UInt64 = 0
    private var exchangeRateAttempts: Set<ExchangeRateAttemptKey> = []

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

    private func markLocalChangesForSync() {
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

    private func loadSetup(
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

    private var currentPreferences: UserPreferences {
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

    private func persistPreferences(
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

    private func snapshotContainsRequiredCurrencies(
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
                unchangedIDs.append(subscription.id)
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
    private func createSubscription(
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
    public func editSubscription(
        id: UUID,
        input: SubscriptionEditInput,
        forecastThrough: Date? = nil
    ) -> Bool {
        editingValidationErrors = [:]
        let scope = carriedLibraryScope

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return false
            }
            editingValidationErrors = validate(
                input,
                lifecycle: existing.lifecycle
            )
            guard editingValidationErrors.isEmpty else {
                return false
            }
            let whitespace = CharacterSet.whitespacesAndNewlines
            guard let timeZone = TimeZone(
                identifier: input.billingSchedule.timeZoneIdentifier
            ),
            let normalizedStartDate = normalizedBillingLocalNoon(
                input.startDate,
                timeZone: timeZone
            ) else {
                editingValidationErrors[.billingSchedule] = .required
                return false
            }
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            guard !existing.priceChanges.contains(where: {
                localCalendar.startOfDay(for: $0.effectiveDate)
                    < localCalendar.startOfDay(for: normalizedStartDate)
            }) else {
                editingValidationErrors[.billingSchedule] = .beforeStartDate
                return false
            }
            let confirmedNextRenewal: Date
            let renewalAnchor: Date
            switch existing.lifecycle {
            case .active:
                guard let resolvedRenewal = BillingDateResolver().nextRenewal(
                    afterStart: input.startDate,
                    interval: input.billingSchedule.interval,
                    asOf: now(),
                    timeZone: timeZone
                ),
                localCalendar.isDate(
                    resolvedRenewal,
                    inSameDayAs: input.confirmedNextRenewal
                ),
                let normalizedRenewal = normalizedBillingLocalNoon(
                    resolvedRenewal,
                    timeZone: timeZone
                ) else {
                    editingValidationErrors[.confirmedNextRenewal] = .required
                    return false
                }
                confirmedNextRenewal = normalizedRenewal
                renewalAnchor = normalizedStartDate
            case .trial, .cancelled:
                guard let normalizedRenewal = normalizedBillingLocalNoon(
                    input.confirmedNextRenewal,
                    timeZone: timeZone
                ) else {
                    editingValidationErrors[.confirmedNextRenewal] = .required
                    return false
                }
                confirmedNextRenewal = normalizedRenewal
                renewalAnchor = switch existing.lifecycle {
                case .trial:
                    normalizedRenewal
                case .cancelled:
                    existing.billingSchedule.renewalAnchor
                case .active:
                    normalizedStartDate
                }
            }
            let billingSchedule = FixedBillingSchedule(
                interval: input.billingSchedule.interval,
                renewalAnchor: renewalAnchor,
                timeZoneIdentifier:
                    input.billingSchedule.timeZoneIdentifier
            )
            let lifecycle = switch existing.lifecycle {
            case .trial:
                SubscriptionLifecycle.trial(
                    firstPaidChargeAt: confirmedNextRenewal
                )
            case .active, .cancelled:
                existing.lifecycle
            }
            let edited = Subscription(
                id: existing.id,
                serviceIdentity: existing.serviceIdentity,
                serviceName: input.serviceName.trimmingCharacters(
                    in: whitespace
                ),
                plan: input.plan.trimmingCharacters(in: whitespace),
                category: input.category.trimmingCharacters(in: whitespace),
                originalAmount: existing.originalAmount,
                billingSchedule: billingSchedule,
                startDate: normalizedStartDate,
                confirmedNextRenewal: confirmedNextRenewal,
                managementURL: input.managementURL,
                notes: input.notes,
                confirmedCharges: existing.confirmedCharges,
                priceChanges: editedPriceChanges(
                    for: existing,
                    amount: input.amount,
                    confirmedNextRenewal: confirmedNextRenewal,
                    calendar: localCalendar
                ),
                lifecycle: lifecycle,
                isArchived: existing.isArchived,
                pinnedAt: existing.pinnedAt
            )
            let editedToPersist = reconciledCatalogAssociation(
                for: edited,
                locale: catalogLocale
            )
            try repository.updateSubscription(editedToPersist)
            markLocalChangesForSync()
            detailState = makeDetail(editedToPersist)
            loadLibrary(scope: scope)
            if let forecastThrough {
                expectedChargesRequest = ExpectedChargesRequest(
                    subscriptionID: id,
                    horizon: forecastThrough,
                    maximumCount: .max
                )
            }
            reloadRequestedConsumers()
            return true
        } catch {
            return false
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
                reloadRequestedConsumers()
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
            reloadRequestedConsumers()
        } catch {
            paymentHistoryActionError = .persistenceFailed
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
            reloadRequestedConsumers()
        } catch {
            paymentHistoryActionError = .persistenceFailed
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
            guard renewalDay > today else {
                lifecycleActionError = .nextRenewalInPast
                return
            }
            guard let normalizedRenewal = normalizedBillingLocalNoon(
                nextRenewal,
                timeZone: timeZone
            ),
            let startDate = BillingDateResolver().previousCycleStart(
                before: normalizedRenewal,
                interval: existing.billingSchedule.interval,
                timeZone: timeZone
            ) else {
                lifecycleActionError = .persistenceFailed
                return
            }

            let updated = existing.replacingLifecycleFacts(
                lifecycle: .active,
                billingSchedule: FixedBillingSchedule(
                    interval: existing.billingSchedule.interval,
                    renewalAnchor: startDate,
                    timeZoneIdentifier:
                        existing.billingSchedule.timeZoneIdentifier
                ),
                startDate: startDate,
                confirmedNextRenewal: normalizedRenewal
            )
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }

    public func setPinned(id: UUID, pinned: Bool) {
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
            guard (existing.pinnedAt != nil) != pinned else {
                return
            }

            let updated = existing.replacingPinnedAt(
                pinned ? now() : nil
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
            paymentHistory = []
            expectedCharges = refreshedExpectedCharges
            if clearsExpectedCharges {
                expectedChargesRequest = nil
            }
            loadLibrary(scope: scope)
            reloadRequestedConsumers()
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

    private func reloadPreferencesAfterRemoteImport() {
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

    private var libraryIsEmptyAfterRemoteImport: Bool? {
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
    public func loadCalendarProjection(locale: Locale) -> Bool {
        calendarProjectionLocale = locale
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
            return true
        } catch {
            calendarProjection = []
            return false
        }
    }

    public func makePortableBackup() -> PortableBackup? {
        do {
            let subscriptions = try repository.listSubscriptions()
            let preferences = try preferencesRepository?.loadPreferences()
                ?? currentPreferences
            return PortableBackup(
                preferences: preferences,
                subscriptions: subscriptions
            )
        } catch {
            return nil
        }
    }

    public func preparePortableBackupImport(
        _ data: Data
    ) throws -> PortableBackupMergePreview {
        let asOf = now()
        let backup = try PortableBackupValidator().decode(
            data,
            asOf: asOf
        )
        let localSubscriptions = try repository.listSubscriptions()
        let localPreferences = try preferencesRepository?.loadPreferences()
            ?? currentPreferences
        return try PortableBackupMergePlanner().makePreview(
            backup: backup,
            localSubscriptions: localSubscriptions,
            localPreferences: localPreferences,
            asOf: asOf
        )
    }

    public func applyPortableBackupImport(
        preview: PortableBackupMergePreview,
        selectedAdditionIDs: Set<UUID>,
        conflictResolutions: [UUID: PortableBackupConflictResolution],
        preferencesResolution: PortableBackupConflictResolution?
    ) throws {
        guard let portableBackupImportRepository else {
            throw PortableBackupImportError.unavailable
        }
        let merge = try PortableBackupMergePlanner().makeMerge(
            preview: preview,
            selectedAdditionIDs: selectedAdditionIDs,
            conflictResolutions: conflictResolutions,
            preferencesResolution: preferencesResolution
        )
        try portableBackupImportRepository.apply(merge)
        markLocalChangesForSync()
        loadLibrary()
        loadSetup(libraryIsEmpty: false)
        reloadRequestedConsumers()
    }

    public func importCalendarProjection(
        _ events: [CalendarProjectionEvent]
    ) async {
        guard !events.isEmpty else {
            calendarImportState = .imported(
                CalendarProjectionImportSummary(
                    createdCount: 0,
                    updatedCount: 0
                )
            )
            return
        }
        guard let calendarProjectionImporter else {
            calendarImportState = .unavailable
            return
        }
        calendarImportState = .importing
        let result = await calendarProjectionImporter.importProjection(
            events: events
        )
        calendarImportState = CalendarImportState(result: result)
    }

    public func reconcileCalendarProjection(locale: Locale) async {
        await enqueueCalendarReconciliation(.reconcile(locale))
    }

    public func rebuildCalendarProjection(locale: Locale) async {
        await enqueueCalendarReconciliation(.rebuild(locale))
    }

    public func disableCalendarReconciliation() async {
        await enqueueCalendarReconciliation(.disable)
    }

    private func enqueueCalendarReconciliation(
        _ request: CalendarReconciliationRequest
    ) async {
        guard calendarProjectionReconciler != nil else {
            calendarReconciliationState = .notConfigured
            return
        }
        guard calendarReconciliationState != .reconciling else {
            pendingCalendarReconciliationRequest =
                coalescedCalendarReconciliationRequest(
                    pending: pendingCalendarReconciliationRequest,
                    incoming: request
                )
            return
        }
        calendarReconciliationState = .reconciling

        var request = request
        while true {
            let result = await performCalendarReconciliation(request)
            guard let pending = pendingCalendarReconciliationRequest else {
                calendarReconciliationState = CalendarReconciliationState(
                    result: result
                )
                return
            }
            pendingCalendarReconciliationRequest = nil
            request = pending
        }
    }

    private func coalescedCalendarReconciliationRequest(
        pending: CalendarReconciliationRequest?,
        incoming: CalendarReconciliationRequest
    ) -> CalendarReconciliationRequest {
        guard let pending else { return incoming }
        return incoming.priority >= pending.priority ? incoming : pending
    }

    private func performCalendarReconciliation(
        _ request: CalendarReconciliationRequest
    ) async -> CalendarReconciliationResult {
        guard let calendarProjectionReconciler else {
            return .notConfigured
        }
        switch request {
        case .reconcile(let locale):
            guard loadCalendarProjection(locale: locale) else {
                return .unavailable
            }
            return await calendarProjectionReconciler.perform(
                .reconcile(calendarProjection)
            )
        case .rebuild(let locale):
            guard loadCalendarProjection(locale: locale) else {
                return .unavailable
            }
            return await calendarProjectionReconciler.perform(
                .rebuild(calendarProjection)
            )
        case .disable:
            return await calendarProjectionReconciler.perform(.disable)
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

    private func validate(
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

    private func editedPriceChanges(
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

    private func billingTimeZone(
        for subscription: Subscription
    ) -> TimeZone {
        TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
    }

    private func publishWidgetSnapshot() {
        guard let snapshot = makeWidgetSnapshot() else { return }
        widgetSnapshotPublisher?.publish(snapshot)
    }

    private func formattedWidgetAmount(_ money: Money) -> String {
        (Decimal(money.minorUnits) / 100).formatted(
            .currency(code: money.currency.rawValue).locale(.current)
        )
    }

    private func finishLifecycleUpdate(
        _ subscription: Subscription
    ) {
        markLocalChangesForSync()
        let scope = carriedLibraryScope
        let refreshedDetailState = makeDetail(subscription)

        detailState = refreshedDetailState
        loadLibrary(scope: scope)
        reloadRequestedConsumers()
    }

    private func reloadRequestedConsumers() {
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

    private func makeLibraryState(
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

    private var carriedLibraryScope: SubscriptionLibraryScope {
        switch libraryState {
        case .loading(let scope),
             .empty(let scope),
             .loaded(let scope, _),
             .failed(let scope):
            scope
        }
    }

    private func matchingCatalogSnapshot() -> CatalogSnapshot? {
        if let catalogSnapshot {
            return catalogSnapshot
        }
        return try? catalogRepository?.loadSnapshot()
    }

    private func reconciledCatalogAssociation(
        for subscription: Subscription,
        locale: Locale
    ) -> Subscription {
        guard let snapshot = matchingCatalogSnapshot() else {
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

    private func normalizedCatalogAssociation(
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

    private func makeExpectedCharges(
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
        let amount = subscription.amount(onBillingDay: scheduledDate)
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
            subscription: presentation.subscription,
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
            subscription: presentation.subscription,
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

    private func makePresentationNextExpectedCharge(
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

    private struct UpcomingTimelineRequest {
        let from: Date
        let through: Date
    }
}
