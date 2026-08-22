import Foundation
import Observation

public struct SubscriptionCreationInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money?
    public let billingInterval: BillingInterval
    public let startDate: Date
    public let renewalAnchor: Date
    public let confirmedNextRenewal: Date
    public let billingTimeZoneIdentifier: String
    public let managementURL: URL?
    public let notes: String
    public let initialStatus: SubscriptionInitialStatus

    public init(
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money?,
        billingInterval: BillingInterval = .monthly,
        startDate: Date,
        renewalAnchor: Date? = nil,
        confirmedNextRenewal: Date,
        billingTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        managementURL: URL?,
        notes: String,
        initialStatus: SubscriptionInitialStatus = .active
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.billingInterval = billingInterval
        self.startDate = startDate
        self.renewalAnchor = renewalAnchor ?? startDate
        self.confirmedNextRenewal = confirmedNextRenewal
        self.billingTimeZoneIdentifier = billingTimeZoneIdentifier
        self.managementURL = managementURL
        self.notes = notes
        self.initialStatus = initialStatus
    }
}

public enum CatalogBillingIntervalSelection: Equatable, Sendable {
    case official
    case `override`(BillingInterval)
}

public struct CatalogOfferSubscriptionInput: Equatable, Sendable {
    public let offerID: String
    public let actualChargeOverride: Money?
    public let billingIntervalSelection: CatalogBillingIntervalSelection
    public let startDate: Date
    public let renewalAnchor: Date
    public let confirmedNextRenewal: Date
    public let billingTimeZoneIdentifier: String
    public let notes: String
    public let initialStatus: SubscriptionInitialStatus

    public init(
        offerID: String,
        actualChargeOverride: Money?,
        billingIntervalSelection: CatalogBillingIntervalSelection = .official,
        startDate: Date,
        renewalAnchor: Date,
        confirmedNextRenewal: Date,
        billingTimeZoneIdentifier: String,
        notes: String,
        initialStatus: SubscriptionInitialStatus
    ) {
        self.offerID = offerID
        self.actualChargeOverride = actualChargeOverride
        self.billingIntervalSelection = billingIntervalSelection
        self.startDate = startDate
        self.renewalAnchor = renewalAnchor
        self.confirmedNextRenewal = confirmedNextRenewal
        self.billingTimeZoneIdentifier = billingTimeZoneIdentifier
        self.notes = notes
        self.initialStatus = initialStatus
    }
}

public enum CatalogSubscriptionCreationCommand: Equatable, Sendable {
    case verifiedOffer(CatalogOfferSubscriptionInput)
    case legacy(SubscriptionCreationInput)
}

public enum CatalogSubscriptionCreationRejection: Equatable, Sendable {
    case presetNotFound
    case offerNotFound
    case offerRequiresReview
    case verifiedOfferRequired
}

public enum CatalogSubscriptionCreationResult: Equatable, Sendable {
    case created(Subscription)
    case rejected(CatalogSubscriptionCreationRejection)
    case validationFailed
    case persistenceFailed
}

@available(*, deprecated, renamed: "SubscriptionCreationInput")
public typealias MonthlySubscriptionCreationInput = SubscriptionCreationInput

public struct SubscriptionEditInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let amount: Money
    public let billingSchedule: FixedBillingSchedule
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String

    public init(
        serviceName: String,
        plan: String,
        category: String,
        amount: Money,
        billingSchedule: FixedBillingSchedule,
        startDate: Date,
        confirmedNextRenewal: Date? = nil,
        managementURL: URL?,
        notes: String
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.amount = amount
        self.billingSchedule = billingSchedule
        self.startDate = startDate
        self.confirmedNextRenewal =
            confirmedNextRenewal ?? billingSchedule.renewalAnchor
        self.managementURL = managementURL
        self.notes = notes
    }

    public init(
        subscription: Subscription,
        billingSchedule: FixedBillingSchedule
    ) {
        self.init(
            serviceName: subscription.serviceName,
            plan: subscription.plan,
            category: subscription.category,
            amount: subscription.amount(
                onBillingDay: subscription.confirmedNextRenewal
            ),
            billingSchedule: billingSchedule,
            startDate: subscription.startDate,
            confirmedNextRenewal: subscription.confirmedNextRenewal,
            managementURL: subscription.managementURL,
            notes: subscription.notes
        )
    }
}

public enum SubscriptionCreationField: Hashable, Sendable {
    case serviceName
    case plan
    case category
    case originalAmount
    case renewalAnchor
    case confirmedNextRenewal
    case billingSchedule
}

public enum SubscriptionCreationValidationError: Equatable, Sendable {
    case required
    case mustBePositive
    case beforeStartDate
}

public enum SubscriptionCreationResult: Equatable, Sendable {
    case created(Subscription)
    case validationFailed
    case persistenceFailed
}

