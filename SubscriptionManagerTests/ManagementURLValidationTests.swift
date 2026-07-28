import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("Subscription lifecycle localization")
struct SubscriptionLifecycleLocalizationTests {
    @Test(
        "Subscription statuses use one production localization mapping",
        arguments: [
            (SubscriptionStatus.active, "Active"),
            (.trial, "Trial"),
            (.cancelledWithAccess, "Cancelled with Access"),
            (.expired, "Expired"),
        ]
    )
    func subscriptionStatusesUseProductionLocalizationMapping(
        status: SubscriptionStatus,
        expected: String
    ) {
        #expect(subscriptionStatusLocalizationKey(status) == expected)
    }

    @Test(
        "Lifecycle action errors use dedicated localization keys",
        arguments: [
            (
                SubscriptionLifecycleActionError
                    .invalidLifecycleTransition,
                "This action isn’t available for the subscription’s current status."
            ),
            (
                .cancellationDateInFuture,
                "The cancellation date cannot be in the future."
            ),
            (
                .accessEndsBeforeCancellation,
                "Access Until cannot be before the cancellation date."
            ),
            (
                .nextRenewalInPast,
                "The next renewal cannot be in the past."
            ),
            (
                .persistenceFailed,
                "Couldn’t save lifecycle changes. Try again."
            ),
        ]
    )
    func lifecycleActionErrorsUseDedicatedLocalizationKeys(
        error: SubscriptionLifecycleActionError,
        expected: String
    ) {
        #expect(lifecycleActionErrorTextKey(error) == expected)
    }
}

@Suite("Management URL validation")
struct ManagementURLValidationTests {
    @Test("Renewal anchor validation identifies the anchor field")
    func renewalAnchorValidationIdentifiesAnchorField() {
        #expect(
            validationTextKey(
                for: .beforeStartDate,
                field: .renewalAnchor
            ) == "The renewal anchor cannot be before the start date."
        )
        #expect(
            validationTextKey(
                for: .beforeStartDate,
                field: .confirmedNextRenewal
            ) == "The next renewal cannot be before the start date."
        )
    }

    @Test(
        "Only absolute HTTP and HTTPS management URLs with a host are accepted",
        arguments: [
            "example.com",
            "not a url",
            "ftp://example.com/account",
            "https:///account",
            "http:/account",
        ]
    )
    func rejectsInvalidManagementURLs(value: String) {
        #expect(ManagementURLParser.parse(value) == .invalid)
    }

    @Test(
        "HTTP and HTTPS management URLs are accepted",
        arguments: [
            "https://example.com/account",
            "http://sub.example.com:8080/manage?plan=1",
        ]
    )
    func acceptsValidManagementURLs(value: String) {
        guard case .valid(let url) = ManagementURLParser.parse(value) else {
            Issue.record("Expected an accepted management URL")
            return
        }

        #expect(url.absoluteString == value)
    }

    @Test("Whitespace is trimmed and an empty value stays optional")
    func trimsWhitespaceAndAllowsEmptyValues() {
        #expect(
            ManagementURLParser.parse(
                " \n https://example.com/manage \t"
            ) == .valid(URL(string: "https://example.com/manage")!)
        )
        #expect(ManagementURLParser.parse(" \n\t ") == .empty)
    }
}
