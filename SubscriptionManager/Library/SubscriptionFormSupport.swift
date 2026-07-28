import SubscriptionCore
import SwiftUI

enum ManagementURLParseResult: Equatable {
    case empty
    case valid(URL)
    case invalid
}

enum ManagementURLParser {
    static func parse(_ text: String) -> ManagementURLParseResult {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return .empty
        }
        guard
            let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty,
            let url = components.url
        else {
            return .invalid
        }

        return .valid(url)
    }
}

struct ValidationMessage: View {
    let text: LocalizedStringKey
    let identifier: String

    init(_ text: LocalizedStringKey, identifier: String) {
        self.text = text
        self.identifier = identifier
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
            .accessibilityIdentifier(identifier)
    }
}

func validationText(
    for error: SubscriptionCreationValidationError,
    field: SubscriptionCreationField? = nil
) -> LocalizedStringKey {
    LocalizedStringKey(validationTextKey(for: error, field: field))
}

func validationTextKey(
    for error: SubscriptionCreationValidationError,
    field: SubscriptionCreationField? = nil
) -> String {
    switch error {
    case .required:
        "This field is required."
    case .mustBePositive:
        "Enter an amount greater than zero."
    case .beforeStartDate:
        field == .renewalAnchor
            ? "The renewal anchor cannot be before the start date."
            : "The next renewal cannot be before the start date."
    }
}

func paymentHistoryActionErrorText(
    _ error: PaymentHistoryActionError
) -> LocalizedStringKey {
    switch error {
    case .archivedSubscription:
        "Restore this subscription before changing its payment history."
    case .invalidScheduledOccurrence:
        "Choose a scheduled billing date."
    case .scheduledDateInFuture:
        "The scheduled date cannot be in the future."
    case .chargedDateInFuture:
        "The payment date cannot be in the future."
    case .effectiveDateBeforeStart:
        "The effective date cannot be before the subscription starts."
    case .duplicatePriceChangeDay:
        "A price change already exists for that day."
    case .mustBePositive:
        "Enter an amount greater than zero."
    case .persistenceFailed:
        "Couldn’t save payment history. Try again."
    }
}

extension SubscriptionCreationField {
    var identifier: String {
        switch self {
        case .serviceName:
            "service-name"
        case .plan:
            "plan"
        case .category:
            "category"
        case .originalAmount:
            "amount"
        case .renewalAnchor:
            "renewal-anchor"
        case .confirmedNextRenewal:
            "next-renewal"
        case .billingSchedule:
            "billing-schedule"
        }
    }
}

extension View {
    @ViewBuilder
    func subscriptionDecimalKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.decimalPad)
        #else
            self
        #endif
    }

    @ViewBuilder
    func subscriptionURLKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            self
        #endif
    }

    @ViewBuilder
    func subscriptionNumberKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.numberPad)
        #else
            self
        #endif
    }
}
