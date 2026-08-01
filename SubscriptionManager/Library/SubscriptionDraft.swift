import Foundation
import SubscriptionCore

struct SubscriptionDraft: Equatable {
    enum DateSource: Hashable {
        case startDate
        case nextRenewal
    }

    enum Mode: Equatable {
        case creating(SubscriptionInitialStatus)
        case editing(SubscriptionLifecycle)
    }

    enum Validation: Hashable {
        case serviceName
        case amount
        case currency
        case billingInterval
        case billingDate
        case managementURL
    }

    var serviceName: String
    var plan: String
    var category: String
    var amountText: String
    var currency: Currency?
    var billingInterval: BillingInterval?
    var customIntervalValueText: String
    var customIntervalUnit: BillingIntervalUnit
    var billingTimeZoneIdentifier: String
    var startDate: Date
    var confirmedNextRenewal: Date
    var dateSource: DateSource
    var acceptedDateSources: Set<DateSource>
    var managementURLText: String
    var notes: String
    var mode: Mode
    var catalogPresetID: String?
    var catalogOfferID: String?

    // A cancelled subscription's renewal anchor is an independent persisted
    // fact. It cannot be reconstructed from its lifecycle dates after an
    // interval edit, so keep it in the value-only draft until Save.
    private var persistedRenewalAnchor: Date?

    static func manual(
        now: Date,
        timeZoneIdentifier: String
    ) -> Self {
        let placeholder = normalizedDate(
            now,
            timeZoneIdentifier: timeZoneIdentifier
        ) ?? now
        return Self(
            serviceName: "",
            plan: "",
            category: "",
            amountText: "",
            currency: nil,
            billingInterval: nil,
            customIntervalValueText: "",
            customIntervalUnit: .day,
            billingTimeZoneIdentifier: timeZoneIdentifier,
            startDate: placeholder,
            confirmedNextRenewal: placeholder,
            dateSource: .startDate,
            acceptedDateSources: [],
            managementURLText: "",
            notes: "",
            mode: .creating(.active),
            catalogPresetID: nil,
            catalogOfferID: nil,
            persistedRenewalAnchor: nil
        )
    }

    static func catalog(
        preset: CatalogPreset,
        offer: CatalogOffer?,
        now: Date,
        locale: Locale,
        timeZoneIdentifier: String
    ) -> Self {
        var draft = Self.manual(
            now: now,
            timeZoneIdentifier: timeZoneIdentifier
        )
        draft.serviceName = preset.serviceName.value(for: locale)
        draft.category = preset.category.value(for: locale)
        draft.managementURLText = preset.managementURL?.absoluteString ?? ""
        draft.catalogPresetID = preset.id

        // A review-required (or absent) offer is identity evidence only. In
        // particular, the preset's suggested interval is never a price or
        // schedule proof.
        guard let offer,
              let adoptedOffer = preset.offers.first(where: {
                  $0 == offer && $0.reviewStatus == .verified
              })
        else {
            return draft
        }

        draft.plan = adoptedOffer.planName.value(for: locale)
        draft.amountText = editableMoneyText(adoptedOffer.price, locale: locale)
        draft.currency = adoptedOffer.price.currency
        draft.billingInterval = adoptedOffer.billingInterval
        draft.setCustomIntervalFields(for: adoptedOffer.billingInterval)
        draft.catalogOfferID = adoptedOffer.id
        return draft
    }

    static func editing(
        subscription: Subscription,
        locale: Locale
    ) -> Self {
        let interval = subscription.billingSchedule.interval
        return Self(
            serviceName: subscription.serviceName,
            plan: subscription.plan,
            category: subscription.category,
            amountText: editableMoneyText(
                subscription.amount(onBillingDay: subscription.confirmedNextRenewal),
                locale: locale
            ),
            currency: subscription.amount(
                onBillingDay: subscription.confirmedNextRenewal
            ).currency,
            billingInterval: interval,
            customIntervalValueText: customIntervalText(for: interval),
            customIntervalUnit: customIntervalUnitValue(for: interval),
            billingTimeZoneIdentifier:
                subscription.billingSchedule.timeZoneIdentifier,
            startDate: subscription.startDate,
            confirmedNextRenewal: subscription.confirmedNextRenewal,
            dateSource: .startDate,
            acceptedDateSources: [.startDate, .nextRenewal],
            managementURLText: subscription.managementURL?.absoluteString ?? "",
            notes: subscription.notes,
            mode: .editing(subscription.lifecycle),
            catalogPresetID: nil,
            catalogOfferID: nil,
            persistedRenewalAnchor: subscription.billingSchedule.renewalAnchor
        )
    }

    @discardableResult
    mutating func selectStartDate(
        _ date: Date,
        asOf now: Date
    ) -> Bool {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let normalizedStart = normalizedDraftDate(date),
              let timeZone = TimeZone(identifier: billingTimeZoneIdentifier)
        else {
            return false
        }

        switch mode {
        case .creating(.active), .editing(.active):
            guard let interval = billingInterval,
                  interval.isValid,
                  let renewal = BillingDateResolver().nextRenewal(
                      afterStart: normalizedStart,
                      interval: interval,
                      asOf: now,
                      timeZone: timeZone
                  ),
                  let normalizedRenewal = normalizedBillingDate(
                      renewal,
                      timeZoneIdentifier: billingTimeZoneIdentifier
                  )
            else {
                return false
            }
            startDate = normalizedStart
            confirmedNextRenewal = normalizedRenewal
            dateSource = .startDate
            acceptedDateSources = [.startDate]
            return true
        case .creating(.trial), .editing(.trial), .editing(.cancelled):
            startDate = normalizedStart
            acceptedDateSources.insert(.startDate)
            return true
        }
    }

    @discardableResult
    mutating func selectNextRenewal(
        _ date: Date,
        asOf now: Date
    ) -> Bool {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let normalizedRenewal = normalizedDraftDate(date),
              let timeZone = TimeZone(identifier: billingTimeZoneIdentifier)
        else {
            return false
        }

        switch mode {
        case .creating(.active), .editing(.active):
            guard let interval = billingInterval,
                  interval.isValid,
                  let start = BillingDateResolver().previousCycleStart(
                      before: normalizedRenewal,
                      interval: interval,
                      timeZone: timeZone
                  ),
                  let normalizedStart = normalizedBillingDate(
                      start,
                      timeZoneIdentifier: billingTimeZoneIdentifier
                  )
            else {
                return false
            }
            startDate = normalizedStart
            confirmedNextRenewal = normalizedRenewal
            dateSource = .nextRenewal
            acceptedDateSources = [.nextRenewal]
            return true
        case .creating(.trial), .editing(.trial), .editing(.cancelled):
            confirmedNextRenewal = normalizedRenewal
            acceptedDateSources.insert(.nextRenewal)
            return true
        }
    }

    @discardableResult
    mutating func changeBillingInterval(
        _ interval: BillingInterval?,
        asOf now: Date
    ) -> Bool {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              startDate.timeIntervalSinceReferenceDate.isFinite,
              confirmedNextRenewal.timeIntervalSinceReferenceDate.isFinite,
              let interval,
              interval.isValid,
              TimeZone(identifier: billingTimeZoneIdentifier) != nil
        else {
            return false
        }

        switch mode {
        case .creating(.active), .editing(.active):
            let timeZone = TimeZone(identifier: billingTimeZoneIdentifier)!
            switch dateSource {
            case .startDate:
                guard let renewal = BillingDateResolver().nextRenewal(
                    afterStart: startDate,
                    interval: interval,
                    asOf: now,
                    timeZone: timeZone
                ),
                let normalizedRenewal = normalizedBillingDate(
                    renewal,
                    timeZoneIdentifier: billingTimeZoneIdentifier
                ) else {
                    return false
                }
                billingInterval = interval
                setCustomIntervalFields(for: interval)
                confirmedNextRenewal = normalizedRenewal
            case .nextRenewal:
                guard let start = BillingDateResolver().previousCycleStart(
                    before: confirmedNextRenewal,
                    interval: interval,
                    timeZone: timeZone
                ),
                let normalizedStart = normalizedBillingDate(
                    start,
                    timeZoneIdentifier: billingTimeZoneIdentifier
                ) else {
                    return false
                }
                billingInterval = interval
                setCustomIntervalFields(for: interval)
                startDate = normalizedStart
            }
            acceptedDateSources = [dateSource]
            return true
        case .creating(.trial), .editing(.trial), .editing(.cancelled):
            billingInterval = interval
            setCustomIntervalFields(for: interval)
            return true
        }
    }

    func parsedAmount(locale: Locale) -> Money? {
        guard let currency else { return nil }
        return MoneyTextParser.parse(
            amountText,
            currency: currency,
            locale: locale
        )
    }

    func requiredBillingSchedule() -> FixedBillingSchedule? {
        guard let interval = billingInterval,
              interval.isValid,
              TimeZone(identifier: billingTimeZoneIdentifier) != nil,
              let anchor = renewalAnchorForCurrentMode,
              anchor.timeIntervalSinceReferenceDate.isFinite,
              startDate.timeIntervalSinceReferenceDate.isFinite,
              confirmedNextRenewal.timeIntervalSinceReferenceDate.isFinite
        else {
            return nil
        }
        return FixedBillingSchedule(
            interval: interval,
            renewalAnchor: anchor,
            timeZoneIdentifier: billingTimeZoneIdentifier
        )
    }

    func makeCreationInput(locale: Locale) -> SubscriptionCreationInput? {
        guard case .creating(let initialStatus) = mode,
              validation(for: locale).isEmpty,
              let amount = parsedAmount(locale: locale),
              let schedule = requiredBillingSchedule(),
              let normalizedAnchor = normalizedBillingDate(
                  schedule.renewalAnchor,
                  timeZoneIdentifier: billingTimeZoneIdentifier
              )
        else {
            return nil
        }
        let managementURL = parsedManagementURL()
        return SubscriptionCreationInput(
            serviceName: trimmed(serviceName),
            plan: trimmed(plan),
            category: trimmed(category),
            originalAmount: amount,
            billingInterval: schedule.interval,
            startDate: normalizedBillingDate(
                startDate,
                timeZoneIdentifier: billingTimeZoneIdentifier
            ) ?? startDate,
            renewalAnchor: normalizedAnchor,
            confirmedNextRenewal: normalizedBillingDate(
                confirmedNextRenewal,
                timeZoneIdentifier: billingTimeZoneIdentifier
            ) ?? confirmedNextRenewal,
            billingTimeZoneIdentifier: billingTimeZoneIdentifier,
            managementURL: managementURL,
            notes: notes,
            initialStatus: initialStatus
        )
    }

    func makeEditInput(locale: Locale) -> SubscriptionEditInput? {
        guard case .editing = mode,
              validation(for: locale).isEmpty,
              let amount = parsedAmount(locale: locale),
              let schedule = requiredBillingSchedule(),
              let normalizedStart = normalizedBillingDate(
                  startDate,
                  timeZoneIdentifier: billingTimeZoneIdentifier
              ),
              let normalizedRenewal = normalizedBillingDate(
                  confirmedNextRenewal,
                  timeZoneIdentifier: billingTimeZoneIdentifier
              ),
              let normalizedAnchor = normalizedBillingDate(
                  schedule.renewalAnchor,
                  timeZoneIdentifier: billingTimeZoneIdentifier
              )
        else {
            return nil
        }
        let managementURL = parsedManagementURL()
        let normalizedSchedule = FixedBillingSchedule(
            interval: schedule.interval,
            renewalAnchor: normalizedAnchor,
            timeZoneIdentifier: schedule.timeZoneIdentifier
        )
        return SubscriptionEditInput(
            serviceName: trimmed(serviceName),
            plan: trimmed(plan),
            category: trimmed(category),
            amount: amount,
            billingSchedule: normalizedSchedule,
            startDate: normalizedStart,
            confirmedNextRenewal: normalizedRenewal,
            managementURL: managementURL,
            notes: notes
        )
    }

    var validation: Set<Validation> {
        validation(for: .current)
    }

    private func validation(for locale: Locale) -> Set<Validation> {
        var errors = Set<Validation>()
        if trimmed(serviceName).isEmpty {
            errors.insert(.serviceName)
        }
        if parsedAmount(locale: locale) == nil {
            errors.insert(.amount)
        }
        if currency == nil {
            errors.insert(.currency)
        }
        guard let interval = billingInterval, interval.isValid else {
            errors.insert(.billingInterval)
            return insertDateValidation(into: errors)
        }
        guard TimeZone(identifier: billingTimeZoneIdentifier) != nil else {
            errors.insert(.billingInterval)
            return insertDateValidation(into: errors)
        }
        guard startDate.timeIntervalSinceReferenceDate.isFinite,
              confirmedNextRenewal.timeIntervalSinceReferenceDate.isFinite
        else {
            errors.insert(.billingDate)
            return errors
        }

        switch mode {
        case .creating(.active):
            guard acceptedDateSources.count == 1,
                  acceptedDateSources.contains(dateSource)
            else {
                errors.insert(.billingDate)
                return errors
            }
        case .editing(.active):
            guard !acceptedDateSources.isEmpty,
                  acceptedDateSources.contains(dateSource)
            else {
                errors.insert(.billingDate)
                return errors
            }
        case .creating(.trial), .editing(.trial):
            guard acceptedDateSources.contains(.startDate),
                  acceptedDateSources.contains(.nextRenewal),
                  confirmedNextRenewal >= startDate
            else {
                errors.insert(.billingDate)
                return errors
            }
        case .editing(.cancelled):
            guard acceptedDateSources.contains(.startDate),
                  acceptedDateSources.contains(.nextRenewal),
                  let anchor = renewalAnchorForCurrentMode,
                  anchor.timeIntervalSinceReferenceDate.isFinite,
                  anchor >= startDate,
                  confirmedNextRenewal >= startDate
            else {
                errors.insert(.billingDate)
                return errors
            }
        }

        if case .invalid = ManagementURLParser.parse(managementURLText) {
            errors.insert(.managementURL)
        }
        return errors
    }

    private func insertDateValidation(
        into errors: Set<Validation>
    ) -> Set<Validation> {
        var errors = errors
        if !startDate.timeIntervalSinceReferenceDate.isFinite
            || !confirmedNextRenewal.timeIntervalSinceReferenceDate.isFinite
        {
            errors.insert(.billingDate)
        }
        switch mode {
        case .creating(.active):
            if acceptedDateSources.count != 1 {
                errors.insert(.billingDate)
            }
        case .editing(.active):
            if acceptedDateSources.isEmpty {
                errors.insert(.billingDate)
            }
        case .creating(.trial), .editing(.trial), .editing(.cancelled):
            if !acceptedDateSources.contains(.startDate)
                || !acceptedDateSources.contains(.nextRenewal)
            {
                errors.insert(.billingDate)
            }
        }
        if case .invalid = ManagementURLParser.parse(managementURLText) {
            errors.insert(.managementURL)
        }
        return errors
    }

    private var renewalAnchorForCurrentMode: Date? {
        switch mode {
        case .creating(.active), .editing(.active):
            startDate
        case .creating(.trial), .editing(.trial):
            confirmedNextRenewal
        case .editing(.cancelled):
            persistedRenewalAnchor ?? startDate
        }
    }

    private func parsedManagementURL() -> URL? {
        switch ManagementURLParser.parse(managementURLText) {
        case .empty:
            return nil
        case .valid(let url):
            return url
        case .invalid:
            return nil
        }
    }

    private mutating func setCustomIntervalFields(
        for interval: BillingInterval
    ) {
        customIntervalValueText = customIntervalText(for: interval)
        customIntervalUnit = customIntervalUnitValue(for: interval)
    }

    private func normalizedDraftDate(_ date: Date) -> Date? {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let timeZone = TimeZone(identifier: billingTimeZoneIdentifier)
        else {
            return nil
        }
        return normalizedBillingDate(
            date,
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedDate(
        _ date: Date,
        timeZoneIdentifier: String
    ) -> Date? {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let timeZone = TimeZone(identifier: timeZoneIdentifier)
        else {
            return nil
        }
        return normalizedBillingDate(
            date,
            timeZoneIdentifier: timeZone.identifier
        )
    }
}

private func customIntervalText(for interval: BillingInterval) -> String {
    guard case .custom(let value, _) = interval else { return "" }
    return String(value)
}

private func customIntervalUnitValue(
    for interval: BillingInterval
) -> BillingIntervalUnit {
    guard case .custom(_, let unit) = interval else { return .day }
    return unit
}
