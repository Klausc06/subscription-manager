import Foundation
import SwiftData

@Model
final class SubscriptionRecord {
    var id: UUID
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
        confirmedChargesData: Data? = nil
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
    }
}
