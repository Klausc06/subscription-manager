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
    @State private var billingDateEditState = BillingDateEditState()

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
        _renewalAnchor = State(initialValue: initialDate)
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

            if initialStatus == .trial {
                Text("Next Renewal is the first paid charge date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
                billingDateEditState.recordUserEdit(.startDate)
            }
        )
    }

    private var renewalAnchorBinding: Binding<Date> {
        Binding(
            get: { renewalAnchor },
            set: { newValue in
                renewalAnchor = newValue
                billingDateEditState.recordUserEdit(.renewalAnchor)
                confirmedNextRenewal = billingDateEditState.nextRenewal(
                    current: confirmedNextRenewal,
                    after: newValue,
                    interval: selectedBillingInterval,
                    timeZoneIdentifier: billingTimeZoneIdentifier
                )
            }
        )
    }

    private var confirmedNextRenewalBinding: Binding<Date> {
        Binding(
            get: { confirmedNextRenewal },
            set: { newValue in
                confirmedNextRenewal = newValue
                billingDateEditState.recordUserEdit(.nextRenewal)
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
              let normalizedRenewalAnchor = normalizedBillingDate(
                  renewalAnchor,
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
            renewalAnchor: normalizedRenewalAnchor,
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
                        renewalAnchor: normalizedRenewalAnchor,
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
        confirmedNextRenewal = billingDateEditState.nextRenewal(
            current: confirmedNextRenewal,
            after: renewalAnchor,
            interval: offer.billingInterval,
            timeZoneIdentifier: billingTimeZoneIdentifier
        )
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
