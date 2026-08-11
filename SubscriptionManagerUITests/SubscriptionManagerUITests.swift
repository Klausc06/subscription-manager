import XCTest
import UIKit

@MainActor
final class SubscriptionManagerUITests: XCTestCase {
    private enum Task6Fixture {
        static let directEditor = "Direct Editor Fixture"
        static let archivedEditor = "Archived Editor Fixture"
        static let due = "Due Today Fixture"
        static let overdue = "Overdue Quarterly Fixture"
        static let future = "Future Quarterly Fixture"
        static let confirmed = "Confirmed Quarterly Fixture"
    }

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

    func testCurrentLibraryUsesMySubscriptionsToolbarWithoutArchiveButton() {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertTrue(
            app.navigationBars["My Subscriptions"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["library.settings"].exists)
        XCTAssertTrue(app.buttons["subscription.add"].exists)
        XCTAssertFalse(app.buttons["library.archived"].exists)
    }

    func testSimplifiedChineseLibraryUsesMySubscriptionsTitle() {
        let app = launch(language: "zh-Hans", locale: "zh_CN")

        XCTAssertTrue(
            app.navigationBars["我的订阅"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["library.settings"].exists)
        XCTAssertTrue(app.buttons["subscription.add"].exists)
        XCTAssertFalse(app.buttons["library.archived"].exists)
    }

    func testCatalogUsesCenteredTitleAndToolbarManualAddPath() {
        let app = launch(language: "zh-Hans", locale: "zh_CN")

        XCTAssertTrue(app.buttons["subscription.add"].waitForExistence(timeout: 5))
        app.buttons["subscription.add"].tap()

        XCTAssertTrue(
            app.navigationBars["浏览目录"].waitForExistence(timeout: 5)
        )
        let addManually = app.buttons["catalog.add-manually"]
        XCTAssertTrue(addManually.waitForExistence(timeout: 5))
        XCTAssertFalse(app.cells["catalog.add-manually"].exists)
        addManually.tap()

        XCTAssertTrue(app.navigationBars["添加订阅"].waitForExistence(timeout: 5))
    }

    func testTopLevelSegmentedControlsUseOneVisualBoundary() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The compact phone layout owns this visual-boundary contract."
        )
        let app = launch(language: "en", locale: "en_US")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let minimumDirectControlWidth = window.frame.width * 0.88

        topLevelTab("Upcoming", in: app).tap()
        let monthTitle = app.staticTexts["upcoming.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["upcoming.month.previous"].exists)
        XCTAssertTrue(app.buttons["upcoming.month.next"].exists)
        XCTAssertGreaterThan(
            monthTitle.frame.width,
            minimumDirectControlWidth * 0.2,
            "Upcoming must expose its month context directly."
        )
        attachScreenshot(named: "r2-14-upcoming-single-boundary")

        topLevelTab("Insights", in: app).tap()
        let insightsMode = app.segmentedControls["insights.mode"]
        XCTAssertTrue(insightsMode.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            insightsMode.frame.width,
            minimumDirectControlWidth,
            "Insights must not inset its segmented control inside another card."
        )
        attachScreenshot(named: "r2-14-insights-single-boundary")
    }

    func testConfirmSubscriptionInitialStatusUsesOneVisualBoundary() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The compact phone layout owns this visual-boundary contract."
        )
        let app = launch(language: "en", locale: "en_US")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        XCTAssertTrue(
            app.navigationBars["Confirm Subscription"].waitForExistence(timeout: 5)
        )
        let initialStatus = app.segmentedControls["subscription.form.initial-status"]
        XCTAssertTrue(initialStatus.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            initialStatus.frame.width,
            window.frame.width * 0.88,
            "Initial Status must not inset its segmented control inside another card."
        )
        attachScreenshot(named: "r2-14-confirm-subscription-initial-status")
    }

    func testManualAddSuggestsAndAdoptsCatalogAlias() {
        let app = launch(language: "en", locale: "en_US")
        openManualAdd(in: app)

        let serviceNameField = app.textFields["subscription.editor.service-name"]
        XCTAssertTrue(serviceNameField.waitForExistence(timeout: 5))
        serviceNameField.tap()
        serviceNameField.typeText("88")

        let match = app.buttons["subscription.catalog-match.taobao-88vip"]
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        XCTAssertTrue(match.label.contains("88VIP"))
        match.tap()

        let serviceName = app.descendants(matching: .any)[
            "subscription.editor.service-name"
        ]
        XCTAssertTrue(
            accessibilityValue(of: serviceName).contains("Taobao 88VIP")
        )
        XCTAssertTrue(app.textFields["subscription.editor.amount"].exists)
        let offerPlan = app.descendants(matching: .any)[
            "subscription.form.offer-plan"
        ]
        XCTAssertTrue(offerPlan.waitForExistence(timeout: 5))
        attachScreenshot(named: "r2-04-taobao-88vip-service-only")

        let category = app.descendants(matching: .any)[
            "subscription.editor.category"
        ]
        XCTAssertTrue(scrollToExistence(category, in: app, maximumSwipes: 6))
        XCTAssertTrue(
            accessibilityValue(of: category).contains("Membership")
        )
        XCTAssertFalse(
            app.textFields["subscription.editor.management-url"].exists
        )
        XCTAssertFalse(
            app.links["subscription.editor.management-url"].exists
        )
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    func testAppearanceModePersistsAndFollowsSystem() {
        let storeToken = "appearance-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        let systemProbe = app.descendants(matching: .any)[
            "appearance.debug.probe"
        ]
        XCTAssertTrue(systemProbe.waitForExistence(timeout: 5))
        let systemBaseline = systemProbe.value as? String
        XCTAssertTrue(
            systemBaseline == "light" || systemBaseline == "dark",
            "System appearance must resolve to light or dark."
        )

        app.buttons["library.settings"].tap()
        let dark = app.buttons["preferences.appearance.dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        dark.tap()
        XCTAssertEqual(dark.value as? String, "Selected")
        app.buttons["preferences.save"].tap()

        app.terminate()
        app.launch()
        let darkProbe = app.descendants(matching: .any)[
            "appearance.debug.probe"
        ]
        XCTAssertTrue(darkProbe.waitForExistence(timeout: 5))
        XCTAssertEqual(darkProbe.value as? String, "dark")
        app.buttons["library.settings"].tap()
        XCTAssertEqual(
            app.buttons["preferences.appearance.dark"].value as? String,
            "Selected"
        )

        app.buttons["preferences.appearance.light"].tap()
        app.buttons["preferences.save"].tap()
        app.terminate()
        app.launch()
        let lightProbe = app.descendants(matching: .any)[
            "appearance.debug.probe"
        ]
        XCTAssertTrue(lightProbe.waitForExistence(timeout: 5))
        XCTAssertEqual(lightProbe.value as? String, "light")
        app.buttons["library.settings"].tap()
        XCTAssertEqual(
            app.buttons["preferences.appearance.light"].value as? String,
            "Selected"
        )

        app.buttons["preferences.appearance.system"].tap()
        app.buttons["preferences.save"].tap()
        app.terminate()
        app.launch()
        let restoredSystemProbe = app.descendants(matching: .any)[
            "appearance.debug.probe"
        ]
        XCTAssertTrue(restoredSystemProbe.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredSystemProbe.value as? String, systemBaseline)
        app.buttons["library.settings"].tap()
        XCTAssertEqual(
            app.buttons["preferences.appearance.system"].value as? String,
            "Selected"
        )
    }

    func testSettingsOffersPortableExports() {
        let app = launch(language: "en", locale: "en_US")

        app.buttons["library.settings"].tap()
        let exportEntry = app.buttons["preferences.portable-export"]
        XCTAssertTrue(scrollToExistence(exportEntry, in: app, maximumSwipes: 8))
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
        XCTAssertTrue(scrollToExistence(restoreEntry, in: app, maximumSwipes: 8))
        restoreEntry.tap()

        XCTAssertTrue(
            app.buttons["portable-restore.select-file"].waitForExistence(timeout: 5)
        )
    }

    func testUpcomingExpectedChargeOpensItsSubscriptionDetail() {
        let app = launchTask6Fixture(timeZoneIdentifier: "UTC")

        topLevelTab("Upcoming", in: app).tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["upcoming.calendar"]
                .waitForExistence(timeout: 5)
        )
        let calendar = app.descendants(matching: .any)["upcoming.calendar"]
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(
            calendar.frame.minX,
            window.frame.minX,
            "The native month calendar must keep content away from the window edge."
        )
        XCTAssertLessThan(
            calendar.frame.maxX,
            window.frame.maxX,
            "The native month calendar must remain fully inside the window."
        )
        XCTAssertTrue(
            app.staticTexts["upcoming.agenda"].waitForExistence(timeout: 5)
        )
        let expectedCharge = upcomingRow(
            named: Task6Fixture.due,
            identifier: "upcoming.row.expected",
            in: app
        )
        XCTAssertTrue(expectedCharge.waitForExistence(timeout: 5))
        expectedCharge.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.textFields["subscription.editor.service-name"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.editor.next-charge"]
                .waitForExistence(timeout: 5)
        )
    }

    func testUpcomingDistinguishesConfirmedPaymentsWithoutColorOnly() {
        let app = launchTask6Fixture(timeZoneIdentifier: "UTC")

        topLevelTab("Upcoming", in: app).tap()
        let due = upcomingRow(
            named: Task6Fixture.due,
            identifier: "upcoming.row.expected",
            in: app
        )
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        let confirm = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "upcoming.expected.confirm",
                Task6Fixture.due
            )
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let save = app.buttons["subscription.confirm.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let confirmed = upcomingRow(
            named: Task6Fixture.due,
            identifier: "upcoming.row.confirmed",
            in: app
        )
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
        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
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
        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
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

    func testStartupReconcilesLegacyChatGPTBeforePublishingLibrary() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "reconcile-chatgpt-\(UUID().uuidString)",
            seedsLegacyChatGPTPlus: true
        )

        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("ChatGPT, Plus"))
        XCTAssertFalse(row.label.contains("ChatGPT Plus,"))
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

    func testCreatesMonthlySubscriptionAndOpensItsEditor() {
        let storeToken = "create-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )

        openManualAdd(in: app)
        fillRequiredEditorFacts(
            serviceName: "Example Video",
            amount: "12.34",
            in: app
        )
        fillOptionalEditorDetails(
            plan: "Standard",
            category: "Entertainment",
            in: app
        )

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

        row.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"]
                .waitForExistence(timeout: 5)
        )
        let detailService = app.textFields["subscription.editor.service-name"]
        XCTAssertTrue(detailService.exists)
        XCTAssertEqual(detailService.value as? String, "Example Video")
        let detailAmount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToExistence(detailAmount, in: app, maximumSwipes: 8))
        XCTAssertTrue((detailAmount.value as? String)?.contains("12.34") == true)
        XCTAssertTrue(
            scrollToExistence(
                app.descendants(matching: .any)["subscription.editor.next-charge"],
                in: app,
                maximumSwipes: 8
            )
        )
        let detailPlan = app.textFields["subscription.editor.plan"]
        XCTAssertTrue(scrollToExistence(detailPlan, in: app, maximumSwipes: 8))
        XCTAssertEqual(detailPlan.value as? String, "Standard")
    }

    func testManualAddAllowsEmptyPlanAndCategory() {
        let serviceName = "Minimum Facts \(UUID().uuidString.prefix(8))"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "minimum-facts-\(UUID().uuidString)"
        )

        openManualAdd(in: app)
        fillRequiredEditorFacts(
            serviceName: serviceName,
            amount: "7.50",
            in: app
        )
        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            app.staticTexts[serviceName].waitForExistence(timeout: 5),
            "Plan, category, and notes must remain optional."
        )
    }

    func testManualAddRequiresFiveMinimumFacts() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "required-facts-\(UUID().uuidString)"
        )

        openManualAdd(in: app)
        app.buttons["subscription.form.save"].tap()

        for identifier in [
            "subscription.validation.service-name",
            "subscription.validation.amount",
            "subscription.validation.currency",
            "subscription.validation.billing-interval",
            "subscription.validation.billing-date",
        ] {
            XCTAssertTrue(
                scrollToExistence(
                    app.descendants(matching: .any)[identifier],
                    in: app,
                    maximumSwipes: 8
                ),
                "Missing required fact must expose \(identifier)."
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"].exists
        )
    }

    func testEditPriceWritesHistoryAutomatically() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "atomic-edit-price-\(UUID().uuidString)"
        )
        createSubscription(named: "Atomic Price", in: app)
        openFirstSubscriptionEditor(in: app)

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("14.99")
        app.buttons["subscription.form.save"].tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()

        XCTAssertTrue(
            scrollToExistence(
                app.descendants(matching: .any)[
                    "subscription.history.price-change"
                ],
                in: app,
                maximumSwipes: 8
            ),
            "Ordinary Save must record the effective price change atomically."
        )
    }

    func testDateTaskHasExplicitDoneAndCancel() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "date-task-\(UUID().uuidString)"
        )
        createSubscription(named: "Date Task", in: app)
        openFirstSubscriptionEditor(in: app)

        let startDate = app.buttons["subscription.editor.start-date"]
        let nextRenewal = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(scrollToHittable(startDate, in: app, maximumSwipes: 6))
        let originalStart = accessibilityValue(of: startDate)
        let originalRenewal = accessibilityValue(of: nextRenewal)

        startDate.tap()
        let picker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(in: picker, app: app, day: 10)
        XCTAssertTrue(app.buttons["subscription.date-task.done"].exists)
        XCTAssertTrue(app.buttons["subscription.date-task.cancel"].exists)
        app.buttons["subscription.date-task.cancel"].tap()

        XCTAssertEqual(accessibilityValue(of: startDate), originalStart)
        XCTAssertEqual(accessibilityValue(of: nextRenewal), originalRenewal)

        startDate.tap()
        let committedPicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(committedPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: committedPicker,
            app: app,
            day: 11
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "subscription.date-task.source-value"
            ].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "subscription.date-task.counterpart-value"
            ].exists
        )
        app.buttons["subscription.date-task.done"].tap()

        let completedStart = accessibilityValue(of: startDate)
        let completedRenewal = accessibilityValue(of: nextRenewal)
        XCTAssertNotEqual(completedStart, originalStart)
        XCTAssertNotEqual(completedRenewal, originalRenewal)

        // A later edit that is cancelled must not roll back the previously
        // completed Start Date task.
        startDate.tap()
        let reopenedStartPicker = app.datePickers[
            "subscription.date-task.picker"
        ]
        XCTAssertTrue(reopenedStartPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: reopenedStartPicker,
            app: app,
            day: 12
        )
        app.buttons["subscription.date-task.cancel"].tap()
        XCTAssertEqual(accessibilityValue(of: startDate), completedStart)
        XCTAssertEqual(accessibilityValue(of: nextRenewal), completedRenewal)

        // Repeat the same transaction contract for Next Renewal: Cancel is a
        // real no-op, while Done publishes the paired date to the editor.
        nextRenewal.tap()
        let renewalPicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(renewalPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: renewalPicker,
            app: app,
            day: 13
        )
        app.buttons["subscription.date-task.cancel"].tap()
        XCTAssertEqual(accessibilityValue(of: nextRenewal), completedRenewal)

        nextRenewal.tap()
        let committedRenewalPicker = app.datePickers[
            "subscription.date-task.picker"
        ]
        XCTAssertTrue(committedRenewalPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: committedRenewalPicker,
            app: app,
            day: 14
        )
        app.buttons["subscription.date-task.done"].tap()

        let completedNextStart = accessibilityValue(of: startDate)
        let completedNextRenewal = accessibilityValue(of: nextRenewal)
        XCTAssertNotEqual(completedNextRenewal, completedRenewal)

        nextRenewal.tap()
        let reopenedRenewalPicker = app.datePickers[
            "subscription.date-task.picker"
        ]
        XCTAssertTrue(reopenedRenewalPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: reopenedRenewalPicker,
            app: app,
            day: 15
        )
        app.buttons["subscription.date-task.cancel"].tap()
        XCTAssertEqual(accessibilityValue(of: startDate), completedNextStart)
        XCTAssertEqual(
            accessibilityValue(of: nextRenewal),
            completedNextRenewal
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"].exists,
            "Done commits only to the editor draft; it must not save or dismiss."
        )
    }

    func testTrialDateTaskDoneAndCancelPreserveIndependentDates() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "trial-date-task-\(UUID().uuidString)"
        )
        createSubscription(
            named: "Trial Date Task",
            statusButton: "Trial",
            in: app
        )
        openFirstSubscriptionEditor(in: app)

        let trialStart = app.buttons["subscription.editor.start-date"]
        let firstPaidCharge = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(scrollToHittable(trialStart, in: app, maximumSwipes: 6))
        let originalStart = accessibilityValue(of: trialStart)
        let originalCharge = accessibilityValue(of: firstPaidCharge)

        trialStart.tap()
        let startPicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(startPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(in: startPicker, app: app, day: 15)
        XCTAssertTrue(app.buttons["subscription.date-task.cancel"].exists)
        app.buttons["subscription.date-task.cancel"].tap()
        XCTAssertEqual(accessibilityValue(of: trialStart), originalStart)
        XCTAssertEqual(accessibilityValue(of: firstPaidCharge), originalCharge)

        trialStart.tap()
        let committedStartPicker = app.datePickers[
            "subscription.date-task.picker"
        ]
        XCTAssertTrue(committedStartPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: committedStartPicker,
            app: app,
            day: 17
        )
        app.buttons["subscription.date-task.done"].tap()
        let committedStart = accessibilityValue(of: trialStart)
        XCTAssertNotEqual(committedStart, originalStart)
        XCTAssertEqual(accessibilityValue(of: firstPaidCharge), originalCharge)

        trialStart.tap()
        let reopenedStartPicker = app.datePickers[
            "subscription.date-task.picker"
        ]
        XCTAssertTrue(reopenedStartPicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: reopenedStartPicker,
            app: app,
            day: 18
        )
        app.buttons["subscription.date-task.cancel"].tap()
        XCTAssertEqual(accessibilityValue(of: trialStart), committedStart)
        XCTAssertEqual(accessibilityValue(of: firstPaidCharge), originalCharge)

        XCTAssertTrue(
            scrollToHittable(firstPaidCharge, in: app, maximumSwipes: 6)
        )
        firstPaidCharge.tap()
        let chargePicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(chargePicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(in: chargePicker, app: app, day: 16)
        XCTAssertTrue(app.buttons["subscription.date-task.cancel"].exists)
        app.buttons["subscription.date-task.cancel"].tap()
        XCTAssertEqual(accessibilityValue(of: trialStart), committedStart)
        XCTAssertEqual(accessibilityValue(of: firstPaidCharge), originalCharge)

        firstPaidCharge.tap()
        let committedChargePicker = app.datePickers[
            "subscription.date-task.picker"
        ]
        XCTAssertTrue(committedChargePicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: committedChargePicker,
            app: app,
            day: 19
        )
        app.buttons["subscription.date-task.done"].tap()
        let committedCharge = accessibilityValue(of: firstPaidCharge)
        XCTAssertEqual(accessibilityValue(of: trialStart), committedStart)
        XCTAssertNotEqual(committedCharge, originalCharge)

        firstPaidCharge.tap()
        let reopenedChargePicker = app.datePickers[
            "subscription.date-task.picker"
        ]
        XCTAssertTrue(reopenedChargePicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: reopenedChargePicker,
            app: app,
            day: 20
        )
        app.buttons["subscription.date-task.cancel"].tap()
        XCTAssertEqual(accessibilityValue(of: trialStart), committedStart)
        XCTAssertEqual(accessibilityValue(of: firstPaidCharge), committedCharge)
    }

    func testVerifiedOfferKeepsEvidencedDefaultsUntilExplicitOverride() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "verified-defaults-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        let plan = app.buttons["subscription.form.offer-plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        plan.tap()
        app.buttons["Pro (5x)"].tap()

        let amount = app.textFields["subscription.editor.amount"]
        let currency = app.buttons["subscription.editor.currency"]
        let interval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(scrollToHittable(amount, in: app, maximumSwipes: 8))
        XCTAssertTrue((amount.value as? String)?.contains("100") == true)
        XCTAssertTrue(currency.label.contains("USD"))

        XCTAssertTrue(scrollToHittable(interval, in: app, maximumSwipes: 8))
        XCTAssertTrue(interval.label.contains("Monthly"))
        interval.tap()
        app.buttons["Yearly"].tap()

        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )
        XCTAssertTrue(scrollBackToHittable(amount, in: app, maximumSwipes: 8))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("101")
        app.buttons["subscription.form.save"].tap()

        app.terminate()
        app.launch()
        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        waitForCurrentSubscriptionEditor(in: app)

        let reloadedAmount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToHittable(reloadedAmount, in: app, maximumSwipes: 8))
        XCTAssertTrue((reloadedAmount.value as? String)?.contains("101") == true)
        let reloadedInterval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(scrollToHittable(reloadedInterval, in: app, maximumSwipes: 8))
        XCTAssertTrue(reloadedInterval.label.contains("Yearly"))
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "subscription.editor.user-adjusted-price"
            ].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "subscription.editor.user-adjusted-schedule"
            ].waitForExistence(timeout: 5)
        )
    }

    func testSubscriptionRowOpensOneSummarySheet() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "summary-sheet-\(UUID().uuidString)"
        )
        createSubscription(named: "Summary Card", in: app)

        let row = subscriptionRow(named: "Summary Card", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.summary"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.form"].exists
        )
        for identifier in [
            "subscription.summary.service",
            "subscription.summary.amount",
            "subscription.summary.interval",
            "subscription.summary.next-renewal",
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].exists,
                "Summary is missing \(identifier)."
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.summary.amount"]
                .label.contains("USD")
        )
    }

    func testSubscriptionSummarySwitchesToEditorInSameSheet() {
        let app = launchTask6Fixture()
        let row = subscriptionRow(
            named: Task6Fixture.directEditor,
            in: app
        )
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let unlabeledChevron = row.images.matching(
            NSPredicate(format: "label == '' AND identifier == ''")
        ).firstMatch
        XCTAssertFalse(
            unlabeledChevron.exists,
            "A subscription row must not expose a second unlabeled chevron."
        )

        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.summary"]
                .waitForExistence(timeout: 5)
        )
        let navigationBarCount = app.navigationBars.count
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        let editor = app.descendants(matching: .any)["subscription.form"]
        XCTAssertTrue(
            editor.waitForExistence(timeout: 5),
            "Editing must replace the summary in the same presentation."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.summary"].exists
        )
        XCTAssertEqual(
            app.navigationBars.count,
            navigationBarCount,
            "Edit must not add a navigation page."
        )
        for identifier in [
            "subscription.editor.service-name",
            "subscription.editor.amount",
            "subscription.editor.billing-interval",
            "subscription.editor.start-date",
            "subscription.editor.next-renewal",
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].exists,
                "Direct editor is missing (identifier)."
            )
        }
        XCTAssertFalse(app.buttons["subscription.lifecycle.actions"].exists)
        XCTAssertFalse(app.buttons["subscription.edit"].exists)

        let lifecycle = app.descendants(matching: .any)[
            "subscription.lifecycle.section"
        ]
        XCTAssertTrue(
            scrollToExistence(lifecycle, in: app, maximumSwipes: 12),
            "Lifecycle section must remain reachable in the direct editor."
        )
        let recordCancellation = app.descendants(matching: .any)[
            "subscription.lifecycle.record-cancellation"
        ]
        XCTAssertTrue(
            scrollToExistence(recordCancellation, in: app, maximumSwipes: 12),
            "Active subscriptions keep cancellation in Lifecycle."
        )
        XCTAssertFalse(app.buttons["subscription.lifecycle.archive"].exists)
        XCTAssertFalse(app.buttons["subscription.lifecycle.delete"].exists)
    }

    func testSubscriptionEditSaveUpdatesSummary() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "summary-save-\(UUID().uuidString)"
        )
        createSubscription(named: "Summary Save", in: app)
        openFirstSubscriptionEditor(in: app)

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToHittable(amount, in: app, maximumSwipes: 8))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("14.99")
        app.buttons["subscription.form.save"].tap()

        let summaryAmount = app.descendants(matching: .any)[
            "subscription.summary.amount"
        ]
        XCTAssertTrue(summaryAmount.waitForExistence(timeout: 5))
        XCTAssertTrue(summaryAmount.label.contains("14.99"))
        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.form"].exists
        )
    }

    func testSubscriptionEditCancelLeavesDataUnchanged() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "summary-cancel-\(UUID().uuidString)"
        )
        createSubscription(named: "Summary Cancel", in: app)
        let row = subscriptionRow(named: "Summary Cancel", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let originalAmount = app.descendants(matching: .any)[
            "subscription.summary.amount"
        ]
        XCTAssertTrue(originalAmount.waitForExistence(timeout: 5))
        let originalAmountLabel = originalAmount.label
        app.buttons["subscription.edit"].tap()

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToHittable(amount, in: app, maximumSwipes: 8))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("24.99")
        app.buttons["subscription.form.cancel"].tap()

        XCTAssertTrue(originalAmount.waitForExistence(timeout: 5))
        XCTAssertEqual(originalAmount.label, originalAmountLabel)
        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.form"].exists
        )
    }

    func testEditorHidesRemovedFieldsAndPreservesCategoryAndNotes() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "editor-cleanup-\(UUID().uuidString)"
        )
        openManualAdd(in: app)
        fillRequiredEditorFacts(
            serviceName: "Clean Editor",
            amount: "8.99",
            in: app
        )

        let category = app.textFields["subscription.editor.category"]
        XCTAssertTrue(scrollToHittable(category, in: app, maximumSwipes: 8))
        category.tap()
        category.typeText("Software")

        let notes = app.descendants(matching: .any)["subscription.editor.notes"]
        XCTAssertTrue(scrollToHittable(notes, in: app, maximumSwipes: 8))
        notes.tap()
        notes.typeText("Keep for work")

        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.editor.status"].exists
        )
        XCTAssertFalse(
            app.textFields["subscription.editor.management-url"].exists
        )
        XCTAssertFalse(app.links["subscription.editor.management-url"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "Open the provider's billing, renewal, or cancellation page; this app will not cancel the subscription for you."
            ].exists
        )

        let form = app.descendants(matching: .any)["subscription.form"]
        app.buttons["subscription.form.save"].tap()
        XCTAssertTrue(form.waitForNonExistence(timeout: 5))
        let row = subscriptionRow(named: "Clean Editor", in: app)
        XCTAssertTrue(scrollToHittable(row, in: app, maximumSwipes: 4))
        let serviceLabel = app.staticTexts["Clean Editor"]
        XCTAssertTrue(serviceLabel.waitForExistence(timeout: 5))
        serviceLabel.tap()

        let summary = app.descendants(matching: .any)["subscription.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))

        let summaryCategory = app.descendants(matching: .any)[
            "subscription.summary.category"
        ]
        let summaryNote = app.descendants(matching: .any)[
            "subscription.summary.note"
        ]
        XCTAssertTrue(summaryCategory.waitForExistence(timeout: 5))
        XCTAssertTrue(summaryNote.waitForExistence(timeout: 5))
        XCTAssertTrue(summaryCategory.label.contains("Software"))
        XCTAssertTrue(summaryNote.label.contains("Keep for work"))

        let edit = app.buttons["subscription.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.editor.status"].exists
        )
        let editorNotes = app.descendants(matching: .any)[
            "subscription.editor.notes"
        ]
        XCTAssertTrue(
            scrollToExistence(editorNotes, in: app, maximumSwipes: 8)
        )
        XCTAssertFalse(
            app.staticTexts[
                "Open the provider's billing, renewal, or cancellation page; this app will not cancel the subscription for you."
            ].exists
        )
    }

    func testFailedOrdinarySaveKeepsEditorAndDraft() {
        let app = launchTask6Fixture(failsLifecycleMutations: true)
        openTask6Editor(named: Task6Fixture.directEditor, in: app)

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToHittable(amount, in: app, maximumSwipes: 8))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("47")
        app.buttons["subscription.form.save"].tap()

        let saveError = app.staticTexts["subscription.validation.save"]
        XCTAssertTrue(
            scrollToExistence(saveError, in: app, maximumSwipes: 12),
            "A failed Save must explain the failure without replacing the editor."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"].exists
        )
        XCTAssertTrue(scrollBackToHittable(amount, in: app, maximumSwipes: 12))
        XCTAssertTrue(
            (amount.value as? String)?.contains("47") == true,
            "A failed Save must keep the user's edited amount in the draft."
        )
    }

    func testArchivedRowOpensEditorWithExternalRestore() {
        let storeToken = "archived-editor-\(UUID().uuidString)"
        let app = launchTask6Fixture(storeToken: storeToken)
        let currentRow = subscriptionRow(
            named: Task6Fixture.archivedEditor,
            in: app
        )
        XCTAssertTrue(currentRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: currentRow)
        let archive = app.buttons["subscription.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        waitForLifecyclePersistence()

        app.terminate()
        let archivedApp = launchTask6Fixture(
            storeToken: storeToken,
            opensArchivedLibrary: true
        )
        let archivedRow = subscriptionRow(
            named: Task6Fixture.archivedEditor,
            in: archivedApp
        )
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 5))
        archivedRow.tap()
        XCTAssertTrue(
            archivedApp.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        archivedApp.buttons["subscription.edit"].tap()

        let editor = archivedApp.descendants(matching: .any)["subscription.form"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let status = archivedApp.descendants(matching: .any)[
            "subscription.editor.status"
        ]
        XCTAssertTrue(scrollToExistence(status, in: archivedApp, maximumSwipes: 12))
        XCTAssertTrue(status.label.contains("Archived"))
        XCTAssertFalse(archivedApp.buttons["subscription.lifecycle.actions"].exists)
        XCTAssertFalse(archivedApp.buttons["subscription.edit"].exists)
        XCTAssertFalse(
            archivedApp.buttons["subscription.lifecycle.restore"].exists,
            "Restore stays on the archived library surface."
        )
        XCTAssertFalse(
            archivedApp.buttons["subscription.lifecycle.delete"].exists,
            "Delete stays on the archived library surface."
        )

        archivedApp.terminate()
        let reopenedArchivedApp = launchTask6Fixture(
            storeToken: storeToken,
            opensArchivedLibrary: true
        )
        let archivedListRow = subscriptionRow(
            named: Task6Fixture.archivedEditor,
            in: reopenedArchivedApp
        )
        XCTAssertTrue(archivedListRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: archivedListRow)
        XCTAssertTrue(
            reopenedArchivedApp.buttons["subscription.restore"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            reopenedArchivedApp.buttons["subscription.delete"]
                .waitForExistence(timeout: 5)
        )
    }

    func testOnlyDueExpectedOccurrenceOffersConfirmCharge() {
        let app = launchTask6Fixture(timeZoneIdentifier: "UTC")
        topLevelTab("Upcoming", in: app).tap()

        let due = upcomingRow(
            named: Task6Fixture.due,
            identifier: "upcoming.row.expected",
            in: app
        )
        let future = upcomingRow(
            named: Task6Fixture.future,
            identifier: "upcoming.row.expected",
            in: app
        )
        let confirmed = upcomingRow(
            named: Task6Fixture.confirmed,
            identifier: "upcoming.row.confirmed",
            in: app
        )
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmed.waitForExistence(timeout: 5))

        let dueConfirm = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "upcoming.expected.confirm",
                Task6Fixture.due
            )
        ).firstMatch
        XCTAssertTrue(
            dueConfirm.waitForExistence(timeout: 5),
            "Only a due expected occurrence gets Confirm Charge."
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "upcoming.expected.confirm",
                    Task6Fixture.future
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "upcoming.expected.confirm",
                    Task6Fixture.confirmed
                )
            ).firstMatch.exists
        )

        app.buttons["upcoming.month.next"].tap()
        XCTAssertTrue(scrollToExistence(future, in: app, maximumSwipes: 6))
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "upcoming.expected.confirm",
                    Task6Fixture.future
                )
            ).firstMatch.exists
        )

        app.buttons["upcoming.month.previous"].tap()
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        let dueConfirmAfterReturning = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "upcoming.expected.confirm",
                Task6Fixture.due
            )
        ).firstMatch
        XCTAssertTrue(dueConfirmAfterReturning.waitForExistence(timeout: 5))
        dueConfirmAfterReturning.tap()
        XCTAssertTrue(
            app.navigationBars["Confirm Charge"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["subscription.confirm.save"].exists)
        let cancel = app.navigationBars["Confirm Charge"].buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
    }

    func testConfirmChargeFallbackRemainsUntilBatchB() {
        let successToken = "task6-confirm-success-\(UUID().uuidString)"
        let successApp = launchTask6Fixture(storeToken: successToken)
        openTask6Editor(named: Task6Fixture.overdue, in: successApp)

        let expected = successApp.descendants(matching: .any)[
            "subscription.history.expected"
        ]
        XCTAssertTrue(
            scrollToExistence(expected, in: successApp, maximumSwipes: 12)
        )
        let expectedConfirm = expected.descendants(matching: .any)[
            "subscription.history.expected.confirm"
        ]
        XCTAssertTrue(expectedConfirm.waitForExistence(timeout: 5))
        expectedConfirm.tap()
        XCTAssertTrue(
            successApp.navigationBars["Confirm Charge"]
                .waitForExistence(timeout: 5)
        )
        let confirmationAmount = successApp.textFields[
            "subscription.confirm.amount"
        ]
        XCTAssertTrue(confirmationAmount.waitForExistence(timeout: 5))
        let successSave = successApp.buttons["subscription.confirm.save"]
        XCTAssertTrue(successSave.waitForExistence(timeout: 5))
        successSave.tap()

        let confirmed = successApp.descendants(matching: .any)[
            "subscription.history.confirmed"
        ]
        XCTAssertTrue(
            scrollToExistence(confirmed, in: successApp, maximumSwipes: 12),
            "The confirmed occurrence remains visible in Payment History."
        )
        XCTAssertFalse(
            successApp.descendants(matching: .any)["subscription.history.expected"]
                .descendants(matching: .any)[
                    "subscription.history.expected.confirm"
                ].exists
        )

        successApp.terminate()
        successApp.launch()
        openTask6Editor(named: Task6Fixture.overdue, in: successApp)
        let reloadedConfirmed = successApp.descendants(matching: .any)[
            "subscription.history.confirmed"
        ]
        XCTAssertTrue(
            scrollToExistence(
                reloadedConfirmed,
                in: successApp,
                maximumSwipes: 12
            ),
            "Reload keeps the single visible confirmed occurrence."
        )
        XCTAssertFalse(
            successApp.descendants(matching: .any)["subscription.history.expected"]
                .descendants(matching: .any)[
                    "subscription.history.expected.confirm"
                ].exists
        )

        let failureToken = "task6-confirm-failure-\(UUID().uuidString)"
        let failureApp = launchTask6Fixture(
            storeToken: failureToken,
            failsLifecycleMutations: true
        )
        openTask6Editor(named: Task6Fixture.overdue, in: failureApp)
        let failureExpected = failureApp.descendants(matching: .any)[
            "subscription.history.expected"
        ]
        XCTAssertTrue(
            scrollToExistence(failureExpected, in: failureApp, maximumSwipes: 12)
        )
        let failureConfirm = failureExpected.descendants(matching: .any)[
            "subscription.history.expected.confirm"
        ]
        XCTAssertTrue(
            failureConfirm.waitForExistence(timeout: 5)
        )
        failureConfirm.tap()
        let failureSave = failureApp.buttons["subscription.confirm.save"]
        XCTAssertTrue(failureSave.waitForExistence(timeout: 5))
        failureSave.tap()
        XCTAssertTrue(
            failureApp.descendants(matching: .any)[
                "subscription.confirm.error"
            ].waitForExistence(timeout: 5)
        )
        let failureCancel = failureApp.navigationBars["Confirm Charge"]
            .buttons["Cancel"]
        XCTAssertTrue(failureCancel.waitForExistence(timeout: 5))
        failureCancel.tap()
        let failureExpectedAfterDismiss = failureApp.descendants(matching: .any)[
            "subscription.history.expected"
        ]
        XCTAssertTrue(
            scrollToExistence(
                failureExpectedAfterDismiss,
                in: failureApp,
                maximumSwipes: 12
            )
        )
        XCTAssertTrue(
            failureExpectedAfterDismiss.descendants(matching: .any)[
                "subscription.history.expected.confirm"
            ].exists,
            "A failed confirmation keeps the expected row actionable."
        )
    }

    func testCatalogRenameClearsStaleIdentityWhilePriceOverrideRetainsIt() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-edit-identity-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()
        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )
        app.buttons["subscription.form.save"].tap()

        // The workspace reloads the underlying library before the catalog
        // sheet finishes dismissing. Wait for that presentation boundary so
        // the row tap cannot land on the covered library during the transition.
        XCTAssertTrue(
            app.descendants(matching: .any)["catalog.list"]
                .waitForNonExistence(timeout: 5),
            "Catalog flow must dismiss before the saved row is reopened."
        )

        openSubscriptionEditor(named: "ChatGPT", in: app)
        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("9")
        app.buttons["subscription.form.save"].tap()

        openCurrentSubscriptionEditor(in: app)
        let retainedName = app.textFields["subscription.editor.service-name"]
        XCTAssertEqual(retainedName.value as? String, "ChatGPT")
        XCTAssertTrue(
            (app.textFields["subscription.editor.amount"].value as? String)?
                .contains("9") == true
        )

        retainedName.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        retainedName.typeText("Personal AI")
        app.buttons["subscription.form.save"].tap()
        openCurrentSubscriptionEditor(in: app)
        XCTAssertEqual(
            app.textFields["subscription.editor.service-name"].value as? String,
            "Personal AI"
        )
        // Exact identity transitions are asserted through the public Workspace
        // seam in SubscriptionWorkspaceTests; this scenario proves the UI
        // sends price-only and rename edits through the same atomic Save path.
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
        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )
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
        XCTAssertFalse(
            app.staticTexts["subscription.form.offer-provenance"].exists
        )

        // Verified metadata is controlled by the selected official offer. The
        // user may choose another offer in the dedicated picker, but should
        // not see a second free-text Service/Plan source that Save would later
        // overwrite from the catalog.
        XCTAssertFalse(app.textFields["subscription.editor.service-name"].exists)
        XCTAssertFalse(app.textFields["subscription.editor.plan"].exists)
        XCTAssertTrue(
            app.buttons["subscription.form.offer-plan"].label
                .contains("Pro (5x)")
        )

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToExistence(amount, in: app, maximumSwipes: 8))
        XCTAssertTrue((amount.value as? String)?.contains("100") == true)

        let currency = app.buttons["subscription.editor.currency"]
        XCTAssertTrue(scrollToExistence(currency, in: app, maximumSwipes: 8))
        XCTAssertTrue(currency.label.contains("USD"))

        let interval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(scrollToExistence(interval, in: app, maximumSwipes: 8))
        XCTAssertTrue(interval.label.contains("Monthly"))

        XCTAssertFalse(app.links["subscription.form.offer-source"].exists)
        XCTAssertFalse(app.staticTexts["Official Pricing Source"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "Official prices may vary by region, tax, and storefront."
            ].exists
        )
    }

    func testChinaCatalogOfferPrefillsEditableAnnualCNY() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "jd-plus-offer-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()

        let jdPlus = app.buttons["catalog.preset.jd-plus"]
        XCTAssertTrue(scrollToExistence(jdPlus, in: app))
        jdPlus.tap()

        let plan = app.buttons["subscription.form.offer-plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        XCTAssertTrue(plan.label.contains("JD PLUS Annual"))

        let price = app.descendants(matching: .any)[
            "subscription.form.selected-price"
        ]
        XCTAssertTrue(price.label.contains("99"))

        let currency = app.buttons["subscription.editor.currency"]
        XCTAssertTrue(scrollToExistence(currency, in: app, maximumSwipes: 8))
        XCTAssertTrue(currency.label.contains("CNY"))

        let interval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(scrollToExistence(interval, in: app, maximumSwipes: 8))
        XCTAssertTrue(interval.label.contains("Yearly"))
        attachScreenshot(named: "r2-06-jd-plus-cny-yearly")

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToHittable(amount, in: app, maximumSwipes: 8))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("100")
        XCTAssertEqual(amount.value as? String, "100")
    }

    func testOfficialOfferAmountValidationIsInline() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-inline-amount-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToHittable(amount, in: app, maximumSwipes: 8))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("0")
        XCTAssertEqual(amount.value as? String, "0")

        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )

        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["subscription.validation.amount"].exists
        )
    }

    func testOfficialOfferBillingErrorStaysInline() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "catalog-inline-interval-\(UUID().uuidString)"
        )
        app.buttons["subscription.add"].tap()
        let chatGPT = app.buttons["catalog.preset.chatgpt"]
        XCTAssertTrue(scrollToExistence(chatGPT, in: app))
        chatGPT.tap()

        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )

        let billingInterval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(
            scrollToHittable(billingInterval, in: app, maximumSwipes: 8)
        )
        billingInterval.tap()
        app.buttons["Custom"].tap()

        let customValue = app.textFields["subscription.editor.custom-interval-value"]
        XCTAssertTrue(customValue.waitForExistence(timeout: 5))
        customValue.tap()
        customValue.typeText("0")
        let customUnit = app.buttons["subscription.editor.custom-interval-unit"]
        customUnit.tap()
        app.buttons["Weeks"].tap()

        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            scrollToExistence(customValue, in: app, maximumSwipes: 4)
        )
        XCTAssertEqual(customValue.value as? String, "0")
        XCTAssertTrue(
            app.buttons["subscription.editor.custom-interval-unit"]
                .label.contains("Weeks")
        )
        XCTAssertTrue(
            app.staticTexts["subscription.validation.billing-interval"]
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

        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )

        let billingInterval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(
            scrollToHittable(billingInterval, in: app, maximumSwipes: 8)
        )
        billingInterval.tap()
        app.buttons["Yearly"].tap()
        app.buttons["subscription.form.save"].tap()

        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        let yearlySchedule = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(
            scrollToExistence(yearlySchedule, in: app, maximumSwipes: 8)
        )
        XCTAssertTrue(yearlySchedule.label.contains("Yearly"))
        let detailStartDate = app.buttons["subscription.editor.start-date"]
        XCTAssertTrue(
            scrollToExistence(detailStartDate, in: app, maximumSwipes: 8)
        )
        let startValue = accessibilityValue(of: detailStartDate)
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
        let detailNextRenewal = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(
            scrollToExistence(
                detailNextRenewal,
                in: app,
                maximumSwipes: 8
            )
        )
        XCTAssertTrue(
            accessibilityValue(of: detailNextRenewal) == expectedRenewalValue,
            "Untouched Next Renewal must follow the selected interval."
        )
    }

    func testAddFormLinksBillingDatesInBothDirections() throws {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "add-linked-dates-\(UUID().uuidString)"
        )
        openManualAdd(in: app)
        fillRequiredEditorFacts(
            serviceName: "Linked Dates",
            amount: "9.99",
            in: app
        )

        let nextRenewal = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(scrollToHittable(nextRenewal, in: app, maximumSwipes: 6))
        let initialStartDate = accessibilityValue(
            of: app.buttons["subscription.editor.start-date"]
        )
        nextRenewal.tap()
        let nextPicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(nextPicker.waitForExistence(timeout: 5))
        let selectedNextRenewal = selectDateTaskInNextMonth(
            in: nextPicker,
            app: app,
            day: 10
        )
        app.buttons["subscription.date-task.done"].tap()

        let startDate = app.buttons["subscription.editor.start-date"]
        XCTAssertTrue(scrollToHittable(startDate, in: app, maximumSwipes: 6))
        let selectedStartDate = accessibilityValue(of: startDate)
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
        XCTAssertNotEqual(selectedStartDate, initialStartDate)

        startDate.tap()
        let startPicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(startPicker.waitForExistence(timeout: 5))
        let editedStartDate = selectDateTaskInNextMonth(
            in: startPicker,
            app: app,
            day: 12
        )
        app.buttons["subscription.date-task.done"].tap()
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
        XCTAssertTrue(scrollToHittable(nextRenewal, in: app, maximumSwipes: 6))
        XCTAssertEqual(
            accessibilityValue(of: nextRenewal),
            localizedDateValue(
                expectedNextRenewal,
                locale: locale,
                calendar: calendar
            )
        )
    }

    func testTrialFormKeepsTrialStartAndFirstPaidChargeIndependent() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "trial-independent-dates-\(UUID().uuidString)"
        )
        openManualAdd(in: app)
        let initialStatus = app.segmentedControls["subscription.form.initial-status"]
        XCTAssertTrue(initialStatus.waitForExistence(timeout: 5))
        initialStatus.buttons["Trial"].tap()
        fillRequiredEditorFacts(
            serviceName: "Trial Dates",
            amount: "9.99",
            in: app
        )
        let firstPaidCharge = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(scrollToHittable(firstPaidCharge, in: app, maximumSwipes: 6))
        XCTAssertTrue(app.staticTexts["First Paid Charge"].exists)
        acceptEditorDate(
            identifier: "subscription.editor.next-renewal",
            in: app
        )

        let trialStart = app.buttons["subscription.editor.start-date"]
        XCTAssertTrue(scrollToHittable(trialStart, in: app, maximumSwipes: 6))
        XCTAssertTrue(app.staticTexts["Trial Start"].exists)
        let originalTrialStart = accessibilityValue(of: trialStart)

        XCTAssertTrue(
            scrollToHittable(firstPaidCharge, in: app, maximumSwipes: 6)
        )
        firstPaidCharge.tap()
        let chargePicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(chargePicker.waitForExistence(timeout: 5))
        _ = selectDateTaskInNextMonth(
            in: chargePicker,
            app: app,
            day: 10
        )
        app.buttons["subscription.date-task.done"].tap()

        XCTAssertTrue(scrollToHittable(trialStart, in: app, maximumSwipes: 6))
        XCTAssertEqual(accessibilityValue(of: trialStart), originalTrialStart)
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
            app.buttons["catalog.category"].label.contains("Category")
                || app.buttons["catalog.category"].label.contains("Categories")
        )

        let reopenedSearch = app.searchFields.firstMatch
        reopenedSearch.tap()
        reopenedSearch.typeText("ChatGPT")
        app.buttons["catalog.preset.chatgpt"].tap()
        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )
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
            app.buttons["catalog.category"].label.contains("Category")
                || app.buttons["catalog.category"].label.contains("Categories")
        )
    }

    func testCatalogAICategoryUsesLocalizedStableFilter() {
        let app = launch(language: "zh-Hans", locale: "zh_CN")
        app.buttons["subscription.add"].tap()
        app.buttons["catalog.category"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)
        ).tap()

        let aiCategory = app.buttons["AI 工具"]
        XCTAssertTrue(aiCategory.waitForExistence(timeout: 5))
        aiCategory.tap()

        XCTAssertTrue(app.buttons["catalog.preset.chatgpt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["catalog.preset.wps-office"].exists)
        XCTAssertTrue(app.buttons["catalog.category"].label.contains("AI 工具"))
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

    func testCreatesTrialWithoutEditorStatusRow() {
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
        let trialRow = subscriptionRow(named: "Example Trial", in: app)
        XCTAssertTrue(trialRow.waitForExistence(timeout: 5))
        trialRow.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()

        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.editor.status"].exists
        )
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

        let row = app.buttons.matching(
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

        revealTrailingActions(on: row)
        app.buttons["subscription.delete"].tap()

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

        revealTrailingActions(on: row)
        app.buttons["subscription.delete"].tap()
        confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete Permanently"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
    }

    func testArchivedRowsSwipeToRestoreOrConfirmedDelete() {
        let serviceName = "Swipe Archive"
        let storeToken = "swipe-archive-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
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
        waitForLifecyclePersistence()

        app.terminate()
        let archivedApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            opensArchivedLibrary: true
        )
        row = archivedApp.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        revealTrailingActions(on: row)
        XCTAssertTrue(
            archivedApp.buttons["subscription.delete"].waitForExistence(timeout: 5)
        )
        let restore = archivedApp.buttons["subscription.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(archivedApp.buttons["subscription.pin"].exists)
        restore.tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))

        archivedApp.terminate()
        let restoredApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        XCTAssertTrue(restoredApp.staticTexts[serviceName].waitForExistence(timeout: 5))

        row = restoredApp.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        revealTrailingActions(on: row)
        restoredApp.buttons["subscription.archive"].tap()
        waitForLifecyclePersistence()
        restoredApp.terminate()

        let archivedDeleteApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            opensArchivedLibrary: true
        )
        row = archivedDeleteApp.buttons.matching(
            identifier: "subscription.row"
        )
        .matching(
            NSPredicate(format: "label CONTAINS %@", serviceName)
        )
        .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        triggerFullTrailingSwipe(on: row)
        let confirmation = archivedDeleteApp.alerts.firstMatch
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

        revealTrailingActions(on: row)
        failingApp.buttons["subscription.delete"].tap()
        let confirmation = failingApp.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete Permanently"].tap()
        error = failingApp.alerts["Couldn’t Complete Action"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
    }

    func testSimplifiedChineseEditorHidesLifecycleStatus() {
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
        let trialRow = subscriptionRow(named: "示例试用", in: app)
        XCTAssertTrue(scrollToHittable(trialRow, in: app, maximumSwipes: 4))
        let serviceLabel = app.staticTexts["示例试用"]
        XCTAssertTrue(serviceLabel.waitForExistence(timeout: 5))
        serviceLabel.tap()
        let edit = app.buttons["subscription.edit"]
        XCTAssertTrue(
            edit.waitForExistence(timeout: 5)
        )
        edit.tap()

        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.editor.status"].exists
        )
    }

    func testArchivesAndRestoresSubscription() {
        let serviceName = "Example Archive"
        let storeToken = "archive-restore-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        createSubscription(
            named: serviceName,
            plan: "Trial",
            statusButton: "Trial",
            in: app
        )

        let currentRow = subscriptionRow(named: serviceName, in: app)
        XCTAssertTrue(currentRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: currentRow)
        let archive = app.buttons["subscription.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["Example Archive"].exists)
        waitForLifecyclePersistence()

        app.terminate()
        let archivedApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            opensArchivedLibrary: true
        )

        XCTAssertTrue(archivedApp.navigationBars["Archived"].waitForExistence(timeout: 5))
        XCTAssertTrue(archivedApp.staticTexts["Example Archive"].waitForExistence(timeout: 5))
        let archivedRow = subscriptionRow(named: serviceName, in: archivedApp)
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(archivedRow.label.contains("Trial"))

        archivedRow.tap()
        XCTAssertTrue(
            archivedApp.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        archivedApp.buttons["subscription.edit"].tap()
        XCTAssertTrue(
            archivedApp.descendants(matching: .any)["subscription.form"]
                .waitForExistence(timeout: 5)
        )
        let archivedStatus = archivedApp.descendants(matching: .any)[
            "subscription.editor.status"
        ]
        XCTAssertTrue(
            scrollToExistence(archivedStatus, in: archivedApp, maximumSwipes: 12)
        )
        XCTAssertFalse(archivedApp.buttons["subscription.lifecycle.restore"].exists)
        XCTAssertFalse(archivedApp.buttons["subscription.lifecycle.delete"].exists)

        // The detail card is presented as a sheet. Return to the archived
        // library through a fresh launch instead of relying on the old pushed
        // navigation bar back button.
        archivedApp.terminate()
        let archivedListApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            opensArchivedLibrary: true
        )
        let archivedListRow = subscriptionRow(
            named: serviceName,
            in: archivedListApp
        )
        XCTAssertTrue(archivedListRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: archivedListRow)
        let restore = archivedListApp.buttons["subscription.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()

        XCTAssertTrue(
            archivedListApp.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(archivedListApp.staticTexts["Example Archive"].exists)

        archivedListApp.terminate()
        let restoredApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        XCTAssertTrue(restoredApp.staticTexts["Example Archive"].waitForExistence(timeout: 5))
        let restoredRow = subscriptionRow(named: serviceName, in: restoredApp)
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredRow.label.contains("Trial"))
    }

    func testPermanentDeleteRequiresConfirmation() {
        let serviceName = "Example Delete"
        let storeToken = "permanent-delete-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        createSubscription(
            named: serviceName,
            plan: "Trial",
            statusButton: "Trial",
            in: app
        )

        let currentRow = subscriptionRow(named: serviceName, in: app)
        XCTAssertTrue(currentRow.waitForExistence(timeout: 5))
        XCTAssertTrue(currentRow.label.contains("Trial"))
        revealTrailingActions(on: currentRow)
        let archive = app.buttons["subscription.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["library.empty-state"]
                .waitForExistence(timeout: 5)
        )
        waitForLifecyclePersistence()

        app.terminate()
        let archivedApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            opensArchivedLibrary: true
        )
        XCTAssertTrue(archivedApp.staticTexts[serviceName].waitForExistence(timeout: 5))
        let archivedRow = subscriptionRow(named: serviceName, in: archivedApp)
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 5))
        archivedRow.tap()
        XCTAssertTrue(
            archivedApp.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        archivedApp.buttons["subscription.edit"].tap()

        let archivedStatus = archivedApp.descendants(matching: .any)[
            "subscription.editor.status"
        ]
        XCTAssertTrue(
            scrollToExistence(archivedStatus, in: archivedApp, maximumSwipes: 12)
        )
        XCTAssertFalse(archivedApp.buttons["subscription.lifecycle.restore"].exists)
        XCTAssertFalse(archivedApp.buttons["subscription.lifecycle.delete"].exists)
        archivedApp.terminate()
        let archivedListApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            opensArchivedLibrary: true
        )
        let archivedListRow = subscriptionRow(
            named: serviceName,
            in: archivedListApp
        )
        XCTAssertTrue(archivedListRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: archivedListRow)
        XCTAssertTrue(archivedListApp.buttons["subscription.delete"].waitForExistence(timeout: 5))
        let confirmation = archivedListApp.alerts.firstMatch
        triggerFullTrailingSwipe(on: archivedListRow)
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
        let cancel = confirmation.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        triggerFullTrailingSwipe(on: archivedListRow)
        let confirmedDeletion = archivedListApp.alerts.firstMatch
        XCTAssertTrue(confirmedDeletion.waitForExistence(timeout: 5))
        confirmedDeletion.buttons["Delete Permanently"].tap()

        XCTAssertTrue(
            archivedListRow.waitForNonExistence(timeout: 5),
            "Permanent deletion removes the archived list row after confirmation."
        )
    }

    func testFailedDirectActionsShowErrorAndKeepLibraryRows() {
        let storeToken = "direct-action-error-\(UUID().uuidString)"
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken
        )
        createSubscription(named: "Current Failure", in: app)
        createSubscription(named: "Archived Failure", in: app)
        let archivedRow = subscriptionRow(named: "Archived Failure", in: app)
        XCTAssertTrue(archivedRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: archivedRow)
        XCTAssertTrue(app.buttons["subscription.archive"].waitForExistence(timeout: 5))
        app.buttons["subscription.archive"].tap()
        XCTAssertTrue(
            app.staticTexts["Current Failure"].waitForExistence(timeout: 5)
        )
        waitForLifecyclePersistence()
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
        let currentRow = subscriptionRow(named: "Current Failure", in: failingApp)
        XCTAssertTrue(currentRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: currentRow)
        XCTAssertTrue(failingApp.buttons["subscription.archive"].waitForExistence(timeout: 5))
        failingApp.buttons["subscription.archive"].tap()

        let actionError = failingApp.alerts["Couldn’t Complete Action"]
        XCTAssertTrue(actionError.waitForExistence(timeout: 5))
        XCTAssertTrue(
            actionError.staticTexts[
                "Couldn’t save lifecycle changes. Try again."
            ].exists
        )
        XCTAssertTrue(currentRow.exists)
        actionError.buttons["OK"].tap()
        XCTAssertFalse(actionError.exists)
        XCTAssertTrue(currentRow.exists)

        revealTrailingActions(on: currentRow)
        failingApp.buttons["subscription.delete"].tap()
        let confirmation = failingApp.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertFalse(actionError.exists)
        confirmation.buttons["Delete Permanently"].tap()
        XCTAssertTrue(actionError.waitForExistence(timeout: 5))
        XCTAssertTrue(currentRow.exists)
        actionError.buttons["OK"].tap()

        failingApp.terminate()
        let archivedFailingApp = launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            failsLifecycleMutations: true,
            opensArchivedLibrary: true
        )
        XCTAssertTrue(
            archivedFailingApp.staticTexts["Archived Failure"]
                .waitForExistence(timeout: 5)
        )
        let failingArchivedRow = subscriptionRow(
            named: "Archived Failure",
            in: archivedFailingApp
        )
        XCTAssertTrue(failingArchivedRow.waitForExistence(timeout: 5))
        revealTrailingActions(on: failingArchivedRow)
        XCTAssertTrue(
            archivedFailingApp.buttons["subscription.restore"]
                .waitForExistence(timeout: 5)
        )
        archivedFailingApp.buttons["subscription.restore"].tap()

        let archivedActionError = archivedFailingApp.alerts["Couldn’t Complete Action"]
        XCTAssertTrue(archivedActionError.waitForExistence(timeout: 5))
        XCTAssertTrue(
            archivedActionError.staticTexts[
                "Couldn’t save lifecycle changes. Try again."
            ].exists
        )
        XCTAssertTrue(failingArchivedRow.exists)
        archivedActionError.buttons["OK"].tap()
        XCTAssertFalse(archivedActionError.exists)
        XCTAssertTrue(failingArchivedRow.exists)
    }

    func testRecordsCancellationAndHidesNextExpectedCharge() {
        let app = launch(
            language: "en",
            locale: "en_US",
            storeToken: "cancel-\(UUID().uuidString)"
        )
        createSubscription(named: "Example Streaming", in: app)
        app.buttons["subscription.row"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()

        let recordCancellation = app.descendants(matching: .any)[
            "subscription.lifecycle.record-cancellation"
        ]
        XCTAssertTrue(
            scrollToExistence(recordCancellation, in: app, maximumSwipes: 12)
        )
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

        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.editor.status"].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.editor.next-charge"]
                .exists
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
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()

        let startDateField = app.buttons["subscription.editor.start-date"]
        XCTAssertTrue(scrollToExistence(startDateField, in: app, maximumSwipes: 8))
        let startDateValue = accessibilityValue(of: startDateField)

        let recordCancellation = app.descendants(matching: .any)[
            "subscription.lifecycle.record-cancellation"
        ]
        XCTAssertTrue(
            scrollToExistence(recordCancellation, in: app, maximumSwipes: 12)
        )
        recordCancellation.tap()
        XCTAssertTrue(
            app.buttons["subscription.cancellation.save"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["subscription.cancellation.save"].tap()

        let reactivate = app.descendants(matching: .any)[
            "subscription.lifecycle.reactivate"
        ]
        XCTAssertTrue(scrollToExistence(reactivate, in: app, maximumSwipes: 12))
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

        XCTAssertFalse(
            app.descendants(matching: .any)["subscription.editor.status"].exists
        )
        let expectedChargeDate = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(scrollToExistence(expectedChargeDate, in: app, maximumSwipes: 8))
        XCTAssertTrue(
            accessibilityValue(of: expectedChargeDate).contains(confirmedDate),
            "Expected \(accessibilityValue(of: expectedChargeDate)) to contain \(confirmedDate)"
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

        let serviceName = app.textFields["subscription.editor.service-name"]
        XCTAssertTrue(serviceName.waitForExistence(timeout: 5))
        serviceName.tap()
        serviceName.typeText("Example Music")

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToHittable(amount, in: app, maximumSwipes: 6))
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
        openFirstSubscriptionEditor(in: app)

        let billingInterval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(billingInterval.waitForExistence(timeout: 5))
        billingInterval.tap()
        app.buttons["Yearly"].tap()
        let startDateButton = app.buttons["subscription.editor.start-date"]
        let nextRenewalButton = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(
            scrollToExistence(startDateButton, in: app, maximumSwipes: 6)
        )
        let startValue = accessibilityValue(of: startDateButton)
        XCTAssertTrue(
            scrollToExistence(nextRenewalButton, in: app, maximumSwipes: 6)
        )
        let nextRenewalValue = accessibilityValue(of: nextRenewalButton)
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

        let savedRow = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 5))
        savedRow.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        let detailInterval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(detailInterval.waitForExistence(timeout: 5))
        XCTAssertTrue(detailInterval.label.contains("Yearly"))

        app.terminate()
        app.launch()
        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        let relaunchedInterval = app.buttons["subscription.editor.billing-interval"]
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
        openFirstSubscriptionEditor(in: app)

        let nextRenewal = app.buttons["subscription.editor.next-renewal"]
        XCTAssertTrue(scrollToHittable(nextRenewal, in: app, maximumSwipes: 6))
        nextRenewal.tap()
        let nextPicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(nextPicker.waitForExistence(timeout: 5))
        let selectedNextRenewal = selectDateTaskInNextMonth(
            in: nextPicker,
            app: app,
            day: 10
        )
        app.buttons["subscription.date-task.done"].tap()

        let startDate = app.buttons["subscription.editor.start-date"]
        XCTAssertTrue(scrollToHittable(startDate, in: app, maximumSwipes: 6))
        let selectedStartDate = accessibilityValue(of: startDate)
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

        startDate.tap()
        let startPicker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(startPicker.waitForExistence(timeout: 5))
        let editedStartDate = selectDateTaskInNextMonth(
            in: startPicker,
            app: app,
            day: 12
        )
        app.buttons["subscription.date-task.done"].tap()
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
        XCTAssertTrue(scrollToHittable(nextRenewal, in: app, maximumSwipes: 6))
        XCTAssertEqual(
            accessibilityValue(of: nextRenewal),
            localizedDateValue(
                expectedNextRenewal,
                locale: locale,
                calendar: calendar
            )
        )
    }

    func testConfirmsChargeAndRecordsPriceHistory() {
        let app = launchTask6Fixture(
            storeToken: "payment-history-\(UUID().uuidString)"
        )
        openTask6Editor(named: Task6Fixture.overdue, in: app)

        let expected = app.descendants(matching: .any)[
            "subscription.history.expected"
        ]
        XCTAssertTrue(scrollToExistence(expected, in: app, maximumSwipes: 12))
        let confirm = expected.descendants(matching: .any)[
            "subscription.history.expected.confirm"
        ]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let confirmSave = app.buttons["subscription.confirm.save"]
        XCTAssertTrue(confirmSave.waitForExistence(timeout: 5))
        confirmSave.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.history.confirmed"]
                .waitForExistence(timeout: 5)
        )

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollBackToHittable(amount, in: app, maximumSwipes: 8))
        amount.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        amount.typeText("31")
        app.buttons["subscription.form.save"].tap()
        openTask6Editor(named: Task6Fixture.overdue, in: app)
        XCTAssertTrue(
            scrollToExistence(
                app.descendants(matching: .any)[
                    "subscription.history.price-change"
                ],
                in: app,
                maximumSwipes: 12
            )
        )
    }

    func testInvalidCustomIntervalIsExplainedInline() {
        let app = launch(language: "en", locale: "en_US")
        createSubscription(named: "Example Fitness", in: app)
        openFirstSubscriptionEditor(in: app)

        let billingInterval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(billingInterval.waitForExistence(timeout: 5))
        billingInterval.tap()
        app.buttons["Custom"].tap()
        let customValue = app.textFields["subscription.editor.custom-interval-value"]
        XCTAssertTrue(customValue.waitForExistence(timeout: 5))
        customValue.tap()
        customValue.typeText("0")
        app.buttons["subscription.form.save"].tap()

        XCTAssertTrue(
            app.staticTexts["subscription.validation.billing-interval"]
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
        XCTAssertTrue(app.staticTexts["价格"].exists)
        XCTAssertTrue(app.staticTexts["账单计划"].exists)
        app.swipeUp()
        XCTAssertFalse(app.textFields["订阅管理网址"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "打开服务商的账单、续订或取消订阅页面；本应用不会替你取消订阅。"
            ].exists
        )
        let billingInterval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(billingInterval.exists)
        XCTAssertTrue(billingInterval.label.contains("选择账单周期"))
        let currency = app.buttons["subscription.editor.currency"]
        XCTAssertTrue(currency.exists)
        XCTAssertFalse(currency.label.contains("选择货币"))
        XCTAssertTrue(app.buttons["保存"].exists)
    }

    func testCurrencyPickerOnlyOffersSupportedCurrencies() {
        let app = launch(language: "en", locale: "en_US")
        openManualAdd(in: app)

        let currency = app.buttons["subscription.editor.currency"]
        XCTAssertTrue(scrollToHittable(currency, in: app, maximumSwipes: 5))
        currency.tap()

        for option in ["CNY", "USD", "EUR"] {
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.buttons["Select Currency"].exists)
    }

    private func launchTask6Fixture(
        storeToken: String = "task6-fixture-\(UUID().uuidString)",
        failsLifecycleMutations: Bool = false,
        opensArchivedLibrary: Bool = false,
        timeZoneIdentifier: String? = nil
    ) -> XCUIApplication {
        launch(
            language: "en",
            locale: "en_US",
            storeToken: storeToken,
            failsLifecycleMutations: failsLifecycleMutations,
            seedsTask6OccurrenceFixture: true,
            opensArchivedLibrary: opensArchivedLibrary,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func waitForLifecyclePersistence() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
    }

    private func subscriptionRow(
        named serviceName: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons
            .matching(identifier: "subscription.row")
            .matching(NSPredicate(format: "label CONTAINS %@", serviceName))
            .firstMatch
    }

    private func upcomingRow(
        named serviceName: String,
        identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .matching(NSPredicate(format: "label CONTAINS %@", serviceName))
            .firstMatch
    }

    private func openTask6Editor(
        named serviceName: String,
        in app: XCUIApplication
    ) {
        let row = subscriptionRow(named: serviceName, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"]
                .waitForExistence(timeout: 5)
        )
    }

    private func openManualAdd(in app: XCUIApplication) {
        XCTAssertTrue(
            app.buttons["subscription.add"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.add"].tap()
        let addManually = app.buttons["catalog.add-manually"]
        XCTAssertTrue(addManually.waitForExistence(timeout: 5))
        addManually.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"]
                .waitForExistence(timeout: 5)
        )
    }

    private func fillRequiredEditorFacts(
        serviceName: String,
        amount amountValue: String,
        in app: XCUIApplication
    ) {
        let serviceNameField = app.textFields[
            "subscription.editor.service-name"
        ]
        XCTAssertTrue(serviceNameField.waitForExistence(timeout: 5))
        serviceNameField.tap()
        serviceNameField.typeText(serviceName)

        let amount = app.textFields["subscription.editor.amount"]
        XCTAssertTrue(scrollToExistence(amount, in: app, maximumSwipes: 3))
        amount.tap()
        amount.typeText(amountValue)

        let currency = app.buttons["subscription.editor.currency"]
        XCTAssertTrue(scrollToExistence(currency, in: app, maximumSwipes: 3))
        currency.tap()
        XCTAssertTrue(app.buttons["USD"].waitForExistence(timeout: 5))
        app.buttons["USD"].tap()

        let interval = app.buttons["subscription.editor.billing-interval"]
        XCTAssertTrue(scrollToExistence(interval, in: app, maximumSwipes: 6))
        interval.tap()
        let englishMonthly = app.buttons["Monthly"]
        let simplifiedChineseMonthly = app.buttons["每月"]
        let monthlyOption = englishMonthly.exists
            ? englishMonthly
            : simplifiedChineseMonthly
        XCTAssertTrue(monthlyOption.waitForExistence(timeout: 5))
        monthlyOption.tap()

        acceptEditorDate(
            identifier: "subscription.editor.start-date",
            in: app
        )
    }

    private func acceptEditorDate(
        identifier: String,
        in app: XCUIApplication
    ) {
        let date = app.buttons[identifier]
        XCTAssertTrue(scrollToHittable(date, in: app, maximumSwipes: 6))
        date.tap()
        let picker = app.datePickers["subscription.date-task.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let done = app.buttons["subscription.date-task.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    private func fillOptionalEditorDetails(
        plan planValue: String,
        category categoryValue: String,
        in app: XCUIApplication
    ) {
        let plan = app.textFields["subscription.editor.plan"]
        XCTAssertTrue(scrollToHittable(plan, in: app, maximumSwipes: 8))
        plan.tap()
        plan.typeText(planValue)

        let category = app.textFields["subscription.editor.category"]
        XCTAssertTrue(scrollToHittable(category, in: app, maximumSwipes: 8))
        category.tap()
        category.typeText(categoryValue)
    }

    private func openFirstSubscriptionEditor(in app: XCUIApplication) {
        let row = app.buttons["subscription.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(
            scrollToHittable(row, in: app, maximumSwipes: 4),
            "The saved subscription row must settle before it is opened."
        )
        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.summary"]
                .waitForExistence(timeout: 5),
            "Opening a saved row must present its summary card."
        )
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        waitForCurrentSubscriptionEditor(in: app)
    }

    private func openSubscriptionEditor(
        named serviceName: String,
        in app: XCUIApplication
    ) {
        let row = subscriptionRow(named: serviceName, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(
            scrollToHittable(row, in: app, maximumSwipes: 4),
            "The named saved subscription row must settle before it is opened."
        )
        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.summary"]
                .waitForExistence(timeout: 5),
            "Opening the named saved row must present its summary card."
        )
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        waitForCurrentSubscriptionEditor(in: app)
    }

    private func openCurrentSubscriptionEditor(in app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.summary"]
                .waitForExistence(timeout: 5),
            "A successful edit must return to the same summary card."
        )
        XCTAssertTrue(
            app.buttons["subscription.edit"].waitForExistence(timeout: 5)
        )
        app.buttons["subscription.edit"].tap()
        waitForCurrentSubscriptionEditor(in: app)
    }

    private func waitForCurrentSubscriptionEditor(in app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["subscription.form"]
                .waitForExistence(timeout: 5)
        )
    }

    private func createSubscription(
        named serviceNameValue: String,
        plan planValue: String = "Standard",
        statusButton: String? = nil,
        in app: XCUIApplication
    ) {
        openManualAdd(in: app)

        if let statusButton {
            let initialStatus = app.segmentedControls[
                "subscription.form.initial-status"
            ]
            XCTAssertTrue(initialStatus.waitForExistence(timeout: 5))
            initialStatus.buttons[statusButton].tap()
        }

        fillRequiredEditorFacts(
            serviceName: serviceNameValue,
            amount: "9.99",
            in: app
        )
        if statusButton != nil {
            acceptEditorDate(
                identifier: "subscription.editor.next-renewal",
                in: app
            )
        }

        let plan = app.textFields["subscription.editor.plan"]
        XCTAssertTrue(scrollToHittable(plan, in: app, maximumSwipes: 8))
        plan.tap()
        plan.typeText(planValue)

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

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 20
    ) -> Bool {
        for _ in 0 ..< maximumSwipes {
            if element.exists, element.isHittable {
                return true
            }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func scrollBackToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 20
    ) -> Bool {
        for _ in 0 ..< maximumSwipes {
            if element.exists, element.isHittable {
                return true
            }
            app.swipeDown()
        }
        return element.exists && element.isHittable
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
        seedsLegacyChatGPTPlus: Bool = false,
        seedsTask6OccurrenceFixture: Bool = false,
        opensArchivedLibrary: Bool = false,
        timeZoneIdentifier: String? = nil
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
        if seedsTask6OccurrenceFixture {
            app.launchArguments.append(
                "--ui-testing-seed-task6-occurrence-fixture"
            )
        }
        if opensArchivedLibrary {
            app.launchArguments.append(
                "--ui-testing-open-archived-library"
            )
        }
        if let timeZoneIdentifier {
            app.launchEnvironment["TZ"] = timeZoneIdentifier
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

    private func selectDateTaskInNextMonth(
        in picker: XCUIElement,
        app: XCUIApplication,
        day: Int
    ) -> String {
        let sourceValue = app.descendants(matching: .any)[
            "subscription.date-task.source-value"
        ]
        XCTAssertTrue(sourceValue.waitForExistence(timeout: 5))
        let originalValue = accessibilityValue(of: sourceValue)
        let month = picker.buttons["DatePicker.Show"]
        let nextMonth = picker.buttons["DatePicker.NextMonth"]
        guard let originalMonth = month.value as? String else {
            XCTFail("Date task must expose its visible calendar month.")
            return originalValue
        }
        nextMonth.tap()
        let monthChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", originalMonth),
            object: month
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [monthChanged], timeout: 3),
            .completed
        )

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US")
        monthFormatter.dateFormat = "MMMM yyyy"
        guard let visibleMonth = month.value as? String,
              let monthDate = monthFormatter.date(from: visibleMonth)
        else {
            XCTFail("Couldn’t parse the visible date-task month.")
            return originalValue
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = monthFormatter.locale
        let validRange = calendar.range(of: .day, in: .month, for: monthDate)
        let targetDay = min(max(day, validRange?.lowerBound ?? 1),
                            (validRange?.upperBound ?? 2) - 1)
        var components = calendar.dateComponents(
            [.year, .month],
            from: monthDate
        )
        components.day = targetDay
        guard let targetDate = calendar.date(from: components) else {
            XCTFail("Couldn’t create a target date in the visible month.")
            return originalValue
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = monthFormatter.locale
        dayFormatter.dateFormat = "EEEE, MMMM d"
        let target = picker.buttons[dayFormatter.string(from: targetDate)]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        let selectedValue = accessibilityValue(of: sourceValue)
        XCTAssertNotEqual(
            selectedValue,
            originalValue,
            "Changing the graphical date must refresh the task summary."
        )
        return selectedValue
    }

    private func accessibilityValue(of element: XCUIElement) -> String {
        let value: String
        if let elementValue = element.value as? String,
           !elementValue.isEmpty
        {
            value = elementValue
        } else {
            value = element.label
        }
        for suffix in [", Source", ", Derived"] where value.hasSuffix(suffix) {
            return String(value.dropLast(suffix.count))
        }
        return value
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
