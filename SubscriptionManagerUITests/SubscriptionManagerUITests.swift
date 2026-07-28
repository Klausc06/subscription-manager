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

    func testCreatesEditableSubscriptionFromBundledCatalog() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-\(UUID().uuidString)"
        )

        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        let catalog = app.buttons["subscription.add.catalog"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        catalog.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Spotify")
        let spotify = app.buttons["catalog.preset.spotify"]
        XCTAssertTrue(spotify.waitForExistence(timeout: 5))
        let diagnostics = app.staticTexts["catalog.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertTrue(diagnostics.label.contains("Catalog version 2"))
        spotify.tap()

        let usePreset = app.buttons["catalog.use-preset"]
        XCTAssertTrue(usePreset.waitForExistence(timeout: 5))
        usePreset.tap()

        let serviceName = app.textFields["subscription.form.service-name"]
        XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
        XCTAssertEqual(serviceName.value as? String, "Spotify")

        let plan = app.textFields["subscription.form.plan"]
        plan.tap()
        plan.typeText("Premium")
        let amount = app.textFields["subscription.form.amount"]
        amount.tap()
        amount.typeText("11.99")
        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            app.buttons["subscription.row"].firstMatch
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Spotify"].exists)
    }

    func testChinaBatchPresetFromEachCategoryCreatesEditableSubscription() {
        let presets = [
            ("tencent-video-vip", "Tencent Video VIP", "Tencent Video"),
            ("qq-music-vip", "QQ Music VIP", "QQ Music"),
            ("wechat-reading-unlimited", "WeChat Reading Unlimited", "WeChat Reading"),
            ("caixin-digital", "Caixin Digital", "Caixin"),
            ("genshin-impact-welkin", "Genshin Impact Welkin Moon", "Genshin"),
        ]

        for (id, expectedServiceName, searchQuery) in presets {
            let app = launch(
                language: "en",
                locale: "en_US",
                storeToken: "catalog-\(id)-\(UUID().uuidString)"
            )
            XCTAssertTrue(app.buttons["subscription.add"].waitForExistence(timeout: 5))
            app.buttons["subscription.add"].tap()
            XCTAssertTrue(
                app.buttons["subscription.add.catalog"].waitForExistence(timeout: 5)
            )
            app.buttons["subscription.add.catalog"].tap()

            let searchField = app.searchFields.firstMatch
            XCTAssertTrue(searchField.waitForExistence(timeout: 5))
            searchField.tap()
            searchField.typeText(searchQuery)

            let preset = app.buttons["catalog.preset.\(id)"]
            XCTAssertTrue(preset.waitForExistence(timeout: 5))
            preset.tap()
            XCTAssertTrue(app.buttons["catalog.use-preset"].waitForExistence(timeout: 5))
            app.buttons["catalog.use-preset"].tap()

            let serviceName = app.textFields["subscription.form.service-name"]
            XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
            XCTAssertEqual(serviceName.value as? String, expectedServiceName)
            let plan = app.textFields["subscription.form.plan"]
            plan.tap()
            plan.typeText("Monthly")
            let amount = app.textFields["subscription.form.amount"]
            amount.tap()
            amount.typeText("9.99")
            app.buttons["subscription.form.save"].tap()

            XCTAssertTrue(app.buttons["subscription.row"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[expectedServiceName].exists)
        }
    }

    func testCreatesTrialWithVisibleTrialStatus() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "trial-en-\(UUID().uuidString)"
        )

        createSubscription(
            named: "Example Trial",
            plan: "Trial",
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

        createSubscription(
            named: "示例试用",
            plan: "Trial",
            statusButton: "试用中",
            in: app
        )
        app.staticTexts["示例试用"].tap()

        let status = app.descendants(matching: .any)["subscription.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("试用中"))
    }

    func testArchivesAndRestoresSubscription() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "archive-restore-\(UUID().uuidString)"
        )
        createSubscription(
            named: "Example Archive",
            plan: "Trial",
            statusButton: "Trial",
            in: app
        )

        app.buttons["subscription.row"].firstMatch.tap()
        let detailStatus = app.descendants(matching: .any)[
            "subscription.status"
        ]
        XCTAssertTrue(detailStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(detailStatus.label.contains("Trial"))

        app.buttons["subscription.lifecycle.actions"].tap()
        let archive = app.buttons["subscription.lifecycle.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()

        app.navigationBars.buttons["Subscriptions"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["Example Archive"].exists)

        let archivedLibrary = app.buttons["library.archived"]
        XCTAssertTrue(archivedLibrary.waitForExistence(timeout: 5))
        archivedLibrary.tap()

        XCTAssertTrue(app.navigationBars["Archived"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Example Archive"].waitForExistence(timeout: 5))
        let archivedStatus = app.descendants(matching: .any)[
            "subscription.status"
        ]
        XCTAssertTrue(archivedStatus.exists)
        XCTAssertTrue(archivedStatus.label.contains("Trial"))

        app.buttons["subscription.row"].firstMatch.tap()
        app.buttons["subscription.lifecycle.actions"].tap()
        let restore = app.buttons["subscription.lifecycle.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()

        app.navigationBars.buttons["Archived"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["Example Archive"].exists)
        app.navigationBars.buttons["Subscriptions"].tap()

        XCTAssertTrue(app.staticTexts["Example Archive"].waitForExistence(timeout: 5))
        let restoredStatus = app.descendants(matching: .any)[
            "subscription.status"
        ]
        XCTAssertTrue(restoredStatus.exists)
        XCTAssertTrue(restoredStatus.label.contains("Trial"))
    }

    func testPermanentDeleteRequiresConfirmation() {
        let serviceName = "Example Delete"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "permanent-delete-\(UUID().uuidString)"
        )
        createSubscription(
            named: serviceName,
            plan: "Trial",
            statusButton: "Trial",
            in: app
        )

        app.buttons["subscription.row"].firstMatch.tap()
        let currentStatus = app.descendants(matching: .any)[
            "subscription.status"
        ]
        XCTAssertTrue(currentStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(currentStatus.label.contains("Trial"))

        let lifecycleActions = app.buttons[
            "subscription.lifecycle.actions"
        ]
        XCTAssertTrue(lifecycleActions.waitForExistence(timeout: 5))
        lifecycleActions.tap()
        XCTAssertTrue(
            app.buttons["subscription.lifecycle.record-cancellation"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.buttons["subscription.lifecycle.delete"]
                .waitForExistence(timeout: 5)
        )
        let archive = app.buttons["subscription.lifecycle.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()

        app.navigationBars.buttons["Subscriptions"].tap()
        let archivedLibrary = app.buttons["library.archived"]
        XCTAssertTrue(archivedLibrary.waitForExistence(timeout: 5))
        archivedLibrary.tap()
        XCTAssertTrue(app.staticTexts[serviceName].waitForExistence(timeout: 5))
        app.buttons["subscription.row"].firstMatch.tap()

        let archivedStatus = app.descendants(matching: .any)[
            "subscription.status"
        ]
        XCTAssertTrue(archivedStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(archivedStatus.label.contains("Trial"))
        lifecycleActions.tap()
        XCTAssertTrue(
            app.buttons["subscription.lifecycle.restore"]
                .waitForExistence(timeout: 5)
        )
        let permanentDelete = app.buttons["subscription.lifecycle.delete"]
        XCTAssertTrue(permanentDelete.waitForExistence(timeout: 5))
        permanentDelete.tap()

        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(
            confirmation.staticTexts
                .matching(
                    NSPredicate(format: "label CONTAINS %@", serviceName)
                )
                .firstMatch
                .exists
        )
        XCTAssertTrue(
            confirmation.staticTexts["This action cannot be undone."].exists
        )
        confirmation.buttons["Delete Permanently"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.detail.not-found"]
                .waitForExistence(timeout: 5)
        )
    }

    func testFailedDirectActionsShowErrorAndKeepDetail() {
        let storeToken = "direct-action-error-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        createSubscription(named: "Current Failure", in: app)
        createSubscription(named: "Archived Failure", in: app)
        app.staticTexts["Archived Failure"].tap()
        app.buttons["subscription.lifecycle.actions"].tap()
        app.buttons["subscription.lifecycle.archive"].tap()
        app.terminate()

        let failingApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            failsLifecycleMutations: true
        )
        XCTAssertTrue(
            failingApp.staticTexts["Current Failure"]
                .waitForExistence(timeout: 5)
        )
        failingApp.staticTexts["Current Failure"].tap()
        let detail = failingApp.descendants(matching: .any)[
            "subscription.detail"
        ]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))

        let lifecycleActions = failingApp.buttons[
            "subscription.lifecycle.actions"
        ]
        lifecycleActions.tap()
        failingApp.buttons["subscription.lifecycle.archive"].tap()

        let actionError = failingApp.alerts["Couldn’t Complete Action"]
        XCTAssertTrue(actionError.waitForExistence(timeout: 5))
        XCTAssertTrue(
            actionError.staticTexts[
                "Couldn’t save lifecycle changes. Try again."
            ].exists
        )
        XCTAssertTrue(detail.exists)
        actionError.buttons["OK"].tap()
        XCTAssertFalse(actionError.exists)
        XCTAssertTrue(detail.exists)

        lifecycleActions.tap()
        failingApp.buttons["subscription.lifecycle.delete"].tap()
        let confirmation = failingApp.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertFalse(actionError.exists)
        confirmation.buttons["Delete Permanently"].tap()
        XCTAssertTrue(actionError.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.exists)
        actionError.buttons["OK"].tap()

        failingApp.navigationBars.buttons["Subscriptions"].tap()
        failingApp.buttons["library.archived"].tap()
        XCTAssertTrue(
            failingApp.staticTexts["Archived Failure"]
                .waitForExistence(timeout: 5)
        )
        failingApp.staticTexts["Archived Failure"].tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        lifecycleActions.tap()
        failingApp.buttons["subscription.lifecycle.restore"].tap()

        XCTAssertTrue(actionError.waitForExistence(timeout: 5))
        XCTAssertTrue(
            actionError.staticTexts[
                "Couldn’t save lifecycle changes. Try again."
            ].exists
        )
        XCTAssertTrue(detail.exists)
        actionError.buttons["OK"].tap()
        XCTAssertFalse(actionError.exists)
        XCTAssertTrue(detail.exists)
    }

    func testRecordsCancellationAndHidesNextExpectedCharge() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "cancel-\(UUID().uuidString)"
        )
        createSubscription(named: "Example Streaming", in: app)
        app.buttons["subscription.row"].firstMatch.tap()

        app.buttons["subscription.lifecycle.actions"].tap()
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

        let renewalAnchor = app.descendants(matching: .any)[
            "subscription.detail.renewal-anchor"
        ]
        if !renewalAnchor.exists {
            app.swipeUp()
        }
        XCTAssertTrue(renewalAnchor.waitForExistence(timeout: 5))
        guard let renewalAnchorValue = renewalAnchor.value as? String else {
            return XCTFail("Renewal Anchor must expose its localized date.")
        }

        app.buttons["subscription.lifecycle.actions"].tap()
        app.buttons["subscription.lifecycle.record-cancellation"].tap()
        XCTAssertTrue(
            app.buttons["subscription.cancellation.save"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["subscription.cancellation.save"].tap()

        app.buttons["subscription.lifecycle.actions"].tap()
        let reactivate = app.buttons["subscription.lifecycle.reactivate"]
        XCTAssertTrue(reactivate.waitForExistence(timeout: 5))
        reactivate.tap()

        let nextRenewal = app.datePickers[
            "subscription.reactivation.next-renewal"
        ]
        XCTAssertTrue(nextRenewal.waitForExistence(timeout: 5))
        let previousRenewal = selectedDate(in: nextRenewal)
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let anchorDate = date(
            fromLocalizedValue: renewalAnchorValue,
            locale: locale,
            calendar: calendar
        )
        let previousRenewalDate = date(
            fromLocalizedValue: previousRenewal,
            locale: locale,
            calendar: calendar
        )
        let nextOccurrence = nextMonthlyOccurrence(
            renewalAnchor: anchorDate,
            after: previousRenewalDate,
            calendar: calendar
        )
        let targetDay = calendar.component(.day, from: nextOccurrence)
        let confirmedDate = selectDistinctGraphicalDate(
            in: nextRenewal,
            direction: .nextMonth(day: targetDay)
        )
        XCTAssertEqual(
            confirmedDate,
            localizedDateValue(
                nextOccurrence,
                locale: locale,
                calendar: calendar
            )
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

        app.buttons["subscription.lifecycle.actions"].tap()
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

    func testConfirmsChargeAndRecordsPriceHistory() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "payment-history-\(UUID().uuidString)"
        )
        createSubscription(named: "Example Payments", in: app)
        app.buttons["subscription.row"].firstMatch.tap()

        app.buttons["subscription.lifecycle.actions"].tap()
        XCTAssertTrue(app.buttons["subscription.confirm"].waitForExistence(
            timeout: 5
        ))
        app.buttons["subscription.confirm"].tap()
        XCTAssertTrue(app.buttons["subscription.confirm.save"].waitForExistence(
            timeout: 5
        ))
        app.buttons["subscription.confirm.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)[
            "subscription.history.confirmed"
        ].waitForExistence(timeout: 5))

        app.buttons["subscription.lifecycle.actions"].tap()
        app.buttons["subscription.price-change"].tap()
        XCTAssertTrue(app.buttons["subscription.price-change.save"].waitForExistence(
            timeout: 5
        ))
        app.buttons["subscription.price-change.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)[
            "subscription.history.price-change"
        ].waitForExistence(timeout: 5))
    }

    func testInvalidCustomIntervalIsExplainedInline() {
        let app = launch(language: "en", locale: "en_US")
        createSubscription(named: "Example Fitness", in: app)
        app.buttons["subscription.row"].firstMatch.tap()
        app.buttons["subscription.lifecycle.actions"].tap()
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
        plan planValue: String = "Standard",
        statusButton: String? = nil,
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
        plan.typeText(planValue)

        let category = app.textFields["subscription.form.category"]
        category.tap()
        category.typeText("Other")

        if let statusButton {
            let initialStatus = app.segmentedControls[
                "subscription.form.initial-status"
            ]
            XCTAssertTrue(initialStatus.waitForExistence(timeout: 5))
            initialStatus.buttons[statusButton].tap()
        }

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
        storeToken: String? = nil,
        failsLifecycleMutations: Bool = false
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
        if failsLifecycleMutations {
            app.launchArguments += [
                "--ui-testing-fail-lifecycle-mutations"
            ]
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

    private func nextMonthlyOccurrence(
        renewalAnchor: Date,
        after confirmedRenewal: Date,
        calendar: Calendar
    ) -> Date {
        for monthOffset in 1 ... 2_400 {
            guard let candidate = calendar.date(
                byAdding: .month,
                value: monthOffset,
                to: renewalAnchor
            ) else {
                continue
            }
            if calendar.startOfDay(for: candidate)
                > calendar.startOfDay(for: confirmedRenewal)
            {
                return candidate
            }
        }
        XCTFail("Couldn’t derive the next monthly schedule occurrence.")
        return confirmedRenewal
    }

    private func date(
        fromLocalizedValue value: String,
        locale: Locale,
        calendar: Calendar
    ) -> Date {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        guard let date = formatter.date(from: value) else {
            XCTFail("Couldn’t parse localized date: \(value)")
            return .distantPast
        }
        return date
    }

    private func localizedDateValue(
        _ date: Date,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
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

        let target: XCUIElement
        switch direction {
        case .earlier:
            if selectedIndex > 0 {
                target = dayButtons[selectedIndex - 1]
            } else {
                let previousMonthDays = moveCalendarMonth(
                    in: picker,
                    controlIdentifier: "DatePicker.PreviousMonth"
                )
                guard let lastDay = previousMonthDays.last else {
                    XCTFail("Previous month has no selectable day.")
                    return originalValue
                }
                target = lastDay
            }
        case .later:
            if selectedIndex + 1 < dayButtons.count {
                target = dayButtons[selectedIndex + 1]
            } else {
                let nextMonthDays = moveCalendarMonth(
                    in: picker,
                    controlIdentifier: "DatePicker.NextMonth"
                )
                guard let firstDay = nextMonthDays.first else {
                    XCTFail("Next month has no selectable day.")
                    return originalValue
                }
                target = firstDay
            }
        case .nextMonth(let day):
            let nextMonthDays = moveCalendarMonth(
                in: picker,
                controlIdentifier: "DatePicker.NextMonth"
            )
            guard !nextMonthDays.isEmpty else {
                XCTFail("Next month doesn’t contain selectable days.")
                return originalValue
            }
            let targetIndex = min(max(day - 1, 0), nextMonthDays.count - 1)
            target = nextMonthDays[targetIndex]
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

    private func moveCalendarMonth(
        in picker: XCUIElement,
        controlIdentifier: String
    ) -> [XCUIElement] {
        let month = picker.buttons["DatePicker.Show"]
        let monthControl = picker.buttons[controlIdentifier]
        guard month.exists,
              monthControl.exists,
              let originalMonth = month.value as? String
        else {
            XCTFail("Couldn’t find native calendar month controls.")
            return []
        }

        monthControl.tap()
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
        return graphicalDayButtons(in: picker)
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
}

private enum GraphicalDateDirection {
    case earlier
    case later
    case nextMonth(day: Int)
}
