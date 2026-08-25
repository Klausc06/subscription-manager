import Foundation
import SubscriptionCore
import UserNotifications

/// Schedules local notifications for upcoming subscription renewals.
///
/// Notification preferences are device-local (not CloudKit-synced) because
/// notification authorization and timing are inherently per-device concerns.
@MainActor
final class RenewalNotificationScheduler {
    static let advanceDaysKey = "subscription-manager.notification-advance-days"
    static let enabledKey = "subscription-manager.notifications-enabled"
    private static let categoryIdentifier = "RENEWAL_REMINDER"

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var advanceDays: Int {
        get {
            let stored = defaults.integer(forKey: Self.advanceDaysKey)
            return stored > 0 ? stored : 1
        }
        set { defaults.set(max(1, newValue), forKey: Self.advanceDaysKey) }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            return false
        }
    }

    /// Reschedules all renewal notifications based on the current library.
    func reschedule(subscriptions: [Subscription]) async {
        guard isEnabled else {
            await removeAll()
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            return
        }

        // Remove existing renewal notifications
        await removeAll()

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let advance = advanceDays

        for subscription in subscriptions {
            guard !subscription.isArchived else { continue }
            if case .cancelled = subscription.lifecycle { continue }

            let renewalDate = subscription.confirmedNextRenewal
            let notifyDate = calendar.date(
                byAdding: .day,
                value: -advance,
                to: renewalDate
            ) ?? renewalDate

            // Only schedule if the notification date is in the future
            guard notifyDate > today else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(
                localized: "Upcoming Renewal"
            )
            content.body = String(
                localized: "\(subscription.serviceName) renews in \(advance) day(s)."
            )
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour],
                from: notifyDate
            )
            var triggerComponents = components
            triggerComponents.hour = 9 // Notify at 9 AM local time

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: triggerComponents,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "renewal-\(subscription.id.uuidString)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                // Silently skip individual scheduling failures
            }
        }
    }

    func removeAll() async {
        let pending = await center.pendingNotificationRequests()
        let renewalIDs = pending
            .filter { $0.identifier.hasPrefix("renewal-") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: renewalIDs)
    }
}
