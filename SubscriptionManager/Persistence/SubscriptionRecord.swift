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
    var startDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    var confirmedNextRenewal: Date = Date(timeIntervalSinceReferenceDate: 0)
    var managementURLString: String?
    var notes: String?

    init(
        id: UUID,
        serviceIdentityRawValue: String = "",
        serviceName: String = "",
        plan: String = "",
        category: String = "",
        originalMinorUnits: Int64 = 0,
        currencyRawValue: String = "USD",
        billingCycleRawValue: String = "monthly",
        startDate: Date = Date(timeIntervalSinceReferenceDate: 0),
        confirmedNextRenewal: Date = Date(
            timeIntervalSinceReferenceDate: 0
        ),
        managementURLString: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.serviceIdentityRawValue = serviceIdentityRawValue
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalMinorUnits = originalMinorUnits
        self.currencyRawValue = currencyRawValue
        self.billingCycleRawValue = billingCycleRawValue
        self.startDate = startDate
        self.confirmedNextRenewal = confirmedNextRenewal
        self.managementURLString = managementURLString
        self.notes = notes
    }
}
