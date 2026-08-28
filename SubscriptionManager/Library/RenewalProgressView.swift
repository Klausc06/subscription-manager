import SubscriptionCore
import SwiftUI

/// A circular progress ring showing how far the current billing period has
/// elapsed. The fraction is derived from the subscription's billing interval
/// and confirmed next renewal date.
///
/// Every derivation runs in the subscription's billing time zone, so the ring
/// and the remaining-day count agree with the projected charge rather than
/// with wherever the device happens to be.
struct RenewalProgressView: View {
    let subscription: Subscription
    let now: Date

    private var periodProgress: RenewalPeriodProgress {
        RenewalPeriodProgress(
            schedule: subscription.billingSchedule,
            confirmedNextRenewal: subscription.confirmedNextRenewal,
            asOf: now
        )
    }

    /// Built as a single localized key so VoiceOver reads the person's
    /// language. Interpolating into `String` would bind the verbatim
    /// `Text` overload and ship English to every locale.
    private func accessibilityLabel(
        for progress: RenewalPeriodProgress
    ) -> Text {
        Text(
            "\(progress.daysRemaining) days until renewal, \(progress.percentElapsed) percent elapsed"
        )
    }

    var body: some View {
        let progress = periodProgress
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(
                        .easeInOut(duration: 0.6),
                        value: progress.fraction
                    )
                VStack(spacing: 2) {
                    Text("\(progress.daysRemaining)")
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: progress))
            .accessibilityIdentifier("subscription.renewal-progress")
        }
    }
}
