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
    var lifecycleRawValue: String?
    var trialFirstPaidChargeAt: Date?
    var cancelledAt: Date?
    var accessUntil: Date?
    var isArchived: Bool?

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
        isArchived: Bool? = nil
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
    }
}

@Model
final class UserPreferencesRecord {
    var primaryCurrencyRawValue: String = "CNY"
    var calendarProjectionHorizonMonths: Int = 12
    var hideAmountsInCalendar: Bool = false
    var menuBarModeEnabled: Bool = false
    var setupStatusRawValue: String = "notCompleted"

    init(
        primaryCurrencyRawValue: String = "CNY",
        calendarProjectionHorizonMonths: Int = 12,
        hideAmountsInCalendar: Bool = false,
        menuBarModeEnabled: Bool = false,
        setupStatusRawValue: String = "notCompleted"
    ) {
        self.primaryCurrencyRawValue = primaryCurrencyRawValue
        self.calendarProjectionHorizonMonths =
            calendarProjectionHorizonMonths
        self.hideAmountsInCalendar = hideAmountsInCalendar
        self.menuBarModeEnabled = menuBarModeEnabled
        self.setupStatusRawValue = setupStatusRawValue
    }
}

@Model
final class CalendarProjectionMappingRecord {
    var projectionUID: String = ""
    var eventIdentifier: String = ""
    var calendarIdentifier: String = ""
    var calendarSyncDisabled: Bool = false

    init(
        projectionUID: String = "",
        eventIdentifier: String = "",
        calendarIdentifier: String
    ) {
        self.projectionUID = projectionUID
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
    }
}
