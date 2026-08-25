import SubscriptionCore
import SwiftUI

/// A circular progress ring showing how far the current billing period has
/// elapsed. The fraction is derived from the subscription's billing interval
/// and confirmed next renewal date.
struct RenewalProgressView: View {
    let subscription: Subscription
    let now: Date

    private var progress: Double {
        let interval = subscription.billingSchedule.interval
        let nextRenewal = subscription.confirmedNextRenewal
        let calendar = Calendar(identifier: .gregorian)

        // Derive the period start by subtracting one billing interval
        // from the next renewal date.
        let periodStart: Date
        switch interval {
        case .weekly:
            periodStart = calendar.date(
                byAdding: .day, value: -7, to: nextRenewal
            ) ?? nextRenewal
        case .monthly:
            periodStart = calendar.date(
                byAdding: .month, value: -1, to: nextRenewal
            ) ?? nextRenewal
        case .quarterly:
            periodStart = calendar.date(
                byAdding: .month, value: -3, to: nextRenewal
            ) ?? nextRenewal
        case .halfYearly:
            periodStart = calendar.date(
                byAdding: .month, value: -6, to: nextRenewal
            ) ?? nextRenewal
        case .yearly:
            periodStart = calendar.date(
                byAdding: .year, value: -1, to: nextRenewal
            ) ?? nextRenewal
        case .custom(let value, let unit):
            switch unit {
            case .day:
                periodStart = calendar.date(
                    byAdding: .day, value: -value, to: nextRenewal
                ) ?? nextRenewal
            case .week:
                periodStart = calendar.date(
                    byAdding: .day, value: -value * 7, to: nextRenewal
                ) ?? nextRenewal
            case .month:
                periodStart = calendar.date(
                    byAdding: .month, value: -value, to: nextRenewal
                ) ?? nextRenewal
            case .year:
                periodStart = calendar.date(
                    byAdding: .year, value: -value, to: nextRenewal
                ) ?? nextRenewal
            }
        }

        let totalDuration = nextRenewal.timeIntervalSince(periodStart)
        guard totalDuration > 0 else { return 0 }

        let elapsed = now.timeIntervalSince(periodStart)
        return min(max(elapsed / totalDuration, 0), 1)
    }

    private var daysRemaining: Int {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: subscription.confirmedNextRenewal)
        )
        return max(components.day ?? 0, 0)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: progress)
                VStack(spacing: 2) {
                    Text("\(daysRemaining)")
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(daysRemaining) days until renewal, \(Int(progress * 100)) percent elapsed"
            )
            .accessibilityIdentifier("subscription.renewal-progress")
        }
    }
}
