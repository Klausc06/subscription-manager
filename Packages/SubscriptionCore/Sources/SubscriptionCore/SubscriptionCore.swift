import Foundation
import Observation

public enum Currency: String, CaseIterable, Codable, Sendable {
    case cny = "CNY"
    case usd = "USD"
}

public struct Money: Codable, Equatable, Sendable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }
}

public enum BillingCycle: String, Codable, Sendable {
    case monthly
}

public struct ServiceIdentity: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ExpectedCharge: Codable, Equatable, Sendable {
    public let subscriptionID: UUID
    public let scheduledDate: Date
    public let amount: Money

    public init(
        subscriptionID: UUID,
        scheduledDate: Date,
        amount: Money
    ) {
        self.subscriptionID = subscriptionID
        self.scheduledDate = scheduledDate
        self.amount = amount
    }
}

public struct Subscription: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let serviceIdentity: ServiceIdentity
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money
    public let billingCycle: BillingCycle
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String

    public var firstExpectedCharge: ExpectedCharge {
        ExpectedCharge(
            subscriptionID: id,
            scheduledDate: confirmedNextRenewal,
            amount: originalAmount
        )
    }

    public init(
        id: UUID,
        serviceIdentity: ServiceIdentity,
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money,
        billingCycle: BillingCycle,
        startDate: Date,
        confirmedNextRenewal: Date,
        managementURL: URL?,
        notes: String
    ) {
        self.id = id
        self.serviceIdentity = serviceIdentity
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.billingCycle = billingCycle
        self.startDate = startDate
        self.confirmedNextRenewal = confirmedNextRenewal
        self.managementURL = managementURL
        self.notes = notes
    }
}

public struct SubscriptionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let serviceIdentity: ServiceIdentity
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money
    public let confirmedNextRenewal: Date
    public let firstExpectedCharge: ExpectedCharge

    public init(subscription: Subscription) {
        id = subscription.id
        serviceIdentity = subscription.serviceIdentity
        serviceName = subscription.serviceName
        plan = subscription.plan
        category = subscription.category
        originalAmount = subscription.originalAmount
        confirmedNextRenewal = subscription.confirmedNextRenewal
        firstExpectedCharge = subscription.firstExpectedCharge
    }
}

public struct MonthlySubscriptionCreationInput: Equatable, Sendable {
    public let serviceName: String
    public let plan: String
    public let category: String
    public let originalAmount: Money?
    public let startDate: Date
    public let confirmedNextRenewal: Date
    public let managementURL: URL?
    public let notes: String

    public init(
        serviceName: String,
        plan: String,
        category: String,
        originalAmount: Money?,
        startDate: Date,
        confirmedNextRenewal: Date,
        managementURL: URL?,
        notes: String
    ) {
        self.serviceName = serviceName
        self.plan = plan
        self.category = category
        self.originalAmount = originalAmount
        self.startDate = startDate
        self.confirmedNextRenewal = confirmedNextRenewal
        self.managementURL = managementURL
        self.notes = notes
    }
}

public enum SubscriptionCreationField: Hashable, Sendable {
    case serviceName
    case plan
    case category
    case originalAmount
    case confirmedNextRenewal
}

public enum SubscriptionCreationValidationError: Equatable, Sendable {
    case required
    case mustBePositive
    case beforeStartDate
}

public enum SubscriptionLibraryState: Equatable, Sendable {
    case loading
    case empty
    case loaded([SubscriptionSummary])
    case failed
}

public enum SubscriptionDetailState: Equatable, Sendable {
    case notLoaded
    case loaded(Subscription)
    case notFound
    case failed
}

@MainActor
public protocol SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws
    func listSubscriptions() throws -> [SubscriptionSummary]
    func subscription(id: UUID) throws -> Subscription?
}

@MainActor
@Observable
public final class SubscriptionWorkspace {
    public private(set) var libraryState: SubscriptionLibraryState = .loading
    public private(set) var detailState: SubscriptionDetailState = .notLoaded
    public private(set) var creationValidationErrors:
        [SubscriptionCreationField: SubscriptionCreationValidationError] = [:]

    private let repository: any SubscriptionRepository
    private let identifierGenerator: () -> UUID

    public init(
        repository: any SubscriptionRepository,
        identifierGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.identifierGenerator = identifierGenerator
    }

    public func createMonthlySubscription(
        _ input: MonthlySubscriptionCreationInput
    ) {
        creationValidationErrors = validate(input)
        guard creationValidationErrors.isEmpty,
              let originalAmount = input.originalAmount
        else {
            return
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        let id = identifierGenerator()
        let subscription = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(id.uuidString)"
            ),
            serviceName: input.serviceName.trimmingCharacters(in: whitespace),
            plan: input.plan.trimmingCharacters(in: whitespace),
            category: input.category.trimmingCharacters(in: whitespace),
            originalAmount: originalAmount,
            billingCycle: .monthly,
            startDate: input.startDate,
            confirmedNextRenewal: input.confirmedNextRenewal,
            managementURL: input.managementURL,
            notes: input.notes
        )

        do {
            try repository.createSubscription(subscription)
            detailState = .loaded(subscription)
            loadLibrary()
        } catch {
            detailState = .failed
        }
    }

    public func loadLibrary() {
        do {
            let subscriptions = try repository.listSubscriptions()
            if subscriptions.isEmpty {
                libraryState = .empty
            } else {
                libraryState = .loaded(subscriptions)
            }
        } catch {
            libraryState = .failed
        }
    }

    public func loadSubscription(id: UUID) {
        do {
            if let subscription = try repository.subscription(id: id) {
                detailState = .loaded(subscription)
            } else {
                detailState = .notFound
            }
        } catch {
            detailState = .failed
        }
    }

    private func validate(
        _ input: MonthlySubscriptionCreationInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.plan.trimmingCharacters(in: whitespace).isEmpty {
            errors[.plan] = .required
        }
        if input.category.trimmingCharacters(in: whitespace).isEmpty {
            errors[.category] = .required
        }
        if let originalAmount = input.originalAmount {
            if originalAmount.minorUnits <= 0 {
                errors[.originalAmount] = .mustBePositive
            }
        } else {
            errors[.originalAmount] = .required
        }
        if input.confirmedNextRenewal < input.startDate {
            errors[.confirmedNextRenewal] = .beforeStartDate
        }

        return errors
    }
}
