#if os(macOS)
import AppKit
import ServiceManagement
import SubscriptionCore
import SwiftUI

struct MacMenuBarScene: Scene {
    let workspace: SubscriptionWorkspace?
    let router: MacWindowRouter

    var body: some Scene {
        MenuBarExtra(
            "Subscription Manager",
            systemImage: "creditcard",
            isInserted: Binding(
                get: { menuBarModeEnabled },
                set: { _ in }
            )
        ) {
            if let workspace {
                MacMenuBarExtraView(workspace: workspace, router: router)
            }
        }
    }

    private var menuBarModeEnabled: Bool {
        guard let workspace else { return false }
        return switch workspace.setupState {
        case .needsSetup(let preferences),
             .completed(let preferences),
             .skipped(let preferences),
             .failed(let preferences):
            preferences.menuBarModeEnabled
        case .notLoaded:
            false
        }
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var failed = false

    init(service: SMAppService = .mainApp) {
        refresh(service: service)
    }

    func setEnabled(_ enabled: Bool, service: SMAppService = .mainApp) {
        failed = false
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh(service: service)
        } catch {
            failed = true
            refresh(service: service)
        }
    }

    private func refresh(service: SMAppService) {
        isEnabled = service.status == .enabled
        requiresApproval = service.status == .requiresApproval
    }
}

struct LaunchAtLoginSettingsView: View {
    @StateObject private var controller = LaunchAtLoginController()

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { controller.isEnabled },
            set: { controller.setEnabled($0) }
        ))
        .accessibilityIdentifier("preferences.launch-at-login")
        if controller.requiresApproval {
            Text("Approve Subscription Manager in Login Items to finish enabling launch at login.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if controller.failed {
            Text("Couldn’t update launch at login. Try again.")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

struct MacMenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow
    let workspace: SubscriptionWorkspace
    let router: MacWindowRouter

    @State private var presentation = MacMenuBarPresentation(
        snapshot: nil,
        insightsState: .notLoaded
    )

    var body: some View {
        Group {
            if let renewal = presentation.nextRenewal {
                Text("Next: \(renewal.serviceName)")
                Text(renewal.renewalDate, format: .dateTime.month().day().year())
                    .foregroundStyle(.secondary)
            } else {
                Text("No Upcoming Renewals")
            }

            if let forecast = presentation.forecast {
                Text("This Month: \(formattedMoney(forecast))")
            } else {
                Text("This Month: Forecast Unavailable")
                    .foregroundStyle(.secondary)
            }

            Divider()
            Button("Quick Add") { open(.quickAdd) }
            Button("Open App") { open(.open) }
            Divider()
            Button("Quit Subscription Manager") { NSApp.terminate(nil) }
        }
        .task {
            workspace.loadLibrary(scope: .current)
            await workspace.refreshExchangeRates()
            let interval = Calendar.current.dateInterval(of: .month, for: Date())
            workspace.loadInsights(
                mode: .expected,
                from: interval?.start ?? Date(),
                through: interval?.end.addingTimeInterval(-1) ?? Date()
            )
            presentation = MacMenuBarPresentation(
                snapshot: workspace.makeWidgetSnapshot(),
                insightsState: workspace.insightsState
            )
        }
    }

    private func open(_ destination: MacWindowDestination) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main-window")
        switch destination {
        case .none:
            break
        case .open:
            router.showMainWindow()
        case .quickAdd:
            router.showQuickAdd()
        }
    }
}
#endif
