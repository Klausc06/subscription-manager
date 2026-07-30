import XCTest
import UIKit

@MainActor
final class SubscriptionManagerUITests: XCTestCase {
    func testWideIPadUsesSidebarToSwitchDestinations() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom != .pad,
            "This adaptive-layout contract runs only on iPad."
        )
        let app = launch(language: "en", locale: "en_US")

        XCTAssertTrue(
            app.descendants(matching: .any)["root.sidebar"]
                .waitForExistence(timeout: 5)
        )
        let upcoming = app.descendants(matching: .any)["root.sidebar.upcoming"]
        XCTAssertTrue(upcoming.waitForExistence(timeout: 5))
        upcoming.tap()
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 5))
    }

    func testTopLevelNavigationProvidesSubscriptionsUpcomingAndInsights() {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertTrue(topLevelTab("Subscriptions", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(topLevelTab("Upcoming", in: app).exists)
        XCTAssertTrue(topLevelTab("Insights", in: app).exists)
    }

    func testInsightsShowsExplicitUnavailableStateWithoutRates() {
        let app = launch(language: "en", locale: "en_US")

        topLevelTab("Insights", in: app).tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["insights.mode"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["insights.unavailable"]
                .waitForExistence(timeout: 5)
        )
    }

    func testSettingsOffersEURAsDisplayCurrency() {
        let app = launch(language: "en", locale: "en_US")

        app.buttons["library.settings"].tap()

        XCTAssertTrue(
            app.buttons["preferences.currency.eur"].waitForExistence(timeout: 5)
        )
    }

    func testSettingsOffersPortableExports() {
        let app = launch(language: "en", locale: "en_US")

        app.buttons["library.settings"].tap()
        let exportEntry = app.buttons["preferences.portable-export"]
        XCTAssertTrue(exportEntry.waitForExistence(timeout: 5))
        exportEntry.tap()

        XCTAssertTrue(
            app.buttons["portable-export.json"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["portable-export.csv"].exists)
    }

    func testSettingsOffersPortableRestore() {
        let app = launch(language: "en", locale: "en_US")

        app.buttons["library.settings"].tap()
        let restoreEntry = app.buttons["preferences.portable-restore"]
        XCTAssertTrue(restoreEntry.waitForExistence(timeout: 5))
        restoreEntry.tap()

        XCTAssertTrue(
            app.buttons["portable-restore.select-file"].waitForExistence(timeout: 5)
        )
    }

    func testUpcomingExpectedChargeOpensItsSubscriptionDetail() {
        let app = launch(language: "en", locale: "en_US")

        app.buttons["subscription.add"].tap()
        XCTAssertTrue(
            app.buttons["catalog.add-manually"].waitForExistence(timeout: 5)
        )
        app.buttons["catalog.add-manually"].tap()
        let serviceName = app.textFields["subscription.form.service-name"]
        XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
        serviceName.tap()
        serviceName.typeText("Upcoming Example")
        app.textFields["subscription.form.plan"].tap()
        app.textFields["subscription.form.plan"].typeText("Monthly")
        app.textFields["subscription.form.category"].tap()
        app.textFields["subscription.form.category"].typeText("Other")
        app.textFields["subscription.form.amount"].tap()
        app.textFields["subscription.form.amount"].typeText("9.99")
        app.buttons["subscription.form.save"].tap()

        topLevelTab("Upcoming", in: app).tap()
        let ninetyDays = app.buttons["Next 90 Days"]
        XCTAssertTrue(ninetyDays.waitForExistence(timeout: 5))
        ninetyDays.tap()
        let expectedCharge = app.buttons["upcoming.row.expected"].firstMatch
        XCTAssertTrue(expectedCharge.waitForExistence(timeout: 5))
        expectedCharge.tap()
        XCTAssertTrue(
            app.staticTexts["Subscription Details"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.detail"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Expected Charge"].exists)
    }

    func testUpcomingDistinguishesConfirmedPaymentsWithoutColorOnly() {
        let app = launch(language: "en", locale: "en_US")
        createSubscription(named: "Confirmed Upcoming", in: app)
        app.buttons["subscription.row"].firstMatch.tap()
        app.buttons["subscription.lifecycle.actions"].tap()
        XCTAssertTrue(app.buttons["subscription.confirm"].waitForExistence(timeout: 5))
        app.buttons["subscription.confirm"].tap()
        XCTAssertTrue(
            app.buttons["subscription.confirm.save"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.confirm.save"].tap()

        topLevelTab("Upcoming", in: app).tap()
        app.buttons["Next 90 Days"].tap()
        let confirmed = app.buttons["upcoming.row.confirmed"].firstMatch
        XCTAssertTrue(confirmed.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmed.label.contains("Confirmed Payment"))
    }

    func testFirstRunShowsPreferenceDefaultsWithoutCalendarPrompt() {
        let app = launch(
            language: "en",
            locale: "en_US",
            onboarding: true
        )

        XCTAssertTrue(app.staticTexts["Set Up Your Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setup.continue"].exists)
        XCTAssertTrue(app.buttons["CNY"].exists)
        XCTAssertTrue(app.buttons["12 Months"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testFirstRunConfirmsEachSelectedPresetBeforeFinishing() {
        let app = launch(
            language: "en",
            locale: "en_US",
            onboarding: true
        )

        XCTAssertTrue(app.buttons["setup.continue"].waitForExistence(timeout: 5))
        app.buttons["setup.continue"].tap()
        let spotify = app.buttons["setup.preset.spotify"]
        XCTAssertTrue(scrollToExistence(spotify, in: app))
        spotify.tap()
        XCTAssertEqual(spotify.value as? String, "Selected")
        app.buttons["setup.actions"].tap()
        app.buttons["setup.confirm-selected"].tap()

        XCTAssertTrue(
            app.buttons["subscription.form.offer-plan"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(app.buttons["setup.actions"].waitForExistence(timeout: 5))
        app.buttons["setup.actions"].tap()
        XCTAssertTrue(app.buttons["setup.finish"].isEnabled)
        app.buttons["setup.finish"].tap()
        XCTAssertTrue(app.staticTexts["Spotify"].waitForExistence(timeout: 5))
    }

    func testInterruptedSetupResumesWithoutDuplicatingConfirmedPreset() {
        let storeToken = "setup-resume-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            onboarding: true
        )

        XCTAssertTrue(app.buttons["setup.continue"].waitForExistence(timeout: 5))
        app.buttons["setup.continue"].tap()
        let initialSpotify = app.buttons["setup.preset.spotify"]
        XCTAssertTrue(scrollToExistence(initialSpotify, in: app))
        initialSpotify.tap()
        app.buttons["setup.actions"].tap()
        app.buttons["setup.confirm-selected"].tap()

        XCTAssertTrue(
            app.buttons["subscription.form.offer-plan"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["subscription.form.save"].tap()
        XCTAssertTrue(app.buttons["setup.actions"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Set Up Your Library"].waitForExistence(timeout: 5))
        app.buttons["setup.continue"].tap()
        let spotify = app.buttons["setup.preset.spotify"]
        XCTAssertTrue(scrollToExistence(spotify, in: app))
        spotify.tap()
        app.buttons["setup.actions"].tap()
        XCTAssertTrue(app.buttons["setup.finish"].isEnabled)
        app.buttons["setup.finish"].tap()
        let spotifyLabels = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Spotify")
        )
        XCTAssertEqual(spotifyLabels.count, 1)
    }

    func testLegacyChatGPTSetupResumeUsesCanonicalCatalogIdentity() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "legacy-chatgpt-\(UUID().uuidString)",
            onboarding: true,
            seedsLegacyChatGPTPlus: true
        )

        XCTAssertTrue(app.buttons["setup.continue"].waitForExistence(timeout: 5))
        app.buttons["setup.continue"].tap()
        let chatGPT = app.buttons["setup.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()
        app.buttons["setup.actions"].tap()
        XCTAssertTrue(app.buttons["setup.finish"].isEnabled)
        app.buttons["setup.finish"].tap()

        let chatGPTLabels = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "ChatGPT")
        )
        XCTAssertEqual(chatGPTLabels.count, 1)
    }

    func testSettingsPersistsSetupDefaultsAfterSkipping() {
        let storeToken = "setup-settings-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            onboarding: true
        )

        XCTAssertTrue(app.buttons["setup.skip"].waitForExistence(timeout: 5))
        app.buttons["setup.skip"].tap()
        XCTAssertTrue(app.buttons["library.settings"].waitForExistence(timeout: 5))
        app.buttons["library.settings"].tap()
        XCTAssertTrue(app.buttons["preferences.currency.usd"].waitForExistence(timeout: 5))
        app.buttons["preferences.currency.usd"].tap()
        app.buttons["preferences.horizon.six-months"].tap()
        app.buttons["preferences.save"].tap()

        app.terminate()
        app.launch()
        app.buttons["library.settings"].tap()
        XCTAssertEqual(
            app.buttons["preferences.currency.usd"].value as? String,
            "Selected"
        )
        XCTAssertEqual(
            app.buttons["preferences.horizon.six-months"].value as? String,
            "Selected"
        )
    }

    func testSkippedSetupCanBeResumedFromSettings() {
        let app = launch(
            language: "en",
            locale: "en_US",
            onboarding: true
        )

        XCTAssertTrue(app.buttons["setup.skip"].waitForExistence(timeout: 5))
        app.buttons["setup.skip"].tap()
        XCTAssertTrue(app.buttons["library.settings"].waitForExistence(timeout: 5))
        app.buttons["library.settings"].tap()
        let resumeSetup = app.buttons["preferences.resume-setup"]
        if !resumeSetup.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(resumeSetup.waitForExistence(timeout: 5))
        resumeSetup.tap()
        XCTAssertTrue(app.staticTexts["Set Up Your Library"].waitForExistence(timeout: 5))
    }

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
        XCTAssertTrue(
            app.buttons["catalog.add-manually"].waitForExistence(timeout: 5)
        )
        app.buttons["catalog.add-manually"].tap()

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

    func testCreatesSubscriptionFromOfficialCatalogOffer() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-\(UUID().uuidString)"
        )

        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        XCTAssertTrue(
            app.navigationBars["Browse Catalog"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["subscription.add.catalog"].exists)

        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        XCTAssertTrue(
            app.navigationBars["Confirm Subscription"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["subscription.form.cancel"].exists)
        XCTAssertTrue(app.buttons["subscription.form.save"].exists)

        let planPicker = app.buttons["subscription.form.offer-plan"]
        XCTAssertTrue(planPicker.waitForExistence(timeout: 5))
        planPicker.tap()
        app.buttons["Pro (5x)"].tap()
        app.buttons["subscription.form.save"].tap()

        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("ChatGPT"))
        XCTAssertTrue(row.label.contains("Pro (5x)"))
        XCTAssertTrue(row.label.contains("$100"))
    }

    func testCatalogOfficialOfferPrefillsConfirmation() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-offer-\(UUID().uuidString)"
        )

        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        let planPicker = app.buttons["subscription.form.offer-plan"]
        XCTAssertTrue(planPicker.waitForExistence(timeout: 5))
        planPicker.tap()
        app.buttons["Pro (5x)"].tap()

        XCTAssertTrue(
            app.buttons["subscription.form.offer-plan"].label
                .contains("Pro (5x)")
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "subscription.form.selected-plan"
            ].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form.selected-price"]
                .label.contains("$100")
        )
        XCTAssertTrue(
            app.staticTexts["subscription.form.offer-provenance"]
                .label.contains("US")
        )
        XCTAssertFalse(app.textFields["subscription.form.service-name"].exists)
        XCTAssertFalse(app.textFields["subscription.form.plan"].exists)
        XCTAssertFalse(app.textFields["subscription.form.amount"].exists)

        let adjustCharge = app.buttons["subscription.form.adjust-charge"]
        XCTAssertTrue(adjustCharge.exists)
        adjustCharge.tap()
        let amount = app.textFields["subscription.form.amount"]
        XCTAssertTrue(
            scrollToExistence(amount, in: app, maximumSwipes: 4)
        )
        XCTAssertTrue(
            app.buttons["subscription.form.billing-interval"].exists
        )
        XCTAssertFalse(app.textFields["subscription.form.service-name"].exists)
        XCTAssertFalse(app.textFields["subscription.form.plan"].exists)

        let source = app.links["subscription.form.offer-source"]
        XCTAssertTrue(
            scrollToExistence(source, in: app, maximumSwipes: 4)
        )
    }

    func testActualChargeDisclosureSummarizesAndRevealsValidation() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-disclosure-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        let disclosure = app.buttons["subscription.form.adjust-charge"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (disclosure.value as? String)?.contains("$8") == true
        )
        XCTAssertTrue(
            (disclosure.value as? String)?.contains("USD") == true
        )
        disclosure.tap()

        let amount = app.textFields["subscription.form.amount"]
        XCTAssertTrue(scrollToExistence(amount, in: app, maximumSwipes: 4))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("0")
        XCTAssertEqual(amount.value as? String, "0")
        disclosure.tap()
        XCTAssertFalse(amount.exists)

        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["subscription.validation.amount"].exists
        )
    }

    func testOfficialOfferBillingErrorReopensAdjustmentDisclosure() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-interval-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        let disclosure = app.buttons["subscription.form.adjust-charge"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.datePickers["subscription.form.renewal-anchor"].exists
        )
        disclosure.tap()

        let billingInterval = app.buttons[
            "subscription.form.billing-interval"
        ]
        XCTAssertTrue(
            scrollToExistence(billingInterval, in: app, maximumSwipes: 4)
        )
        billingInterval.tap()
        app.buttons["Custom"].tap()

        let customValue = app.textFields[
            "subscription.form.custom-interval-value"
        ]
        XCTAssertTrue(customValue.waitForExistence(timeout: 5))
        customValue.tap()
        customValue.typeText("0")
        let customUnit = app.buttons[
            "subscription.form.custom-interval-unit"
        ]
        customUnit.tap()
        app.buttons["Weeks"].tap()
        for _ in 0 ..< 4 where !disclosure.exists {
            app.swipeDown()
        }
        XCTAssertTrue(disclosure.exists)
        disclosure.tap()
        XCTAssertFalse(customValue.exists)

        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            scrollToExistence(customValue, in: app, maximumSwipes: 4)
        )
        XCTAssertEqual(customValue.value as? String, "0")
        XCTAssertTrue(
            app.buttons["subscription.form.custom-interval-unit"]
                .label.contains("Weeks")
        )
        XCTAssertTrue(
            app.staticTexts["subscription.validation.billing-schedule"]
                .exists
        )
    }

    func testOfficialOfferIntervalChangeRecomputesUntouchedRenewal() throws {
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-renewal-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        let disclosure = app.buttons["subscription.form.adjust-charge"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.tap()
        let billingInterval = app.buttons[
            "subscription.form.billing-interval"
        ]
        XCTAssertTrue(
            scrollToExistence(billingInterval, in: app, maximumSwipes: 4)
        )
        billingInterval.tap()
        app.buttons["Yearly"].tap()
        app.buttons["subscription.form.save"].tap()

        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let yearlySchedule = app.descendants(matching: .any)[
            "subscription.detail.billing-interval"
        ]
        XCTAssertTrue(
            scrollToExistence(yearlySchedule, in: app, maximumSwipes: 4)
        )
        XCTAssertTrue(yearlySchedule.label.contains("Yearly"))
        let detailStartDate = app.descendants(matching: .any)[
            "subscription.detail.start-date"
        ]
        XCTAssertTrue(
            scrollToExistence(detailStartDate, in: app, maximumSwipes: 8)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "subscription.detail.renewal-anchor"
            ].exists
        )
        let startValue = try XCTUnwrap(detailStartDate.value as? String)
        let startDate = date(
            fromLocalizedValue: startValue,
            locale: locale,
            calendar: calendar
        )
        let expectedRenewal = try XCTUnwrap(
            calendar.date(byAdding: .year, value: 1, to: startDate)
        )
        let expectedRenewalValue = localizedDateValue(
            expectedRenewal,
            locale: locale,
            calendar: calendar
        )
        let detailNextRenewal = app.cells.containing(
            .staticText,
            identifier: "Next Renewal"
        ).firstMatch
        XCTAssertTrue(
            scrollToExistence(
                detailNextRenewal,
                in: app,
                maximumSwipes: 8
            )
        )
        XCTAssertTrue(
            detailNextRenewal.staticTexts[expectedRenewalValue].exists,
            "Untouched Next Renewal must follow the selected interval."
        )
    }

    func testAddFormLinksBillingDatesInBothDirections() throws {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "add-linked-dates-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        app.buttons["catalog.add-manually"].tap()

        let nextRenewal = app.datePickers[
            "subscription.form.next-renewal"
        ]
        XCTAssertTrue(
            scrollToExistence(nextRenewal, in: app, maximumSwipes: 6)
        )
        let selectedNextRenewal = selectCompactDateInNextMonth(
            in: nextRenewal,
            app: app,
            day: 10
        )

        let startDate = app.datePickers["subscription.form.start-date"]
        for _ in 0 ..< 6 where !startDate.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(startDate.waitForExistence(timeout: 5))
        let selectedStartDate = selectedDate(in: startDate)
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let nextRenewalDate = date(
            fromLocalizedValue: selectedNextRenewal,
            locale: locale,
            calendar: calendar
        )
        let expectedStartDate = try XCTUnwrap(
            calendar.date(
                byAdding: .month,
                value: -1,
                to: nextRenewalDate
            )
        )

        XCTAssertEqual(
            selectedStartDate,
            localizedDateValue(
                expectedStartDate,
                locale: locale,
                calendar: calendar
            )
        )

        let editedStartDate = selectCompactDateInNextMonth(
            in: startDate,
            app: app,
            day: 12
        )
        let editedStart = date(
            fromLocalizedValue: editedStartDate,
            locale: locale,
            calendar: calendar
        )
        let expectedNextRenewal = try XCTUnwrap(
            calendar.date(
                byAdding: .month,
                value: 1,
                to: editedStart
            )
        )
        for _ in 0 ..< 6 where !nextRenewal.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(
            selectedDate(in: nextRenewal),
            localizedDateValue(
                expectedNextRenewal,
                locale: locale,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            app.datePickers["subscription.form.renewal-anchor"].exists
        )
    }

    func testTrialFormKeepsTrialStartAndFirstPaidChargeIndependent() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "trial-independent-dates-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        app.buttons["catalog.add-manually"].tap()

        let initialStatus = app.segmentedControls[
            "subscription.form.initial-status"
        ]
        XCTAssertTrue(initialStatus.waitForExistence(timeout: 5))
        initialStatus.buttons["Trial"].tap()

        let firstPaidCharge = app.datePickers[
            "subscription.form.next-renewal"
        ]
        XCTAssertTrue(
            scrollToExistence(firstPaidCharge, in: app, maximumSwipes: 6)
        )
        XCTAssertTrue(app.staticTexts["First Paid Charge"].exists)

        let trialStart = app.datePickers[
            "subscription.form.start-date"
        ]
        for _ in 0 ..< 6 where !trialStart.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(trialStart.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Trial Start"].exists)
        let originalTrialStart = selectedDate(in: trialStart)

        for _ in 0 ..< 6 where !firstPaidCharge.isHittable {
            app.swipeUp()
        }
        _ = selectCompactDateInNextMonth(
            in: firstPaidCharge,
            app: app,
            day: 10
        )

        for _ in 0 ..< 6 where !trialStart.isHittable {
            app.swipeDown()
        }
        XCTAssertEqual(selectedDate(in: trialStart), originalTrialStart)
    }

    func testCatalogFiltersResetAfterCancelAndSaveReopen() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-reopen-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        app.buttons["catalog.category"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)
        ).tap()
        let musicCategory = app.buttons["Music"]
        XCTAssertTrue(musicCategory.waitForExistence(timeout: 5))
        musicCategory.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Spotify")
        app.keyboards.buttons["Search"].tap()
        let closeSearch = app.buttons["close"]
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
        closeSearch.tap()
        let cancel = app.buttons["catalog.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        app.buttons["subscription.add"].tap()
        XCTAssertFalse(
            (app.searchFields.firstMatch.value as? String) == "Spotify"
        )
        XCTAssertTrue(
            app.buttons["catalog.category"].label.contains("All Categories")
        )

        let reopenedSearch = app.searchFields.firstMatch
        reopenedSearch.tap()
        reopenedSearch.typeText("ChatGPT")
        app.buttons["catalog.preset.chatgpt"].tap()
        app.buttons["subscription.form.save"].tap()
        XCTAssertTrue(
            app.buttons["subscription.row"].firstMatch
                .waitForExistence(timeout: 5)
        )

        app.buttons["subscription.add"].tap()
        XCTAssertFalse(
            (app.searchFields.firstMatch.value as? String) == "ChatGPT"
        )
        XCTAssertTrue(
            app.buttons["catalog.category"].label.contains("All Categories")
        )
    }

    func testSetupCanResumeAfterPriorCatalogFilters() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "setup-filter-\(UUID().uuidString)",
            onboarding: true
        )
        XCTAssertTrue(app.buttons["setup.skip"].waitForExistence(timeout: 5))
        app.buttons["setup.skip"].tap()
        XCTAssertTrue(app.buttons["subscription.add"].waitForExistence(timeout: 5))
        app.buttons["subscription.add"].tap()
        app.buttons["catalog.category"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)
        ).tap()
        let musicCategory = app.buttons["Music"]
        XCTAssertTrue(musicCategory.waitForExistence(timeout: 5))
        musicCategory.tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Spotify")
        app.keyboards.buttons["Search"].tap()
        let closeSearch = app.buttons["close"]
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
        closeSearch.tap()
        let cancel = app.buttons["catalog.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        app.buttons["library.settings"].tap()
        let resumeSetup = app.buttons["preferences.resume-setup"]
        XCTAssertTrue(scrollToExistence(resumeSetup, in: app))
        resumeSetup.tap()
        XCTAssertTrue(
            app.staticTexts["Set Up Your Library"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["setup.continue"].exists)
    }

    func testCatalogAlphabetIndexSupportsTapAndDrag() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-index-\(UUID().uuidString)"
        )

        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()

        let index = app.otherElements["catalog.alphabet-index"]
        XCTAssertTrue(index.waitForExistence(timeout: 5))

        let letterB = app.buttons["catalog.alphabet-index.B"]
        XCTAssertTrue(letterB.exists)
        letterB.tap()
        XCTAssertTrue(
            app.staticTexts["catalog.section.B"]
                .waitForExistence(timeout: 5)
        )

        let start = index.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)
        )
        let end = index.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)
        )
        start.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertTrue(
            app.staticTexts["catalog.section.#"]
                .waitForExistence(timeout: 5)
        )
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

    func testLeadingSwipePinsAndUnpinsLibraryRows() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "pin-unpin-\(UUID().uuidString)"
        )
        createSubscription(named: "Alpha Service", in: app)
        createSubscription(named: "Beta Service", in: app)

        let betaRow = app.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", "Beta Service")
        )
        .firstMatch
        XCTAssertTrue(betaRow.waitForExistence(timeout: 5))
        betaRow.swipeRight()

        let pin = app.buttons["subscription.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()

        let firstPinnedRow = app.buttons[
            "subscription.row"
        ].firstMatch
        XCTAssertTrue(firstPinnedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(firstPinnedRow.label.contains("Beta Service"))
        XCTAssertTrue(firstPinnedRow.value as? String == "Pinned")

        firstPinnedRow.swipeRight()
        let unpin = app.buttons["subscription.unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 5))
        unpin.tap()

        let firstUnpinnedRow = app.buttons[
            "subscription.row"
        ].firstMatch
        XCTAssertTrue(firstUnpinnedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(firstUnpinnedRow.label.contains("Alpha Service"))
    }

    func testTrailingSwipeRequiresConfirmationBeforePermanentDelete() {
        let serviceName = "Swipe Delete"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "swipe-delete-\(UUID().uuidString)"
        )
        createSubscription(named: serviceName, in: app)

        var row = app.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        revealTrailingActions(on: row)
        XCTAssertTrue(
            app.buttons["subscription.delete"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.buttons["subscription.archive"].waitForExistence(timeout: 5)
        )

        app.navigationBars["Subscriptions"].tap()
        row = app.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        triggerFullTrailingSwipe(on: row)

        var confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        XCTAssertTrue(
            confirmation.staticTexts
                .matching(
                    NSPredicate(
                        format: "label CONTAINS %@",
                        serviceName
                    )
                )
                .firstMatch
                .exists
        )
        XCTAssertTrue(
            confirmation.staticTexts
                .matching(
                    NSPredicate(format: "label CONTAINS %@", "Standard")
                )
                .firstMatch
                .exists
        )
        XCTAssertTrue(
            confirmation.staticTexts[
                "This permanently removes its schedule, notes, lifecycle "
                    + "details, and payment history. This action cannot be "
                    + "undone."
            ].exists
        )
        let cancel = confirmation.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        triggerFullTrailingSwipe(on: row)
        confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete Permanently"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
    }

    func testArchivedRowsSwipeToRestoreOrConfirmedDelete() {
        let serviceName = "Swipe Archive"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "swipe-archive-\(UUID().uuidString)"
        )
        createSubscription(named: serviceName, in: app)

        var row = app.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        revealTrailingActions(on: row)
        let archive = app.buttons["subscription.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))

        app.buttons["library.archived"].tap()
        row = app.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        revealTrailingActions(on: row)
        XCTAssertTrue(
            app.buttons["subscription.delete"].waitForExistence(timeout: 5)
        )
        let restore = app.buttons["subscription.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["subscription.pin"].exists)
        restore.tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))

        app.navigationBars.buttons["Subscriptions"].tap()
        XCTAssertTrue(app.staticTexts[serviceName].waitForExistence(timeout: 5))

        row = app.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        revealTrailingActions(on: row)
        app.buttons["subscription.archive"].tap()
        app.buttons["library.archived"].tap()
        row = app.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        triggerFullTrailingSwipe(on: row)
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        confirmation.buttons["Delete Permanently"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
    }

    func testFailedSwipeActionsKeepTheLibraryRow() {
        let storeToken = "failed-swipe-\(UUID().uuidString)"
        let serviceName = "Swipe Failure"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        createSubscription(named: serviceName, in: app)
        app.terminate()

        let failingApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            failsLifecycleMutations: true
        )
        let row = failingApp.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        revealTrailingActions(on: row)
        failingApp.buttons["subscription.archive"].tap()

        var error = failingApp.alerts["Couldn’t Complete Action"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        error.buttons["OK"].tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))

        triggerFullTrailingSwipe(on: row)
        let confirmation = failingApp.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete Permanently"].tap()
        error = failingApp.alerts["Couldn’t Complete Action"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
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
        let archivedRow = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(archivedRow.label.contains("Trial"))

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
        let restoredRow = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredRow.label.contains("Trial"))
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
        XCTAssertTrue(
            app.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
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
            confirmation.staticTexts[
                "This permanently removes its schedule, notes, lifecycle "
                    + "details, and payment history. This action cannot be "
                    + "undone."
            ].exists
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
        app.navigationBars.buttons["Subscriptions"].tap()
        XCTAssertTrue(
            app.staticTexts["Current Failure"].waitForExistence(timeout: 5)
        )
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

        let startDateField = app.descendants(matching: .any)[
            "subscription.detail.start-date"
        ]
        if !startDateField.exists {
            app.swipeUp()
        }
        XCTAssertTrue(startDateField.waitForExistence(timeout: 5))
        guard let startDateValue = startDateField.value as? String else {
            return XCTFail("Start Date must expose its localized date.")
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
            fromLocalizedValue: startDateValue,
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
        XCTAssertTrue(
            app.buttons["catalog.add-manually"].waitForExistence(timeout: 5)
        )
        app.buttons["catalog.add-manually"].tap()

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

    func testEditsBillingScheduleAndKeepsItAfterRelaunch() throws {
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
        XCTAssertFalse(
            app.datePickers["subscription.form.renewal-anchor"].exists
        )
        let startDatePicker = app.datePickers[
            "subscription.form.start-date"
        ]
        let nextRenewalPicker = app.datePickers[
            "subscription.form.next-renewal"
        ]
        XCTAssertTrue(
            scrollToExistence(startDatePicker, in: app, maximumSwipes: 4)
        )
        let startValue = selectedDate(in: startDatePicker)
        XCTAssertTrue(
            scrollToExistence(nextRenewalPicker, in: app, maximumSwipes: 4)
        )
        let nextRenewalValue = selectedDate(in: nextRenewalPicker)
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let selectedStart = date(
            fromLocalizedValue: startValue,
            locale: locale,
            calendar: calendar
        )
        let expectedNextRenewal = try XCTUnwrap(
            calendar.date(byAdding: .year, value: 1, to: selectedStart)
        )
        XCTAssertEqual(
            nextRenewalValue,
            localizedDateValue(
                expectedNextRenewal,
                locale: locale,
                calendar: calendar
            )
        )
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

    func testEditFormLinksBillingDatesInBothDirections() throws {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "edit-linked-dates-\(UUID().uuidString)"
        )
        createSubscription(named: "Linked Dates", in: app)
        app.buttons["subscription.row"].firstMatch.tap()
        app.buttons["subscription.lifecycle.actions"].tap()
        app.buttons["subscription.edit"].tap()

        let nextRenewal = app.datePickers[
            "subscription.form.next-renewal"
        ]
        XCTAssertTrue(
            scrollToExistence(nextRenewal, in: app, maximumSwipes: 6)
        )
        let selectedNextRenewal = selectCompactDateInNextMonth(
            in: nextRenewal,
            app: app,
            day: 10
        )

        let startDate = app.datePickers["subscription.form.start-date"]
        for _ in 0 ..< 6 where !startDate.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(startDate.waitForExistence(timeout: 5))
        let selectedStartDate = selectedDate(in: startDate)
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let nextRenewalDate = date(
            fromLocalizedValue: selectedNextRenewal,
            locale: locale,
            calendar: calendar
        )
        let expectedStartDate = try XCTUnwrap(
            calendar.date(
                byAdding: .month,
                value: -1,
                to: nextRenewalDate
            )
        )

        XCTAssertEqual(
            selectedStartDate,
            localizedDateValue(
                expectedStartDate,
                locale: locale,
                calendar: calendar
            )
        )

        let editedStartDate = selectCompactDateInNextMonth(
            in: startDate,
            app: app,
            day: 12
        )
        let editedStart = date(
            fromLocalizedValue: editedStartDate,
            locale: locale,
            calendar: calendar
        )
        let expectedNextRenewal = try XCTUnwrap(
            calendar.date(
                byAdding: .month,
                value: 1,
                to: editedStart
            )
        )
        for _ in 0 ..< 6 where !nextRenewal.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(
            selectedDate(in: nextRenewal),
            localizedDateValue(
                expectedNextRenewal,
                locale: locale,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            app.datePickers["subscription.form.renewal-anchor"].exists
        )
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
        XCTAssertTrue(
            app.buttons["catalog.add-manually"].waitForExistence(timeout: 5)
        )
        app.buttons["catalog.add-manually"].tap()

        XCTAssertTrue(app.navigationBars["添加订阅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["服务"].exists)
        XCTAssertTrue(app.staticTexts["订阅信息"].exists)
        XCTAssertTrue(app.staticTexts["账单计划"].exists)
        app.swipeUp()
        XCTAssertTrue(app.textFields["订阅管理网址"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "打开服务商的账单、续订或取消订阅页面；本应用不会替你取消订阅。"
            ].exists
        )
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
        XCTAssertTrue(
            app.buttons["catalog.add-manually"].waitForExistence(timeout: 5)
        )
        app.buttons["catalog.add-manually"].tap()

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

        let form = app.descendants(matching: .any)["subscription.form"]
        app.buttons["subscription.form.save"].tap()
        XCTAssertTrue(form.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts[serviceNameValue]
                .waitForExistence(timeout: 5)
        )
    }

    private func scrollToExistence(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 20
    ) -> Bool {
        for _ in 0 ..< maximumSwipes {
            if element.exists {
                return true
            }
            app.swipeUp()
        }
        return element.exists
    }

    private func topLevelTab(
        _ title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let phoneTab = app.tabBars.buttons[title]
        if phoneTab.exists {
            return phoneTab
        }
        let iPadFloatingTab = app.cells[title]
        if iPadFloatingTab.exists {
            return iPadFloatingTab
        }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
    }

    private func launch(
        language: String,
        locale: String,
        storeToken: String? = nil,
        failsLifecycleMutations: Bool = false,
        onboarding: Bool = false,
        seedsLegacyChatGPTPlus: Bool = false
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
        if onboarding {
            app.launchArguments.append("--ui-testing-onboarding")
        }
        if seedsLegacyChatGPTPlus {
            app.launchArguments.append(
                "--ui-testing-seed-legacy-chatgpt-plus"
            )
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

    private func selectCompactDateInNextMonth(
        in picker: XCUIElement,
        app: XCUIApplication,
        day: Int
    ) -> String {
        let originalValue = selectedDate(in: picker)
        picker.tap()

        let nextMonth = app.buttons["DatePicker.NextMonth"]
        let month = app.buttons["DatePicker.Show"]
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 5))
        let originalMonth = month.value as? String
        nextMonth.tap()
        if let originalMonth {
            let monthChanged = NSPredicate(
                format: "value != %@",
                originalMonth
            )
            let expectation = XCTNSPredicateExpectation(
                predicate: monthChanged,
                object: month
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [expectation], timeout: 3),
                .completed
            )
        }

        let target = app.staticTexts[String(day)].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()

        let selectedValue = selectedDate(in: picker)
        XCTAssertNotEqual(
            selectedValue,
            originalValue,
            "Choosing a next-month day must update the compact date picker."
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

    private func revealTrailingActions(on row: XCUIElement) {
        let start = row.coordinate(
            withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)
        )
        let end = row.coordinate(
            withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0
        )
    }

    private func triggerFullTrailingSwipe(on row: XCUIElement) {
        let start = row.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)
        )
        let end = row.coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)
        )
        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: .fast,
            thenHoldForDuration: 0
        )
    }
}

private enum GraphicalDateDirection {
    case earlier
    case later
    case nextMonth(day: Int)
}
