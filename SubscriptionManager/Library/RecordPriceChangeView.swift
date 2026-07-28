import SubscriptionCore
import SwiftUI

struct RecordPriceChangeView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let subscription: Subscription

    @State private var effectiveDate: Date
    @State private var amountText: String
    @State private var currency: Currency
    @State private var error: PaymentHistoryActionError?

    init(workspace: SubscriptionWorkspace, subscription: Subscription) {
        self.workspace = workspace
        self.subscription = subscription
        _effectiveDate = State(initialValue: subscription.confirmedNextRenewal)
        _amountText = State(initialValue: editableMoneyText(
            subscription.originalAmount,
            locale: .current
        ))
        _currency = State(initialValue: subscription.originalAmount.currency)
    }

    var body: some View {
        Form {
            Section("Price Change") {
                DatePicker(
                    "Effective Date",
                    selection: $effectiveDate,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("subscription.price-change.effective-date")
                TextField("Amount", text: $amountText)
                    .subscriptionDecimalKeyboard()
                    .accessibilityIdentifier("subscription.price-change.amount")
                Picker("Currency", selection: $currency) {
                    ForEach(Currency.allCases, id: \.rawValue) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("subscription.price-change.currency")
            }
            if let error {
                Section {
                    ValidationMessage(
                        paymentHistoryActionErrorText(error),
                        identifier: "subscription.price-change.error"
                    )
                }
            }
        }
        .navigationTitle("Record Price Change")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("subscription.price-change.save")
            }
        }
    }

    private func save() {
        guard let amount = MoneyTextParser.parse(
            amountText,
            currency: currency,
            locale: .current
        ) else {
            error = .mustBePositive
            return
        }
        workspace.recordPriceChange(
            id: subscription.id,
            effectiveDate: effectiveDate,
            amount: amount
        )
        error = workspace.paymentHistoryActionError
        if error == nil { dismiss() }
    }
}
