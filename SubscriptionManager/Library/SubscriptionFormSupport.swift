import SubscriptionCore
import SwiftUI

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
    for error: SubscriptionCreationValidationError
) -> LocalizedStringKey {
    switch error {
    case .required:
        "This field is required."
    case .mustBePositive:
        "Enter an amount greater than zero."
    case .beforeStartDate:
        "The next renewal cannot be before the start date."
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
        case .confirmedNextRenewal:
            "next-renewal"
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
}
