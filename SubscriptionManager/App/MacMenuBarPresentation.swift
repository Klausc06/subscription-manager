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

enum MacAddSubscriptionTrigger: CaseIterable, Equatable {
    case toolbar
    case command
    case quickAdd
}

struct MacAddPresentationState: Equatable {
    private(set) var trigger: MacAddSubscriptionTrigger?
    private(set) var scope: SubscriptionLibraryScope?

    var isPresented: Bool {
        trigger != nil
    }

    mutating func present(
        from trigger: MacAddSubscriptionTrigger,
        scope: SubscriptionLibraryScope
    ) {
        self.trigger = trigger
        self.scope = scope
    }

    func complete(
        _ reload: (SubscriptionLibraryScope) -> Void
    ) {
        guard let scope else { return }
        reload(scope)
    }

    mutating func dismiss() {
        trigger = nil
        scope = nil
    }
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
