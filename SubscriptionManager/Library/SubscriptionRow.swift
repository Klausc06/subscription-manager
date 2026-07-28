import SubscriptionCore
import SwiftUI

struct SubscriptionRow: View {
    @Environment(\.locale) private var locale

    let subscription: SubscriptionSummary

    private var timeZone: TimeZone {
        billingTimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        )
    }

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
                Text(formattedBillingDate(
                    subscription.confirmedNextRenewal,
                    timeZoneIdentifier:
                        subscription.billingSchedule.timeZoneIdentifier,
                    locale: locale
                ))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .environment(\.timeZone, timeZone)
    }
}
