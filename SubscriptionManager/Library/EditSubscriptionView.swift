import Foundation
import SubscriptionCore
import SwiftUI

struct EditSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let subscription: Subscription

    @State private var serviceName: String
    @State private var plan: String
    @State private var category: String
    @State private var amountText: String
    @State private var currency: Currency
    @State private var intervalChoice: BillingIntervalChoice
    @State private var customValueText: String
    @State private var customUnit: BillingIntervalUnit
    @State private var startDate: Date
    @State private var renewalAnchor: Date
    @State private var confirmedNextRenewal: Date
    @State private var managementURLText: String
    @State private var notes: String
    @State private var amountInputIsInvalid = false
    @State private var managementURLIsInvalid = false
    @State private var saveFailed = false

    init(
        workspace: SubscriptionWorkspace,
        subscription: Subscription
    ) {
        self.workspace = workspace
        self.subscription = subscription
        _serviceName = State(initialValue: subscription.serviceName)
        _plan = State(initialValue: subscription.plan)
        _category = State(initialValue: subscription.category)
        _amountText = State(
            initialValue: editableMoneyText(
                subscription.originalAmount,
                locale: .current
            )
        )
        _currency = State(initialValue: subscription.originalAmount.currency)
        _intervalChoice = State(
            initialValue: BillingIntervalChoice(
                interval: subscription.billingSchedule.interval
            )
        )
        _customValueText = State(
            initialValue: subscription.billingSchedule.interval.customValue
                .map(String.init) ?? ""
        )
        _customUnit = State(
            initialValue:
                subscription.billingSchedule.interval.customUnit ?? .day
        )
        let timeZoneIdentifier =
            subscription.billingSchedule.timeZoneIdentifier
        _startDate = State(
            initialValue: normalizedBillingDate(
                subscription.startDate,
                timeZoneIdentifier: timeZoneIdentifier
            ) ?? subscription.startDate
        )
        _renewalAnchor = State(
            initialValue: normalizedBillingDate(
                subscription.billingSchedule.renewalAnchor,
                timeZoneIdentifier: timeZoneIdentifier
            ) ?? subscription.billingSchedule.renewalAnchor
        )
        _confirmedNextRenewal = State(
            initialValue: normalizedBillingDate(
                subscription.confirmedNextRenewal,
                timeZoneIdentifier: timeZoneIdentifier
            ) ?? subscription.confirmedNextRenewal
        )
        _managementURLText = State(
            initialValue: subscription.managementURL?.absoluteString ?? ""
        )
        _notes = State(initialValue: subscription.notes)
    }

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
                        "Couldn’t save changes. Try again.",
                        identifier: "subscription.validation.save"
                    )
                }
            }
        }
        .accessibilityIdentifier("subscription.form")
        .onAppear {
            workspace.beginEditing()
        }
        .navigationTitle("Edit Subscription")
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
                    workspace.editingValidationErrors[.billingSchedule]
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

            validationMessage(for: .renewalAnchor)
            validationMessage(for: .confirmedNextRenewal)
        }
        .environment(
            \.timeZone,
            TimeZone(
                identifier: subscription.billingSchedule.timeZoneIdentifier
            ) ?? .autoupdatingCurrent
        )
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
        if let error = workspace.editingValidationErrors[field] {
            ValidationMessage(
                validationText(for: error),
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
        let timeZoneIdentifier =
            subscription.billingSchedule.timeZoneIdentifier
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

        let interval = intervalChoice.interval(
            customValueText: customValueText,
            customUnit: customUnit
        )
        workspace.editSubscription(
            id: subscription.id,
            input: SubscriptionEditInput(
                serviceName: serviceName,
                plan: plan,
                category: category,
                originalAmount: amount,
                billingSchedule: FixedBillingSchedule(
                    interval: interval,
                    renewalAnchor: normalizedRenewalAnchor,
                    timeZoneIdentifier: timeZoneIdentifier
                ),
                startDate: normalizedStartDate,
                confirmedNextRenewal: normalizedNextRenewal,
                managementURL: managementURL(from: managementURLResult),
                notes: notes
            )
        )

        guard workspace.editingValidationErrors.isEmpty else {
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
