# TB-14 Exchange-Rate Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert subscription charges using cached daily reference rates and expose accessible expected/confirmed spending insights in the selected display currency.

**Architecture:** `SubscriptionCore` owns immutable rate snapshots, cache/source protocols, refresh policy, conversion, and report projection. The app supplies a Frankfurter v2 URLSession adapter and atomic file cache, then renders the workspace report using native Charts and a complete textual alternative.

**Tech Stack:** Swift 6.2, Foundation/URLSession, Decimal, Swift Testing, SwiftData, SwiftUI, Swift Charts, XCTest UI tests, Frankfurter v2.

## Global Constraints

- Support `CNY`, `USD`, and `EUR`; original subscription amounts never change.
- Use an EUR-anchored `ExchangeRateSnapshot`; a missing rate is unavailable, never a 1:1 fallback.
- Read the local cache before refresh; make no more than one successful or failed network attempt per calendar day.
- Send only `base`, `quotes`, and provider-required route/date data; never subscription/account/device data.
- Expected totals use current eligible schedule projections; confirmed totals use stored charges for non-archived subscriptions in the selected range.
- Render a native category chart and an equivalent VoiceOver-readable textual category summary.
- Keep the iOS 27 target, English/Simplified Chinese localization, and no EventKit dependency.

---

## File structure

- Create: `Packages/SubscriptionCore/Sources/SubscriptionCore/ExchangeRates.swift` — rate snapshot/cache/source contracts, conversion, report value types.
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift` — workspace refresh policy and report projection.
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift` — fake clock/cache/source tests.
- Modify: `SubscriptionManager/Catalog/GitHubCatalogUpdateSource.swift` — Frankfurter v2 source.
- Modify: `SubscriptionManager/Catalog/FileCatalogCache.swift` — atomic exchange-rate file cache.
- Modify: `SubscriptionManager/App/AppDependencies.swift` — inject source/cache.
- Modify: `SubscriptionManager/Library/LibraryView.swift` — Insights destination and EUR preference UI.
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`, `SubscriptionManagerTests/AppDependenciesTests.swift`, and `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`.

### Task 1: Define rate and report domain contracts

**Files:**
- Create: `Packages/SubscriptionCore/Sources/SubscriptionCore/ExchangeRates.swift`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift:4-11`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Consumes:** `Money`, `Currency`, `ExpectedCharge`, `ConfirmedCharge`, and `Subscription`.

**Produces:** `ExchangeRateSnapshot`, `ExchangeRateCacheState`, `ExchangeRateSource`, `ExchangeRateCache`, `ExchangeRateStatus`, `SpendingReportMode`, `SpendingInsightItem`, `SpendingInsights`, and `Currency.eur`.

- [ ] **Step 1: Write the failing conversion test**

```swift
@Test("EUR snapshot converts CNY and USD without a one-to-one fallback")
func snapshotConvertsThroughEUR() throws {
    let snapshot = ExchangeRateSnapshot(
        base: .eur, providerDate: day("2026-07-29"), fetchedAt: now,
        source: "fixture", rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
    )
    #expect(try snapshot.convert(Money(minorUnits: 840, currency: .cny), to: .usd)
        == Money(minorUnits: 120, currency: .usd))
    #expect(throws: ExchangeRateConversionError.missingRate(.usd)) {
        try ExchangeRateSnapshot(base: .eur, providerDate: now, fetchedAt: now,
            source: "fixture", rates: [.eur: 1]).convert(
                Money(minorUnits: 100, currency: .usd), to: .cny
            )
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests/snapshotConvertsThroughEUR`

Expected: FAIL because the rate snapshot types do not exist.

- [ ] **Step 3: Implement the public contracts**

```swift
public enum Currency: String, CaseIterable, Codable, Sendable {
    case cny = "CNY", usd = "USD", eur = "EUR"
}

@MainActor public protocol ExchangeRateSource {
    func fetchRates(base: Currency, quotes: Set<Currency>) async throws -> ExchangeRateSnapshot
}

@MainActor public protocol ExchangeRateCache {
    func loadState() throws -> ExchangeRateCacheState?
    func saveState(_ state: ExchangeRateCacheState) throws
}

public enum SpendingReportMode: String, CaseIterable, Codable, Sendable {
    case expected, confirmed
}
```

Implement `ExchangeRateSnapshot.convert(_:to:)` with Decimal, EUR rate 1, source-to-EUR-to-target math, and explicit two-minor-unit `.plain` rounding. `ExchangeRateCacheState` must store both a snapshot and `lastAttemptAt`, so a failed fetch is rate-limited too.

- [ ] **Step 4: Verify the test passes and commit**

Run: `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests/snapshotConvertsThroughEUR`

Expected: PASS.

```bash
git add Packages/SubscriptionCore/Sources/SubscriptionCore/ExchangeRates.swift Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift
git commit -m "feat(core): add exchange-rate domain contracts"
```

### Task 2: Implement daily refresh policy and report projection

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift:389-555,1331-1455`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Consumes:** Task 1 contracts, repository data, and injected `now`/calendar.

**Produces:** `SubscriptionWorkspace.refreshExchangeRates()`, `SubscriptionWorkspace.loadInsights(mode:from:through:)`, `exchangeRateStatus`, and `insightsState`.

- [ ] **Step 1: Write failing fake-clock/source/cache tests**

```swift
@Test("Rate refresh reuses today's cache and records a failed attempt")
@MainActor
func rateRefreshUsesDailyCacheAndDoesNotRetryFailure() async {
    let source = RecordingRateSource(result: .failure(FixtureError.offline))
    let cache = InMemoryExchangeRateCache(
        state: .init(snapshot: nil, lastAttemptAt: nil)
    )
    let workspace = SubscriptionWorkspace(
        repository: InMemorySubscriptionRepository(),
        exchangeRateSource: source, exchangeRateCache: cache, now: { now }
    )
    await workspace.refreshExchangeRates()
    await workspace.refreshExchangeRates()
    #expect(source.requests.count == 1)
    #expect(cache.state?.lastAttemptAt == now)
    #expect(workspace.exchangeRateStatus == .unavailable)
}
```

Add CNY/USD/EUR subscription fixtures with `8.4 CNY/EUR` and `1.2 USD/EUR`. Assert expected and confirmed modes separately expose selected-range, monthly, annualized, and category totals in the primary currency; also assert the captured request contains only the required symbols.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests/rateRefreshUsesDailyCacheAndDoesNotRetryFailure`

Expected: FAIL because the workspace has no rate-refresh API.

- [ ] **Step 3: Implement cache-first refresh and report APIs**

```swift
public func refreshExchangeRates() async {
    let cached = try? exchangeRateCache?.loadState()
    if let cached, calendar.isDate(cached.lastAttemptAt ?? .distantPast,
        inSameDayAs: now()) {
        apply(cached)
        return
    }
    let subscriptions = (try? repository.listSubscriptions()) ?? []
    let quotes = Set(subscriptions.map(\.originalAmount.currency))
        .union([currentPreferences.primaryCurrency]).subtracting([.eur])
    let attemptAt = now()
    do {
        let snapshot = try await exchangeRateSource?.fetchRates(base: .eur, quotes: quotes)
        let state = ExchangeRateCacheState(snapshot: snapshot, lastAttemptAt: attemptAt)
        try exchangeRateCache?.saveState(state)
        exchangeRateStatus = .fresh(snapshot)
    } catch {
        let state = ExchangeRateCacheState(snapshot: cached?.snapshot, lastAttemptAt: attemptAt)
        try? exchangeRateCache?.saveState(state)
        exchangeRateStatus = cached?.snapshot.map(ExchangeRateStatus.stale) ?? .unavailable
    }
}
```

`loadInsights` returns unavailable if rates are absent/incomplete. Expected mode projects active/trial non-archived charges inclusively through the range; confirmed mode aggregates stored non-archived confirmed charges in the same range. Sort monthly totals by month and categories by localized title.

- [ ] **Step 4: Run all core tests and commit**

Run: `swift test --package-path Packages/SubscriptionCore`

Expected: all SubscriptionCore tests PASS.

```bash
git add Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift
git commit -m "feat(core): project cached currency insights"
```

### Task 3: Add the provider and persistent cache adapters

**Files:**
- Modify: `SubscriptionManager/Catalog/GitHubCatalogUpdateSource.swift`
- Modify: `SubscriptionManager/Catalog/FileCatalogCache.swift`
- Modify: `SubscriptionManager/App/AppDependencies.swift:70-115`
- Test: `SubscriptionManagerTests/AppDependenciesTests.swift`

**Consumes:** Task 1 protocols.

**Produces:** `FrankfurterExchangeRateSource`, `FileExchangeRateCache`, and live workspace injection.

- [ ] **Step 1: Write failing URL/decode/cache tests**

```swift
@Test("Frankfurter requests only EUR base and required quote symbols")
@MainActor
func frankfurterRequestIsPrivacyMinimal() async throws {
    let session = RecordingURLSession(responseData: fixtureRatesData)
    let source = FrankfurterExchangeRateSource(session: session, now: { now })
    _ = try await source.fetchRates(base: .eur, quotes: [.cny, .usd])
    #expect(session.requestURL?.query == "base=EUR&quotes=CNY,USD")
    #expect(session.requestURL?.absoluteString.contains("subscription") == false)
}
```

Add a temporary-directory cache round trip asserting snapshot, provider date, source, decimal rates, and last attempt survive reload.

- [ ] **Step 2: Verify the tests fail**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerTests/AppDependenciesTests`

Expected: FAIL because provider/cache adapters do not exist.

- [ ] **Step 3: Implement adapters and live wiring**

```swift
let url = URL(string: "https://api.frankfurter.dev/v2/rates")!
    .appending(queryItems: [
        .init(name: "base", value: base.rawValue),
        .init(name: "quotes", value: quotes.map(\.rawValue).sorted().joined(separator: ",")),
    ])
```

Decode only `date`, `base`, `quote`, and `rate`; reject incomplete requested quotes. Persist `ExchangeRateCacheState` atomically at `Application Support/SubscriptionManager/Insights/exchange-rates.json`. Inject both adapters from `AppDependencies.make`.

- [ ] **Step 4: Run tests and commit**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerTests/AppDependenciesTests`

Expected: selected tests PASS.

```bash
git add SubscriptionManager/Catalog/GitHubCatalogUpdateSource.swift SubscriptionManager/Catalog/FileCatalogCache.swift SubscriptionManager/App/AppDependencies.swift SubscriptionManagerTests/AppDependenciesTests.swift
git commit -m "feat(app): cache Frankfurter reference rates"
```

### Task 4: Render accessible Insights and support EUR preferences

**Files:**
- Modify: `SubscriptionManager/Library/LibraryView.swift:1-390,606-850`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Consumes:** workspace report state and existing Settings/first-run preferences.

**Produces:** live Insights navigation, expected/confirmed picker, chart/text summary, rate status, and EUR selection.

- [ ] **Step 1: Write failing UI contracts**

```swift
func testInsightsExposesTextSummaryAndRateStatus() {
    let app = launch(language: "en", locale: "en_US")
    topLevelTab("Insights", in: app).tap()
    XCTAssertTrue(app.buttons["insights.mode.expected"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["insights.text-summary"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["insights.rate-status"].exists)
}

func testSettingsCanSelectEURDisplayCurrency() {
    let app = launch(language: "en", locale: "en_US")
    app.buttons["library.settings"].tap()
    XCTAssertTrue(app.buttons["preferences.currency.eur"].waitForExistence(timeout: 5))
}
```

- [ ] **Step 2: Verify UI tests fail**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testInsightsExposesTextSummaryAndRateStatus -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSettingsCanSelectEURDisplayCurrency`

Expected: FAIL because Insights is a placeholder and EUR has no control.

- [ ] **Step 3: Implement the report surface**

```swift
Chart(workspace.insightsState.categoryTotals) { total in
    BarMark(x: .value("Amount", decimalAmount(total.amount)),
            y: .value("Category", total.category))
        .accessibilityLabel("\(total.category): \(formattedMoney(total.amount))")
}
.accessibilityIdentifier("insights.category-chart")

Section("Category Totals") {
    ForEach(workspace.insightsState.categoryTotals) { total in
        LabeledContent(total.category, value: formattedMoney(total.amount))
    }
}
.accessibilityIdentifier("insights.text-summary")
```

Use stable `insights.mode.expected` and `insights.mode.confirmed` identifiers. Render fresh/stale/unavailable status with provider date/timestamp. Only the view task calls `await workspace.refreshExchangeRates()`, then loads the report. Add `setup.currency.eur` and `preferences.currency.eur` controls; presentation currency changes must not change original values.

- [ ] **Step 4: Localize, test, and commit**

Run: `jq empty SubscriptionManager/Resources/Localizable.xcstrings && xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testInsightsExposesTextSummaryAndRateStatus -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSettingsCanSelectEURDisplayCurrency`

Expected: JSON validates and both UI tests PASS.

```bash
git add SubscriptionManager/Library/LibraryView.swift SubscriptionManager/Resources/Localizable.xcstrings SubscriptionManagerUITests/SubscriptionManagerUITests.swift
git commit -m "feat(app): present accessible spending insights"
```

### Task 5: Run regression validation and prepare the stacked PR

**Files:**
- Modify: `docs/superpowers/specs/2026-07-29-exchange-rate-insights-design.md` only if validation reveals a design contradiction.

**Consumes:** Tasks 1-4.

**Produces:** a validated `feat/tb-14-insights` branch and stacked PR targeting `feat/tb-13-upcoming`.

- [ ] **Step 1: Run core regression**

Run: `swift test --package-path Packages/SubscriptionCore`

Expected: all core tests PASS.

- [ ] **Step 2: Build for both target form factors**

Run: `xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` and `xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'`

Expected: both builds PASS.

- [ ] **Step 3: Run focused app and UI regressions**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerTests`, then TB-12/TB-13/TB-14 focused UI tests.

Expected: selected tests PASS; record a full-suite tool timeout separately from a failing test.

- [ ] **Step 4: Inspect and publish**

Run: `git diff --check && git status --short && git push -u origin feat/tb-14-insights`

Expected: no whitespace errors and no unintended changes.

```bash
gh pr create --base feat/tb-13-upcoming --head feat/tb-14-insights \
  --title "feat: add exchange-rate spending insights" \
  --body-file /tmp/tb14-pr-body.md
```

Expected: stacked PR open with verification evidence; it remains unmerged until its base lands.

## Plan self-review

- Spec coverage: Tasks 1-2 cover daily cache reuse, fresh/stale/unavailable behavior, decimal CNY/USD/EUR conversion, and expected/confirmed monthly/annualized/range/category reports.
- Privacy coverage: Task 3 constrains the exact Frankfurter query and verifies no subscription data enters it.
- Accessibility coverage: Task 4 requires a native chart plus full textual summary and stable UI test identifiers.
- Consistency: all types and workspace APIs used by Tasks 3-4 are introduced by Tasks 1-2.
