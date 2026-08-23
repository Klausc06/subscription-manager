import Foundation
import Observation

extension SubscriptionWorkspace {
    @discardableResult
    public func editSubscription(
        id: UUID,
        input: SubscriptionEditInput,
        forecastThrough: Date? = nil
    ) -> Bool {
        editingValidationErrors = [:]
        let scope = carriedLibraryScope

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return false
            }
            editingValidationErrors = validate(
                input,
                lifecycle: existing.lifecycle
            )
            guard editingValidationErrors.isEmpty else {
                return false
            }
            let whitespace = CharacterSet.whitespacesAndNewlines
            guard let timeZone = TimeZone(
                identifier: input.billingSchedule.timeZoneIdentifier
            ),
            let normalizedStartDate = normalizedBillingLocalNoon(
                input.startDate,
                timeZone: timeZone
            ) else {
                editingValidationErrors[.billingSchedule] = .required
                return false
            }
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            guard !existing.priceChanges.contains(where: {
                localCalendar.startOfDay(for: $0.effectiveDate)
                    < localCalendar.startOfDay(for: normalizedStartDate)
            }) else {
                editingValidationErrors[.billingSchedule] = .beforeStartDate
                return false
            }
            let confirmedNextRenewal: Date
            let renewalAnchor: Date
            switch existing.lifecycle {
            case .active:
                guard let resolvedRenewal = BillingDateResolver().nextRenewal(
                    afterStart: input.startDate,
                    interval: input.billingSchedule.interval,
                    asOf: now(),
                    timeZone: timeZone
                ),
                localCalendar.isDate(
                    resolvedRenewal,
                    inSameDayAs: input.confirmedNextRenewal
                ),
                let normalizedRenewal = normalizedBillingLocalNoon(
                    resolvedRenewal,
                    timeZone: timeZone
                ) else {
                    editingValidationErrors[.confirmedNextRenewal] = .required
                    return false
                }
                confirmedNextRenewal = normalizedRenewal
                renewalAnchor = normalizedStartDate
            case .trial, .cancelled:
                guard let normalizedRenewal = normalizedBillingLocalNoon(
                    input.confirmedNextRenewal,
                    timeZone: timeZone
                ) else {
                    editingValidationErrors[.confirmedNextRenewal] = .required
                    return false
                }
                confirmedNextRenewal = normalizedRenewal
                renewalAnchor = switch existing.lifecycle {
                case .trial:
                    normalizedRenewal
                case .cancelled:
                    existing.billingSchedule.renewalAnchor
                case .active:
                    normalizedStartDate
                }
            }
            let billingSchedule = FixedBillingSchedule(
                interval: input.billingSchedule.interval,
                renewalAnchor: renewalAnchor,
                timeZoneIdentifier:
                    input.billingSchedule.timeZoneIdentifier
            )
            let lifecycle = switch existing.lifecycle {
            case .trial:
                SubscriptionLifecycle.trial(
                    firstPaidChargeAt: confirmedNextRenewal
                )
            case .active, .cancelled:
                existing.lifecycle
            }
            let edited = Subscription(
                id: existing.id,
                serviceIdentity: existing.serviceIdentity,
                serviceName: input.serviceName.trimmingCharacters(
                    in: whitespace
                ),
                plan: input.plan.trimmingCharacters(in: whitespace),
                category: input.category.trimmingCharacters(in: whitespace),
                originalAmount: existing.originalAmount,
                billingSchedule: billingSchedule,
                startDate: normalizedStartDate,
                confirmedNextRenewal: confirmedNextRenewal,
                managementURL: input.managementURL,
                notes: input.notes,
                confirmedCharges: existing.confirmedCharges,
                priceChanges: editedPriceChanges(
                    for: existing,
                    amount: input.amount,
                    confirmedNextRenewal: confirmedNextRenewal,
                    calendar: localCalendar
                ),
                lifecycle: lifecycle,
                isArchived: existing.isArchived,
                pinnedAt: existing.pinnedAt
            )
            let editedToPersist = reconciledCatalogAssociation(
                for: edited,
                locale: catalogLocale
            )
            try repository.updateSubscription(editedToPersist)
            markLocalChangesForSync()
            detailState = makeDetail(editedToPersist)
            loadLibrary(scope: scope)
            if let forecastThrough {
                expectedChargesRequest = ExpectedChargesRequest(
                    subscriptionID: id,
                    horizon: forecastThrough,
                    maximumCount: .max
                )
            }
            reloadRequestedConsumers()
            return true
        } catch {
            return false
        }
    }
    public func recordCancellation(
        id: UUID,
        cancelledAt: Date,
        accessUntil: Date
    ) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }
            switch existing.lifecycle {
            case .trial, .active:
                break
            case .cancelled:
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            let cancellationDay = localCalendar.startOfDay(for: cancelledAt)
            let accessUntilDay = localCalendar.startOfDay(for: accessUntil)
            let today = localCalendar.startOfDay(for: now())
            guard cancellationDay <= today else {
                lifecycleActionError = .cancellationDateInFuture
                return
            }
            guard accessUntilDay >= cancellationDay else {
                lifecycleActionError = .accessEndsBeforeCancellation
                return
            }
            guard let normalizedCancellation = normalizedBillingLocalNoon(
                cancelledAt,
                timeZone: timeZone
            ),
            let normalizedAccessUntil = normalizedBillingLocalNoon(
                accessUntil,
                timeZone: timeZone
            ) else {
                lifecycleActionError = .persistenceFailed
                return
            }

            let updated = existing.replacingLifecycleFacts(
                lifecycle: .cancelled(
                    cancelledAt: normalizedCancellation,
                    accessUntil: normalizedAccessUntil
                )
            )
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }
    public func confirmCharge(
        id: UUID,
        scheduledDate: Date,
        chargedDate: Date,
        amount: Money
    ) {
        paymentHistoryActionError = nil
        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                paymentHistoryActionError = .archivedSubscription
                return
            }
            switch existing.lifecycle {
            case .trial, .active:
                break
            case .cancelled:
                paymentHistoryActionError = .invalidScheduledOccurrence
                return
            }

            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            let today = localCalendar.startOfDay(for: now())
            guard amount.minorUnits > 0 else {
                paymentHistoryActionError = .mustBePositive
                return
            }
            guard let normalizedScheduledDate = normalizedBillingLocalNoon(
                      scheduledDate,
                      timeZone: timeZone
                  ),
                  let normalizedChargedDate = normalizedBillingLocalNoon(
                      chargedDate,
                      timeZone: timeZone
                  ),
                  localCalendar.startOfDay(for: normalizedScheduledDate)
                    <= today
            else {
                paymentHistoryActionError = .scheduledDateInFuture
                return
            }
            guard localCalendar.startOfDay(for: normalizedChargedDate)
                <= today
            else {
                paymentHistoryActionError = .chargedDateInFuture
                return
            }
            guard isScheduledOccurrence(
                normalizedScheduledDate,
                for: existing,
                calendar: localCalendar
            ) else {
                paymentHistoryActionError = .invalidScheduledOccurrence
                return
            }

            let components = localCalendar.dateComponents(
                [.year, .month, .day],
                from: normalizedScheduledDate
            )
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day
            else {
                return
            }
            let sourceScheduledChargeID = ScheduledChargeID(
                subscriptionID: existing.id,
                year: year,
                month: month,
                day: day
            )
            guard !existing.confirmedCharges.contains(where: {
                $0.sourceScheduledChargeID == sourceScheduledChargeID
            }) else {
                detailState = makeDetail(existing)
                reloadRequestedConsumers()
                return
            }

            let updated = existing.replacingPaymentHistory(
                confirmedCharges: existing.confirmedCharges + [
                    ConfirmedCharge(
                        id: identifierGenerator(),
                        chargedDate: normalizedChargedDate,
                        amount: amount,
                        sourceScheduledChargeID: sourceScheduledChargeID
                    )
                ]
            )
            try repository.updateSubscription(updated)
            markLocalChangesForSync()
            detailState = makeDetail(updated)
            loadLibrary()
            reloadRequestedConsumers()
        } catch {
            paymentHistoryActionError = .persistenceFailed
        }
    }
    public func recordPriceChange(
        id: UUID,
        effectiveDate: Date,
        amount: Money
    ) {
        paymentHistoryActionError = nil
        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                paymentHistoryActionError = .archivedSubscription
                return
            }
            guard amount.minorUnits > 0 else {
                paymentHistoryActionError = .mustBePositive
                return
            }
            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            guard let normalizedEffectiveDate = normalizedBillingLocalNoon(
                effectiveDate,
                timeZone: timeZone
            ) else {
                paymentHistoryActionError = .persistenceFailed
                return
            }
            guard normalizedEffectiveDate >= localCalendar.startOfDay(
                for: existing.startDate
            ) else {
                paymentHistoryActionError = .effectiveDateBeforeStart
                return
            }
            guard !existing.priceChanges.contains(where: {
                localCalendar.isDate(
                    $0.effectiveDate,
                    inSameDayAs: normalizedEffectiveDate
                )
            }) else {
                paymentHistoryActionError = .duplicatePriceChangeDay
                return
            }
            let updated = existing.replacingPaymentHistory(
                priceChanges: existing.priceChanges + [
                    PriceChange(
                        id: identifierGenerator(),
                        effectiveDate: normalizedEffectiveDate,
                        amount: amount
                    )
                ]
            )
            try repository.updateSubscription(updated)
            markLocalChangesForSync()
            detailState = makeDetail(updated)
            loadLibrary()
            reloadRequestedConsumers()
        } catch {
            paymentHistoryActionError = .persistenceFailed
        }
    }
    public func reactivate(id: UUID, nextRenewal: Date) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived,
                  case .cancelled = existing.lifecycle
            else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let timeZone = billingTimeZone(for: existing)
            let localCalendar = billingLocalCalendar(timeZone: timeZone)
            let renewalDay = localCalendar.startOfDay(for: nextRenewal)
            let today = localCalendar.startOfDay(for: now())
            guard renewalDay > today else {
                lifecycleActionError = .nextRenewalInPast
                return
            }
            guard let normalizedRenewal = normalizedBillingLocalNoon(
                nextRenewal,
                timeZone: timeZone
            ),
            let startDate = BillingDateResolver().previousCycleStart(
                before: normalizedRenewal,
                interval: existing.billingSchedule.interval,
                timeZone: timeZone
            ) else {
                lifecycleActionError = .persistenceFailed
                return
            }

            let updated = existing.replacingLifecycleFacts(
                lifecycle: .active,
                billingSchedule: FixedBillingSchedule(
                    interval: existing.billingSchedule.interval,
                    renewalAnchor: startDate,
                    timeZoneIdentifier:
                        existing.billingSchedule.timeZoneIdentifier
                ),
                startDate: startDate,
                confirmedNextRenewal: normalizedRenewal
            )
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }
    public func setPinned(id: UUID, pinned: Bool) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }
            guard (existing.pinnedAt != nil) != pinned else {
                return
            }

            let updated = existing.replacingPinnedAt(
                pinned ? now() : nil
            )
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }
    public func archive(id: UUID) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard !existing.isArchived else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let updated = existing.replacingLifecycleFacts(isArchived: true)
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }
    public func restore(id: UUID) {
        lifecycleActionError = nil

        do {
            guard let existing = try repository.subscription(id: id) else {
                detailState = .notFound
                return
            }
            guard existing.isArchived else {
                lifecycleActionError = .invalidLifecycleTransition
                return
            }

            let updated = existing.replacingLifecycleFacts(isArchived: false)
            try repository.updateSubscription(updated)
            finishLifecycleUpdate(updated)
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }
    public func deletePermanently(id: UUID) {
        lifecycleActionError = nil

        do {
            guard try repository.subscription(id: id) != nil else {
                detailState = .notFound
                return
            }

            let scope = carriedLibraryScope
            let clearsExpectedCharges =
                expectedChargesRequest?.subscriptionID == id
            let refreshedExpectedCharges: [ExpectedCharge]? =
                clearsExpectedCharges ? nil : expectedCharges
            try repository.deleteSubscription(id: id)
            markLocalChangesForSync()

            detailState = .notFound
            paymentHistory = []
            expectedCharges = refreshedExpectedCharges
            if clearsExpectedCharges {
                expectedChargesRequest = nil
            }
            loadLibrary(scope: scope)
            reloadRequestedConsumers()
        } catch {
            lifecycleActionError = .persistenceFailed
        }
    }
    public func clearLifecycleActionError() {
        lifecycleActionError = nil
    }
}
