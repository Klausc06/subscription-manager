import Foundation
import Observation

public enum SubscriptionLibraryScope: Hashable, Sendable {
    case current
    case archived
}

public enum SubscriptionLibraryState: Equatable, Sendable {
    case loading(SubscriptionLibraryScope)
    case empty(SubscriptionLibraryScope)
    case loaded(SubscriptionLibraryScope, [SubscriptionSummary])
    case failed(SubscriptionLibraryScope)
}

public enum UpcomingTimelineState: Equatable, Sendable {
    case notLoaded
    case empty
    case loaded([UpcomingTimelineItem])
    case failed
}

public enum SubscriptionTableSort: String, CaseIterable, Codable, Sendable {
    case serviceName
    case plan
    case category
    case nextRenewal
    case amount
}

public struct SubscriptionTableQuery: Equatable, Sendable {
    public let searchText: String
    public let sort: SubscriptionTableSort
    public let ascending: Bool

    public init(
        searchText: String = "",
        sort: SubscriptionTableSort = .serviceName,
        ascending: Bool = true
    ) {
        self.searchText = searchText
        self.sort = sort
        self.ascending = ascending
    }

    public func apply(
        to summaries: [SubscriptionSummary],
        locale: Locale = .current
    ) -> [SubscriptionSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return summaries
            .filter { summary in
                guard !query.isEmpty else { return true }
                return [summary.serviceName, summary.plan, summary.category]
                    .contains {
                        $0.range(
                            of: query,
                            options: [.caseInsensitive, .diacriticInsensitive],
                            range: nil,
                            locale: locale
                        ) != nil
                    }
            }
            .sorted { lhs, rhs in
                switch (lhs.pinnedAt, rhs.pinnedAt) {
                case let (left?, right?):
                    if left != right {
                        return left > right
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                let order = comparison(of: lhs, and: rhs, locale: locale)
                if order == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return ascending
                    ? order == .orderedAscending
                    : order == .orderedDescending
            }
    }

    private func comparison(
        of lhs: SubscriptionSummary,
        and rhs: SubscriptionSummary,
        locale: Locale
    ) -> ComparisonResult {
        switch sort {
        case .serviceName:
            return lhs.serviceName.localizedCompare(rhs.serviceName)
        case .plan:
            return lhs.plan.localizedCompare(rhs.plan)
        case .category:
            return lhs.category.localizedCompare(rhs.category)
        case .nextRenewal:
            return lhs.confirmedNextRenewal.compare(rhs.confirmedNextRenewal)
        case .amount:
            let currencyOrder = lhs.amount.currency.rawValue
                .localizedCompare(rhs.amount.currency.rawValue)
            if currencyOrder != .orderedSame {
                return currencyOrder
            } else if lhs.amount.minorUnits == rhs.amount.minorUnits {
                return .orderedSame
            } else {
                return lhs.amount.minorUnits < rhs.amount.minorUnits
                    ? .orderedAscending
                    : .orderedDescending
            }
        }
    }
}

public enum SubscriptionDetailState: Equatable, Sendable {
    case notLoaded
    case loaded(
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    )
    case notFound
    case failed
}
