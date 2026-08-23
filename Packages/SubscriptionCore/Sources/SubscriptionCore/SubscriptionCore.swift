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

    /// Marks setup complete when existing subscriptions prove this is not a
    /// first-run library. A failed persistence attempt remains observable,
    /// but must not send that existing library through onboarding.

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

    nonisolated static func defaultRenewalCalendar() -> Calendar {
        BillingCalendar.calendar(timeZone: .autoupdatingCurrent)
    }

    var currentExchangeRateSnapshot: ExchangeRateSnapshot? {
        switch exchangeRateStatus {
        case .fresh(let snapshot), .stale(let snapshot): snapshot
        case .notLoaded, .unavailable:
            // Insights render from the persisted cache before the first
            // refresh of the session completes; conversion re-validates
            // every required currency, so an incomplete cache still ends
            // up unavailable.
            try? exchangeRateCache?.loadState()?.snapshot
        }
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

    /// Exports a portable backup and reports how many unreadable local
    /// records the repository skipped during that load, so callers can
    /// surface incomplete exports instead of failing silently.

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

    var carriedLibraryScope: SubscriptionLibraryScope {
        switch libraryState {
        case .loading(let scope),
             .empty(let scope),
             .loaded(let scope, _),
             .failed(let scope):
            scope
        }
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
