import Foundation
import SubscriptionCore
import SwiftUI

struct EditSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    let subscription: Subscription

    @State private var serviceName: String
    @State private var plan: String
    @State private var category: String
    @State private var intervalChoice: BillingIntervalChoice
    @State private var customValueText: String
    @State private var customUnit: BillingIntervalUnit
    @State private var startDate: Date
    @State private var confirmedNextRenewal: Date
    @State private var managementURLText: String
    @State private var notes: String
    @State private var managementURLIsInvalid = false
    @State private var saveFailed = false
    private let billingDateEditState = BillingDateEditState()

    init(
        workspace: SubscriptionWorkspace,
        subscription: Subscription
    ) {
        self.workspace = workspace
        self.subscription = subscription
        _serviceName = State(initialValue: subscription.serviceName)
        _plan = State(initialValue: subscription.plan)
        _category = State(initialValue: subscription.category)
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
        .onChange(of: selectedBillingInterval) { _, interval in
            updateDatesForInterval(interval)
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
                LocalizedStringKey(
                    billingStartDateLabelKey(isTrial: isTrial)
                ),
                selection: startDateBinding,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.start-date")
            .accessibilityValue(
                formattedBillingDate(
                    startDate,
                    timeZoneIdentifier:
                        subscription.billingSchedule.timeZoneIdentifier,
                    locale: locale
                )
            )

            DatePicker(
                LocalizedStringKey(
                    billingNextDateLabelKey(isTrial: isTrial)
                ),
                selection: confirmedNextRenewalBinding,
                displayedComponents: .date
            )
            .accessibilityIdentifier("subscription.form.next-renewal")
            .accessibilityValue(
                formattedBillingDate(
                    confirmedNextRenewal,
                    timeZoneIdentifier:
                        subscription.billingSchedule.timeZoneIdentifier,
                    locale: locale
                )
            )

            validationMessage(for: .confirmedNextRenewal)
        }
        .environment(
            \.timeZone,
            TimeZone(
                identifier: subscription.billingSchedule.timeZoneIdentifier
            ) ?? .autoupdatingCurrent
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { startDate },
            set: { newValue in
                startDate = newValue
                guard linksBillingDates,
                      let dates = billingDateEditState.editingStartDate(
                          newValue,
                          interval: selectedBillingInterval,
                          asOf: Date(),
                          timeZoneIdentifier:
                              subscription.billingSchedule.timeZoneIdentifier
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
                guard linksBillingDates,
                      let dates = billingDateEditState.editingNextRenewal(
                          newValue,
                          interval: selectedBillingInterval,
                          timeZoneIdentifier:
                              subscription.billingSchedule.timeZoneIdentifier
                      )
                else {
                    return
                }
                apply(dates)
            }
        )
    }

    private var optionalSection: some View {
        Section("Optional") {
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

    @ViewBuilder
    private func validationMessage(
        for field: SubscriptionCreationField
    ) -> some View {
        if let error = workspace.editingValidationErrors[field] {
            ValidationMessage(
                validationText(for: error, field: field),
                identifier: "subscription.validation.\(field.identifier)"
            )
        }
    }

    private func save() {
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
                amount: effectiveEditAmount(
                    for: subscription,
                    onBillingDay: normalizedNextRenewal
                ),
                billingSchedule: FixedBillingSchedule(
                    interval: interval,
                    renewalAnchor: isTrial
                        ? normalizedNextRenewal
                        : normalizedStartDate,
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

    private var linksBillingDates: Bool {
        subscription.lifecycle == .active
    }

    private var isTrial: Bool {
        if case .trial = subscription.lifecycle {
            return true
        }
        return false
    }

    private var selectedBillingInterval: BillingInterval {
        intervalChoice.interval(
            customValueText: customValueText,
            customUnit: customUnit
        )
    }

    private func updateDatesForInterval(_ interval: BillingInterval) {
        guard linksBillingDates,
              let dates = billingDateEditState.changingInterval(
                  startDate: startDate,
                  interval: interval,
                  asOf: Date(),
                  timeZoneIdentifier:
                      subscription.billingSchedule.timeZoneIdentifier
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

    private func managementURL(
        from result: ManagementURLParseResult
    ) -> URL? {
        guard case .valid(let url) = result else {
            return nil
        }
        return url
    }
}
