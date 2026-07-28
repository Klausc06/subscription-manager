# TB-13 Upcoming Navigation Implementation Plan

> **For agentic workers:** Execute each task with a focused test cycle and commit only after its listed verification passes.

**Goal:** Present a stable, accessible chronological view of expected and confirmed charges through native iPhone and iPad navigation.

**Architecture:** `SubscriptionWorkspace` creates a date-bounded, ordered timeline from the local subscription repository. SwiftUI renders that projection in an Upcoming tab and reuses the existing detail route. The root uses adaptive SwiftUI tabs/navigation and keeps Insights as a clearly scoped placeholder for TB-14.

**Tech Stack:** Swift 6, Observation, SwiftUI, Swift Testing, XCTest UI tests.

## Global Constraints

- Use `SubscriptionWorkspace` for every subscription query and navigation ID.
- Exclude archived subscriptions and lifecycle-ineligible future renewals.
- Represent expected and confirmed charges with localized text and symbols, not colour alone.
- Ship English and Simplified Chinese strings; add stable accessibility identifiers.
- Do not add Calendar/EventKit, network, exchange-rate, or account behavior.

---

### Task 1: Add a workspace-level upcoming timeline projection

**Files:** Modify `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`; test in `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`.

- [ ] Add a failing test using two active subscriptions, one confirmed payment, and one cancelled subscription. Request a 90-day interval and assert chronological expected/confirmed items, stable subscription IDs, and no cancelled item.
- [ ] Run `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests`; expect the timeline API/type to be missing.
- [ ] Add `UpcomingTimelineItem` with `Kind.expected`/`.confirmed`, a `UpcomingTimelineState`, and `loadUpcomingTimeline(from:through:)`. Derive expected items with `makeExpectedCharges`, derive confirmed items from `confirmedCharges`, filter by inclusive date range, and sort by date then stable item identity.
- [ ] Add tests for archived records, empty interval results, and equal-date ordering.
- [ ] Run the full core suite and commit `feat(core): add upcoming timeline query`.

### Task 2: Create adaptive root destinations and the Upcoming screen

**Files:** Create `SubscriptionManager/Upcoming/UpcomingView.swift`; modify `SubscriptionManager/App/SubscriptionManagerApp.swift`, `SubscriptionManager/Library/LibraryView.swift`, and `SubscriptionManager/Resources/Localizable.xcstrings`.

- [ ] Add a failing UI test that launches the compact app, selects `tab.upcoming`, finds an expected-charge row, and opens its subscription detail.
- [ ] Replace the single library root with a `TabView` containing Subscriptions, Upcoming, and Insights. Preserve the existing LibraryView navigation and Settings behaviour inside the Subscriptions tab.
- [ ] Render date-range filter controls (Today, Next 30 Days, Next 90 Days), grouped chronological rows, distinct expected/confirmed labels/icons, loading/empty/error states, and detail navigation from each row.
- [ ] Add bilingual copy and identifiers `tab.subscriptions`, `tab.upcoming`, `tab.insights`, `upcoming.range.*`, `upcoming.row.expected`, and `upcoming.row.confirmed`.
- [ ] Run the focused UI test on the iPhone simulator and commit `feat(app): add upcoming charge navigation`.

### Task 3: Verify lifecycle, accessibility, and adaptive behavior

**Files:** Modify `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`; modify `SubscriptionManager/Upcoming/UpcomingView.swift` only if tests expose a defect.

- [ ] Add UI tests for expected versus confirmed accessibility values, empty results, Simplified Chinese labels, and compact tab selection.
- [ ] Run the affected UI tests on iPhone and a widened iPad simulator destination; assert navigation remains selected after a size-class transition.
- [ ] Run `swift test --package-path Packages/SubscriptionCore`, `SubscriptionManagerTests`, and the new UI suite.
- [ ] Inspect `git diff --check`, verify no EventKit imports, commit `test: verify upcoming navigation`, push `feat/tb-13-upcoming`, and create a stacked PR with base `feat/tb-12-onboarding`.

## Self-Review

- The workspace owns all record aggregation and date/lifecycle semantics; the view only presents observable state.
- Confirmed and expected entries retain their individual dates and types, so the UI has no inferred status logic.
- The plan keeps exchange-rate insights, Calendar export, and iPad-specific custom layout work out of TB-13.
