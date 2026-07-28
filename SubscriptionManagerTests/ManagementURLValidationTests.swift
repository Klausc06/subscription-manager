import Foundation
import Testing
@testable import SubscriptionManager

@Suite("Management URL validation")
struct ManagementURLValidationTests {
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
