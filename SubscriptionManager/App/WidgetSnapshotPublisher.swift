import Foundation
import SubscriptionCore

@MainActor
struct AppGroupWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private let store: WidgetSnapshotStore?

    init(
        suiteName: String = WidgetSnapshotStore.appGroupIdentifier
    ) {
        store = WidgetSnapshotStore(suiteName: suiteName)
    }

    func publish(_ snapshot: WidgetSnapshot) {
        store?.write(snapshot)
    }
}
