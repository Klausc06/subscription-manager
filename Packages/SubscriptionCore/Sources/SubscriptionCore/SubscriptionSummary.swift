import Foundation
import Observation

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

