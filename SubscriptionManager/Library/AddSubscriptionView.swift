import Foundation
import SubscriptionCore
import SwiftUI

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace

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

    var body: some View {
        Form {
            serviceSection
            subscriptionSection
            priceSection
            billingScheduleSection
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
        .navigationTitle("Add Subscription")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("subscription.form.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .accessibilityIdentifier("subscription.form.save")
            }
        }
    }

    private var serviceSection: some View {
        Section("Service") {
            TextField("Service Name", text: $serviceName)
                .textContentType(.organizationName)
                .accessibilityIdentifier("subscription.form.service-name")
            validationMessage(for: .serviceName)
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription Details") {
            TextField("Plan", text: $plan)
                .accessibilityIdentifier("subscription.form.plan")
            validationMessage(for: .plan)

            TextField("Category", text: $category)
                .accessibilityIdentifier("subscription.form.category")
            validationMessage(for: .category)

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
                selection: $startDate,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.start-date")

            DatePicker(
                "Renewal Anchor",
                selection: $renewalAnchor,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.renewal-anchor")

            DatePicker(
                "Next Renewal",
                selection: $confirmedNextRenewal,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.next-renewal")

            validationMessage(for: .confirmedNextRenewal)
            validationMessage(for: .renewalAnchor)
        }
    }

    private var optionalSection: some View {
        Section("Optional") {
            TextField("Management URL", text: $managementURLText)
                .textContentType(.URL)
                .subscriptionURLKeyboard()
                .accessibilityIdentifier("subscription.form.management-url")

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

        workspace.createSubscription(
            SubscriptionCreationInput(
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
        )

        guard workspace.creationValidationErrors.isEmpty else {
            return
        }

        if case .loaded = workspace.detailState {
            dismiss()
        } else {
            saveFailed = true
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
