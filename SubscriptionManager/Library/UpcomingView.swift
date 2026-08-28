import SubscriptionCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct UpcomingView: View {
    let workspace: SubscriptionWorkspace
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var selectsFirstChargeAfterMonthChange = false
    @State private var confirmationPresentation:
        UpcomingConfirmationPresentation?
    @State private var subscriptionsByID: [UUID: Subscription] = [:]
    @State private var confirmedSourceChargeIDsBySubscription:
        [UUID: Set<ScheduledChargeID>] = [:]
    @State private var cachedProjection: UpcomingCalendarProjection?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let projection = calendarProjection
        let selectedDayItems = selectedDayItems(in: projection)
        NavigationStack {
            GeometryReader { geometry in
                List {
                    monthOverview(
                        availableWidth: geometry.size.width,
                        projection: projection
                    )

                    Section {
                        if hasUpcomingFailure {
                            ContentUnavailableView(
                                "Upcoming Unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(
                                    "Renewals could not be loaded. Try again later."
                                )
                            )
                            .accessibilityIdentifier("upcoming.agenda.failed")
                        } else if selectedDayItems.isEmpty {
                            ContentUnavailableView(
                                "No Charges This Day",
                                systemImage: "calendar",
                                description: Text(
                                    "Choose a day with a charge or another month."
                                )
                            )
                            .accessibilityIdentifier(
                                "upcoming.agenda.empty"
                            )
                        } else {
                            ForEach(selectedDayItems) { item in
                                let confirmation = confirmationContext(
                                    for: item
                                )
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    NavigationLink(value: item.subscriptionID) {
                                        UpcomingTimelineRow(
                                            item: item,
                                            billingTimeZoneIdentifier:
                                                subscriptionsByID[item.subscriptionID]?
                                                .billingSchedule.timeZoneIdentifier
                                                ?? TimeZone.autoupdatingCurrent.identifier
                                        )
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier(
                                        item.kind == .expected
                                            ? "upcoming.row.expected"
                                            : "upcoming.row.confirmed"
                                    )

                                    if let confirmation {
                                        Button {
                                            confirmationPresentation = confirmation
                                        } label: {
                                            Label(
                                                "Confirm Charge",
                                                systemImage: "checkmark.circle"
                                            )
                                            .labelStyle(.iconOnly)
                                            .frame(minWidth: 28, minHeight: 28)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(
                                            "Confirm Charge, \(item.serviceName)"
                                        )
                                        .accessibilityIdentifier(
                                            "upcoming.expected.confirm"
                                        )
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(
                            selectedDay,
                            format: .dateTime.month().day().weekday()
                        )
                        .accessibilityIdentifier("upcoming.agenda")
                    }
                    .listRowInsets(
                        EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                    )
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !canUseNativeMonthCalendar(availableWidth: geometry.size.width) {
                        monthNavigationHeader
                            .background(.background)
                    }
                }
            }
            .navigationTitle("Upcoming")
            .navigationDestination(for: UUID.self) { subscriptionID in
                SubscriptionDetailView(
                    workspace: workspace,
                    subscriptionID: subscriptionID
                )
            }
        }
        .sheet(item: $confirmationPresentation) { presentation in
            NavigationStack {
                ConfirmChargeView(
                    workspace: workspace,
                    subscription: presentation.subscription,
                    expectedOccurrence: presentation.expectedOccurrence
                )
            }
            .presentationBackground(.background)
            .presentationCornerRadius(28)
        }
        .onAppear {
            refreshSubscriptionCaches()
            loadTimeline()
        }
        .task(id: displayedMonth) {
            loadTimeline()
        }
        .onChange(of: workspace.upcomingTimeline) { _, _ in
            rebuildProjection()
        }
        .onChange(of: workspace.libraryState) { _, _ in
            refreshSubscriptionCaches()
        }
    }

    @ViewBuilder
    private var monthNavigationHeader: some View {
        HStack {
            Button { moveMonth(by: -1) } label: {
                Label("Previous Month", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Previous Month")
            .accessibilityIdentifier("upcoming.month.previous")
            .buttonStyle(.borderless)

            Spacer()
            Text(displayedMonth, format: .dateTime.year().month(.wide))
                .font(.headline)
                .accessibilityIdentifier("upcoming.month.title")
            Spacer()

            Button { moveMonth(by: 1) } label: {
                Label("Next Month", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Next Month")
            .accessibilityIdentifier("upcoming.month.next")
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func monthOverview(
        availableWidth: CGFloat,
        projection: UpcomingCalendarProjection
    ) -> some View {
#if os(iOS)
        if hasUpcomingFailure {
            Section {
                ContentUnavailableView(
                    "Upcoming Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Renewals could not be loaded. Try again later."
                    )
                )
                .accessibilityIdentifier("upcoming.month.failed")
            }
        } else if canUseNativeMonthCalendar(availableWidth: availableWidth) {
            Section {
                UpcomingMonthCalendar(
                    selectedDay: $selectedDay,
                    displayedMonth: displayedMonth,
                    dayCounts: Dictionary(
                        uniqueKeysWithValues: projection.days.map {
                            ($0.date, $0.items.count)
                        }
                    ),
                    calendar: calendar,
                    onDisplayedMonthChange: selectMonth
                )
                .frame(maxWidth: .infinity)
                .frame(height: calendarHeight)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("upcoming.calendar")
            }
            .listRowInsets(
                EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )
        } else {
            groupedDayList(projection: projection)
        }
#else
        if hasUpcomingFailure {
            Section {
                ContentUnavailableView(
                    "Upcoming Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Renewals could not be loaded. Try again later."
                    )
                )
                .accessibilityIdentifier("upcoming.month.failed")
            }
        } else {
            groupedDayList(projection: projection)
        }
#endif
    }

    private func groupedDayList(
        projection: UpcomingCalendarProjection
    ) -> some View {
        Section("Days") {
            if projection.days.isEmpty {
                ContentUnavailableView(
                    "No Charges This Month",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(
                        "Select another month or add a subscription."
                    )
                )
                .accessibilityIdentifier("upcoming.month.empty")
            } else {
                ForEach(projection.days) { day in
                    Button {
                        selectedDay = day.date
                    } label: {
                        HStack {
                            Text(day.date, format: .dateTime.month().day().weekday())
                            Spacer()
                            Text(day.items.count, format: .number)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier(dayIdentifier(for: day.date))
                    .accessibilityValue(
                        selectedDay == day.date ? "Selected" : ""
                    )
                    .accessibilityAddTraits(
                        selectedDay == day.date ? .isSelected : []
                    )
                }
            }
        }
    }

    private func canUseNativeMonthCalendar(availableWidth: CGFloat) -> Bool {
#if os(iOS)
        if ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-accessibility-upcoming-layout"
        ) {
            return false
        }
        guard !dynamicTypeSize.isAccessibilitySize else { return false }
        return availableWidth >= nativeCalendarMinimumWidth
#else
        false
#endif
    }

    private var nativeCalendarMinimumWidth: CGFloat {
        // Seven readable day cells plus the list's measured horizontal insets.
        7 * 36 + 32
    }

    private var calendarHeight: CGFloat {
        // Scale calendar height for larger Dynamic Type sizes that remain
        // below the accessibility threshold (where the calendar is hidden).
        // Accessibility sizes (accessibility1–5) hit the default case but
        // never render because canUseNativeMonthCalendar returns false.
        switch dynamicTypeSize {
        case .xxxLarge:
            420
        case .xxLarge:
            400
        case .xLarge:
            380
        default:
            360
        }
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var monthInterval: DateInterval? {
        calendar.dateInterval(of: .month, for: displayedMonth)
    }

    private var calendarProjection: UpcomingCalendarProjection {
        cachedProjection ?? UpcomingCalendarProjection(
            monthContaining: displayedMonth,
            items: [],
            calendar: calendar
        )
    }

    /// Rebuilds the month projection from the already-loaded timeline and
    /// subscription cache. This never touches persistence, so it is safe to
    /// run on every timeline change without re-fetching the library.
    private func rebuildProjection() {
        cachedProjection = UpcomingCalendarProjection(
            monthContaining: displayedMonth,
            items: workspace.upcomingTimeline.map { item in
                UpcomingTimelineItem(
                    id: item.id,
                    kind: item.kind,
                    subscriptionID: item.subscriptionID,
                    serviceName: item.serviceName,
                    date: billingLocalDay(
                        item.date,
                        billingTimeZoneIdentifier:
                            subscriptionsByID[item.subscriptionID]?
                            .billingSchedule.timeZoneIdentifier
                            ?? TimeZone.autoupdatingCurrent.identifier,
                        displayCalendar: calendar
                    ),
                    amount: item.amount
                )
            },
            calendar: calendar
        )
    }

    /// Fetches the subscriptions once and derives every per-row lookup the
    /// agenda needs, including confirmed-charge ID sets that used to be
    /// rebuilt inside each ForEach row.
    private func refreshSubscriptionCaches() {
        guard let subscriptions = try? workspace.subscriptions() else { return }
        var subscriptionsByID: [UUID: Subscription] = [:]
        var confirmedIDsBySubscription:
            [UUID: Set<ScheduledChargeID>] = [:]
        for subscription in subscriptions {
            subscriptionsByID[subscription.id] = subscription
            confirmedIDsBySubscription[subscription.id] = Set(
                subscription.confirmedCharges.compactMap(
                    \.sourceScheduledChargeID
                )
            )
        }
        self.subscriptionsByID = subscriptionsByID
        confirmedSourceChargeIDsBySubscription = confirmedIDsBySubscription
        rebuildProjection()
    }

    private func selectedDayItems(
        in projection: UpcomingCalendarProjection
    ) -> [UpcomingTimelineItem] {
        let selectedIDs = Set(
            projection.days.first(where: { $0.date == selectedDay })?
                .items.map(\.id) ?? []
        )
        return workspace.upcomingTimeline
            .filter { selectedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
    }

    private var hasUpcomingFailure: Bool {
        if case .failed = workspace.upcomingTimelineState {
            return true
        }
        return false
    }

    private func loadTimeline() {
        guard let monthInterval else { return }
        let lastDay = calendar.date(
            byAdding: .nanosecond,
            value: -1,
            to: monthInterval.end
        ) ?? monthInterval.end
        let queryStart = calendar.date(
            byAdding: .day,
            value: -2,
            to: monthInterval.start
        ) ?? monthInterval.start
        let queryEnd = calendar.date(
            byAdding: .day,
            value: 2,
            to: lastDay
        ) ?? lastDay
        workspace.loadUpcomingTimeline(
            from: queryStart,
            through: queryEnd
        )
        rebuildProjection()

        if selectsFirstChargeAfterMonthChange {
            selectedDay = calendarProjection.days.first?.date
                ?? monthInterval.start
            selectsFirstChargeAfterMonthChange = false
        }
    }

    private func moveMonth(by offset: Int) {
        guard let month = calendar.date(
            byAdding: .month,
            value: offset,
            to: displayedMonth
        ) else {
            return
        }
        selectMonth(month)
    }

    private func selectMonth(_ month: Date) {
        let normalizedMonth = calendar.dateInterval(of: .month, for: month)?.start
            ?? calendar.startOfDay(for: month)
        guard !calendar.isDate(
            normalizedMonth,
            equalTo: displayedMonth,
            toGranularity: .month
        ) else {
            return
        }
        displayedMonth = normalizedMonth
        selectedDay = normalizedMonth
        selectsFirstChargeAfterMonthChange = true
    }

    private func dayIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "upcoming.day.\(components.year ?? 0)-\(components.month ?? 0)-"
            + "\(components.day ?? 0)"
    }

    private func confirmationContext(
        for item: UpcomingTimelineItem
    ) -> UpcomingConfirmationPresentation? {
        guard item.kind == .expected,
              let subscription = subscriptionsByID[item.subscriptionID]
        else {
            return nil
        }
        let timeZone = billingTimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: item.date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        let expectedOccurrence = ExpectedCharge(
            id: ScheduledChargeID(
                subscriptionID: subscription.id,
                year: year,
                month: month,
                day: day
            ),
            subscriptionID: subscription.id,
            scheduledDate: item.date,
            amount: item.amount
        )
        let confirmedIDs = confirmedSourceChargeIDsBySubscription[
            subscription.id
        ] ?? []
        guard ConfirmChargeEligibility.isEligible(
            expectedOccurrence: expectedOccurrence,
            confirmedIDs: confirmedIDs,
            now: Date(),
            billingTimeZone: timeZone
        ) else {
            return nil
        }
        return UpcomingConfirmationPresentation(
            subscription: subscription,
            expectedOccurrence: expectedOccurrence
        )
    }
}

#if os(iOS)
struct UpcomingMonthCalendar: UIViewRepresentable {
    @Binding var selectedDay: Date
    let displayedMonth: Date
    let dayCounts: [Date: Int]
    let calendar: Calendar
    let onDisplayedMonthChange: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedDay: $selectedDay,
            calendar: calendar,
            onDisplayedMonthChange: onDisplayedMonthChange
        )
    }

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        configureLayoutMargins(of: calendarView)
        calendarView.calendar = calendar
        calendarView.locale = calendar.locale ?? .current
        calendarView.delegate = context.coordinator
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(
            delegate: context.coordinator
        )
        calendarView.visibleDateComponents = monthComponents(for: displayedMonth)
        calendarView.accessibilityIdentifier = "upcoming.calendar"
        return calendarView
    }

    func updateUIView(_ calendarView: UICalendarView, context: Context) {
        configureLayoutMargins(of: calendarView)
        context.coordinator.calendar = calendar
        context.coordinator.onDisplayedMonthChange = onDisplayedMonthChange
        context.coordinator.dayCounts = dayCounts

        let monthComponents = monthComponents(for: displayedMonth)
        if calendarView.visibleDateComponents.year != monthComponents.year
            || calendarView.visibleDateComponents.month != monthComponents.month {
            // Respect Reduce Motion: jump straight to the paged month.
            calendarView.setVisibleDateComponents(
                monthComponents,
                animated: !UIAccessibility.isReduceMotionEnabled
            )
        }

        if let selection = calendarView.selectionBehavior
            as? UICalendarSelectionSingleDate {
            let selectedComponents = calendar.dateComponents(
                [.year, .month, .day],
                from: selectedDay
            )
            if selection.selectedDate != selectedComponents {
                selection.setSelected(selectedComponents, animated: false)
            }
        }

        calendarView.reloadDecorations(
            forDateComponents: dateComponentsInDisplayedMonth(),
            animated: false
        )
    }

    private func configureLayoutMargins(of calendarView: UICalendarView) {
        // Keep the UIKit calendar's day cells inset from its SwiftUI/List row
        // on every update; otherwise the system can lay digits against the
        // wrapper edge when the month or selection changes.
        calendarView.preservesSuperviewLayoutMargins = false
        calendarView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 8,
            bottom: 8,
            trailing: 8
        )
    }

    private func monthComponents(for date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month], from: date)
    }

    private func dateComponentsInDisplayedMonth() -> [DateComponents] {
        guard let interval = calendar.dateInterval(
            of: .month,
            for: displayedMonth
        ) else {
            return []
        }
        var components: [DateComponents] = []
        var date = interval.start
        while date < interval.end {
            components.append(
                calendar.dateComponents([.year, .month, .day], from: date)
            )
            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }
            date = nextDate
        }
        return components
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate,
        UICalendarSelectionSingleDateDelegate {
        @Binding private var selectedDay: Date
        var calendar: Calendar
        var dayCounts: [Date: Int] = [:]
        var onDisplayedMonthChange: (Date) -> Void

        init(
            selectedDay: Binding<Date>,
            calendar: Calendar,
            onDisplayedMonthChange: @escaping (Date) -> Void
        ) {
            _selectedDay = selectedDay
            self.calendar = calendar
            self.onDisplayedMonthChange = onDisplayedMonthChange
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let dateComponents,
                  let date = calendar.date(from: dateComponents)
            else {
                return
            }
            selectedDay = calendar.startOfDay(for: date)
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            canSelectDate dateComponents: DateComponents?
        ) -> Bool {
            true
        }

        func calendarView(
            _ calendarView: UICalendarView,
            didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents
        ) {
            guard let visibleMonth = calendar.date(
                from: calendarView.visibleDateComponents
            ) else {
                return
            }
            onDisplayedMonthChange(visibleMonth)
        }

        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            guard let date = calendar.date(from: dateComponents) else {
                return nil
            }
            let count = dayCounts[calendar.startOfDay(for: date)] ?? 0
            guard count > 0 else { return nil }

            return .customView {
                let badge = CalendarBadgeLabel()
                badge.text = count > 99 ? "99+" : "\(count)"
                badge.textAlignment = .center
                badge.font = .preferredFont(forTextStyle: .caption2)
                badge.adjustsFontForContentSizeCategory = true
                badge.textColor = .white
                badge.backgroundColor = .tintColor
                badge.clipsToBounds = true
                badge.translatesAutoresizingMaskIntoConstraints = false
                badge.widthAnchor.constraint(
                    greaterThanOrEqualTo: badge.heightAnchor
                ).isActive = true
                badge.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: 18
                ).isActive = true
                badge.setContentHuggingPriority(.required, for: .horizontal)
                badge.setContentHuggingPriority(.required, for: .vertical)
                badge.setContentCompressionResistancePriority(
                    .required, for: .horizontal
                )
                badge.setContentCompressionResistancePriority(
                    .required, for: .vertical
                )
                badge.isAccessibilityElement = true
                badge.accessibilityLabel = String(
                    localized: "\(count) charges"
                )
                return badge
            }
        }
    }
}

private final class CalendarBadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerCurve = .continuous
        layer.cornerRadius = bounds.height / 2
    }
}
#endif

struct UpcomingConfirmationPresentation: Identifiable {
    let subscription: Subscription
    let expectedOccurrence: ExpectedCharge

    var id: String {
        let occurrenceID = expectedOccurrence.id
        return "\(occurrenceID.subscriptionID.uuidString)-"
            + "\(occurrenceID.year)-\(occurrenceID.month)-"
            + "\(occurrenceID.day)"
    }
}

struct UpcomingTimelineRow: View {
    let item: UpcomingTimelineItem
    let billingTimeZoneIdentifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(
                systemName: item.kind == .expected
                    ? "calendar"
                    : "checkmark.circle"
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.serviceName)
                    .lineLimit(2)
                Text(statusTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedMoney(item.amount))
                    .lineLimit(2)
                Text(
                    formattedBillingDate(
                        item.date,
                        timeZoneIdentifier: billingTimeZoneIdentifier,
                        locale: .current
                    )
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.serviceName), \(statusAccessibilityText), "
                + "\(formattedMoney(item.amount)), "
                + formattedBillingDate(
                    item.date,
                    timeZoneIdentifier: billingTimeZoneIdentifier,
                    locale: .current
                )
        )
    }

    private var statusTitle: LocalizedStringKey {
        item.kind == .expected ? "Expected Charge" : "Confirmed Payment"
    }

    private var statusAccessibilityText: String {
        item.kind == .expected
            ? String(localized: "Expected Charge")
            : String(localized: "Confirmed Payment")
    }
}
