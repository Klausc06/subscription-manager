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
    let catalogOfferAdjustment: CatalogOfferAdjustment?
    let locksCatalogMetadata: Bool
    let showsValidation: Bool
    let onEditDate: (SubscriptionDraft.DateSource) -> Void

    init(
        draft: Binding<SubscriptionDraft>,
        status: SubscriptionStatus?,
        nextExpectedCharge: ExpectedCharge?,
        catalogOfferAdjustment: CatalogOfferAdjustment? = nil,
        locksCatalogMetadata: Bool = false,
        showsValidation: Bool = true,
        onEditDate: @escaping (SubscriptionDraft.DateSource) -> Void
    ) {
        self._draft = draft
        self.status = status
        self.nextExpectedCharge = nextExpectedCharge
        self.catalogOfferAdjustment = catalogOfferAdjustment
        self.locksCatalogMetadata = locksCatalogMetadata
        self.showsValidation = showsValidation
        self.onEditDate = onEditDate
    }

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
            if locksCatalogMetadata {
                LabeledContent("Service Name", value: draft.serviceName)
                    .accessibilityIdentifier(
                        "subscription.editor.service-name"
                    )
            } else {
                TextField("Service Name", text: $draft.serviceName)
                    .textContentType(.organizationName)
                    .accessibilityIdentifier(
                        "subscription.editor.service-name"
                    )
            }

            if showsValidation, draft.validation.contains(.serviceName) {
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

            if showsValidation, draft.validation.contains(.amount) {
                ValidationMessage(
                    amountValidationText,
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

            if showsValidation, draft.validation.contains(.currency) {
                ValidationMessage(
                    "Select Currency",
                    identifier: "subscription.validation.currency"
                )
            }

            if catalogOfferAdjustment?.isPriceAdjusted == true {
                Text("User-adjusted price")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(
                        "subscription.editor.user-adjusted-price"
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

            if showsValidation, draft.validation.contains(.billingInterval) {
                ValidationMessage(
                    billingIntervalValidationText,
                    identifier: "subscription.validation.billing-interval"
                )
            }

            if catalogOfferAdjustment?.isScheduleAdjusted == true {
                Text("User-adjusted schedule")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(
                        "subscription.editor.user-adjusted-schedule"
                    )
            }
        }
    }

    private var billingDatesSection: some View {
        Section("Dates") {
            dateEditorRow(for: .startDate)
            dateEditorRow(for: .nextRenewal)

            if showsValidation, draft.validation.contains(.billingDate) {
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
        Section("Additional Details") {
            if locksCatalogMetadata {
                LabeledContent("Category", value: draft.category)
                    .accessibilityIdentifier("subscription.editor.category")

                if !draft.managementURLText.isEmpty,
                   let managementURL = URL(
                    string: draft.managementURLText
                   )
                {
                    Link(
                        "Subscription Management URL",
                        destination: managementURL
                    )
                    .accessibilityIdentifier(
                        "subscription.editor.management-url"
                    )
                }
            } else {
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
                .accessibilityIdentifier(
                    "subscription.editor.management-url"
                )

                if showsValidation,
                   draft.validation.contains(.managementURL)
                {
                    ValidationMessage(
                        "Enter a complete HTTP or HTTPS URL.",
                        identifier: "subscription.validation.management-url"
                    )
                }
            }

            Text(
                "Open the provider's billing, renewal, or cancellation page; this app will not cancel the subscription for you."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3 ... 8)
                .accessibilityIdentifier("subscription.editor.notes")
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

    private var amountValidationText: LocalizedStringKey {
        if draft.amountText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return "Enter a price."
        }
        if draft.parsedAmount(locale: locale) == nil {
            return "Enter a valid amount."
        }
        return "Enter an amount greater than zero."
    }

    private func dateEditorRow(
        for source: SubscriptionDraft.DateSource
    ) -> some View {
        let title = LocalizedStringKey(labelKey(for: source))
        let value = formattedBillingDate(
            date(for: source),
            timeZoneIdentifier: draft.billingTimeZoneIdentifier,
            locale: locale
        )
        return Button {
            onEditDate(source)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier(for: source))
        .accessibilityLabel(Text(title))
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
