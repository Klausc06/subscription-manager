import SubscriptionCore
import SwiftUI

enum BillingIntervalChoice: String, CaseIterable, Identifiable {
    case weekly
    case monthly
    case quarterly
    case halfYearly
    case yearly
    case custom

    var id: String { rawValue }

    init(interval: BillingInterval) {
        switch interval {
        case .weekly:
            self = .weekly
        case .monthly:
            self = .monthly
        case .quarterly:
            self = .quarterly
        case .halfYearly:
            self = .halfYearly
        case .yearly:
            self = .yearly
        case .custom:
            self = .custom
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .weekly:
            "Weekly"
        case .monthly:
            "Monthly"
        case .quarterly:
            "Quarterly"
        case .halfYearly:
            "Half-yearly"
        case .yearly:
            "Yearly"
        case .custom:
            "Custom"
        }
    }

    func interval(
        customValueText: String,
        customUnit: BillingIntervalUnit
    ) -> BillingInterval {
        switch self {
        case .weekly:
            .weekly
        case .monthly:
            .monthly
        case .quarterly:
            .quarterly
        case .halfYearly:
            .halfYearly
        case .yearly:
            .yearly
        case .custom:
            .custom(
                value: Int(customValueText) ?? 0,
                unit: customUnit
            )
        }
    }
}

struct BillingScheduleFields: View {
    @Binding var intervalChoice: BillingIntervalChoice
    @Binding var customValueText: String
    @Binding var customUnit: BillingIntervalUnit

    let validationError: SubscriptionCreationValidationError?

    var body: some View {
        Picker("Billing Interval", selection: $intervalChoice) {
            ForEach(BillingIntervalChoice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .accessibilityIdentifier("subscription.form.billing-interval")

        if intervalChoice == .custom {
            TextField("Interval", text: $customValueText)
                .subscriptionNumberKeyboard()
                .accessibilityIdentifier(
                    "subscription.form.custom-interval-value"
                )

            Picker("Unit", selection: $customUnit) {
                ForEach(BillingIntervalUnit.allCases, id: \.rawValue) { unit in
                    Text(unit.localizedTitle).tag(unit)
                }
            }
            .accessibilityIdentifier("subscription.form.custom-interval-unit")
        }

        if let validationError {
            ValidationMessage(
                billingScheduleValidationText(for: validationError),
                identifier: "subscription.validation.billing-schedule"
            )
        }
    }
}

func localizedBillingInterval(_ interval: BillingInterval) -> String {
    switch interval {
    case .weekly:
        String(localized: "Weekly")
    case .monthly:
        String(localized: "Monthly")
    case .quarterly:
        String(localized: "Quarterly")
    case .halfYearly:
        String(localized: "Half-yearly")
    case .yearly:
        String(localized: "Yearly")
    case .custom(let value, let unit):
        "\(String(localized: "Custom")) · \(value) \(unit.localizedString)"
    }
}

func billingScheduleValidationText(
    for error: SubscriptionCreationValidationError
) -> LocalizedStringKey {
    switch error {
    case .mustBePositive:
        "Enter an interval greater than zero."
    case .required, .beforeStartDate:
        "Choose a valid billing schedule."
    }
}

private extension BillingIntervalUnit {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .day:
            "Days"
        case .week:
            "Weeks"
        case .month:
            "Months"
        case .year:
            "Years"
        }
    }

    var localizedString: String {
        switch self {
        case .day:
            String(localized: "Days")
        case .week:
            String(localized: "Weeks")
        case .month:
            String(localized: "Months")
        case .year:
            String(localized: "Years")
        }
    }
}
