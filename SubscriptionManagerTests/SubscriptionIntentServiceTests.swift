import Foundation
import AppIntents
import SubscriptionCore
import SwiftData
import Testing
@testable import SubscriptionManager

@Suite("Subscription intent service")
struct SubscriptionIntentServiceTests {
    @Test("Adding through the service returns the one workspace record")
    @MainActor
    func addUsesTheLiveWorkspaceCommand() throws {
        let dependencies = try makeDependencies()
        let service = SubscriptionIntentService(
            workspace: dependencies.workspace
        )

        let result = service.add(
            SubscriptionCreationInput(
                serviceName: "Atlas",
                plan: "Pro",
                category: "Productivity",
                originalAmount: Money(minorUnits: 1_299, currency: .usd),
                startDate: Date(timeIntervalSince1970: 1_767_225_600),
                confirmedNextRenewal: Date(timeIntervalSince1970: 1_769_904_000),
                managementURL: nil,
                notes: ""
            )
        )

        guard case .created(let subscription) = result else {
            Issue.record("Expected one created subscription")
            return
        }
        #expect(subscription.serviceName == "Atlas")
        #expect(try dependencies.workspace.subscriptions() == [subscription])
    }

    @Test("Financial App Intents require local-device authentication")
    func sensitiveIntentsRequireLocalAuthentication() {
        #expect(
            AddSubscriptionIntent.authenticationPolicy
                == .requiresLocalDeviceAuthentication
        )
        #expect(
            ShowUpcomingRenewalsIntent.authenticationPolicy
                == .requiresLocalDeviceAuthentication
        )
        #expect(
            ShowMonthlyForecastIntent.authenticationPolicy
                == .requiresLocalDeviceAuthentication
        )
    }

    @MainActor
    private func makeDependencies() throws -> AppDependencies {
        let state = AppDependencies.make(
            allowsExchangeRateNetworking: false,
            modelContainer: {
                try ModelContainer(
                    for: SubscriptionRecord.self,
                    UserPreferencesRecord.self,
                    CalendarProjectionMappingRecord.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                )
            }
        )
        guard case .ready(let dependencies) = state else {
            throw TestFailure.startupFailed
        }
        return dependencies
    }
}

private enum TestFailure: Error {
    case startupFailed
}
