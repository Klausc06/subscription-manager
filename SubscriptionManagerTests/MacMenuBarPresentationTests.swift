import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct MacMenuBarPresentationTests {
    @Test("Menu-bar presentation carries the workspace renewal and forecast")
    func presentationUsesWorkspaceDerivedValues() {
        let renewal = WidgetRenewalSnapshot(
            subscriptionID: UUID(),
            serviceName: "StreamBox",
            renewalDate: Date(timeIntervalSince1970: 1_800_000_000),
            amountDescription: "US$12.99",
            isRateStale: false
        )
        let forecast = Money(minorUnits: 2_598, currency: .usd)
        let insights = SpendingInsights(
            mode: .expected,
            displayCurrency: .usd,
            selectedRangeTotal: forecast,
            annualizedTotal: forecast,
            monthlyTotals: [],
            categoryTotals: [],
            items: []
        )

        let presentation = MacMenuBarPresentation(
            snapshot: WidgetSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_799_000_000),
                nextRenewal: renewal
            ),
            insightsState: .available(insights)
        )

        #expect(presentation.nextRenewal == renewal)
        #expect(presentation.forecast == forecast)
    }

    @Test("Menu-bar presentation makes unavailable forecasts explicit")
    func presentationMarksUnavailableForecast() {
        let presentation = MacMenuBarPresentation(
            snapshot: nil,
            insightsState: .unavailable
        )

        #expect(presentation.nextRenewal == nil)
        #expect(presentation.forecast == nil)
    }
}
