# TB-05 Payment History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task.

**Goal:** Confirm one scheduled charge exactly once and apply append-only price changes to future forecasts.

**Architecture:** Core derives stable occurrence identities and history; SwiftData stores additive JSON; SwiftUI sends commands and renders workspace-owned state.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, XcodeBuildMCP.

## Global Constraints

- Gregorian billing-local dates; one `SubscriptionWorkspace`; bilingual and accessible copy.
- Confirmed charges and price changes are immutable facts; ordinary edit never changes money.
- Preserve TB-04 data; do not add CloudKit, exchange rates, provider contact, or payment discovery.

### Task 1: Domain values and copies

**Files:** `FixedBillingSchedule.swift`, `SubscriptionCore.swift`, `SubscriptionLifecycle.swift`, `SubscriptionDomainTests.swift`, `FixedBillingScheduleTests.swift`.

**Interfaces:**

```swift
public struct ScheduledChargeID: Codable, Equatable, Hashable, Sendable {
    public let subscriptionID: UUID
    public let year: Int
    public let month: Int
    public let day: Int
}

public struct PriceChange: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let effectiveDate: Date
    public let amount: Money
}
```

- [ ] Add a failing test that an `ExpectedCharge` has a scheduled ID, that a `ConfirmedCharge` preserves an optional `sourceScheduledChargeID`, and that `Subscription` copies retain `priceChanges`.
- [ ] Run `swift test --package-path Packages/SubscriptionCore --filter SubscriptionDomainTests`; expect missing types.
- [ ] Add the two values above; add `ExpectedCharge.id`, optional `ConfirmedCharge.sourceScheduledChargeID = nil`, and `Subscription.priceChanges = []`; thread price changes through all constructors/copies.
- [ ] Re-run the selected test; commit `feat(core): model payments and price changes`.

### Task 2: Workspace commands, forecasting, and history

**Files:** `SubscriptionCore.swift`, `SubscriptionWorkspaceTests.swift`.

**Interfaces:**

```swift
public func confirmCharge(id: UUID, scheduledDate: Date, chargedDate: Date, amount: Money)
public func recordPriceChange(id: UUID, effectiveDate: Date, amount: Money)
public enum SubscriptionHistoryEntry: Equatable, Sendable {
    case expected(ExpectedCharge)
    case confirmed(ConfirmedCharge)
    case priceChange(PriceChange)
}
```

- [ ] Write failing workspace tests: first confirmation appends one source-linked fact; identical retry remains one fact; passed occurrence confirms; future/non-scheduled/non-positive input fails; price effective on the same billing day applies; a duplicate price day fails; confirmed money remains unchanged; archive retains history and blocks mutation.
- [ ] Run `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests`; expect missing commands/state.
- [ ] Add a separate payment-history action error and loaded-detail history. Validate current-schedule occurrences using billing-local Gregorian days. De-duplicate on source ID. Exclude confirmed IDs from forecasts. Resolve expected money from the latest price change at or before its effective day. Build history from latest missed expected, next expected, confirmed, and price changes; same-day order is Price Change → Expected → Confirmed. Remove `originalAmount` from `SubscriptionEditInput` and preserve base money/history during edit.
- [ ] Re-run selected tests; commit `feat(core): confirm charges and resolve price history`.

### Task 3: Additive SwiftData compatibility

**Files:** `SubscriptionRecord.swift`, `SwiftDataSubscriptionRepository.swift`, `SwiftDataSubscriptionRepositoryTests.swift`, `AppDependenciesTests.swift`.

- [ ] Write failing repository tests for `priceChangesData`, missing legacy price data, and legacy confirmed-charge JSON without a source identity.
- [ ] Run `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:SubscriptionManagerTests/SwiftDataSubscriptionRepositoryTests test`; expect missing storage.
- [ ] Add optional `priceChangesData: Data?`, encode changes in `apply(_:to:)`, decode `nil` as `[]`, preserve existing charge JSON decoding and rollback/fail-fast behavior.
- [ ] Re-run tests; commit `feat(persistence): store price history`.

### Task 4: Native payment forms and history UI

**Files:** create `ConfirmChargeView.swift`, `RecordPriceChangeView.swift`; modify `SubscriptionDetailView.swift`, `EditSubscriptionView.swift`, `SubscriptionFormSupport.swift`, `Localizable.xcstrings`, Xcode project; test `ManagementURLValidationTests.swift`, `SubscriptionManagerUITests.swift`.

- [ ] Write failing English and Simplified-Chinese UI tests that confirm a charge, record a price change, verify Expected/Confirmed/Price Change labels, then archive and verify read-only history.
- [ ] Run `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testConfirmsChargeAndRecordsPriceHistory test`; expect missing UI.
- [ ] Add current Trial/Active action-menu entries, two `NavigationStack` forms, localized payment-error mapping, and history row identifiers `subscription.history.*`. Remove Edit amount/currency controls and direct price changes to the new action. Render only workspace-derived history and add every key in both languages.
- [ ] Re-run focused UI plus `SubscriptionManagerTests`; commit `feat(ui): manage payment and price history`.

### Task 5: Integration gate

- [ ] Run `swift test --package-path Packages/SubscriptionCore --disable-sandbox`.
- [ ] Use Build iOS Apps: call `session_show_defaults`, then run simulator app-unit and UI tests.
- [ ] Build Release for iOS Simulator and unsigned macOS; run `git diff --check`; audit bilingual copy, no provider networking, and no TB-06+ scope.
- [ ] Commit only verified gate fixes as `fix: resolve payment history gate findings`.
