import Foundation
import SubscriptionCore
import WidgetKit

@MainActor
struct AppGroupWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private let store: WidgetSnapshotStore?
    private let reloadTimelines: @MainActor (String) -> Void

    init(
        suiteName: String = WidgetSnapshotStore.appGroupIdentifier,
        reloadTimelines: @escaping @MainActor (String) -> Void = { kind in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    ) {
        store = WidgetSnapshotStore(suiteName: suiteName)
        self.reloadTimelines = reloadTimelines
    }

    func publish(_ snapshot: WidgetSnapshot) {
        guard let store, store.write(snapshot) else { return }
        reloadTimelines(WidgetSnapshotStore.renewalWidgetKind)
    }
}
