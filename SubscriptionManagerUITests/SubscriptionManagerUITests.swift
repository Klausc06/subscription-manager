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

    func testCreatesMonthlySubscriptionAndOpensItsDetail() {
        let storeToken = "create-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )

        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        let serviceName = app.textFields["subscription.form.service-name"]
        XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
        serviceName.tap()
        serviceName.typeText("Example Video")

        let plan = app.textFields["subscription.form.plan"]
        plan.tap()
        plan.typeText("Standard")

        let category = app.textFields["subscription.form.category"]
        category.tap()
        category.typeText("Entertainment")

        let amount = app.textFields["subscription.form.amount"]
        amount.tap()
        amount.typeText("12.34")

        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            app.buttons["subscription.row"].firstMatch
                .waitForExistence(timeout: 5)
        )
        app.terminate()
        app.launch()

        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Example Video"].exists)
        XCTAssertTrue(app.staticTexts["Standard"].exists)
        let rowAmount = app.staticTexts["subscription.row.amount"]
        XCTAssertTrue(rowAmount.exists)
        XCTAssertTrue(rowAmount.label.contains("12.34"))

        app.staticTexts["Example Video"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.detail"]
                .waitForExistence(timeout: 5)
        )
        let detailService = app.descendants(matching: .any)[
            "subscription.detail.service-name"
        ]
        XCTAssertTrue(detailService.exists)
        XCTAssertTrue(detailService.label.contains("Example Video"))
        let detailPlan = app.descendants(matching: .any)[
            "subscription.detail.plan"
        ]
        XCTAssertTrue(detailPlan.exists)
        XCTAssertTrue(detailPlan.label.contains("Standard"))
        let detailAmount = app.staticTexts["subscription.detail.amount"]
        XCTAssertTrue(detailAmount.exists)
        XCTAssertTrue(detailAmount.label.contains("12.34"))
        XCTAssertTrue(app.staticTexts["Next Expected Charge"].exists)
    }

    func testInvalidAmountIsExplainedInline() {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        let serviceName = app.textFields["subscription.form.service-name"]
        XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
        serviceName.tap()
        serviceName.typeText("Example Music")

        let plan = app.textFields["subscription.form.plan"]
        plan.tap()
        plan.typeText("Individual")

        let category = app.textFields["subscription.form.category"]
        category.tap()
        category.typeText("Music")

        let amount = app.textFields["subscription.form.amount"]
        amount.tap()
        amount.typeText("twelve")

        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            app.staticTexts["subscription.validation.amount"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Enter a valid amount."].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"]
                .exists
        )
    }

    func testSimplifiedChineseAddFlowUsesLocalizedCopy() {
        let app = launch(language: "zh-Hans", locale: "zh_CN")

        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        XCTAssertTrue(app.navigationBars["添加订阅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["服务"].exists)
        XCTAssertTrue(app.staticTexts["订阅信息"].exists)
        XCTAssertTrue(app.buttons["保存"].exists)
    }

    private func launch(
        language: String,
        locale: String,
        storeToken: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        if let storeToken {
            app.launchArguments += ["--ui-testing-store", storeToken]
        }
        app.launch()
        return app
    }
}
