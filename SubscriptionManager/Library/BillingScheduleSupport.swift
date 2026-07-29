import Foundation
import SubscriptionCore
import SwiftUI

func normalizedBillingDate(
    _ date: Date,
    timeZoneIdentifier: String
) -> Date? {
    guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
        return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    var components = calendar.dateComponents(
        [.year, .month, .day],
        from: date
    )
    components.hour = 12
    return calendar.date(from: components)
}

func billingTimeZone(identifier: String) -> TimeZone {
    TimeZone(identifier: identifier) ?? .autoupdatingCurrent
}

func formattedBillingDate(
    _ date: Date,
    timeZoneIdentifier: String,
    locale: Locale
) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = billingTimeZone(identifier: timeZoneIdentifier)
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

func defaultNextRenewal(
    after date: Date,
    interval: BillingInterval,
    timeZoneIdentifier: String
) -> Date {
    guard interval.isValid,
          let calendar = BillingCalendar.calendar(
              timeZoneIdentifier: timeZoneIdentifier
          )
    else {
        return date
    }
    let component: Calendar.Component
    let value: Int
    switch interval {
    case .weekly:
        component = .weekOfYear
        value = 1
    case .monthly:
        component = .month
        value = 1
    case .quarterly:
        component = .month
        value = 3
    case .halfYearly:
        component = .month
        value = 6
    case .yearly:
        component = .year
        value = 1
    case .custom(let count, let unit):
        switch unit {
        case .day:
            component = .day
            value = count
        case .week:
            component = .weekOfYear
            value = count
        case .month:
            component = .month
            value = count
        case .year:
            component = .year
            value = count
        }
    }
    return calendar.date(
        byAdding: component,
        value: value,
        to: date
    ) ?? date
}

enum BillingDateField {
    case startDate
    case renewalAnchor
    case nextRenewal
}

struct BillingDateEditState {
    private var nextRenewalWasEdited = false

    mutating func recordUserEdit(_ field: BillingDateField) {
        if field == .nextRenewal {
            nextRenewalWasEdited = true
        }
    }

    func nextRenewal(
        current: Date,
        after renewalAnchor: Date,
        interval: BillingInterval,
        timeZoneIdentifier: String
    ) -> Date {
        guard !nextRenewalWasEdited else {
            return current
        }
        return defaultNextRenewal(
            after: renewalAnchor,
            interval: interval,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

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

struct BillingIntervalFormValues {
    let choice: BillingIntervalChoice
    let customValueText: String
    let customUnit: BillingIntervalUnit

    init(interval: BillingInterval) {
        choice = BillingIntervalChoice(interval: interval)
        switch interval {
        case .custom(let value, let unit):
            customValueText = String(value)
            customUnit = unit
        default:
            customValueText = ""
            customUnit = .day
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

extension CatalogPurchaseChannel {
    var localizedTitle: String {
        switch self {
        case .web:
            String(localized: "Web")
        case .ios:
            String(localized: "iOS App Store")
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
