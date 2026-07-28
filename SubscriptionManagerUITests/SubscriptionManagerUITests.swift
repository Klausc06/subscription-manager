import XCTest

@MainActor
final class SubscriptionManagerUITests: XCTestCase {
    func testFreshLaunchShowsEnglishEmptyLibrary() {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertTrue(
            app.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["No Subscriptions Yet"].exists)
    }

    func testFreshLaunchShowsSimplifiedChineseEmptyLibrary() {
        let app = launch(language: "zh-Hans", locale: "zh_CN")

        XCTAssertTrue(
            app.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["还没有订阅"].exists)
    }

    private func launch(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launch()
        return app
    }
}
