import Foundation
import Observation

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
