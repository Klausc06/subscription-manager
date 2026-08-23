import Foundation
import Observation

extension SubscriptionWorkspace {
    @discardableResult
    public func loadCalendarProjection(locale: Locale) -> Bool {
        calendarProjectionLocale = locale
        let horizon = calendar.date(
            byAdding: .month,
            value: currentPreferences.calendarProjectionHorizon.rawValue,
            to: now()
        ) ?? now()
        do {
            calendarProjection = try repository.listSubscriptions()
                .flatMap { subscription in
                    makeCalendarProjectionEvents(
                        for: subscription,
                        through: horizon,
                        locale: locale,
                        hidesAmounts: currentPreferences.hideAmountsInCalendar
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.startDate != rhs.startDate {
                        return lhs.startDate < rhs.startDate
                    }
                    return lhs.uid < rhs.uid
                }
            return true
        } catch {
            calendarProjection = []
            return false
        }
    }
    public func importCalendarProjection(
        _ events: [CalendarProjectionEvent]
    ) async {
        guard !events.isEmpty else {
            calendarImportState = .imported(
                CalendarProjectionImportSummary(
                    createdCount: 0,
                    updatedCount: 0
                )
            )
            return
        }
        guard let calendarProjectionImporter else {
            calendarImportState = .unavailable
            return
        }
        calendarImportState = .importing
        let result = await calendarProjectionImporter.importProjection(
            events: events
        )
        calendarImportState = CalendarImportState(result: result)
    }
    public func reconcileCalendarProjection(locale: Locale) async {
        await enqueueCalendarReconciliation(.reconcile(locale))
    }
    public func rebuildCalendarProjection(locale: Locale) async {
        await enqueueCalendarReconciliation(.rebuild(locale))
    }
    public func disableCalendarReconciliation() async {
        await enqueueCalendarReconciliation(.disable)
    }
    func enqueueCalendarReconciliation(
        _ request: CalendarReconciliationRequest
    ) async {
        guard calendarProjectionReconciler != nil else {
            calendarReconciliationState = .notConfigured
            return
        }
        guard calendarReconciliationState != .reconciling else {
            pendingCalendarReconciliationRequest =
                coalescedCalendarReconciliationRequest(
                    pending: pendingCalendarReconciliationRequest,
                    incoming: request
                )
            return
        }
        calendarReconciliationState = .reconciling

        var request = request
        while true {
            let result = await performCalendarReconciliation(request)
            guard let pending = pendingCalendarReconciliationRequest else {
                calendarReconciliationState = CalendarReconciliationState(
                    result: result
                )
                return
            }
            pendingCalendarReconciliationRequest = nil
            request = pending
        }
    }
    func coalescedCalendarReconciliationRequest(
        pending: CalendarReconciliationRequest?,
        incoming: CalendarReconciliationRequest
    ) -> CalendarReconciliationRequest {
        guard let pending else { return incoming }
        return incoming.priority >= pending.priority ? incoming : pending
    }
    func performCalendarReconciliation(
        _ request: CalendarReconciliationRequest
    ) async -> CalendarReconciliationResult {
        guard let calendarProjectionReconciler else {
            return .notConfigured
        }
        switch request {
        case .reconcile(let locale):
            guard loadCalendarProjection(locale: locale) else {
                return .unavailable
            }
            return await calendarProjectionReconciler.perform(
                .reconcile(calendarProjection)
            )
        case .rebuild(let locale):
            guard loadCalendarProjection(locale: locale) else {
                return .unavailable
            }
            return await calendarProjectionReconciler.perform(
                .rebuild(calendarProjection)
            )
        case .disable:
            return await calendarProjectionReconciler.perform(.disable)
        }
    }
}
