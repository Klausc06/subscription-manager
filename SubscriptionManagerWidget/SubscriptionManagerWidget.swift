import Foundation
import SubscriptionCore
import SwiftUI
import WidgetKit

struct RenewalWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var isStale: Bool {
        guard let snapshot else { return false }
        return date.timeIntervalSince(snapshot.generatedAt) > 36 * 60 * 60
    }
}

struct RenewalWidgetProvider: TimelineProvider {
    private let store = WidgetSnapshotStore(
        suiteName: WidgetSnapshotStore.appGroupIdentifier
    )

    func placeholder(in context: Context) -> RenewalWidgetEntry {
        RenewalWidgetEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                generatedAt: .now,
                nextRenewal: WidgetRenewalSnapshot(
                    subscriptionID: UUID(),
                    serviceName: "Example Service",
                    renewalDate: .now,
                    amountDescription: "$9.99",
                    isRateStale: false
                )
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (RenewalWidgetEntry) -> Void
    ) {
        completion(currentEntry(at: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<RenewalWidgetEntry>) -> Void
    ) {
        let entry = currentEntry(at: .now)
        let refreshDate = Calendar.current.nextDate(
            after: entry.date,
            matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? entry.date.addingTimeInterval(6 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func currentEntry(at date: Date) -> RenewalWidgetEntry {
        RenewalWidgetEntry(date: date, snapshot: store?.read())
    }
}

struct RenewalWidgetView: View {
    @Environment(\.redactionReasons) private var redactionReasons
    let entry: RenewalWidgetEntry

    private var renewal: WidgetRenewalSnapshot? {
        entry.snapshot?.nextRenewal
    }

    private var privacy: WidgetPrivacyMode {
        redactionReasons.contains(.privacy) ? .redacted : .standard
    }

    private var title: String {
        renewal?.serviceName ?? String(localized: "widget.empty.title")
    }

    private var amountDescription: String? {
        privacy == .standard ? renewal?.amountDescription : nil
    }

    private var deepLink: URL? {
        guard let renewal else {
            return URL(string: "subscription-manager://subscriptions")
        }
        return URL(
            string: "subscription-manager://subscription/"
                + renewal.subscriptionID.uuidString
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let amountDescription {
                Text(amountDescription)
                    .font(.title3.weight(.semibold))
                    .privacySensitive()
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(deepLink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var subtitle: String {
        if entry.snapshot == nil {
            return String(localized: "widget.unavailable.subtitle")
        }
        if entry.isStale {
            return String(localized: "widget.stale.subtitle")
        }
        guard let renewal else {
            return String(localized: "widget.empty.subtitle")
        }
        return renewal.renewalDate.formatted(
            .dateTime.month(.abbreviated).day()
        )
    }

    private var accessibilityLabel: String {
        [title, subtitle, amountDescription]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct RenewalWidget: Widget {
    let kind = WidgetSnapshotStore.renewalWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RenewalWidgetProvider()) { entry in
            RenewalWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.display-name")
        .description("widget.description")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium])
    }
}

@main
struct SubscriptionManagerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RenewalWidget()
    }
}
