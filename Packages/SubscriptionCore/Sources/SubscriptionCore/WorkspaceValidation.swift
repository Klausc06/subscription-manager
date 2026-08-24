import Foundation
import Observation

extension SubscriptionWorkspace {
    func validate(
        _ input: SubscriptionCreationInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if let originalAmount = input.originalAmount {
            if originalAmount.minorUnits <= 0 {
                errors[.originalAmount] = .mustBePositive
            }
        } else {
            errors[.originalAmount] = .required
        }
        if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
            errors[.billingSchedule] = .required
        }
        if input.initialStatus == .trial {
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        }
        if !input.billingInterval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingTimeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }
    func validate(
        _ input: SubscriptionEditInput,
        lifecycle: SubscriptionLifecycle
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.amount.minorUnits <= 0 {
            errors[.originalAmount] = .mustBePositive
        }
        switch lifecycle {
        case .active:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
                errors[.billingSchedule] = .required
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            }
        case .trial:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
                errors[.billingSchedule] = .required
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        case .cancelled:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite
                || !input.billingSchedule.renewalAnchor
                    .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.billingSchedule] = .required
            } else if input.billingSchedule.renewalAnchor < input.startDate {
                errors[.renewalAnchor] = .beforeStartDate
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        }
        if !input.billingSchedule.interval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingSchedule.timeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }
    func editedPriceChanges(
        for existing: Subscription,
        amount: Money,
        confirmedNextRenewal: Date,
        calendar: Calendar
    ) -> [PriceChange] {
        let currentAmount = existing.amount(
            onBillingDay: confirmedNextRenewal
        )
        guard amount != currentAmount else {
            return existing.priceChanges
        }

        let sameDayWinnerIndex = existing.priceChanges.indices
            .filter {
                calendar.isDate(
                    existing.priceChanges[$0].effectiveDate,
                    inSameDayAs: confirmedNextRenewal
                )
            }
            .max {
                existing.priceChanges[$0].id.uuidString
                    < existing.priceChanges[$1].id.uuidString
            }

        if let index = sameDayWinnerIndex {
            var corrected = existing.priceChanges
            let existingChange = corrected[index]
            corrected[index] = PriceChange(
                id: existingChange.id,
                effectiveDate: confirmedNextRenewal,
                amount: amount
            )
            return corrected
        }

        return existing.priceChanges + [
            PriceChange(
                id: identifierGenerator(),
                effectiveDate: confirmedNextRenewal,
                amount: amount
            ),
        ]
    }
}
