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
            return order(lhs.serviceName, rhs.serviceName, locale: locale)
        case .plan:
            return order(lhs.plan, rhs.plan, locale: locale)
        case .category:
            return order(lhs.category, rhs.category, locale: locale)
        case .nextRenewal:
            return lhs.confirmedNextRenewal.compare(rhs.confirmedNextRenewal)
        case .amount:
            let currencyOrder = order(
                lhs.amount.currency.rawValue,
                rhs.amount.currency.rawValue,
                locale: locale
            )
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

    /// Orders two user-facing strings in the caller's locale.
    ///
    /// `localizedCompare` is defined as an option-free comparison in the
    /// current locale, so for the existing call sites that take the default
    /// `.current` locale this is equivalent and their ordering does not
    /// change. It also lets a surface that carries its own locale sort in
    /// that locale instead.
    ///
    /// `MacLibraryView` previously sorted with
    /// `[.caseInsensitive, .diacriticInsensitive]`. Folding its table query
    /// into this single implementation moves it to the locale-sensitive
    /// default ordering, which changes two things. Two rows differing only by
    /// case or diacritic are no longer `.orderedSame`, so they stop falling
    /// through to the uuid tiebreak and take an order of their own. And in a
    /// locale that collates a diacritic apart from its base letter, such as
    /// `sv_SE` sorting `Ä` after `Z`, those rows move a long way. Under the
    /// en_US default `Ä` and `A` still share a primary weight, so `Äpple`
    /// stays adjacent to `Apple` there. That is the behavior change approved
    /// in issue #118 under ADR-0001, not a regression.
    ///
    /// The asymmetry with filtering is deliberate: `apply(to:locale:)` still
    /// matches search text with `[.caseInsensitive, .diacriticInsensitive]`,
    /// so search ignores diacritics while sorting respects them.
    private func order(
        _ lhs: String,
        _ rhs: String,
        locale: Locale
    ) -> ComparisonResult {
        lhs.compare(rhs, options: [], range: nil, locale: locale)
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
