import Foundation
import SwiftData

@Model
final class SubscriptionRecord {
    var id: UUID = UUID()
    var serviceIdentityRawValue: String = ""
    var serviceName: String = ""
    var plan: String = ""
    var category: String = ""
    var originalMinorUnits: Int64 = 0
    var currencyRawValue: String = "USD"
    var billingCycleRawValue: String = "monthly"
    var billingIntervalValue: Int?
    var billingIntervalUnitRawValue: String?
    var billingTimeZoneIdentifier: String?
    var startDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var renewalAnchor: Date?
    var confirmedNextRenewal: Date = Date(timeIntervalSinceReferenceDate: 0)
    var managementURLString: String?
    var notes: String?
    var confirmedChargesData: Data?
    var priceChangesData: Data?
    @Relationship(deleteRule: .cascade, inverse: \ConfirmedChargeRecord.subscription)
    var confirmedChargeRecords: [ConfirmedChargeRecord]?
    @Relationship(deleteRule: .cascade, inverse: \PriceChangeRecord.subscription)
    var priceChangeRecords: [PriceChangeRecord]?
    var lifecycleRawValue: String?
    var trialFirstPaidChargeAt: Date?
    var cancelledAt: Date?
    var accessUntil: Date?
    var isArchived: Bool?
    var pinnedAt: Date?

    init(
        id: UUID,
        serviceIdentityRawValue: String = "",
        serviceName: String = "",
        plan: String = "",
        category: String = "",
        originalMinorUnits: Int64 = 0,
        currencyRawValue: String = "USD",
        billingCycleRawValue: String = "monthly",
        billingIntervalValue: Int? = nil,
        billingIntervalUnitRawValue: String? = nil,
        billingTimeZoneIdentifier: String? = nil,
        startDate: Date = Date(timeIntervalSinceReferenceDate: 0),
        renewalAnchor: Date? = nil,
        confirmedNextRenewal: Date = Date(
            timeIntervalSinceReferenceDate: 0
        ),
        managementURLString: String? = nil,
        notes: String? = nil,
        confirmedChargesData: Data? = nil,
        priceChangesData: Data? = nil,
        lifecycleRawValue: String? = nil,
        trialFirstPaidChargeAt: Date? = nil,
        cancelledAt: Date? = nil,
        accessUntil: Date? = nil,
        isArchived: Bool? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.serviceIdentityRawValue = serviceIdentityRawValue
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalMinorUnits = originalMinorUnits
        self.currencyRawValue = currencyRawValue
        self.billingCycleRawValue = billingCycleRawValue
        self.billingIntervalValue = billingIntervalValue
        self.billingIntervalUnitRawValue = billingIntervalUnitRawValue
        self.billingTimeZoneIdentifier = billingTimeZoneIdentifier
        self.startDate = startDate
        self.renewalAnchor = renewalAnchor
        self.confirmedNextRenewal = confirmedNextRenewal
        self.managementURLString = managementURLString
        self.notes = notes
        self.confirmedChargesData = confirmedChargesData
        self.priceChangesData = priceChangesData
        self.lifecycleRawValue = lifecycleRawValue
        self.trialFirstPaidChargeAt = trialFirstPaidChargeAt
        self.cancelledAt = cancelledAt
        self.accessUntil = accessUntil
        self.isArchived = isArchived
        self.pinnedAt = pinnedAt
    }
}

@Model
final class ConfirmedChargeRecord {
    var id: UUID = UUID()
    var sequence: Int = 0
    var appendOrderDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var chargedDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var amountMinorUnits: Int64 = 0
    var currencyRawValue: String = "USD"
    var sourceScheduledChargeSubscriptionID: UUID?
    var sourceScheduledChargeYear: Int?
    var sourceScheduledChargeMonth: Int?
    var sourceScheduledChargeDay: Int?
    var subscriptionID: UUID?
    var subscription: SubscriptionRecord?

    init(
        id: UUID,
        sequence: Int,
        appendOrderDate: Date = Date(timeIntervalSinceReferenceDate: 0),
        chargedDate: Date,
        amountMinorUnits: Int64,
        currencyRawValue: String,
        sourceScheduledChargeSubscriptionID: UUID? = nil,
        sourceScheduledChargeYear: Int? = nil,
        sourceScheduledChargeMonth: Int? = nil,
        sourceScheduledChargeDay: Int? = nil,
        subscriptionID: UUID? = nil,
        subscription: SubscriptionRecord? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.appendOrderDate = appendOrderDate
        self.chargedDate = chargedDate
        self.amountMinorUnits = amountMinorUnits
        self.currencyRawValue = currencyRawValue
        self.sourceScheduledChargeSubscriptionID =
            sourceScheduledChargeSubscriptionID
        self.sourceScheduledChargeYear = sourceScheduledChargeYear
        self.sourceScheduledChargeMonth = sourceScheduledChargeMonth
        self.sourceScheduledChargeDay = sourceScheduledChargeDay
        self.subscriptionID = subscriptionID
        self.subscription = subscription
    }
}

@Model
final class PriceChangeRecord {
    var id: UUID = UUID()
    var sequence: Int = 0
    var appendOrderDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var effectiveDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var amountMinorUnits: Int64 = 0
    var currencyRawValue: String = "USD"
    var subscriptionID: UUID?
    var subscription: SubscriptionRecord?

    init(
        id: UUID,
        sequence: Int,
        appendOrderDate: Date = Date(timeIntervalSinceReferenceDate: 0),
        effectiveDate: Date,
        amountMinorUnits: Int64,
        currencyRawValue: String,
        subscriptionID: UUID? = nil,
        subscription: SubscriptionRecord? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.appendOrderDate = appendOrderDate
        self.effectiveDate = effectiveDate
        self.amountMinorUnits = amountMinorUnits
        self.currencyRawValue = currencyRawValue
        self.subscriptionID = subscriptionID
        self.subscription = subscription
    }
}

@Model
final class UserPreferencesRecord {
    static let canonicalID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000001"
    )!
    var id: UUID = UserPreferencesRecord.canonicalID
    var primaryCurrencyRawValue: String = "CNY"
    var calendarProjectionHorizonMonths: Int = 12
    var hideAmountsInCalendar: Bool = false
    var menuBarModeEnabled: Bool = false
    var appearanceModeRawValue: String = "system"
    var setupStatusRawValue: String = "notCompleted"

    init(
        id: UUID = UserPreferencesRecord.canonicalID,
        primaryCurrencyRawValue: String = "CNY",
        calendarProjectionHorizonMonths: Int = 12,
        hideAmountsInCalendar: Bool = false,
        menuBarModeEnabled: Bool = false,
        appearanceModeRawValue: String = "system",
        setupStatusRawValue: String = "notCompleted"
    ) {
        self.id = id
        self.primaryCurrencyRawValue = primaryCurrencyRawValue
        self.calendarProjectionHorizonMonths =
            calendarProjectionHorizonMonths
        self.hideAmountsInCalendar = hideAmountsInCalendar
        self.menuBarModeEnabled = menuBarModeEnabled
        self.appearanceModeRawValue = appearanceModeRawValue
        self.setupStatusRawValue = setupStatusRawValue
    }
}

@Model
final class CalendarProjectionMappingRecord {
    var projectionUID: String = ""
    var eventIdentifier: String = ""
    var calendarIdentifier: String = ""
    var calendarSyncDisabled: Bool = false
    var legacyMappingMigrationCompleted: Bool = false

    init(
        projectionUID: String = "",
        eventIdentifier: String = "",
        calendarIdentifier: String,
        legacyMappingMigrationCompleted: Bool = false
    ) {
        self.projectionUID = projectionUID
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.legacyMappingMigrationCompleted =
            legacyMappingMigrationCompleted
    }
}
