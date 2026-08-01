import Foundation
import SubscriptionCore
import SwiftUI
import Testing
@testable import SubscriptionManager

@Suite("Subscription draft")
struct SubscriptionDraftTests {
    @Test("Shared editor views expose direct draft bindings")
    @MainActor
    func sharedEditorViewsExposeDirectDraftBindings() {
        var draft = SubscriptionDraft.manual(
            now: Date(timeIntervalSinceReferenceDate: 0),
            timeZoneIdentifier: "UTC"
        )
        let binding = Binding<SubscriptionDraft>(
            get: { draft },
            set: { draft = $0 }
        )
        let sections = SubscriptionEditorSections(
            draft: binding,
            status: nil,
            nextExpectedCharge: nil,
            onEditDate: { _ in }
        )
        let dateTask = BillingDateTaskView(
            draft: binding,
            source: .startDate,
            now: Date(timeIntervalSinceReferenceDate: 0)
        )

        _ = sections
        _ = dateTask
    }

    @Test("Selecting custom preserves whitespace while parsing its value")
    @MainActor
    func customIntervalSelectionTrimsStoredText() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        draft.customIntervalValueText = " 3 "
        let binding = Binding<SubscriptionDraft>(
            get: { draft },
            set: { draft = $0 }
        )
        let interval = subscriptionBillingIntervalBinding(binding, asOf: now)

        interval.wrappedValue = "custom"

        #expect(draft.customIntervalValueText == " 3 ")
        #expect(draft.billingInterval == .custom(value: 3, unit: .day))
    }

    @Test("Billing date role labels honor their requested locale")
    func billingDateRoleLabelsHonorLocale() {
        let zhHans = Locale(identifier: "zh-Hans")
        let english = Locale(identifier: "en")

        #expect(
            billingDateRoleText(
                source: .startDate,
                selectedSource: .startDate,
                locale: zhHans
            ) == "来源"
        )
        #expect(
            billingDateRoleText(
                source: .nextRenewal,
                selectedSource: .startDate,
                locale: zhHans
            ) == "推导"
        )
        #expect(
            billingDateRoleText(
                source: .startDate,
                selectedSource: .startDate,
                locale: english
            ) == "Source"
        )
        #expect(
            billingDateRoleText(
                source: .nextRenewal,
                selectedSource: .startDate,
                locale: english
            ) == "Derived"
        )
    }

    @Test("Date task state commits active source and derived counterpart")
    func dateTaskStateCommitsActiveSource() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let selectedStart = try date(year: 2026, month: 1, day: 15, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        configureActive(&draft)
        let original = draft
        var state = BillingDateTaskState(
            draft: draft,
            source: .startDate,
            now: now
        )

        #expect(state.workingDraft == original)
        let selected = state.applySelection(selectedStart)
        #expect(selected)
        #expect(draft == original)
        #expect(state.workingDraft.startDate != original.startDate)
        #expect(state.workingDraft.confirmedNextRenewal != original.confirmedNextRenewal)

        let committedValue = state.commit()
        let committed = try #require(committedValue)
        #expect(committed == state.workingDraft)
        #expect(committed.dateSource == .startDate)
    }

    @Test("Date task state commits an initial active renewal and derives start")
    func dateTaskStateCommitsInitialRenewal() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        configureActive(&draft)
        var state = BillingDateTaskState(
            draft: draft,
            source: .nextRenewal,
            now: now
        )

        let committedValue = state.commit()
        let committed = try #require(committedValue)

        #expect(state.didApplySelection)
        #expect(committed.dateSource == .nextRenewal)
        #expect(committed.startDate != draft.startDate)
    }

    @Test("Date task state keeps trial sources independent")
    func dateTaskStateKeepsTrialSourcesIndependent() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let selectedStart = try date(year: 2026, month: 7, day: 1, hour: 19)
        let selectedRenewal = try date(year: 2026, month: 8, day: 15, hour: 19)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        draft.mode = .creating(.trial)
        draft.billingInterval = .monthly
        let originalRenewal = draft.confirmedNextRenewal
        var startState = BillingDateTaskState(
            draft: draft,
            source: .startDate,
            now: now
        )
        let startSelected = startState.applySelection(selectedStart)
        #expect(startSelected)
        #expect(startState.workingDraft.confirmedNextRenewal == originalRenewal)

        var renewalState = BillingDateTaskState(
            draft: draft,
            source: .nextRenewal,
            now: now
        )
        let renewalSelected = renewalState.applySelection(selectedRenewal)
        #expect(renewalSelected)
        #expect(renewalState.workingDraft.startDate == draft.startDate)
    }

    @Test("Date task state leaves cancelled dates independent")
    func dateTaskStateLeavesCancelledDatesIndependent() throws {
        let start = try date(year: 2025, month: 9, day: 15, hour: 12)
        let renewal = try date(year: 2025, month: 10, day: 15, hour: 12)
        let cancelledAt = try date(year: 2026, month: 1, day: 10, hour: 12)
        let accessUntil = try date(year: 2026, month: 2, day: 10, hour: 12)
        let subscription = Subscription(
            id: UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-000000000000")!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:cancelled-task"),
            serviceName: "Cancelled Task Service",
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
        let draft = SubscriptionDraft.editing(
            subscription: subscription,
            locale: Locale(identifier: "en_US")
        )
        let originalStart = draft.startDate
        let originalRenewal = draft.confirmedNextRenewal

        var startState = BillingDateTaskState(
            draft: draft,
            source: .startDate,
            now: accessUntil
        )
        let startSelected = startState.applySelection(
            try date(year: 2025, month: 8, day: 15, hour: 12)
        )
        #expect(startSelected)
        #expect(startState.workingDraft.confirmedNextRenewal == originalRenewal)

        var renewalState = BillingDateTaskState(
            draft: draft,
            source: .nextRenewal,
            now: accessUntil
        )
        let renewalSelected = renewalState.applySelection(
            try date(year: 2025, month: 11, day: 15, hour: 12)
        )
        #expect(renewalSelected)
        #expect(renewalState.workingDraft.startDate == originalStart)
    }

    @Test("Date task state does not commit failed selections")
    func dateTaskStateRejectsFailedSelection() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        var state = BillingDateTaskState(
            draft: draft,
            source: .startDate,
            now: now
        )
        let original = state.workingDraft

        let selected = state.applySelection(now)
        #expect(!selected)
        #expect(!state.didApplySelection)
        #expect(state.workingDraft == original)
        let committed = state.commit()
        #expect(committed == nil)
        #expect(!state.didApplySelection)
    }

    @Test("Interval bindings preserve optional and custom draft values")
    @MainActor
    func intervalBindingsPreserveOptionalAndCustomValues() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        var draft = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: "UTC"
        )
        let binding = Binding<SubscriptionDraft>(
            get: { draft },
            set: { draft = $0 }
        )
        let interval = subscriptionBillingIntervalBinding(binding, asOf: now)

        #expect(interval.wrappedValue == nil)
        interval.wrappedValue = "custom"
        #expect(draft.customIntervalValueText.isEmpty)
        #expect(draft.billingInterval == .custom(value: 0, unit: .day))
        #expect(draft.validation.contains(.billingInterval))

        let value = subscriptionCustomIntervalValueBinding(binding, asOf: now)
        value.wrappedValue = "3"
        #expect(draft.customIntervalValueText == "3")
        #expect(draft.billingInterval == .custom(value: 3, unit: .day))

        let unit = subscriptionCustomIntervalUnitBinding(binding, asOf: now)
        unit.wrappedValue = BillingIntervalUnit.week.rawValue
        #expect(draft.billingInterval == .custom(value: 3, unit: .week))

        value.wrappedValue = ""
        #expect(draft.customIntervalValueText.isEmpty)
        #expect(draft.billingInterval == .custom(value: 0, unit: .week))
        #expect(draft.validation.contains(.billingInterval))

        configureActive(&draft)
        let start = try date(year: 2026, month: 1, day: 15, hour: 12)
        let selectedStart = draft.selectStartDate(start, asOf: now)
        #expect(selectedStart)
        let renewalBeforeCadenceChange = draft.confirmedNextRenewal
        interval.wrappedValue = BillingInterval.yearly.rawValue

        #expect(draft.billingInterval == .yearly)
        #expect(draft.dateSource == .startDate)
        #expect(draft.confirmedNextRenewal != renewalBeforeCadenceChange)
    }

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

    @Test("Custom intervals preserve their value and unit through inputs")
    func customIntervalRoundTripsThroughCreationAndEditing() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let pickedStart = try date(year: 2026, month: 8, day: 1, hour: 18)
        let expectedStart = try date(year: 2026, month: 8, day: 1, hour: 12)
        let expectedRenewal = try date(year: 2026, month: 8, day: 22, hour: 12)
        let interval = BillingInterval.custom(value: 3, unit: .week)
        var draft = SubscriptionDraft.manual(now: now, timeZoneIdentifier: "UTC")
        draft.serviceName = "Custom Service"
        draft.amountText = "12.00"
        draft.currency = .usd
        let changedInterval = draft.changeBillingInterval(interval, asOf: now)
        #expect(changedInterval)

        let selectedStart = draft.selectStartDate(pickedStart, asOf: now)
        #expect(selectedStart)
        #expect(draft.billingInterval == interval)
        #expect(draft.customIntervalValueText == "3")
        #expect(draft.customIntervalUnit == .week)

        let creation = try #require(
            draft.makeCreationInput(locale: Locale(identifier: "en_US"))
        )
        #expect(creation.billingInterval == interval)
        #expect(creation.startDate == expectedStart)
        #expect(creation.confirmedNextRenewal == expectedRenewal)
        #expect(creation.renewalAnchor == expectedStart)

        let subscription = Subscription(
            id: UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-000000000000")!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:custom"),
            serviceName: "Custom Service",
            plan: "",
            category: "",
            originalAmount: Money(minorUnits: 1_200, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: interval,
                renewalAnchor: expectedStart,
                timeZoneIdentifier: "UTC"
            ),
            startDate: expectedStart,
            confirmedNextRenewal: expectedRenewal,
            managementURL: nil,
            notes: ""
        )
        let edit = SubscriptionDraft.editing(
            subscription: subscription,
            locale: Locale(identifier: "en_US")
        )
        #expect(edit.customIntervalValueText == "3")
        #expect(edit.customIntervalUnit == .week)
        let editInput = try #require(
            edit.makeEditInput(locale: Locale(identifier: "en_US"))
        )
        #expect(editInput.billingSchedule.interval == interval)
        #expect(editInput.billingSchedule.renewalAnchor == expectedStart)
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
        let originalAnchor = subscription.billingSchedule.renewalAnchor
        let changedInterval = draft.changeBillingInterval(.yearly, asOf: accessUntil)
        #expect(changedInterval)
        #expect(draft.startDate == originalStart)
        #expect(draft.confirmedNextRenewal == originalRenewal)
        let editInput = try #require(
            draft.makeEditInput(locale: Locale(identifier: "en_US"))
        )
        #expect(editInput.billingSchedule.interval == .yearly)
        #expect(editInput.billingSchedule.renewalAnchor == originalAnchor)
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
        #expect(editInput.billingSchedule.renewalAnchor == start)
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
        let expectedRenewal = try date(year: 2026, month: 9, day: 15, hour: 12)
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
        #expect(input.confirmedNextRenewal == expectedRenewal)
        #expect(input.managementURL == URL(string: "https://example.com/account"))
        #expect(draft.requiredBillingSchedule() == FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: expectedStart,
            timeZoneIdentifier: "UTC"
        ))
    }

    @Test("Creation and edit inputs normalize every billing date to local noon")
    func inputDatesNormalizeToBillingLocalNoon() throws {
        let timeZoneIdentifier = "Asia/Shanghai"
        let now = try date(
            year: 2026,
            month: 7,
            day: 30,
            hour: 4,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let start = try date(
            year: 2026,
            month: 8,
            day: 1,
            hour: 3,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let renewal = try date(
            year: 2026,
            month: 8,
            day: 15,
            hour: 22,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let expectedStart = try date(
            year: 2026,
            month: 8,
            day: 1,
            hour: 12,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let expectedRenewal = try date(
            year: 2026,
            month: 8,
            day: 15,
            hour: 12,
            timeZoneIdentifier: timeZoneIdentifier
        )
        var creation = SubscriptionDraft.manual(
            now: now,
            timeZoneIdentifier: timeZoneIdentifier
        )
        creation.serviceName = "Noon Service"
        creation.amountText = "9.99"
        creation.currency = .usd
        creation.billingInterval = .monthly
        creation.startDate = start
        creation.confirmedNextRenewal = renewal
        creation.dateSource = .startDate
        creation.acceptedDateSources = [.startDate]

        let creationInput = try #require(
            creation.makeCreationInput(locale: Locale(identifier: "en_US"))
        )
        #expect(creationInput.startDate == expectedStart)
        #expect(creationInput.confirmedNextRenewal == expectedRenewal)
        #expect(creationInput.renewalAnchor == expectedStart)

        let subscription = Subscription(
            id: UUID(uuidString: "DDDDDDDD-EEEE-FFFF-0000-111111111111")!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:noon"),
            serviceName: "Noon Service",
            plan: "",
            category: "",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: start,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            startDate: start,
            confirmedNextRenewal: renewal,
            managementURL: nil,
            notes: ""
        )
        let edit = SubscriptionDraft.editing(
            subscription: subscription,
            locale: Locale(identifier: "en_US")
        )
        let editInput = try #require(
            edit.makeEditInput(locale: Locale(identifier: "en_US"))
        )
        #expect(editInput.startDate == expectedStart)
        #expect(editInput.confirmedNextRenewal == expectedRenewal)
        #expect(editInput.billingSchedule.renewalAnchor == expectedStart)
    }

    @Test("Corrupted dates and time zones block both input builders")
    func corruptedStateBlocksCreationAndEditInputs() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let start = try date(year: 2026, month: 8, day: 1, hour: 12)
        let renewal = try date(year: 2026, month: 8, day: 15, hour: 12)

        var creation = SubscriptionDraft.manual(now: now, timeZoneIdentifier: "UTC")
        creation.serviceName = "Corrupted Service"
        creation.amountText = "9.99"
        creation.currency = .usd
        creation.billingInterval = .monthly
        creation.startDate = start
        creation.confirmedNextRenewal = renewal
        creation.acceptedDateSources = [.startDate]

        creation.billingTimeZoneIdentifier = "Not/A_TimeZone"
        #expect(creation.validation.contains(.billingInterval))
        #expect(creation.makeCreationInput(locale: Locale(identifier: "en_US")) == nil)

        creation.billingTimeZoneIdentifier = "UTC"
        creation.startDate = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(creation.validation.contains(.billingDate))
        #expect(creation.makeCreationInput(locale: Locale(identifier: "en_US")) == nil)

        let subscription = Subscription(
            id: UUID(uuidString: "EEEEEEEE-FFFF-0000-1111-222222222222")!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:corrupted"),
            serviceName: "Corrupted Service",
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
            notes: ""
        )
        var edit = SubscriptionDraft.editing(
            subscription: subscription,
            locale: Locale(identifier: "en_US")
        )
        edit.billingTimeZoneIdentifier = "Not/A_TimeZone"
        #expect(edit.validation.contains(.billingInterval))
        #expect(edit.makeEditInput(locale: Locale(identifier: "en_US")) == nil)

        edit.billingTimeZoneIdentifier = "UTC"
        edit.confirmedNextRenewal = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(edit.validation.contains(.billingDate))
        #expect(edit.makeEditInput(locale: Locale(identifier: "en_US")) == nil)
    }

    @Test("Trial creation keeps First Paid Charge as its renewal anchor")
    func trialCreationUsesFirstPaidChargeAnchor() throws {
        let now = try date(year: 2026, month: 7, day: 30, hour: 12)
        let trialStart = try date(year: 2026, month: 8, day: 1, hour: 18)
        let firstPaidCharge = try date(year: 2026, month: 8, day: 15, hour: 21)
        let expectedStart = try date(year: 2026, month: 8, day: 1, hour: 12)
        let expectedFirstPaidCharge = try date(year: 2026, month: 8, day: 15, hour: 12)
        var draft = SubscriptionDraft.manual(now: now, timeZoneIdentifier: "UTC")
        draft.mode = .creating(.trial)
        draft.serviceName = "Trial Service"
        draft.amountText = "9.99"
        draft.currency = .usd
        draft.billingInterval = .monthly

        let selectedStart = draft.selectStartDate(trialStart, asOf: now)
        let selectedFirstPaidCharge = draft.selectNextRenewal(
            firstPaidCharge,
            asOf: now
        )
        #expect(selectedStart)
        #expect(selectedFirstPaidCharge)

        let input = try #require(
            draft.makeCreationInput(locale: Locale(identifier: "en_US"))
        )
        #expect(input.initialStatus == .trial)
        #expect(input.startDate == expectedStart)
        #expect(input.confirmedNextRenewal == expectedFirstPaidCharge)
        #expect(input.renewalAnchor == expectedFirstPaidCharge)
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
        minute: Int = 0,
        timeZoneIdentifier: String = "UTC"
    ) throws -> Date {
        let timeZone = try #require(TimeZone(identifier: timeZoneIdentifier))
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
