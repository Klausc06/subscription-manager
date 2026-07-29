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
                renewalAnchor: startDate,
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
    }
}
