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

func billingStartDateLabelKey(isTrial: Bool) -> String {
    isTrial ? "Trial Start" : "Start Date"
}

func billingNextDateLabelKey(isTrial: Bool) -> String {
    isTrial ? "First Paid Charge" : "Next Renewal"
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

/// A picker-friendly adapter for the draft's optional billing interval.
///
/// The editor deliberately keeps the unselected state as `nil`; callers must
/// provide a visible `Select Billing Interval` row rather than silently
/// choosing a monthly schedule. Custom interval text and unit edits use the
/// same adapter so changing a valid value also rederives linked dates.
func subscriptionBillingIntervalBinding(
    _ draft: Binding<SubscriptionDraft>,
    asOf now: Date = Date()
) -> Binding<String?> {
    Binding(
        get: {
            draft.wrappedValue.billingInterval?.storageIdentifier
        },
        set: { rawValue in
            var updated = draft.wrappedValue
            guard let rawValue else {
                updated.billingInterval = nil
                draft.wrappedValue = updated
                return
            }

            if rawValue == "custom" {
                let value = Int(
                    updated.customIntervalValueText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                ) ?? 0
                applyEditorInterval(
                    .custom(value: value, unit: updated.customIntervalUnit),
                    to: &updated,
                    asOf: now
                )
            } else if let interval = BillingInterval(rawValue: rawValue) {
                applyEditorInterval(interval, to: &updated, asOf: now)
            } else {
                updated.billingInterval = nil
            }
            draft.wrappedValue = updated
        }
    )
}

func subscriptionCustomIntervalValueBinding(
    _ draft: Binding<SubscriptionDraft>,
    asOf now: Date = Date()
) -> Binding<String> {
    Binding(
        get: { draft.wrappedValue.customIntervalValueText },
        set: { text in
            var updated = draft.wrappedValue
            updated.customIntervalValueText = text
            let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? 0
            applyEditorInterval(
                .custom(value: value, unit: updated.customIntervalUnit),
                to: &updated,
                asOf: now
            )
            draft.wrappedValue = updated
        }
    )
}

func subscriptionCustomIntervalUnitBinding(
    _ draft: Binding<SubscriptionDraft>,
    asOf now: Date = Date()
) -> Binding<String> {
    Binding(
        get: { draft.wrappedValue.customIntervalUnit.rawValue },
        set: { rawValue in
            guard let unit = BillingIntervalUnit(rawValue: rawValue) else {
                return
            }
            var updated = draft.wrappedValue
            updated.customIntervalUnit = unit
            let value = Int(
                updated.customIntervalValueText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            ) ?? 0
            applyEditorInterval(
                .custom(value: value, unit: unit),
                to: &updated,
                asOf: now
            )
            draft.wrappedValue = updated
        }
    )
}

private func applyEditorInterval(
    _ interval: BillingInterval,
    to draft: inout SubscriptionDraft,
    asOf now: Date
) {
    switch interval {
    case .custom(_, let unit):
        draft.customIntervalUnit = unit
    default:
        draft.customIntervalValueText = ""
        draft.customIntervalUnit = .day
    }

    // Before a user accepts a date, changing the interval must not turn a
    // placeholder date into accepted evidence. Once a date is accepted, use
    // SubscriptionDraft's operation so linked dates stay consistent.
    guard !draft.acceptedDateSources.isEmpty else {
        draft.billingInterval = interval
        return
    }
    if !draft.changeBillingInterval(interval, asOf: now) {
        draft.billingInterval = interval
    }
}
