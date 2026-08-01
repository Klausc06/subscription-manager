import Foundation
import SubscriptionCore
import SwiftUI

private struct DateTaskSelection: Identifiable {
    let source: SubscriptionDraft.DateSource

    var id: String {
        switch source {
        case .startDate:
            "start-date"
        case .nextRenewal:
            "next-renewal"
        }
    }
}

/// The Add shell owns navigation/task chrome while the editable values live in
/// one `SubscriptionDraft`. Catalog selection is intentionally kept here: it
/// is task UI state, not a second copy of any editable value.
struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    private let onSuccessfulSave: (() -> Void)?
    private let showsCancellationAction: Bool
    private let now: Date

    @State private var draft: SubscriptionDraft
    @State private var selectedCatalogPreset: CatalogPreset?
    @State private var selectedOfferID: String?
    @State private var selectedPeriodRawValue: String
    @State private var dateTaskSelection: DateTaskSelection?
    @State private var didAttemptSave = false
    @State private var saveFailed = false

    init(
        workspace: SubscriptionWorkspace,
        preset: CatalogPreset? = nil,
        showsCancellationAction: Bool = true,
        onSuccessfulSave: (() -> Void)? = nil
    ) {
        self.workspace = workspace
        self.onSuccessfulSave = onSuccessfulSave
        self.showsCancellationAction = showsCancellationAction

        let initialDate = Date()
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        now = initialDate

        let defaultOffer = preset.flatMap {
            CatalogOfferSelection.defaultOffer(in: $0)
        }
        let initialDraft: SubscriptionDraft
        if let preset {
            initialDraft = SubscriptionDraft.catalog(
                preset: preset,
                offer: defaultOffer,
                now: initialDate,
                locale: .current,
                timeZoneIdentifier: timeZoneIdentifier
            )
        } else {
            initialDraft = SubscriptionDraft.manual(
                now: initialDate,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }
        _draft = State(initialValue: initialDraft)
        _selectedCatalogPreset = State(initialValue: preset)
        _selectedOfferID = State(initialValue: defaultOffer?.id)
        _selectedPeriodRawValue = State(
            initialValue: defaultOffer?.billingInterval.rawValue
                ?? BillingInterval.monthly.rawValue
        )
    }

    var body: some View {
        Form {
            officialOfferSection
            initialStatusSection
            SubscriptionEditorSections(
                draft: $draft,
                status: nil,
                nextExpectedCharge: nil,
                catalogMatches: catalogMatches,
                onSelectCatalogMatch: selectCatalogPreset,
                locksCatalogMetadata: hasVerifiedOffers,
                showsValidation: didAttemptSave,
                onEditDate: beginDateTask
            )

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
            selectedCatalogPreset == nil
                ? "Add Subscription"
                : "Confirm Subscription"
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
        .onChange(of: draft.serviceName) { _, serviceName in
            clearCatalogSelectionIfNeeded(for: serviceName)
        }
        .sheet(item: $dateTaskSelection) { selection in
            NavigationStack {
                BillingDateTaskView(
                    draft: $draft,
                    source: selection.source,
                    now: now
                )
            }
        }
    }

    private var availablePeriods: [String] {
        guard let selectedCatalogPreset else { return [] }
        return CatalogOfferSelection.periods(in: selectedCatalogPreset)
    }

    private var offersForSelectedPeriod: [CatalogOffer] {
        guard let selectedCatalogPreset else { return [] }
        return CatalogOfferSelection.offers(
            in: selectedCatalogPreset,
            periodRawValue: selectedPeriodRawValue
        )
    }

    private var selectedOffer: CatalogOffer? {
        guard let selectedOfferID, let selectedCatalogPreset else { return nil }
        return CatalogOfferSelection.selectableOffers(in: selectedCatalogPreset)
            .first(where: { $0.id == selectedOfferID })
    }

    private var hasVerifiedOffers: Bool {
        !availablePeriods.isEmpty
    }

    private var catalogMatches: [CatalogPreset] {
        guard selectedCatalogPreset == nil,
              !draft.serviceName.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty
        else {
            return []
        }
        return workspace.catalogMatches(query: draft.serviceName, locale: locale)
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
                    .accessibilityIdentifier("subscription.form.offer-period")
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
                    .accessibilityIdentifier("subscription.form.selected-price")

                    Text(
                        "\(selectedOffer.market) · "
                            + selectedOffer.purchaseChannel.localizedTitle
                            + " · \(String(localized: "Verified")) "
                            + selectedOffer.verifiedOn
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("subscription.form.offer-provenance")
                }

                if let selectedOffer {
                    Link(
                        "Official Pricing Source",
                        destination: selectedOffer.sourceURL
                    )
                    .accessibilityIdentifier("subscription.form.offer-source")

                    Text(
                        "Official prices may vary by region, tax, and storefront."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var initialStatusSection: some View {
        Picker("Initial Status", selection: initialStatusBinding) {
            Text("Active").tag(SubscriptionInitialStatus.active)
            Text("Trial").tag(SubscriptionInitialStatus.trial)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("subscription.form.initial-status")
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var initialStatusBinding: Binding<SubscriptionInitialStatus> {
        Binding(
            get: {
                if case .creating(let status) = draft.mode {
                    return status
                }
                return .active
            },
            set: { status in
                if case .creating(let currentStatus) = draft.mode,
                   currentStatus != status
                {
                    // Active dates have a source/derived relationship while
                    // Trial dates are independent facts. Never carry date
                    // acceptance evidence across that semantic boundary.
                    draft.acceptedDateSources = []
                    draft.dateSource = .startDate
                }
                draft.mode = .creating(status)
            }
        )
    }

    private func beginDateTask(_ source: SubscriptionDraft.DateSource) {
        dateTaskSelection = DateTaskSelection(source: source)
    }

    private func save() {
        didAttemptSave = true
        saveFailed = false

        // This is the single validation/input construction seam for Add. It
        // also guarantees malformed optional URL text and unaccepted dates do
        // not reach any Workspace creation branch.
        guard let input = draft.makeCreationInput(locale: locale) else {
            return
        }

        let wasCreated: Bool
        if let catalogPresetID = selectedCatalogPreset?.id,
           hasVerifiedOffers,
           let selectedOffer
        {
            let result = workspace.createCatalogSubscription(
                presetID: catalogPresetID,
                command: .verifiedOffer(
                    CatalogOfferSubscriptionInput(
                        offerID: selectedOffer.id,
                        actualChargeOverride:
                            input.originalAmount == selectedOffer.price
                                ? nil
                                : input.originalAmount,
                        billingIntervalSelection:
                            input.billingInterval
                                == selectedOffer.billingInterval
                                ? .official
                                : .override(input.billingInterval),
                        startDate: input.startDate,
                        renewalAnchor: input.renewalAnchor,
                        confirmedNextRenewal: input.confirmedNextRenewal,
                        billingTimeZoneIdentifier:
                            input.billingTimeZoneIdentifier,
                        notes: input.notes,
                        initialStatus: input.initialStatus
                    )
                )
            )
            wasCreated = if case .created = result { true } else { false }
        } else if let catalogPresetID = selectedCatalogPreset?.id {
            // A service-only preset carries identity evidence only. Its
            // suggested interval is intentionally not adopted by the draft.
            let result = workspace.createCatalogSubscription(
                presetID: catalogPresetID,
                command: .legacy(input)
            )
            wasCreated = if case .created = result { true } else { false }
        } else {
            let result = workspace.createSubscription(input)
            wasCreated = if case .created = result { true } else { false }
        }

        guard wasCreated, workspace.creationValidationErrors.isEmpty else {
            saveFailed = true
            return
        }

        onSuccessfulSave?()
        dismiss()
    }

    private func applySelectedOffer() {
        guard let offer = selectedOffer else { return }
        draft.plan = offer.planName.value(for: locale)
        draft.amountText = editableMoneyText(offer.price, locale: locale)
        draft.currency = offer.price.currency
        draft.catalogOfferID = offer.id
        applyBillingInterval(offer.billingInterval)
    }

    private func selectCatalogPreset(_ preset: CatalogPreset) {
        let defaultOffer = CatalogOfferSelection.defaultOffer(in: preset)
        selectedCatalogPreset = preset
        selectedOfferID = defaultOffer?.id
        selectedPeriodRawValue = defaultOffer?.billingInterval.rawValue
            ?? BillingInterval.monthly.rawValue
        draft = SubscriptionDraft.catalog(
            preset: preset,
            offer: defaultOffer,
            now: now,
            locale: locale,
            timeZoneIdentifier: draft.billingTimeZoneIdentifier
        )
        didAttemptSave = false
    }

    private func clearCatalogSelectionIfNeeded(for serviceName: String) {
        guard let selectedCatalogPreset,
              !hasVerifiedOffers,
              serviceName != selectedCatalogPreset.serviceName.value(for: locale)
        else {
            return
        }
        self.selectedCatalogPreset = nil
        selectedOfferID = nil
    }

    private func applyBillingInterval(_ interval: BillingInterval) {
        switch interval {
        case .custom(let value, let unit):
            draft.customIntervalValueText = String(value)
            draft.customIntervalUnit = unit
        default:
            draft.customIntervalValueText = ""
            draft.customIntervalUnit = .day
        }

        // Choosing a verified offer is evidence for its price/cadence, not for
        // either billing date. Keep manual/offer placeholders unaccepted until
        // the person completes a date task. Once a date is accepted, use the
        // draft operation so the linked date follows the selected interval.
        guard !draft.acceptedDateSources.isEmpty else {
            draft.billingInterval = interval
            return
        }
        if !draft.changeBillingInterval(interval, asOf: now) {
            draft.billingInterval = interval
        }
    }
}
