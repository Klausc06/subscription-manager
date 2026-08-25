import AppIntents
import Foundation
import SubscriptionCore

enum SubscriptionCurrencyIntentValue: String, AppEnum {
    case cny = "CNY"
    case usd = "USD"
    case eur = "EUR"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .cny: "CNY",
        .usd: "USD",
        .eur: "EUR",
    ]

    var currency: Currency { Currency(rawValue: rawValue)! }
}

enum SubscriptionIntervalIntentValue: String, AppEnum {
    case weekly
    case monthly
    case quarterly
    case yearly

    static let typeDisplayRepresentation: TypeDisplayRepresentation =
        "Billing Interval"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .weekly: "Weekly",
        .monthly: "Monthly",
        .quarterly: "Quarterly",
        .yearly: "Yearly",
    ]

    var billingInterval: BillingInterval {
        switch self {
        case .weekly: .weekly
        case .monthly: .monthly
        case .quarterly: .quarterly
        case .yearly: .yearly
        }
    }
}

enum SubscriptionInitialStatusIntentValue: String, AppEnum {
    case active
    case trial

    static let typeDisplayRepresentation: TypeDisplayRepresentation =
        "Initial Status"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .active: "Active",
        .trial: "Trial",
    ]

    var status: SubscriptionInitialStatus {
        switch self {
        case .active: .active
        case .trial: .trial
        }
    }
}

struct AddSubscriptionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Subscription"
    static let description = IntentDescription("Add a subscription to your library.")
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background

    @Dependency private var service: SubscriptionIntentService

    @Parameter(title: "Service Name") var serviceName: String
    @Parameter(title: "Plan") var plan: String
    @Parameter(title: "Category") var category: String
    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Currency") var currency: SubscriptionCurrencyIntentValue
    @Parameter(title: "Billing Interval") var interval: SubscriptionIntervalIntentValue
    @Parameter(title: "Start Date") var startDate: Date
    @Parameter(title: "Next Renewal") var nextRenewal: Date
    @Parameter(title: "Initial Status") var initialStatus: SubscriptionInitialStatusIntentValue

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$serviceName) subscription")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let minorUnits = NSDecimalNumber(value: amount)
            .multiplying(by: 100)
            .rounding(accordingToBehavior: nil)
            .int64Value
        let result = await service.add(
            SubscriptionCreationInput(
                serviceName: serviceName,
                plan: plan,
                category: category,
                originalAmount: Money(
                    minorUnits: minorUnits,
                    currency: currency.currency
                ),
                billingInterval: interval.billingInterval,
                startDate: startDate,
                renewalAnchor: initialStatus.status == .trial
                    ? nextRenewal
                    : startDate,
                confirmedNextRenewal: nextRenewal,
                managementURL: nil,
                notes: "",
                initialStatus: initialStatus.status
            )
        )
        switch result {
        case .created:
            return .result(dialog: "Subscription added.")
        case .validationFailed:
            return .result(dialog: "Check the subscription details and try again.")
        case .persistenceFailed:
            return .result(dialog: "Couldn’t save this subscription. Try again.")
        }
    }
}

struct ShowUpcomingRenewalsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Upcoming Renewals"
    static let description = IntentDescription("Show your upcoming subscription renewals.")
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background

    @Dependency private var service: SubscriptionIntentService

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let through = Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: now
        ) ?? now
        let renewals = try await service.upcomingRenewals(from: now, through: through)
        return renewals.isEmpty
            ? .result(dialog: "No upcoming renewals in the next 30 days.")
            : .result(dialog: "Upcoming renewals are available in Subscription Manager.")
    }
}

struct ShowMonthlyForecastIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Monthly Forecast"
    static let description = IntentDescription("Show this month’s expected subscription spending.")
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background

    @Dependency private var service: SubscriptionIntentService

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let forecast = await service.monthlyForecast(containing: Date())
        guard case .available = forecast else {
            return .result(dialog: "Forecast is unavailable. Open Subscription Manager and try again.")
        }
        return .result(dialog: "Your monthly forecast is available in Subscription Manager.")
    }
}

struct FindSubscriptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Subscriptions"
    static let description = IntentDescription(
        "Search your subscription library by name."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background

    @Dependency private var service: SubscriptionIntentService

    @Parameter(title: "Search Query") var query: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Find subscriptions matching \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog
        & ReturnsValue<[SubscriptionAppEntity]>
    {
        let subscriptions = try await service.subscriptions()
        let filtered: [Subscription]
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = subscriptions.filter {
                $0.serviceName.localizedCaseInsensitiveContains(query)
                    || $0.plan.localizedCaseInsensitiveContains(query)
                    || $0.category.localizedCaseInsensitiveContains(query)
            }
        } else {
            filtered = subscriptions.filter { !$0.isArchived }
        }
        let entities = filtered.map(SubscriptionAppEntity.init)
        let count = entities.count
        let dialog: IntentDialog = count == 0
            ? "No matching subscriptions found."
            : "Found \(count) subscription(s)."
        return .result(value: entities, dialog: dialog)
    }
}

struct NextRenewalIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Renewal"
    static let description = IntentDescription(
        "Check when a subscription renews next."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background

    @Dependency private var service: SubscriptionIntentService

    @Parameter(title: "Subscription") var subscription: SubscriptionAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("When does \(\.$subscription) renew?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let date = subscription.nextRenewalDate else {
            return .result(
                dialog: "No renewal date is available for \(subscription.serviceName)."
            )
        }
        let formatted = date.formatted(.dateTime.month().day().year())
        return .result(
            dialog: "\(subscription.serviceName) renews on \(formatted) for \(subscription.amountDescription)."
        )
    }
}

struct MonthlySpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Monthly Spending Total"
    static let description = IntentDescription(
        "Get your total expected subscription spending this month."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background

    @Dependency private var service: SubscriptionIntentService

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await service.monthlyForecast(containing: Date())
        guard case .available(let insights) = state else {
            return .result(
                dialog: "Monthly spending is unavailable. Open the app and try again."
            )
        }
        let total = insights.selectedRangeTotal
        let amount = Decimal(total.minorUnits) / 100
        let formatted = amount.formatted(
            .currency(code: total.currency.rawValue)
        )
        return .result(
            dialog: "Your expected subscription spending this month is \(formatted)."
        )
    }
}

struct SubscriptionManagerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddSubscriptionIntent(),
            phrases: ["Add a subscription in \(.applicationName)"],
            shortTitle: "Add Subscription",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ShowUpcomingRenewalsIntent(),
            phrases: ["Show upcoming renewals in \(.applicationName)"],
            shortTitle: "Upcoming Renewals",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: ShowMonthlyForecastIntent(),
            phrases: ["Show monthly forecast in \(.applicationName)"],
            shortTitle: "Monthly Forecast",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: FindSubscriptionsIntent(),
            phrases: ["Find subscriptions in \(.applicationName)"],
            shortTitle: "Find Subscriptions",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: NextRenewalIntent(),
            phrases: [
                "When does \(\.$subscription) renew in \(.applicationName)",
            ],
            shortTitle: "Next Renewal",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: MonthlySpendIntent(),
            phrases: [
                "How much do I spend on subscriptions in \(.applicationName)",
            ],
            shortTitle: "Monthly Spending",
            systemImageName: "dollarsign.circle"
        )
    }
}
