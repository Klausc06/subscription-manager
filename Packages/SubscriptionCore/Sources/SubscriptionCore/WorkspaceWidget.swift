import Foundation
import Observation

extension SubscriptionWorkspace {
    public func makeWidgetSnapshot() -> WidgetSnapshot? {
        let hidesAmounts = currentPreferences.hideAmountsInCalendar
        do {
            let nextRenewal = try repository.listSubscriptions()
                .compactMap { subscription -> WidgetRenewalSnapshot? in
                    guard let charge = makePresentationNextExpectedCharge(
                        for: subscription
                    ) else {
                        return nil
                    }
                    return WidgetRenewalSnapshot(
                        subscriptionID: subscription.id,
                        serviceName: subscription.serviceName,
                        renewalDate: charge.scheduledDate,
                        amountDescription: hidesAmounts
                            ? nil : formattedWidgetAmount(charge.amount),
                        isRateStale: false
                    )
                }
                .min { lhs, rhs in
                    if lhs.renewalDate != rhs.renewalDate {
                        return lhs.renewalDate < rhs.renewalDate
                    }
                    return lhs.subscriptionID.uuidString < rhs.subscriptionID.uuidString
                }
            return WidgetSnapshot(generatedAt: now(), nextRenewal: nextRenewal)
        } catch {
            return nil
        }
    }
    func publishWidgetSnapshot() {
        guard let snapshot = makeWidgetSnapshot() else { return }
        widgetSnapshotPublisher?.publish(snapshot)
    }
    func formattedWidgetAmount(_ money: Money) -> String {
        (Decimal(money.minorUnits) / 100).formatted(
            .currency(code: money.currency.rawValue).locale(.current)
        )
    }
}
