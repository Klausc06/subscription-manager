import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("Subscription draft")
struct SubscriptionDraftTests {
    @Test("Manual drafts leave optional facts and date acceptance empty")
    func manualDraftStartsUnselected() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )

        #expect(draft.serviceName.isEmpty)
        #expect(draft.plan.isEmpty)
        #expect(draft.category.isEmpty)
        #expect(draft.amountText.isEmpty)
        #expect(draft.currency == nil)
        #expect(draft.billingInterval == nil)
        #expect(draft.acceptedDateSources.isEmpty)
        #expect(draft.catalogPresetID == nil)
        #expect(draft.catalogOfferID == nil)
        #expect(draft.validation.contains(.amount))
        #expect(draft.validation.contains(.currency))
        #expect(draft.validation.contains(.billingInterval))
        #expect(draft.validation.contains(.billingDate))
        #expect(draft.makeCreationInput(locale: Locale(identifier: "en_US")) == nil)
    }

    @Test("Selecting an active Start Date resolves the first renewal after today")
    func activeStartDateResolvesStrictlyAfterToday() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let start = try date(year: 2025, month: 9, day: 15, hour: 21, minute: 45)
        let expectedStart = try date(year: 2025, month: 9, day: 15, hour: 12)
        let expectedRenewal = try date(year: 2026, month: 8, day: 15, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        configureActive(&draft)

        let selectedStart = draft.selectStartDate(start, asOf: now)
        #expect(selectedStart)
        #expect(draft.startDate == expectedStart)
        #expect(draft.confirmedNextRenewal == expectedRenewal)
        #expect(draft.dateSource == .startDate)
        #expect(draft.acceptedDateSources == [.startDate])
        #expect(draft.validation.isEmpty)
        #expect(draft.makeCreationInput(locale: Locale(identifier: "en_US")) != nil)
    }

    @Test("Selecting an active Next Renewal derives its preceding Start Date")
    func activeNextRenewalDerivesPrecedingStartDate() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let renewal = try date(year: 2026, month: 10, day: 28, hour: 23)
        let expectedStart = try date(year: 2026, month: 9, day: 28, hour: 12)
        let expectedRenewal = try date(year: 2026, month: 10, day: 28, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        configureActive(&draft)

        let selectedRenewal = draft.selectNextRenewal(renewal, asOf: now)
        #expect(selectedRenewal)
        #expect(draft.startDate == expectedStart)
        #expect(draft.confirmedNextRenewal == expectedRenewal)
        #expect(draft.dateSource == .nextRenewal)
        #expect(draft.acceptedDateSources == [.nextRenewal])

        let changedInterval = draft.changeBillingInterval(.yearly, asOf: now)
        #expect(changedInterval)
        let yearlyStart = try date(year: 2025, month: 10, day: 28, hour: 12)
        #expect(draft.startDate == yearlyStart)
        #expect(draft.confirmedNextRenewal == expectedRenewal)
        #expect(draft.dateSource == .nextRenewal)
    }

    @Test("Billing dates normalize to local noon in Asia Shanghai")
    func billingDatesNormalizeToAsiaShanghaiNoon() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let billingCalendar = BillingCalendar.calendar(timeZone: timeZone)
        let now = try #require(
            billingCalendar.date(
                from: DateComponents(year: 2026, month: 7, day: 30, hour: 12)
            )
        )
        let picked = try #require(
            billingCalendar.date(
                from: DateComponents(year: 2026, month: 8, day: 1, hour: 3)
            )
        )
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: timeZone.identifier
        )
        configureActive(&draft)

        let selectedStart = draft.selectStartDate(picked, asOf: now)
        #expect(selectedStart)
        let components = billingCalendar.dateComponents(
            [.year, .month, .day, .hour],
            from: draft.startDate
        )
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 1)
        #expect(components.hour == 12)
    }

    @Test("Month-end billing resolves across a leap year")
    func monthEndBillingResolvesAcrossLeapYear() throws {
        let now = try date(year: 2027, month: 12, day: 1, hour: 12)
        let start = try date(year: 2028, month: 1, day: 31, hour: 12)
        let expectedRenewal = try date(year: 2028, month: 2, day: 29, hour: 12)
        var draft = SubscriptionDraft.manual(now: now, timeZoneIdentifier: "UTC")
        configureActive(&draft)

        let selectedStart = draft.selectStartDate(start, asOf: now)
        #expect(selectedStart)
        #expect(draft.confirmedNextRenewal == expectedRenewal)
    }

    @Test("An empty service name remains invalid")
    func serviceNameIsRequired() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        var draft = SubscriptionDraft.manual(now: now, timeZoneIdentifier: "UTC")
        configureActive(&draft)
        let selectedStart = draft.selectStartDate(now, asOf: now)
        #expect(selectedStart)
        draft.serviceName = " \n\t"

        #expect(draft.validation.contains(.serviceName))
        #expect(draft.makeCreationInput(locale: Locale(identifier: "en_US")) == nil)
    }

    @Test("Changing an active interval rederives from the current source")
    func activeIntervalChangeUsesCurrentSource() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let start = try date(year: 2026, month: 1, day: 15, hour: 12)
        let expectedRenewal = try date(year: 2027, month: 1, day: 15, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        configureActive(&draft)
        let selectedStart = draft.selectStartDate(start, asOf: now)
        #expect(selectedStart)

        let changedInterval = draft.changeBillingInterval(.yearly, asOf: now)
        #expect(changedInterval)
        #expect(draft.billingInterval == .yearly)
        #expect(draft.startDate == start)
        #expect(draft.confirmedNextRenewal == expectedRenewal)
        #expect(draft.dateSource == .startDate)
        #expect(draft.acceptedDateSources == [.startDate])
    }

    @Test("Trial date selectors keep Trial Start and First Paid Charge independent")
    func trialDatesRemainIndependent() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let trialStart = try date(year: 2026, month: 7, day: 1, hour: 19)
        let firstPaidCharge = try date(year: 2026, month: 8, day: 15, hour: 19)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        draft.mode = .creating(.trial)
        draft.serviceName = "Trial Service"
        draft.amountText = "9.99"
        draft.currency = .usd
        draft.billingInterval = .monthly

        let selectedTrialStart = draft.selectStartDate(trialStart, asOf: now)
        let selectedFirstPaidCharge = draft.selectNextRenewal(
            firstPaidCharge,
            asOf: now
        )
        #expect(selectedTrialStart)
        #expect(selectedFirstPaidCharge)
        let expectedStart = try date(year: 2026, month: 7, day: 1, hour: 12)
        let expectedRenewal = try date(year: 2026, month: 8, day: 15, hour: 12)
        #expect(draft.startDate == expectedStart)
        #expect(draft.confirmedNextRenewal == expectedRenewal)
        #expect(draft.acceptedDateSources == [.startDate, .nextRenewal])
        #expect(draft.validation.isEmpty)
        #expect(draft.makeCreationInput(locale: Locale(identifier: "en_US"))?.initialStatus == .trial)
    }

    @Test("Cancelled editing preserves its stored schedule facts")
    func cancelledEditDoesNotInventFutureDates() throws {
        let start = try date(year: 2025, month: 9, day: 15, hour: 12)
        let renewal = try date(year: 2025, month: 10, day: 15, hour: 12)
        let cancelledAt = try date(year: 2026, month: 1, day: 10, hour: 12)
        let accessUntil = try date(year: 2026, month: 2, day: 10, hour: 12)
        let subscription = Subscription(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:cancelled"),
            serviceName: "Cancelled Service",
            plan: "",
            category: "",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: start,
                timeZoneIdentifier: "UTC"
            ),
            startDate: start,
            confirmedNextRenewal: renewal,
            managementURL: nil,
            notes: "",
            lifecycle: .cancelled(cancelledAt: cancelledAt, accessUntil: accessUntil)
        )

        var draft = SubscriptionDraft.editing(
            subscription: subscription,
            locale: Locale(identifier: "en_US")
        )
        let originalStart = draft.startDate
        let originalRenewal = draft.confirmedNextRenewal
        let changedInterval = draft.changeBillingInterval(.yearly, asOf: accessUntil)
        #expect(changedInterval)
        #expect(draft.startDate == originalStart)
        #expect(draft.confirmedNextRenewal == originalRenewal)
        #expect(draft.makeEditInput(locale: Locale(identifier: "en_US")) != nil)
    }

    @Test("Only a verified offer adopts plan, price, currency, interval, and offer identity")
    func verifiedCatalogOfferAdoption() throws {
        let offer = makeOffer(reviewStatus: .verified)
        let preset = makePreset(offers: [offer])
        let draft = SubscriptionDraft.catalog(
            preset: preset,
            offer: offer,
            now: try date(year: 2026, month: 7, day: 30, hour: 12),
            locale: Locale(identifier: "en_US"),
            timeZoneIdentifier: "UTC"
        )

        #expect(draft.serviceName == "Example Service")
        #expect(draft.plan == "Plus")
        #expect(draft.category == "Productivity")
        #expect(draft.amountText == "9.99")
        #expect(draft.currency == .usd)
        #expect(draft.billingInterval == .monthly)
        #expect(draft.catalogPresetID == preset.id)
        #expect(draft.catalogOfferID == offer.id)
        #expect(draft.acceptedDateSources.isEmpty)
        #expect(draft.validation == [.billingDate])
    }

    @Test("Service-only and review-required offers do not invent offer facts")
    func unverifiedCatalogOfferAdoption() throws {
        let reviewOffer = makeOffer(reviewStatus: .reviewRequired)
        let preset = makePreset(offers: [reviewOffer])
        let draft = SubscriptionDraft.catalog(
            preset: preset,
            offer: reviewOffer,
            now: try date(year: 2026, month: 7, day: 30, hour: 12),
            locale: Locale(identifier: "en_US"),
            timeZoneIdentifier: "UTC"
        )

        #expect(draft.serviceName == "Example Service")
        #expect(draft.category == "Productivity")
        #expect(draft.managementURLText == "https://example.com/account")
        #expect(draft.plan.isEmpty)
        #expect(draft.amountText.isEmpty)
        #expect(draft.currency == nil)
        #expect(draft.billingInterval == nil)
        #expect(draft.catalogPresetID == preset.id)
        #expect(draft.catalogOfferID == nil)
    }

    @Test("An offer from another preset cannot be adopted")
    func catalogOfferMustBelongToPreset() throws {
        let verifiedOffer = makeOffer(reviewStatus: .verified)
        let preset = makePreset(offers: [])
        let draft = SubscriptionDraft.catalog(
            preset: preset,
            offer: verifiedOffer,
            now: try date(year: 2026, month: 7, day: 30, hour: 12),
            locale: Locale(identifier: "en_US"),
            timeZoneIdentifier: "UTC"
        )

        #expect(draft.catalogPresetID == preset.id)
        #expect(draft.catalogOfferID == nil)
        #expect(draft.plan.isEmpty)
        #expect(draft.amountText.isEmpty)
        #expect(draft.currency == nil)
        #expect(draft.billingInterval == nil)
    }

    @Test("Editing accepts persisted dates and uses the current effective amount")
    func editingStartsWithPersistedDatesAccepted() throws {
        let storedStart = try date(year: 2026, month: 1, day: 15, hour: 18)
        let storedRenewal = try date(year: 2026, month: 8, day: 15, hour: 21)
        let start = try date(year: 2026, month: 1, day: 15, hour: 12)
        let renewal = try date(year: 2026, month: 8, day: 15, hour: 12)
        let subscription = Subscription(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:editing"),
            serviceName: "Editing Service",
            plan: "",
            category: "",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: storedStart,
                timeZoneIdentifier: "UTC"
            ),
            startDate: storedStart,
            confirmedNextRenewal: storedRenewal,
            managementURL: URL(string: "https://example.com/account"),
            notes: "Notes"
        )
        let draft = SubscriptionDraft.editing(
            subscription: subscription,
            locale: Locale(identifier: "en_US")
        )

        #expect(draft.acceptedDateSources == [.startDate, .nextRenewal])
        #expect(draft.validation.isEmpty)
        let editInput = try #require(
            draft.makeEditInput(locale: Locale(identifier: "en_US"))
        )
        #expect(editInput.amount == Money(minorUnits: 999, currency: .usd))
        #expect(editInput.startDate == start)
        #expect(editInput.confirmedNextRenewal == renewal)
    }

    @Test("Invalid selector values return false and leave the draft unchanged")
    func invalidSelectorLeavesDraftUnchanged() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        configureActive(&draft)
        let before = draft

        let selectedInvalidDate = draft.selectStartDate(
            Date(timeIntervalSinceReferenceDate: .nan),
            asOf: now
        )
        #expect(!selectedInvalidDate)
        #expect(draft == before)

        draft.billingTimeZoneIdentifier = "Not/A_TimeZone"
        let beforeInvalidTimeZone = draft
        let selectedInvalidTimeZone = draft.selectStartDate(now, asOf: now)
        #expect(!selectedInvalidTimeZone)
        #expect(draft == beforeInvalidTimeZone)

        draft.billingTimeZoneIdentifier = "UTC"
        let beforeInvalidInterval = draft
        let changedInvalidInterval = draft.changeBillingInterval(
            .custom(value: 0, unit: .month),
            asOf: now
        )
        #expect(!changedInvalidInterval)
        #expect(draft == beforeInvalidInterval)
    }

    @Test("Amount and management URL validation remain locale-aware and exact")
    func amountAndURLValidation() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        configureActive(&draft)
        let selectedStart = draft.selectStartDate(now, asOf: now)
        #expect(selectedStart)

        draft.amountText = "1.001"
        #expect(draft.parsedAmount(locale: Locale(identifier: "en_US")) == nil)
        #expect(draft.validation.contains(.amount))
        for invalidText in ["0", "-1", "-0.01"] {
            draft.amountText = invalidText
            #expect(draft.parsedAmount(locale: Locale(identifier: "en_US")) == nil)
            #expect(draft.validation.contains(.amount))
        }
        draft.amountText = "9,99"
        #expect(draft.parsedAmount(locale: Locale(identifier: "de_DE")) == Money(minorUnits: 999, currency: .usd))
        draft.managementURLText = "not a URL"
        #expect(draft.validation.contains(.managementURL))
        draft.managementURLText = ""
        #expect(!draft.validation.contains(.managementURL))
    }

    @Test("Creation input trims optional metadata and carries the required schedule")
    func creationInputTrimsMetadataAndCarriesSchedule() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let start = try date(year: 2026, month: 8, day: 15, hour: 18)
        let expectedStart = try date(year: 2026, month: 8, day: 15, hour: 12)
        var draft = SubscriptionDraft.manual(now: now, timeZoneIdentifier: "UTC")
        draft.serviceName = "  Example Service  "
        draft.plan = "  Pro  "
        draft.category = " \n "
        draft.amountText = "9.99"
        draft.currency = .usd
        draft.billingInterval = .monthly
        draft.managementURLText = " https://example.com/account "
        let selectedStart = draft.selectStartDate(start, asOf: now)
        #expect(selectedStart)

        let input = try #require(
            draft.makeCreationInput(locale: Locale(identifier: "en_US"))
        )
        #expect(input.serviceName == "Example Service")
        #expect(input.plan == "Pro")
        #expect(input.category.isEmpty)
        #expect(input.billingInterval == .monthly)
        #expect(input.startDate == expectedStart)
        #expect(input.renewalAnchor == expectedStart)
        #expect(input.managementURL == URL(string: "https://example.com/account"))
        #expect(draft.requiredBillingSchedule() == FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: expectedStart,
            timeZoneIdentifier: "UTC"
        ))
    }

    private func configureActive(_ draft: inout SubscriptionDraft) {
        draft.serviceName = "Example Service"
        draft.amountText = "9.99"
        draft.currency = .usd
        draft.billingInterval = .monthly
    }

    private func makePreset(offers: [CatalogOffer]) -> CatalogPreset {
        CatalogPreset(
            id: "example.service",
            serviceName: CatalogLocalizedText(
                en: "Example Service",
                zhHans: "示例服务"
            ),
            category: CatalogLocalizedText(
                en: "Productivity",
                zhHans: "效率"
            ),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://example.com/account"),
            icon: .productivity,
            offers: offers
        )
    }

    private func makeOffer(
        reviewStatus: CatalogOfferReviewStatus
    ) -> CatalogOffer {
        CatalogOffer(
            id: "example.plus.monthly",
            planName: CatalogLocalizedText(en: "Plus", zhHans: "Plus"),
            price: Money(minorUnits: 999, currency: .usd),
            billingInterval: .monthly,
            market: "US",
            purchaseChannel: .web,
            sourceURL: URL(string: "https://example.com/pricing")!,
            verifiedOn: "2026-07-30",
            reviewStatus: reviewStatus
        )
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) throws -> Date {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        var calendar = BillingCalendar.calendar(timeZone: timeZone)
        return try #require(
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
}
