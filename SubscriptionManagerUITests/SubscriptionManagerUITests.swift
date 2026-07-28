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

    func testCreatesTrialWithVisibleTrialStatus() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "trial-en-\(UUID().uuidString)"
        )

        createTrial(
            named: "Example Trial",
            statusButton: "Trial",
            in: app
        )
        app.staticTexts["Example Trial"].tap()

        let status = app.descendants(matching: .any)["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Trial"))
    }

    func testSimplifiedChineseLifecycleStatusIsLocalized() {
        let app = launch(
            language: "zh-Hans",
            locale: "zh_CN",
            storeToken: "trial-zh-\(UUID().uuidString)"
        )

        createTrial(
            named: "示例试用",
            statusButton: "试用中",
            in: app
        )
        app.staticTexts["示例试用"].tap()

        let status = app.descendants(matching: .any)["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("试用中"))
    }

    func testRecordsCancellationAndHidesNextExpectedCharge() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "cancel-\(UUID().uuidString)"
        )
        createSubscription(named: "Example Streaming", in: app)
        app.buttons["subscription.row"].firstMatch.tap()

        app.buttons["subscription.actions"].tap()
        let recordCancellation = app.buttons[
            "subscription.lifecycle.record-cancellation"
        ]
        XCTAssertTrue(recordCancellation.waitForExistence(timeout: 5))
        recordCancellation.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.cancellation.form"]
                .waitForExistence(timeout: 5)
        )
        let cancellationPicker = app.datePickers[
            "subscription.cancellation.date"
        ]
        let accessUntilPicker = app.datePickers[
            "subscription.cancellation.access-until"
        ]
        XCTAssertTrue(cancellationPicker.exists)
        XCTAssertTrue(accessUntilPicker.exists)

        let initialCancellationDate = selectedDate(in: cancellationPicker)
        let selectedCancellationDate = selectDistinctGraphicalDate(
            in: cancellationPicker,
            direction: .earlier
        )
        XCTAssertNotEqual(
            selectedCancellationDate,
            initialCancellationDate,
            "Cancellation Date must change from its default."
        )

        app.swipeUp()
        let initialAccessUntil = selectedDate(in: accessUntilPicker)
        let selectedAccessUntil = selectDistinctGraphicalDate(
            in: accessUntilPicker,
            direction: .later
        )
        XCTAssertNotEqual(
            selectedAccessUntil,
            initialAccessUntil,
            "Access Until must change from its default."
        )
        app.buttons["subscription.cancellation.save"].tap()

        let status = app.descendants(matching: .any)["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Cancelled with Access"))
        XCTAssertFalse(app.staticTexts["Next Expected Charge"].exists)
        let accessUntil = app.descendants(matching: .any)[
            "subscription.detail.access-until"
        ]
        if !accessUntil.exists {
            app.swipeUp()
        }
        XCTAssertTrue(accessUntil.waitForExistence(timeout: 5))
        let cancellationDate = app.descendants(matching: .any)[
            "subscription.detail.cancellation-date"
        ]
        XCTAssertTrue(cancellationDate.exists)
        XCTAssertTrue(
            cancellationDate.label.contains(selectedCancellationDate),
            "Expected \(cancellationDate.label) to contain "
                + selectedCancellationDate
        )
        XCTAssertTrue(
            accessUntil.label.contains(selectedAccessUntil),
            "Expected \(accessUntil.label) to contain \(selectedAccessUntil)"
        )
    }

    func testReactivatesWithConfirmedNextRenewal() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "reactivate-\(UUID().uuidString)"
        )
        createSubscription(named: "Example Cloud", in: app)
        app.buttons["subscription.row"].firstMatch.tap()

        app.buttons["subscription.actions"].tap()
        app.buttons["subscription.lifecycle.record-cancellation"].tap()
        XCTAssertTrue(
            app.buttons["subscription.cancellation.save"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["subscription.cancellation.save"].tap()

        app.buttons["subscription.actions"].tap()
        let reactivate = app.buttons["subscription.lifecycle.reactivate"]
        XCTAssertTrue(reactivate.waitForExistence(timeout: 5))
        reactivate.tap()

        let nextRenewal = app.datePickers[
            "subscription.reactivation.next-renewal"
        ]
        XCTAssertTrue(nextRenewal.waitForExistence(timeout: 5))
        let previousRenewal = selectedDate(in: nextRenewal)
        let confirmedDate = selectDistinctGraphicalDate(
            in: nextRenewal,
            direction: .nextMonthSameDay
        )
        XCTAssertNotEqual(
            confirmedDate,
            previousRenewal,
            "Next Renewal must change from its pre-cancellation value."
        )
        app.buttons["subscription.reactivation.save"].tap()

        let status = app.descendants(matching: .any)["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Active"))
        XCTAssertTrue(app.staticTexts["Next Expected Charge"].exists)
        let expectedChargeDate = app.descendants(matching: .any)[
            "subscription.detail.expected-charge.date"
        ]
        if !expectedChargeDate.exists {
            app.swipeUp()
        }
        XCTAssertTrue(expectedChargeDate.waitForExistence(timeout: 5))
        XCTAssertTrue(
            expectedChargeDate.label.contains(confirmedDate),
            "Expected \(expectedChargeDate.label) to contain \(confirmedDate)"
        )
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

    func testEditsBillingScheduleAndKeepsItAfterRelaunch() {
        let storeToken = "edit-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        createSubscription(named: "Example News", in: app)
        app.buttons["subscription.row"].firstMatch.tap()

        app.buttons["subscription.actions"].tap()
        let editButton = app.buttons["subscription.edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let billingInterval = app.buttons[
            "subscription.form.billing-interval"
        ]
        XCTAssertTrue(billingInterval.waitForExistence(timeout: 5))
        billingInterval.tap()
        app.buttons["Yearly"].tap()
        app.buttons["subscription.form.save"].tap()

        let detailInterval = app.descendants(matching: .any)[
            "subscription.detail.billing-interval"
        ]
        XCTAssertTrue(detailInterval.waitForExistence(timeout: 5))
        XCTAssertTrue(detailInterval.label.contains("Yearly"))

        app.terminate()
        app.launch()
        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let relaunchedInterval = app.descendants(matching: .any)[
            "subscription.detail.billing-interval"
        ]
        XCTAssertTrue(relaunchedInterval.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunchedInterval.label.contains("Yearly"))
    }

    func testInvalidCustomIntervalIsExplainedInline() {
        let app = launch(language: "en", locale: "en_US")
        createSubscription(named: "Example Fitness", in: app)
        app.buttons["subscription.row"].firstMatch.tap()
        app.buttons["subscription.actions"].tap()
        app.buttons["subscription.edit"].tap()

        let billingInterval = app.buttons[
            "subscription.form.billing-interval"
        ]
        XCTAssertTrue(billingInterval.waitForExistence(timeout: 5))
        billingInterval.tap()
        app.buttons["Custom"].tap()
        let customValue = app.textFields[
            "subscription.form.custom-interval-value"
        ]
        XCTAssertTrue(customValue.waitForExistence(timeout: 5))
        customValue.tap()
        customValue.typeText("0")
        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            app.staticTexts["subscription.validation.billing-schedule"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Enter an interval greater than zero."].exists
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
        XCTAssertTrue(app.staticTexts["账单计划"].exists)
        let billingInterval = app.buttons[
            "subscription.form.billing-interval"
        ]
        XCTAssertTrue(billingInterval.exists)
        XCTAssertTrue(billingInterval.label.contains("每月"))
        XCTAssertTrue(app.buttons["保存"].exists)
    }

    private func createSubscription(
        named serviceNameValue: String,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        let serviceName = app.textFields["subscription.form.service-name"]
        XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
        serviceName.tap()
        serviceName.typeText(serviceNameValue)

        let plan = app.textFields["subscription.form.plan"]
        plan.tap()
        plan.typeText("Standard")

        let category = app.textFields["subscription.form.category"]
        category.tap()
        category.typeText("Other")

        let amount = app.textFields["subscription.form.amount"]
        amount.tap()
        amount.typeText("9.99")

        app.buttons["subscription.form.save"].tap()
        XCTAssertTrue(
            app.buttons["subscription.row"].firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    private func createTrial(
        named serviceNameValue: String,
        statusButton: String,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        let serviceName = app.textFields["subscription.form.service-name"]
        XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
        serviceName.tap()
        serviceName.typeText(serviceNameValue)

        let plan = app.textFields["subscription.form.plan"]
        plan.tap()
        plan.typeText("Trial")

        let category = app.textFields["subscription.form.category"]
        category.tap()
        category.typeText("Other")

        let initialStatus = app.segmentedControls[
            "subscription.form.initial-status"
        ]
        XCTAssertTrue(initialStatus.waitForExistence(timeout: 5))
        initialStatus.buttons[statusButton].tap()

        let amount = app.textFields["subscription.form.amount"]
        amount.tap()
        amount.typeText("9.99")

        app.buttons["subscription.form.save"].tap()
        XCTAssertTrue(
            app.buttons["subscription.row"].firstMatch
                .waitForExistence(timeout: 5)
        )
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

    private func selectedDate(in picker: XCUIElement) -> String {
        guard let value = picker.value as? String, !value.isEmpty else {
            XCTFail("Graphical DatePicker must expose its selected date.")
            return ""
        }
        return value
    }

    private func selectDistinctGraphicalDate(
        in picker: XCUIElement,
        direction: GraphicalDateDirection
    ) -> String {
        let originalValue = selectedDate(in: picker)
        let dayButtons = graphicalDayButtons(in: picker)
        guard dayButtons.contains(where: {
            $0.isSelected && $0.isHittable
        }) else {
            XCTFail("Couldn’t find the selected graphical calendar day.")
            return originalValue
        }

        guard let selectedIndex = dayButtons.firstIndex(where: {
            $0.isSelected
        }) else {
            XCTFail("Couldn’t locate the selected day in the calendar grid.")
            return originalValue
        }

        let preferredCandidates: [XCUIElement]
        let fallbackCandidates: [XCUIElement]
        switch direction {
        case .earlier:
            preferredCandidates = Array(
                dayButtons[..<selectedIndex].reversed()
            )
            fallbackCandidates = Array(
                dayButtons[(selectedIndex + 1)...]
            )
        case .later:
            preferredCandidates = Array(
                dayButtons[(selectedIndex + 1)...]
            )
            fallbackCandidates = Array(
                dayButtons[..<selectedIndex].reversed()
            )
        case .nextMonthSameDay:
            let month = picker.buttons["DatePicker.Show"]
            let nextMonth = picker.buttons["DatePicker.NextMonth"]
            guard month.exists,
                  nextMonth.exists,
                  let originalMonth = month.value as? String
            else {
                XCTFail("Couldn’t find native calendar month controls.")
                return originalValue
            }

            nextMonth.tap()
            let monthChanged = NSPredicate(format: "value != %@", originalMonth)
            let monthExpectation = XCTNSPredicateExpectation(
                predicate: monthChanged,
                object: month
            )
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [monthExpectation],
                    timeout: 3
                ),
                .completed
            )

            let refreshedDayButtons = graphicalDayButtons(in: picker)
            guard !refreshedDayButtons.isEmpty else {
                XCTFail("Next month doesn’t contain selectable days.")
                return originalValue
            }
            let targetIndex = min(
                selectedIndex,
                refreshedDayButtons.count - 1
            )
            tapCalendarDay(
                frame: refreshedDayButtons[targetIndex].frame,
                in: picker
            )
            let selectedValue = selectedDate(in: picker)
            XCTAssertNotEqual(
                selectedValue,
                originalValue,
                "Next-month selection must update the picker."
            )
            return selectedValue
        }

        guard let target = (preferredCandidates + fallbackCandidates)
            .first(where: { !$0.isSelected })
        else {
            XCTFail("Couldn’t find a distinct graphical calendar day.")
            return originalValue
        }

        target.tap()
        let selectedValue = selectedDate(in: picker)
        XCTAssertNotEqual(
            selectedValue,
            originalValue,
            "Tapping a distinct calendar day must update the picker."
        )
        return selectedValue
    }

    private func graphicalDayButtons(
        in picker: XCUIElement
    ) -> [XCUIElement] {
        let month = picker.buttons["DatePicker.Show"]
        let gridStartY = month.exists ? month.frame.maxY : picker.frame.minY
        return picker.buttons.allElementsBoundByIndex
            .filter {
                $0.isEnabled
                    && $0.isHittable
                    && $0.frame.minY > gridStartY
            }
            .sorted {
                if abs($0.frame.minY - $1.frame.minY) < 2 {
                    return $0.frame.minX < $1.frame.minX
                }
                return $0.frame.minY < $1.frame.minY
            }
    }

    private func tapCalendarDay(
        frame: CGRect,
        in picker: XCUIElement
    ) {
        let pickerFrame = picker.frame
        picker.coordinate(
            withNormalizedOffset: CGVector(
                dx: (frame.midX - pickerFrame.minX) / pickerFrame.width,
                dy: (frame.midY - pickerFrame.minY) / pickerFrame.height
            )
        )
        .tap()
    }
}

private enum GraphicalDateDirection {
    case earlier
    case later
    case nextMonthSameDay
}
