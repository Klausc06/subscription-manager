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
    private let billingTimeZoneIdentifier: String

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
    private let billingDateEditState = BillingDateEditState()

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
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        billingTimeZoneIdentifier = timeZoneIdentifier
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
        _confirmedNextRenewal = State(
            initialValue: defaultNextRenewal(
                after: initialDate,
                interval: interval,
                timeZoneIdentifier: timeZoneIdentifier
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
            if !hasVerifiedOffers {
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
        .onChange(
            of: selectedBillingInterval
        ) { _, interval in
            updateDatesForInterval(interval)
        }
        .onChange(of: initialStatus) { _, status in
            guard status == .active else { return }
            updateDatesForInterval(selectedBillingInterval)
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
                .accessibilityValue(
                    selectedOffer?.planName.value(for: locale) ?? ""
                )

                if let selectedOffer {
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

                DisclosureGroup(
                    isExpanded: $adjustsActualCharge
                ) {
                    actualChargeFields
                    BillingScheduleFields(
                        intervalChoice: $intervalChoice,
                        customValueText: $customValueText,
                        customUnit: $customUnit,
                        validationError:
                            workspace.creationValidationErrors[
                                .billingSchedule
                            ]
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adjust Actual Charge")
                            .accessibilityIdentifier(
                                "subscription.form.adjust-charge"
                            )
                        if !adjustsActualCharge {
                            Text(offerAdjustmentSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityValue(offerAdjustmentSummary)
                }
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

        }
    }

    private var priceSection: some View {
        Section("Price") {
            actualChargeFields
        }
    }

    @ViewBuilder
    private var actualChargeFields: some View {
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

    private var actualChargeSummary: String {
        let amount = MoneyTextParser.parse(
            amountText,
            currency: currency,
            locale: locale
        )
        let value = amount.map(formattedMoney)
            ?? amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(value) · \(currency.rawValue)"
    }

    private var offerAdjustmentSummary: String {
        "\(actualChargeSummary) · "
            + localizedBillingInterval(selectedBillingInterval)
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
                LocalizedStringKey(
                    billingStartDateLabelKey(
                        isTrial: initialStatus == .trial
                    )
                ),
                selection: startDateBinding,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.start-date")
            .accessibilityValue(
                formattedBillingDate(
                    startDate,
                    timeZoneIdentifier: billingTimeZoneIdentifier,
                    locale: locale
                )
            )

            DatePicker(
                LocalizedStringKey(
                    billingNextDateLabelKey(
                        isTrial: initialStatus == .trial
                    )
                ),
                selection: confirmedNextRenewalBinding,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.next-renewal")
            .accessibilityValue(
                formattedBillingDate(
                    confirmedNextRenewal,
                    timeZoneIdentifier: billingTimeZoneIdentifier,
                    locale: locale
                )
            )

            validationMessage(for: .confirmedNextRenewal)
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

            if hasVerifiedOffers {
                if let managementURL = catalogPreset?.managementURL {
                    Link(
                        "Subscription Management URL",
                        destination: managementURL
                    )
                    .accessibilityIdentifier(
                        "subscription.form.management-url"
                    )
                }
            } else {
                TextField(
                    "Subscription Management URL",
                    text: $managementURLText
                )
                .textContentType(.URL)
                .subscriptionURLKeyboard()
                .accessibilityIdentifier(
                    "subscription.form.management-url"
                )
            }

            Text(
                "Open the provider's billing, renewal, or cancellation page; this app will not cancel the subscription for you."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if !hasVerifiedOffers, managementURLIsInvalid {
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
                guard initialStatus == .active,
                      let dates = billingDateEditState.editingStartDate(
                          newValue,
                          interval: selectedBillingInterval,
                          asOf: Date(),
                          timeZoneIdentifier: billingTimeZoneIdentifier
                      )
                else {
                    return
                }
                apply(dates)
            }
        )
    }

    private var confirmedNextRenewalBinding: Binding<Date> {
        Binding(
            get: { confirmedNextRenewal },
            set: { newValue in
                confirmedNextRenewal = newValue
                guard initialStatus == .active,
                      let dates = billingDateEditState.editingNextRenewal(
                          newValue,
                          interval: selectedBillingInterval,
                          timeZoneIdentifier: billingTimeZoneIdentifier
                      )
                else {
                    return
                }
                apply(dates)
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
        if hasVerifiedOffers, amountInputIsInvalid {
            adjustsActualCharge = true
        }
        let managementURLResult = ManagementURLParser.parse(managementURLText)
        managementURLIsInvalid = managementURLResult == .invalid
        saveFailed = false

        guard !managementURLIsInvalid else {
            return
        }
        guard !amountInputIsInvalid else {
            return
        }
        guard let normalizedStartDate = normalizedBillingDate(
                  startDate,
                  timeZoneIdentifier: billingTimeZoneIdentifier
              ),
              let normalizedNextRenewal = normalizedBillingDate(
                  confirmedNextRenewal,
                  timeZoneIdentifier: billingTimeZoneIdentifier
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
            renewalAnchor: initialStatus == .trial
                ? normalizedNextRenewal
                : normalizedStartDate,
            confirmedNextRenewal: normalizedNextRenewal,
            billingTimeZoneIdentifier: billingTimeZoneIdentifier,
            managementURL: managementURL(from: managementURLResult),
            notes: notes,
            initialStatus: initialStatus
        )
        let wasCreated: Bool
        if let catalogPresetID, let selectedOffer {
            let result = workspace.createCatalogSubscription(
                presetID: catalogPresetID,
                command: .verifiedOffer(
                    CatalogOfferSubscriptionInput(
                        offerID: selectedOffer.id,
                        actualChargeOverride:
                            amount == selectedOffer.price ? nil : amount,
                        billingIntervalSelection:
                            selectedBillingInterval
                                == selectedOffer.billingInterval
                                ? .official
                                : .override(selectedBillingInterval),
                        startDate: normalizedStartDate,
                        renewalAnchor: initialStatus == .trial
                            ? normalizedNextRenewal
                            : normalizedStartDate,
                        confirmedNextRenewal: normalizedNextRenewal,
                        billingTimeZoneIdentifier:
                            billingTimeZoneIdentifier,
                        notes: notes,
                        initialStatus: initialStatus
                    )
                )
            )
            if case .created = result {
                wasCreated = true
            } else {
                wasCreated = false
            }
        } else if let catalogPresetID {
            let result = workspace.createCatalogSubscription(
                presetID: catalogPresetID,
                command: .legacy(input)
            )
            if case .created = result {
                wasCreated = true
            } else {
                wasCreated = false
            }
        } else {
            let result = workspace.createSubscription(input)
            if case .created = result {
                wasCreated = true
            } else {
                wasCreated = false
            }
        }

        guard workspace.creationValidationErrors.isEmpty, wasCreated else {
            if hasVerifiedOffers,
               workspace.creationValidationErrors[.originalAmount] != nil
                || workspace.creationValidationErrors[
                    .billingSchedule
                ] != nil
            {
                adjustsActualCharge = true
            }
            saveFailed = workspace.creationValidationErrors.isEmpty
            return
        }

        if let onSuccessfulSave {
            onSuccessfulSave()
        }
        dismiss()
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
        updateDatesForInterval(offer.billingInterval)
    }

    private func updateDatesForInterval(_ interval: BillingInterval) {
        guard initialStatus == .active,
              let dates = billingDateEditState.changingInterval(
                  startDate: startDate,
                  interval: interval,
                  asOf: Date(),
                  timeZoneIdentifier: billingTimeZoneIdentifier
              )
        else {
            return
        }
        apply(dates)
    }

    private func apply(_ dates: BillingDateValues) {
        startDate = dates.startDate
        confirmedNextRenewal = dates.nextRenewal
    }

    private var selectedBillingInterval: BillingInterval {
        intervalChoice.interval(
            customValueText: customValueText,
            customUnit: customUnit
        )
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
