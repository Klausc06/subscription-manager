import SubscriptionCore
import SwiftUI

/// A narrow, UI-neutral representation derived only from workspace outputs.
struct MacMenuBarPresentation: Equatable {
    let nextRenewal: WidgetRenewalSnapshot?
    let forecast: Money?

    init(
        snapshot: WidgetSnapshot?,
        insightsState: SpendingInsightsState
    ) {
        nextRenewal = snapshot?.nextRenewal
        forecast = insightsState.availableValue?.selectedRangeTotal
    }
}

@MainActor
enum MacWindowDestination: Equatable {
    case none
    case open
    case quickAdd
}

/// Keeps menu-bar commands available until a newly recreated window is ready.
@MainActor
final class MacWindowRouter: ObservableObject {
    @Published private(set) var destination: MacWindowDestination = .none

    func showMainWindow() {
        destination = .open
    }

    func showQuickAdd() {
        destination = .quickAdd
    }

    func takeDestination() -> MacWindowDestination {
        defer { destination = .none }
        return destination
    }
}
