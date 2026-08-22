import Foundation
import Observation

extension SubscriptionWorkspace {
    public func createSubscription(
        _ input: SubscriptionCreationInput
    ) -> SubscriptionCreationResult {
        createSubscription(input) { id in
            ServiceIdentity(rawValue: "manual:\(id.uuidString)")
        }
    }
    public func loadCatalog(locale: Locale) {
        catalogSearchQuery = ""
        catalogCategoryID = nil
        guard let catalogRepository else {
            catalogState = .failed
            return
        }
        do {
            catalogSnapshot = try catalogRepository.loadSnapshot()
            catalogLocale = locale
            catalogDiagnostics = CatalogDiagnostics(
                source: catalogRepository.catalogSource,
                version: catalogSnapshot?.catalogVersion ?? 0,
                refreshStatus: .idle
            )
            refreshCatalogState()
        } catch {
            catalogSnapshot = nil
            catalogState = .failed
        }
    }
    public func catalogMatches(
        query: String,
        locale: Locale
    ) -> [CatalogPreset] {
        let snapshot = catalogSnapshot ?? (try? catalogRepository?.loadSnapshot())
        return snapshot?.search(query: query, locale: locale) ?? []
    }
    public func catalogOfferAdjustment(
        for subscription: Subscription
    ) -> CatalogOfferAdjustment? {
        guard let snapshot = matchingCatalogSnapshot() else { return nil }
        return CatalogOfferMatcher().adjustment(
            for: subscription,
            in: snapshot,
            onBillingDay: subscription.confirmedNextRenewal
        )
    }
    public func reconcileCatalogAssociations(
        locale: Locale
    ) -> CatalogAssociationReconciliationSummary {
        catalogReconciliationError = nil
        catalogLocale = locale
        guard let snapshot = matchingCatalogSnapshot() else {
            catalogReconciliationError = .catalogUnavailable
            return CatalogAssociationReconciliationSummary(
                commandError: .catalogUnavailable
            )
        }

        let subscriptions: [Subscription]
        do {
            subscriptions = try repository.listSubscriptions()
        } catch {
            catalogReconciliationError = .persistenceFailed
            return CatalogAssociationReconciliationSummary(
                commandError: .persistenceFailed
            )
        }

        var normalizedIDs: [UUID] = []
        var unchangedIDs: [UUID] = []
        var ambiguousIDs: [UUID] = []
        var failedIDs: [UUID] = []
        var normalizedByID: [UUID: Subscription] = [:]
        for subscription in subscriptions {
            switch CatalogOfferMatcher().match(
                subscription: subscription,
                in: snapshot,
                onBillingDay: subscription.confirmedNextRenewal
            ) {
            case .none:
                // Reuse the per-subscription reconcile contract so a stale
                // `catalog:` identity demotes to `manual:<uuid>` exactly as
                // the create and edit paths do.
                let reconciled = reconciledCatalogAssociation(
                    for: subscription,
                    locale: locale,
                    snapshot: snapshot
                )
                guard reconciled != subscription else {
                    unchangedIDs.append(subscription.id)
                    continue
                }
                do {
                    try repository.updateSubscription(reconciled)
                    normalizedIDs.append(subscription.id)
                    normalizedByID[subscription.id] = reconciled
                } catch {
                    failedIDs.append(subscription.id)
                    catalogReconciliationError = .persistenceFailed
                }
            case .ambiguous:
                ambiguousIDs.append(subscription.id)
            case .unique(let candidate):
                let normalized = normalizedCatalogAssociation(
                    for: subscription,
                    candidate: candidate,
                    locale: locale
                )
                guard normalized != subscription else {
                    unchangedIDs.append(subscription.id)
                    continue
                }
                do {
                    try repository.updateSubscription(normalized)
                    normalizedIDs.append(subscription.id)
                    normalizedByID[subscription.id] = normalized
                } catch {
                    failedIDs.append(subscription.id)
                    catalogReconciliationError = .persistenceFailed
                }
            }
        }

        if !normalizedIDs.isEmpty {
            markLocalChangesForSync()
            if case .loaded(let selected, _, _) = detailState,
               let normalized = normalizedByID[selected.id]
            {
                detailState = makeDetail(normalized)
            }
            loadLibrary(scope: carriedLibraryScope)
            reloadRequestedConsumers()
        }

        return CatalogAssociationReconciliationSummary(
            normalizedIDs: normalizedIDs,
            unchangedIDs: unchangedIDs,
            ambiguousIDs: ambiguousIDs,
            failedIDs: failedIDs,
            commandError: catalogReconciliationError
        )
    }
    public func clearCatalogReconciliationError() {
        catalogReconciliationError = nil
    }
    public func refreshCatalog() async {
        guard let catalogRepository,
              let catalogUpdateSource,
              let catalogCache
        else {
            return
        }
        catalogRefreshGeneration &+= 1
        let refreshGeneration = catalogRefreshGeneration

        do {
            let persistedSnapshot = try catalogSnapshot == nil
                ? catalogRepository.loadSnapshot()
                : nil
            let data = try await catalogUpdateSource.fetchCatalogData()
            let candidate = try JSONDecoder().decode(
                CatalogSnapshot.self,
                from: data
            )
            let latestActiveSnapshot: CatalogSnapshot
            if let catalogSnapshot {
                latestActiveSnapshot = catalogSnapshot
            } else if let persistedSnapshot {
                latestActiveSnapshot = persistedSnapshot
            } else {
                latestActiveSnapshot = try catalogRepository.loadSnapshot()
            }
            guard candidate.catalogVersion > latestActiveSnapshot.catalogVersion else {
                catalogDiagnostics = CatalogDiagnostics(
                    source: catalogDiagnostics?.source
                        ?? catalogRepository.catalogSource,
                    version: latestActiveSnapshot.catalogVersion,
                    refreshStatus: .alreadyCurrent
                )
                return
            }

            try catalogCache.storeCatalogData(data)
            catalogSnapshot = candidate
            catalogDiagnostics = CatalogDiagnostics(
                source: .cached,
                version: candidate.catalogVersion,
                refreshStatus: .updated
            )
            refreshCatalogState()
        } catch {
            guard refreshGeneration == catalogRefreshGeneration else {
                return
            }
            if let catalogSnapshot {
                catalogDiagnostics = CatalogDiagnostics(
                    source: catalogDiagnostics?.source
                        ?? catalogRepository.catalogSource,
                    version: catalogSnapshot.catalogVersion,
                    refreshStatus: .failed
                )
            }
        }
    }
    public func setCatalogSearchQuery(_ query: String) {
        catalogSearchQuery = query
        refreshCatalogState()
    }
    public func setCatalogCategory(_ categoryID: String?) {
        catalogCategoryID = categoryID
        refreshCatalogState()
    }
    func createSubscription(
        _ input: SubscriptionCreationInput,
        serviceIdentity: (UUID) -> ServiceIdentity
    ) -> SubscriptionCreationResult {
        creationValidationErrors = validate(input)
        guard creationValidationErrors.isEmpty,
              let originalAmount = input.originalAmount
        else {
            return .validationFailed
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        let id = identifierGenerator()
        let confirmedNextRenewal: Date
        switch input.initialStatus {
        case .active:
            guard let timeZone = TimeZone(
                identifier: input.billingTimeZoneIdentifier
            ),
            let resolvedRenewal = BillingDateResolver().nextRenewal(
                afterStart: input.startDate,
                interval: input.billingInterval,
                asOf: now(),
                timeZone: timeZone
            ) else {
                creationValidationErrors[.confirmedNextRenewal] = .required
                return .validationFailed
            }
            confirmedNextRenewal = resolvedRenewal
        case .trial:
            confirmedNextRenewal = input.confirmedNextRenewal
        }
        let lifecycle: SubscriptionLifecycle =
            input.initialStatus == .trial
                ? .trial(firstPaidChargeAt: confirmedNextRenewal)
                : .active
        let renewalAnchor = input.initialStatus == .trial
            ? confirmedNextRenewal
            : input.startDate
        let subscription = Subscription(
            id: id,
            serviceIdentity: serviceIdentity(id),
            serviceName: input.serviceName.trimmingCharacters(in: whitespace),
            plan: input.plan.trimmingCharacters(in: whitespace),
            category: input.category.trimmingCharacters(in: whitespace),
            originalAmount: originalAmount,
            billingSchedule: FixedBillingSchedule(
                interval: input.billingInterval,
                renewalAnchor: renewalAnchor,
                timeZoneIdentifier: input.billingTimeZoneIdentifier
            ),
            startDate: input.startDate,
            confirmedNextRenewal: confirmedNextRenewal,
            managementURL: input.managementURL,
            notes: input.notes,
            lifecycle: lifecycle,
            isArchived: false
        )
        let subscriptionToPersist = reconciledCatalogAssociation(
            for: subscription,
            locale: catalogLocale
        )

        do {
            try repository.createSubscription(subscriptionToPersist)
            markLocalChangesForSync()
            detailState = makeDetail(subscriptionToPersist)
            loadLibrary()
            reloadRequestedConsumers()
            return .created(subscriptionToPersist)
        } catch {
            detailState = .failed
            return .persistenceFailed
        }
    }
    public func createMonthlySubscription(
        _ input: SubscriptionCreationInput
    ) {
        createSubscription(input)
    }
    func matchingCatalogSnapshot() -> CatalogSnapshot? {
        if let catalogSnapshot {
            return catalogSnapshot
        }
        return try? catalogRepository?.loadSnapshot()
    }
    func reconciledCatalogAssociation(
        for subscription: Subscription,
        locale: Locale,
        snapshot providedSnapshot: CatalogSnapshot? = nil
    ) -> Subscription {
        guard let snapshot = providedSnapshot ?? matchingCatalogSnapshot()
        else {
            return subscription
        }
        let matcher = CatalogOfferMatcher()
        let serviceNameMatch = matcher.matchesCatalogServiceName(
            subscription: subscription,
            in: snapshot
        )
        let hasCatalogIdentity = subscription.serviceIdentity.rawValue
            .hasPrefix("catalog:")
        guard !hasCatalogIdentity || serviceNameMatch != nil
        else {
            return subscription
        }
        switch matcher.match(
            subscription: subscription,
            in: snapshot,
            onBillingDay: subscription.confirmedNextRenewal
        ) {
        case .none:
            guard hasCatalogIdentity,
                  serviceNameMatch == false
            else {
                return subscription
            }
            return subscription.replacingCatalogAssociation(
                serviceIdentity: ServiceIdentity(
                    rawValue: "manual:\(subscription.id.uuidString)"
                ),
                serviceName: subscription.serviceName,
                plan: subscription.plan,
                category: subscription.category,
                managementURL: subscription.managementURL
            )
        case .ambiguous:
            return subscription
        case .unique(let candidate):
            return normalizedCatalogAssociation(
                for: subscription,
                candidate: candidate,
                locale: locale
            )
        }
    }
    func normalizedCatalogAssociation(
        for subscription: Subscription,
        candidate: CatalogOfferMatchCandidate,
        locale: Locale
    ) -> Subscription {
        subscription.replacingCatalogAssociation(
            serviceIdentity: ServiceIdentity(
                rawValue: "catalog:\(candidate.preset.id)"
            ),
            serviceName: candidate.preset.serviceName.value(for: locale),
            plan: candidate.offer.planName.value(for: locale),
            category: candidate.preset.category.value(for: locale),
            managementURL: candidate.preset.managementURL
        )
    }
    func refreshCatalogState() {
        guard let catalogSnapshot else {
            return
        }
        let presets = catalogSnapshot.search(
            query: catalogSearchQuery,
            locale: catalogLocale
        )
        .filter { preset in
            guard let catalogCategoryID else { return true }
            return preset.category.en.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en")
            ) == catalogCategoryID
        }
        catalogState = .loaded(
            categories: catalogSnapshot.categories(locale: catalogLocale),
            presets: presets
        )
    }
}
