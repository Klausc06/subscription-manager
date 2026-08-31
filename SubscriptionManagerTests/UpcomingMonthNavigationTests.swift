import Testing
@testable import SubscriptionManager
@Suite("Upcoming month navigation")
struct UpcomingMonthNavigationTests {
    @Test("A wide, loaded month leaves navigation to the native calendar")
    func loadedWideMonthUsesNativeCalendarOnly() {
        #expect(
            UpcomingView.showsNativeMonthCalendar(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: false
            )
        )
        #expect(
            !UpcomingView.showsPinnedMonthNavigation(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: false
            )
        )
    }

    @Test("A failed month keeps navigation reachable on a wide layout")
    func failedWideMonthKeepsPinnedNavigation() {
        #expect(
            !UpcomingView.showsNativeMonthCalendar(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: true
            )
        )
        #expect(
            UpcomingView.showsPinnedMonthNavigation(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: true
            )
        )
    }

    @Test("Layouts without the native calendar always pin navigation")
    func layoutsWithoutNativeCalendarPinNavigation() {
        for hasUpcomingFailure in [false, true] {
            #expect(
                !UpcomingView.showsNativeMonthCalendar(
                    canUseNativeMonthCalendar: false,
                    hasUpcomingFailure: hasUpcomingFailure
                )
            )
            #expect(
                UpcomingView.showsPinnedMonthNavigation(
                    canUseNativeMonthCalendar: false,
                    hasUpcomingFailure: hasUpcomingFailure
                )
            )
        }
    }
}
