import Foundation
import SubscriptionCore
import SwiftUI

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    private let catalogPreset: CatalogPreset?
    private let catalogPresetID: String?
    private let onSuccessfulSave: (() -> Void)?
    private let showsCancellationAction: Bool

    @State private var serviceName = ""
    @State private var plan = ""
    @State private var category = ""
    @State private var initialStatus: SubscriptionInitialStatus = .active
    @State private var amountText = ""
    @State private var currency: Currency = .usd
    @State private var intervalChoice: BillingIntervalChoice = .monthly
    @State private var customValueText = ""
    @State private var customUnit: BillingIntervalUnit = .day
    @State private var startDate = Date()
    @State private var renewalAnchor = Date()
    @State private var confirmedNextRenewal =
        Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var managementURLText = ""
    @State private var notes = ""
    @State private var amountInputIsInvalid = false
    @State private var managementURLIsInvalid = false
    @State private var saveFailed = false
    @State private var selectedOfferID: String?
    @State private var selectedPeriodRawValue = BillingInterval.monthly.rawValue
    @State private var adjustsActualCharge = false
    @State private var renewalDatesWereEdited = false

    init(
        workspace: SubscriptionWorkspace,
        preset: CatalogPreset? = nil,
        showsCancellationAction: Bool = true,
        onSuccessfulSave: (() -> Void)? = nil
    ) {
        self.workspace = workspace
        catalogPreset = preset
        catalogPresetID = preset?.id
        self.onSuccessfulSave = onSuccessfulSave
        self.showsCancellationAction = showsCancellationAction

        let locale = Locale.current
        let defaultOffer = preset.flatMap {
            CatalogOfferSelection.defaultOffer(in: $0)
        }
        let interval = defaultOffer?.billingInterval
            ?? preset?.suggestedInterval
            ?? .monthly
        let intervalFormValues = BillingIntervalFormValues(
            interval: interval
        )
        let initialDate = Date()
        _serviceName = State(
            initialValue: preset?.serviceName.value(for: locale) ?? ""
        )
        _plan = State(
            initialValue: defaultOffer?.planName.value(for: locale) ?? ""
        )
        _category = State(
            initialValue: preset?.category.value(for: locale) ?? ""
        )
        _amountText = State(
            initialValue: defaultOffer.map {
                editableMoneyText($0.price, locale: locale)
            } ?? ""
        )
        _currency = State(initialValue: defaultOffer?.price.currency ?? .usd)
        _intervalChoice = State(
            initialValue: intervalFormValues.choice
        )
        _customValueText = State(
            initialValue: intervalFormValues.customValueText
        )
        _customUnit = State(initialValue: intervalFormValues.customUnit)
        _startDate = State(initialValue: initialDate)
        _renewalAnchor = State(initialValue: initialDate)
        _confirmedNextRenewal = State(
            initialValue: defaultNextRenewal(
                after: initialDate,
                interval: interval,
                calendar: .current
            )
        )
        _managementURLText = State(
            initialValue: preset?.managementURL?.absoluteString ?? ""
        )
        _selectedOfferID = State(initialValue: defaultOffer?.id)
        _selectedPeriodRawValue = State(
            initialValue: defaultOffer?.billingInterval.rawValue
                ?? preset?.suggestedInterval.rawValue
                ?? BillingInterval.monthly.rawValue
        )
    }

    var body: some View {
        Form {
            officialOfferSection
            serviceSection
            subscriptionSection
            if !hasVerifiedOffers || adjustsActualCharge {
                priceSection
                billingScheduleSection
            }
            billingDatesSection
            optionalSection

            if saveFailed {
                Section {
                    ValidationMessage(
                        "Couldn’t save this subscription. Try again.",
                        identifier: "subscription.validation.save"
                    )
                }
            }
        }
        .accessibilityIdentifier("subscription.form")
        .navigationTitle(
            catalogPresetID == nil ? "Add Subscription" : "Confirm Subscription"
        )
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsCancellationAction {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("subscription.form.cancel")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .accessibilityIdentifier("subscription.form.save")
            }
        }
        .onChange(of: selectedPeriodRawValue) { _, _ in
            selectedOfferID = offersForSelectedPeriod.first?.id
        }
        .onChange(of: selectedOfferID) { _, _ in
            applySelectedOffer()
        }
    }

    private var availablePeriods: [String] {
        guard let catalogPreset else { return [] }
        return CatalogOfferSelection.periods(in: catalogPreset)
    }

    private var offersForSelectedPeriod: [CatalogOffer] {
        guard let catalogPreset else { return [] }
        return CatalogOfferSelection.offers(
            in: catalogPreset,
            periodRawValue: selectedPeriodRawValue
        )
    }

    private var selectedOffer: CatalogOffer? {
        guard let selectedOfferID, let catalogPreset else { return nil }
        return CatalogOfferSelection.selectableOffers(in: catalogPreset)
            .first(where: { $0.id == selectedOfferID })
    }

    private var hasVerifiedOffers: Bool {
        !availablePeriods.isEmpty
    }

    @ViewBuilder
    private var officialOfferSection: some View {
        if hasVerifiedOffers {
            Section("Official Offer") {
                if availablePeriods.count > 1 {
                    Picker(
                        "Billing Period",
                        selection: $selectedPeriodRawValue
                    ) {
                        ForEach(availablePeriods, id: \.self) { rawValue in
                            Text(
                                localizedBillingInterval(
                                    BillingInterval(rawValue: rawValue)
                                        ?? .monthly
                                )
                            )
                            .tag(rawValue)
                        }
                    }
                    .accessibilityIdentifier(
                        "subscription.form.offer-period"
                    )
                } else if let selectedOffer {
                    LabeledContent(
                        "Billing Period",
                        value: localizedBillingInterval(
                            selectedOffer.billingInterval
                        )
                    )
                }

                Picker("Plan", selection: $selectedOfferID) {
                    ForEach(offersForSelectedPeriod) { offer in
                        Text(offer.planName.value(for: locale))
                            .tag(Optional(offer.id))
                    }
                }
                .accessibilityIdentifier("subscription.form.offer-plan")

                if let selectedOffer {
                    LabeledContent(
                        "Plan",
                        value: selectedOffer.planName.value(for: locale)
                    )
                    .accessibilityIdentifier(
                        "subscription.form.selected-plan"
                    )

                    LabeledContent(
                        "Official Price",
                        value: formattedMoney(selectedOffer.price)
                    )
                    .accessibilityIdentifier(
                        "subscription.form.selected-price"
                    )

                    Text(
                        "\(selectedOffer.market) · "
                            + selectedOffer.purchaseChannel.localizedTitle
                            + " · \(String(localized: "Verified")) "
                            + selectedOffer.verifiedOn
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(
                        "subscription.form.offer-provenance"
                    )
                }

                Button("Adjust Actual Charge") {
                    adjustsActualCharge.toggle()
                }
                .accessibilityIdentifier(
                    "subscription.form.adjust-charge"
                )
            }
        }
    }

    @ViewBuilder
    private var serviceSection: some View {
        Section("Service") {
            if hasVerifiedOffers {
                LabeledContent("Service", value: serviceName)
                LabeledContent("Category", value: category)
            } else {
                TextField("Service Name", text: $serviceName)
                    .textContentType(.organizationName)
                    .accessibilityIdentifier(
                        "subscription.form.service-name"
                    )
                validationMessage(for: .serviceName)
            }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section("Subscription Details") {
            if !hasVerifiedOffers {
                TextField("Plan", text: $plan)
                    .accessibilityIdentifier("subscription.form.plan")
                validationMessage(for: .plan)

                TextField("Category", text: $category)
                    .accessibilityIdentifier("subscription.form.category")
                validationMessage(for: .category)
            }

            Picker("Initial Status", selection: $initialStatus) {
                Text("Active").tag(SubscriptionInitialStatus.active)
                Text("Trial").tag(SubscriptionInitialStatus.trial)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("subscription.form.initial-status")

            if initialStatus == .trial {
                Text("Next Renewal is the first paid charge date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var priceSection: some View {
        Section("Price") {
            TextField("Amount", text: $amountText)
                .subscriptionDecimalKeyboard()
                .accessibilityIdentifier("subscription.form.amount")

            Picker("Currency", selection: $currency) {
                ForEach(Currency.allCases, id: \.rawValue) { currency in
                    Text(currency.rawValue).tag(currency)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("subscription.form.currency")

            if amountInputIsInvalid {
                ValidationMessage(
                    "Enter a valid amount.",
                    identifier: "subscription.validation.amount"
                )
            } else {
                validationMessage(for: .originalAmount)
            }
        }
    }

    private var billingScheduleSection: some View {
        Section("Billing Schedule") {
            BillingScheduleFields(
                intervalChoice: $intervalChoice,
                customValueText: $customValueText,
                customUnit: $customUnit,
                validationError:
                    workspace.creationValidationErrors[.billingSchedule]
            )
        }
    }

    private var billingDatesSection: some View {
        Section("Billing Dates") {
            DatePicker(
                "Start Date",
                selection: startDateBinding,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.start-date")

            DatePicker(
                "Renewal Anchor",
                selection: renewalAnchorBinding,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.renewal-anchor")

            DatePicker(
                "Next Renewal",
                selection: confirmedNextRenewalBinding,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.next-renewal")

            validationMessage(for: .confirmedNextRenewal)
            validationMessage(for: .renewalAnchor)
        }
    }

    private var optionalSection: some View {
        Section("Optional") {
            if let selectedOffer {
                Link(
                    "Official Pricing Source",
                    destination: selectedOffer.sourceURL
                )
                .accessibilityIdentifier(
                    "subscription.form.offer-source"
                )

                Text(
                    "Official prices may vary by region, tax, and storefront."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            TextField("Subscription Management URL", text: $managementURLText)
                .textContentType(.URL)
                .subscriptionURLKeyboard()
                .accessibilityIdentifier("subscription.form.management-url")

            Text(
                "Open the provider's billing, renewal, or cancellation page; this app will not cancel the subscription for you."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if managementURLIsInvalid {
                ValidationMessage(
                    "Enter a complete HTTP or HTTPS URL.",
                    identifier: "subscription.validation.management-url"
                )
            }

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)
                .accessibilityIdentifier("subscription.form.notes")
        }
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { startDate },
            set: { newValue in
                startDate = newValue
                renewalDatesWereEdited = true
            }
        )
    }

    private var renewalAnchorBinding: Binding<Date> {
        Binding(
            get: { renewalAnchor },
            set: { newValue in
                renewalAnchor = newValue
                renewalDatesWereEdited = true
            }
        )
    }

    private var confirmedNextRenewalBinding: Binding<Date> {
        Binding(
            get: { confirmedNextRenewal },
            set: { newValue in
                confirmedNextRenewal = newValue
                renewalDatesWereEdited = true
            }
        )
    }

    @ViewBuilder
    private func validationMessage(
        for field: SubscriptionCreationField
    ) -> some View {
        if let error = workspace.creationValidationErrors[field] {
            ValidationMessage(
                field == .billingSchedule
                    ? billingScheduleValidationText(for: error)
                    : validationText(for: error, field: field),
                identifier: "subscription.validation.\(field.identifier)"
            )
        }
    }

    private func save() {
        let amount = MoneyTextParser.parse(
            amountText,
            currency: currency,
            locale: .current
        )
        amountInputIsInvalid = amount == nil
        let managementURLResult = ManagementURLParser.parse(managementURLText)
        managementURLIsInvalid = managementURLResult == .invalid
        saveFailed = false

        guard !managementURLIsInvalid else {
            return
        }
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        guard let normalizedStartDate = normalizedBillingDate(
                  startDate,
                  timeZoneIdentifier: timeZoneIdentifier
              ),
              let normalizedRenewalAnchor = normalizedBillingDate(
                  renewalAnchor,
                  timeZoneIdentifier: timeZoneIdentifier
              ),
              let normalizedNextRenewal = normalizedBillingDate(
                  confirmedNextRenewal,
                  timeZoneIdentifier: timeZoneIdentifier
              )
        else {
            saveFailed = true
            return
        }

        let input = SubscriptionCreationInput(
            serviceName: serviceName,
            plan: plan,
            category: category,
            originalAmount: amount,
            billingInterval: intervalChoice.interval(
                customValueText: customValueText,
                customUnit: customUnit
            ),
            startDate: normalizedStartDate,
            renewalAnchor: normalizedRenewalAnchor,
            confirmedNextRenewal: normalizedNextRenewal,
            billingTimeZoneIdentifier: timeZoneIdentifier,
            managementURL: managementURL(from: managementURLResult),
            notes: notes,
            initialStatus: initialStatus
        )
        if let catalogPresetID {
            workspace.createCatalogSubscription(
                presetID: catalogPresetID,
                input: input
            )
        } else {
            workspace.createSubscription(input)
        }

        guard workspace.creationValidationErrors.isEmpty else {
            return
        }

        if case .loaded = workspace.detailState {
            if let onSuccessfulSave {
                onSuccessfulSave()
            }
            dismiss()
        } else {
            saveFailed = true
        }
    }

    private func applySelectedOffer() {
        guard let offer = selectedOffer else { return }
        plan = offer.planName.value(for: locale)
        amountText = editableMoneyText(offer.price, locale: locale)
        currency = offer.price.currency
        let intervalFormValues = BillingIntervalFormValues(
            interval: offer.billingInterval
        )
        intervalChoice = intervalFormValues.choice
        customValueText = intervalFormValues.customValueText
        customUnit = intervalFormValues.customUnit
        if !renewalDatesWereEdited {
            confirmedNextRenewal = defaultNextRenewal(
                after: renewalAnchor,
                interval: offer.billingInterval,
                calendar: .current
            )
        }
    }

    private func managementURL(
        from result: ManagementURLParseResult
    ) -> URL? {
        guard case .valid(let url) = result else {
            return nil
        }
        return url
    }
}
