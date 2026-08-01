import SubscriptionCore
import SwiftUI

struct ConfirmChargeView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let subscription: Subscription

    @State private var scheduledDate: Date
    @State private var chargedDate: Date
    @State private var amountText: String
    @State private var currency: Currency
    @State private var error: PaymentHistoryActionError?

    init(workspace: SubscriptionWorkspace, subscription: Subscription) {
        self.workspace = workspace
        self.subscription = subscription
        let expected = workspace.paymentHistory.compactMap { entry -> ExpectedCharge? in
            if case .expected(let charge) = entry { return charge }
            return nil
        }.first
        let date = expected?.scheduledDate ?? subscription.confirmedNextRenewal
        let amount = expected?.amount
            ?? subscription.amount(onBillingDay: date)
        _scheduledDate = State(initialValue: date)
        _chargedDate = State(initialValue: date)
        _amountText = State(initialValue: editableMoneyText(
            amount,
            locale: .current
        ))
        _currency = State(initialValue: amount.currency)
    }

    var body: some View {
        Form {
            Section("Scheduled Charge") {
                DatePicker(
                    "Scheduled Date",
                    selection: $scheduledDate,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("subscription.confirm.scheduled-date")
            }
            Section("Confirmed Payment") {
                DatePicker(
                    "Payment Date",
                    selection: $chargedDate,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("subscription.confirm.charged-date")
                TextField("Amount", text: $amountText)
                    .subscriptionDecimalKeyboard()
                    .accessibilityIdentifier("subscription.confirm.amount")
                Picker("Currency", selection: $currency) {
                    ForEach(Currency.allCases, id: \.rawValue) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("subscription.confirm.currency")
            }
            if let error {
                Section {
                    ValidationMessage(
                        paymentHistoryActionErrorText(error),
                        identifier: "subscription.confirm.error"
                    )
                }
            }
        }
        .navigationTitle("Confirm Charge")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") { confirm() }
                    .accessibilityIdentifier("subscription.confirm.save")
            }
        }
    }

    private func confirm() {
        guard let amount = MoneyTextParser.parse(
            amountText,
            currency: currency,
            locale: .current
        ) else {
            error = .mustBePositive
            return
        }
        workspace.confirmCharge(
            id: subscription.id,
            scheduledDate: scheduledDate,
            chargedDate: chargedDate,
            amount: amount
        )
        error = workspace.paymentHistoryActionError
        if error == nil { dismiss() }
    }
}
