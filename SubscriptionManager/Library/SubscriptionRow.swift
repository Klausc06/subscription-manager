import SubscriptionCore
import SwiftUI

struct SubscriptionRow: View {
    let subscription: SubscriptionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(subscription.serviceName)
                    .font(.headline)
                Spacer()
                Text(formattedMoney(subscription.originalAmount))
                    .font(.headline)
                    .accessibilityIdentifier("subscription.row.amount")
            }
            HStack(alignment: .firstTextBaseline) {
                Text(subscription.plan)
                Spacer()
                Text(
                    subscription.confirmedNextRenewal,
                    format: .dateTime.year().month().day()
                )
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
