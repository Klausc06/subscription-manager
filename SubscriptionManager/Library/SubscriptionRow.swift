import SubscriptionCore
import SwiftUI

struct SubscriptionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    let subscription: SubscriptionSummary

    private var timeZone: TimeZone {
        billingTimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        )
    }

    var body: some View {
        rowContent
        .padding(.vertical, 4)
        .environment(\.timeZone, timeZone)
    }

    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(subscription.serviceName)
                    .font(.headline)
                Text(formattedMoney(subscription.amount))
                    .font(.headline)
                    .accessibilityIdentifier("subscription.row.amount")
                SubscriptionStatusBadge(status: subscription.status)
                Text(subscription.plan)
                    .foregroundStyle(.secondary)
                if let nextExpectedCharge = subscription.nextExpectedCharge {
                    Text(formattedBillingDate(
                        nextExpectedCharge.scheduledDate,
                        timeZoneIdentifier:
                            subscription.billingSchedule.timeZoneIdentifier,
                        locale: locale
                    ))
                    .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(subscription.serviceName)
                        .font(.headline)
                    SubscriptionStatusBadge(status: subscription.status)
                    Spacer()
                    Text(formattedMoney(subscription.amount))
                        .font(.headline)
                        .accessibilityIdentifier("subscription.row.amount")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(subscription.plan)
                    Spacer()
                    if let nextExpectedCharge = subscription.nextExpectedCharge {
                        Text(formattedBillingDate(
                            nextExpectedCharge.scheduledDate,
                            timeZoneIdentifier:
                                subscription.billingSchedule.timeZoneIdentifier,
                            locale: locale
                        ))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}
