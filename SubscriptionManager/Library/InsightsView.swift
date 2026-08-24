import SubscriptionCore
import SwiftUI
import Charts

struct InsightsView: View {
    let workspace: SubscriptionWorkspace
    @State private var mode: SpendingReportMode = .expected
    @State private var isRefreshingRates = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Total Mode", selection: $mode) {
                    Text("Expected").tag(SpendingReportMode.expected)
                    Text("Confirmed").tag(SpendingReportMode.confirmed)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Total Mode")
                .accessibilityIdentifier("insights.mode")
                .listRowInsets(
                    EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if isRefreshingRates, !isInsightsLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Updating exchange rates…")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("insights.rates-refreshing")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                switch workspace.insightsState {
                case .notLoaded:
                    ProgressView("Loading Insights")
                case .unavailable:
                    ContentUnavailableView(
                        "Insights Unavailable",
                        systemImage: "chart.bar.xaxis",
                        description: Text(
                            "Exchange rates are unavailable. Original subscription values are unchanged."
                        )
                    )
                    .accessibilityIdentifier("insights.unavailable")
                case .available(let insights):
                    rateStatus
                    Section("Selected Range") {
                        LabeledContent(
                            "Total",
                            value: formattedMoney(insights.selectedRangeTotal)
                        )
                        LabeledContent(
                            "Annualized",
                            value: formattedMoney(insights.annualizedTotal)
                        )
                    }
                    if !insights.categoryTotals.isEmpty {
                        Section("Spending by Category") {
                            Chart(insights.categoryTotals) { total in
                                BarMark(
                                    x: .value("Amount", total.amount.minorUnits),
                                    y: .value("Category", total.category)
                                )
                                .accessibilityLabel(
                                    "\(total.category): \(formattedMoney(total.amount))"
                                )
                            }
                            .frame(minHeight: 180)
                            .accessibilityIdentifier("insights.category-chart")
                        }
                        Section("Category Totals") {
                            ForEach(insights.categoryTotals) { total in
                                LabeledContent(
                                    total.category,
                                    value: formattedMoney(total.amount)
                                )
                            }
                        }
                        .accessibilityIdentifier("insights.text-summary")
                    }
                }
            }
            .navigationTitle("Insights")
        }
        .task(id: mode) {
            await reloadInsights(for: mode)
        }
    }

    private var isInsightsLoading: Bool {
        if case .notLoaded = workspace.insightsState { return true }
        return false
    }

    /// Renders the mode's totals from whatever snapshot is already available
    /// before awaiting the network, so switching Expected/Confirmed never
    /// blanks out or freezes on stale figures.
    private func reloadInsights(for selectedMode: SpendingReportMode) async {
        loadInsights(for: selectedMode)
        isRefreshingRates = true
        await workspace.refreshExchangeRates()
        isRefreshingRates = false
        loadInsights(for: selectedMode)
    }

    private func loadInsights(for selectedMode: SpendingReportMode) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let rangeStart = selectedMode == .expected
            ? today
            : calendar.date(
                byAdding: .day,
                value: -29,
                to: today
            ) ?? today
        let finalDay = selectedMode == .expected
            ? calendar.date(
                byAdding: .day,
                value: 29,
                to: today
            ) ?? today
            : today
        let rangeEnd = calendar.dateInterval(of: .day, for: finalDay).flatMap {
            calendar.date(
                byAdding: .nanosecond,
                value: -1,
                to: $0.end
            )
        } ?? finalDay
        workspace.loadInsights(
            mode: selectedMode,
            from: rangeStart,
            through: rangeEnd
        )
    }

    @ViewBuilder
    private var rateStatus: some View {
        switch workspace.exchangeRateStatus {
        case .fresh(let snapshot):
            rateStatusContainer(
                Text(
                    "Rates updated \(snapshot.providerDate, format: .dateTime.year().month().day())"
                )
            )
        case .stale(let snapshot):
            rateStatusContainer(
                Text(
                    "Using cached rates from \(snapshot.providerDate, format: .dateTime.year().month().day())"
                )
            )
        case .notLoaded, .unavailable:
            EmptyView()
        }
    }

    private func rateStatusContainer(_ content: Text) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.vertical, 4)
            .accessibilityIdentifier("insights.rate-status")
    }
}
