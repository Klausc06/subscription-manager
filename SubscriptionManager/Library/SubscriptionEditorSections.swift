import Foundation
import SubscriptionCore
import SwiftUI

/// The compact, shared fields used by both Add and Edit.
///
/// Add/Edit owns the surrounding `Form`; this view intentionally emits only
/// sibling native `Section` values so the parent can place lifecycle and
/// history sections alongside these fields.
struct SubscriptionEditorSections: View {
    @Environment(\.locale) private var locale

    @Binding var draft: SubscriptionDraft
    let status: SubscriptionStatus?
    let nextExpectedCharge: ExpectedCharge?
    let onEditDate: (SubscriptionDraft.DateSource) -> Void

    @ViewBuilder
    var body: some View {
        serviceSection
        priceSection
        billingScheduleSection
        billingDatesSection
        derivedSection
        additionalDetailsSection
    }

    private var serviceSection: some View {
        Section("Service") {
            TextField("Service Name", text: $draft.serviceName)
                .textContentType(.organizationName)
                .accessibilityIdentifier("subscription.editor.service-name")

            if draft.validation.contains(.serviceName) {
                ValidationMessage(
                    "This field is required.",
                    identifier: "subscription.validation.service-name"
                )
            }
        }
    }

    private var priceSection: some View {
        Section("Price") {
            TextField("Amount", text: $draft.amountText)
                .subscriptionDecimalKeyboard()
                .accessibilityIdentifier("subscription.editor.amount")

            if draft.validation.contains(.amount) {
                ValidationMessage(
                    draft.amountText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ? "Enter a price." : "Enter an amount greater than zero.",
                    identifier: "subscription.validation.amount"
                )
            }

            Picker("Currency", selection: currencyBinding) {
                Text("Select Currency").tag(String?.none)
                ForEach(Currency.allCases, id: \.rawValue) { currency in
                    Text(currency.rawValue).tag(Optional(currency.rawValue))
                }
            }
            .accessibilityIdentifier("subscription.editor.currency")

            if draft.validation.contains(.currency) {
                ValidationMessage(
                    "Select Currency",
                    identifier: "subscription.validation.currency"
                )
            }

        }
    }

    private var billingScheduleSection: some View {
        Section("Billing Schedule") {
            Picker(
                "Billing Interval",
                selection: subscriptionBillingIntervalBinding($draft)
            ) {
                Text("Select Billing Interval").tag(String?.none)
                ForEach(BillingIntervalChoice.allCases) { choice in
                    Text(choice.title).tag(Optional(choice.rawValue))
                }
            }
            .accessibilityIdentifier("subscription.editor.billing-interval")

            if draft.billingInterval?.storageIdentifier == "custom" {
                TextField(
                    "Interval",
                    text: subscriptionCustomIntervalValueBinding($draft)
                )
                .subscriptionNumberKeyboard()
                .accessibilityIdentifier(
                    "subscription.editor.custom-interval-value"
                )

                Picker(
                    "Unit",
                    selection: subscriptionCustomIntervalUnitBinding($draft)
                ) {
                    ForEach(BillingIntervalUnit.allCases, id: \.rawValue) { unit in
                        Text(unit.localizedEditorTitle)
                            .tag(unit.rawValue)
                    }
                }
                .accessibilityIdentifier("subscription.editor.custom-interval-unit")
            }

            if draft.validation.contains(.billingInterval) {
                ValidationMessage(
                    billingIntervalValidationText,
                    identifier: "subscription.validation.billing-interval"
                )
            }
        }
    }

    private var billingDatesSection: some View {
        Section("Dates") {
            dateEditorRow(for: .startDate)
            dateEditorRow(for: .nextRenewal)

            if draft.validation.contains(.billingDate) {
                ValidationMessage(
                    "Choose a billing date.",
                    identifier: "subscription.validation.billing-date"
                )
            }
        }
    }

    @ViewBuilder
    private var derivedSection: some View {
        if let status {
            Section("Status") {
                LabeledContent(
                    "Status",
                    value: localizedSubscriptionStatus(status)
                )
                .accessibilityIdentifier("subscription.editor.status")
            }
        }

        if !isCancelled, let nextExpectedCharge {
            Section("Next Expected Charge") {
                LabeledContent(
                    "Next Expected Charge",
                    value: formattedMoney(nextExpectedCharge.amount)
                )
                .accessibilityIdentifier("subscription.editor.next-charge")

                LabeledContent(
                    "Date",
                    value: formattedBillingDate(
                        nextExpectedCharge.scheduledDate,
                        timeZoneIdentifier: draft.billingTimeZoneIdentifier,
                        locale: locale
                    )
                )
            }
        }
    }

    private var additionalDetailsSection: some View {
        Section {
            DisclosureGroup("Additional Details") {
                TextField("Plan", text: $draft.plan)
                    .accessibilityIdentifier("subscription.editor.plan")

                TextField("Category", text: $draft.category)
                    .accessibilityIdentifier("subscription.editor.category")

                TextField(
                    "Subscription Management URL",
                    text: $draft.managementURLText
                )
                .textContentType(.URL)
                .subscriptionURLKeyboard()
                .accessibilityIdentifier("subscription.editor.management-url")

                if draft.validation.contains(.managementURL) {
                    ValidationMessage(
                        "Enter a complete HTTP or HTTPS URL.",
                        identifier: "subscription.validation.management-url"
                    )
                }

                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .accessibilityIdentifier("subscription.editor.notes")
            }
            .accessibilityIdentifier("subscription.editor.additional-details")
        }
    }

    private var currencyBinding: Binding<String?> {
        Binding(
            get: { draft.currency?.rawValue },
            set: { rawValue in
                draft.currency = rawValue.flatMap(Currency.init(rawValue:))
            }
        )
    }

    private var billingIntervalValidationText: LocalizedStringKey {
        if case .custom(let value, _) = draft.billingInterval,
           value <= 0
        {
            return "Enter an interval greater than zero."
        }
        return "Select Billing Interval"
    }

    private func dateEditorRow(
        for source: SubscriptionDraft.DateSource
    ) -> some View {
        Button {
            onEditDate(source)
        } label: {
            LabeledContent(
                LocalizedStringKey(labelKey(for: source)),
                value: formattedBillingDate(
                    date(for: source),
                    timeZoneIdentifier: draft.billingTimeZoneIdentifier,
                    locale: locale
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier(for: source))
        .accessibilityValue(dateAccessibilityValue(for: source))
    }

    private func date(for source: SubscriptionDraft.DateSource) -> Date {
        switch source {
        case .startDate:
            draft.startDate
        case .nextRenewal:
            draft.confirmedNextRenewal
        }
    }

    private func labelKey(for source: SubscriptionDraft.DateSource) -> String {
        switch source {
        case .startDate:
            billingStartDateLabelKey(isTrial: isTrial)
        case .nextRenewal:
            billingNextDateLabelKey(isTrial: isTrial)
        }
    }

    private func identifier(
        for source: SubscriptionDraft.DateSource
    ) -> String {
        switch source {
        case .startDate:
            "subscription.editor.start-date"
        case .nextRenewal:
            "subscription.editor.next-renewal"
        }
    }

    private func dateAccessibilityValue(
        for source: SubscriptionDraft.DateSource
    ) -> String {
        let value = formattedBillingDate(
            date(for: source),
            timeZoneIdentifier: draft.billingTimeZoneIdentifier,
            locale: locale
        )
        guard isActive else { return value }
        let role = billingDateRoleText(
            source: source,
            selectedSource: draft.dateSource,
            locale: locale
        )
        return value + ", " + role
    }

    private var isTrial: Bool {
        switch draft.mode {
        case .creating(.trial), .editing(.trial):
            true
        default:
            false
        }
    }

    private var isActive: Bool {
        switch draft.mode {
        case .creating(.active), .editing(.active):
            true
        default:
            false
        }
    }

    private var isCancelled: Bool {
        if case .editing(.cancelled) = draft.mode {
            return true
        }
        return false
    }
}

private extension BillingIntervalUnit {
    var localizedEditorTitle: LocalizedStringKey {
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
}
