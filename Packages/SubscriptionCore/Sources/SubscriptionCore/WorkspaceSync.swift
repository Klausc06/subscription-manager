import Foundation
import Observation

extension SubscriptionWorkspace {
    public func refreshSyncStatus() async {
        syncStatus = await syncMonitor?.refreshStatus() ?? .localOnly
    }
    func markLocalChangesForSync() {
        switch syncStatus {
        case .current, .synchronizing:
            syncStatus = .synchronizing
        case .notLoaded, .localOnly, .signedOut, .requiresAttention:
            break
        }
        Task { [weak self] in
            await self?.reconcileCalendarProjection(locale: .current)
        }
    }
    public func refreshExchangeRates() async {
        exchangeRateRefreshGeneration &+= 1
        let refreshGeneration = exchangeRateRefreshGeneration
        let cachedState = try? exchangeRateCache?.loadState()
        guard let subscriptions = try? repository.listSubscriptions() else {
            exchangeRateStatus = .unavailable
            return
        }
        let requiredCurrencies = Set(
            subscriptions.flatMap { subscription in
                [subscription.originalAmount.currency]
                    + subscription.priceChanges.map(\.amount.currency)
                    + subscription.confirmedCharges.map(\.amount.currency)
            }
        )
            .union([currentPreferences.primaryCurrency])
        let requiredQuotes = requiredCurrencies.subtracting([.eur])
        let cacheIsComplete = cachedState?.snapshot.map {
            snapshotContainsRequiredCurrencies(
                $0,
                requiredCurrencies: requiredCurrencies
            )
        } ?? false
        if let cachedState,
           cacheIsComplete,
           calendar.isDate(
               cachedState.lastAttemptAt
                   ?? cachedState.snapshot?.fetchedAt
                   ?? .distantPast,
               inSameDayAs: now()
           )
        {
            exchangeRateStatus = cachedState.snapshot.map { snapshot in
                calendar.isDate(snapshot.fetchedAt, inSameDayAs: now())
                    ? .fresh(snapshot)
                    : .stale(snapshot)
            } ?? .unavailable
            return
        }

        let attemptKey = ExchangeRateAttemptKey(
            day: calendar.startOfDay(for: now()),
            quotes: requiredQuotes
        )
        if exchangeRateAttempts.contains(attemptKey) {
            return
        }

        guard let exchangeRateSource else {
            exchangeRateStatus = cacheIsComplete
                ? cachedState?.snapshot.map(ExchangeRateStatus.stale)
                    ?? .unavailable
                : .unavailable
            return
        }

        let attemptedAt = now()
        do {
            let snapshot = try await exchangeRateSource.fetchRates(
                base: .eur,
                quotes: requiredQuotes
            )
            guard refreshGeneration == exchangeRateRefreshGeneration else {
                return
            }
            guard snapshotContainsRequiredCurrencies(
                snapshot,
                requiredCurrencies: requiredCurrencies
            ) else {
                throw ExchangeRateRefreshError.incompleteSnapshot
            }
            let state = ExchangeRateCacheState(
                snapshot: snapshot,
                lastAttemptAt: attemptedAt
            )
            do {
                try exchangeRateCache?.saveState(state)
            } catch {
                exchangeRateAttempts.insert(attemptKey)
            }
            exchangeRateStatus = .fresh(snapshot)
        } catch is CancellationError {
            guard refreshGeneration == exchangeRateRefreshGeneration else {
                return
            }
            exchangeRateStatus = cacheIsComplete
                ? cachedState?.snapshot.map(ExchangeRateStatus.stale)
                    ?? .unavailable
                : .unavailable
        } catch {
            guard refreshGeneration == exchangeRateRefreshGeneration else {
                return
            }
            exchangeRateAttempts.insert(attemptKey)
            let state = ExchangeRateCacheState(
                snapshot: cachedState?.snapshot,
                lastAttemptAt: attemptedAt
            )
            try? exchangeRateCache?.saveState(state)
            exchangeRateStatus = cacheIsComplete
                ? cachedState?.snapshot.map(ExchangeRateStatus.stale)
                    ?? .unavailable
                : .unavailable
        }
    }
    func snapshotContainsRequiredCurrencies(
        _ snapshot: ExchangeRateSnapshot,
        requiredCurrencies: Set<Currency>
    ) -> Bool {
        requiredCurrencies.allSatisfy { currency in
            currency == snapshot.base || snapshot.rates[currency] != nil
        }
    }
}
