# Convergent Calendar Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use an inline test-driven execution loop task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a previously imported dedicated Calendar projection convergent with the Subscription Library while requiring explicit rebuild or disable after external deletion.

**Architecture:** `SubscriptionWorkspace` builds the desired rolling projection and delegates commands to an injected reconciliation adapter. The app target owns EventKit observation and SwiftData mapping metadata; it returns decision states rather than silently recreating deleted data.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, EventKit, iOS/iPadOS/macOS 27.

## Global Constraints

- Keep UI and system integrations behind `SubscriptionWorkspace`.
- Only initial import and rebuild may request Calendar access or create a calendar.
- Preserve ICS export and the Subscription Library for every failure state.
- Localize all copy in English and Simplified Chinese with accessibility identifiers.

---

### Task 1: Model workspace reconciliation state

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/CalendarImport.swift`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Interfaces:** Produces `CalendarProjectionReconciler`, `CalendarReconciliationCommand`, `CalendarReconciliationResult`, and workspace reconcile/rebuild/disable commands.

- [ ] **Step 1: Write a failing workspace test.**

```swift
await workspace.reconcileCalendarProjection(locale: Locale(identifier: "en_US"))
#expect(reconciler.commands == [.reconcile(workspace.calendarProjection)])
#expect(workspace.calendarReconciliationState == .needsDecision(.calendarMissing))
```

Also assert a second request during `.reconciling` does not start a second call and disable changes no subscription.

- [ ] **Step 2: Verify failure.** Run `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests`; expect missing reconciliation APIs.

- [ ] **Step 3: Implement the smallest seam.**

```swift
public enum CalendarReconciliationCommand: Equatable, Sendable {
    case initialImport([CalendarProjectionEvent])
    case reconcile([CalendarProjectionEvent])
    case rebuild([CalendarProjectionEvent])
    case disable
}
@MainActor public protocol CalendarProjectionReconciler: Sendable {
    func perform(_ command: CalendarReconciliationCommand) async -> CalendarReconciliationResult
}
```

Reload the selected-horizon projection for each command and coalesce concurrent requests.

- [ ] **Step 4: Verify and commit.** Run the focused suite; expect PASS. Commit with `feat(core): model calendar reconciliation`.

### Task 2: Reconcile EventKit and persistent mappings

**Files:**
- Modify: `SubscriptionManager/Calendar/EventKitCalendarProjectionImporter.swift`
- Modify: `SubscriptionManager/Persistence/SubscriptionRecord.swift`
- Modify: `SubscriptionManager/App/AppDependencies.swift`
- Test: `SubscriptionManagerTests/EventKitCalendarProjectionImporterTests.swift`
- Test: `SubscriptionManagerTests/AppDependenciesTests.swift`

**Interfaces:** Produces an `EventKitCalendarProjectionReconciler`, list/delete mapping APIs, and persisted management mode (`enabled`, `needsRebuild`, `disabled`).

- [ ] **Step 1: Write failing adapter tests.**

```swift
#expect(await reconciler.perform(.reconcile(changed))
    == .reconciled(createdCount: 0, updatedCount: 1, removedCount: 0))
store.deleteEvent(uid: "renewal-1")
#expect(await reconciler.perform(.reconcile(changed))
    == .needsDecision(.eventsMissing(count: 1)))
#expect(store.createdCalendarCount == 1)
```

Cover repeated reconciliation, cancellation removal, horizon extension, external event edit, missing event/calendar, explicit rebuild, disable, partial retry, and SwiftData reload.

- [ ] **Step 2: Verify failure.** Run the focused iPhone `EventKitCalendarProjectionImporterTests`; expect missing reconciliation APIs.

- [ ] **Step 3: Implement refetch-and-compare reconciliation.**

```swift
for mapping in try mappingRepository.eventMappings() {
    guard desiredUIDs.contains(mapping.projectionUID) else {
        try eventStore.removeEvent(identifier: mapping.eventIdentifier)
        try mappingRepository.removeEventMapping(for: mapping.projectionUID)
        continue
    }
    guard eventStore.event(identifier: mapping.eventIdentifier) != nil else {
        return .needsDecision(.eventsMissing(count: missingCount))
    }
}
```

Reapply every managed field to existing events. Only initial import/rebuild can create a calendar or missing event; missing external data returns a decision result.

- [ ] **Step 4: Verify and commit.** Run focused adapter/AppDependencies tests plus core tests; commit `feat(app): reconcile managed calendar projection`.

### Task 3: Route foreground, EventKit, and CloudKit delivery triggers

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify: `SubscriptionManager/Calendar/EventKitCalendarProjectionImporter.swift`
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
- Test: `SubscriptionManagerTests/EventKitCalendarProjectionImporterTests.swift`

**Interfaces:** Produces coalesced `requestCalendarReconciliation(trigger:locale:)` and an EventKit change trigger that never itself writes or requests access.

- [ ] **Step 1: Write failing trigger tests.** Prove a successful subscription/preference update and a foreground request enqueue one reconciliation, while disabled/not-imported/lost-access states make no authorization request.

- [ ] **Step 2: Verify failure.** Run focused core tests; expect missing trigger API.

- [ ] **Step 3: Implement only coalesced delivery.**

```swift
@Environment(\.scenePhase) private var scenePhase
.onChange(of: scenePhase) { _, phase in
    guard phase == .active else { return }
    Task { await workspace.requestCalendarReconciliation(trigger: .foreground) }
}
```

Observe `EKEventStore.EventStoreChanged`, discard stale EventKit references, and feed the same request after a relevant SwiftData/CloudKit reload.

- [ ] **Step 4: Verify and commit.** Run focused core and adapter suites; commit `feat(app): trigger calendar reconciliation`.

### Task 4: Add explicit recovery UI and verification record

**Files:**
- Modify: `SubscriptionManager/Library/CalendarProjectionView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Create: `docs/verification/2026-07-29-calendar-reconciliation-matrix.md`

**Interfaces:** Consumes reconciliation state and produces accessible Rebuild Calendar and Disable Calendar Sync decisions.

- [ ] **Step 1: Write a failing UI test.**

```swift
app.launchArguments += ["--ui-testing", "--calendar-missing-fixture"]
app.launch()
app.buttons["preferences.calendar.preview"].tap()
XCTAssertTrue(app.buttons["calendar.rebuild"].exists)
XCTAssertTrue(app.buttons["calendar.disable"].exists)
```

- [ ] **Step 2: Verify failure.** Run only `SubscriptionManagerUITests/testCalendarDeletionRecovery`; expect missing recovery controls.

- [ ] **Step 3: Implement decisions and localize.**

```swift
Button("Rebuild Calendar", action: rebuild)
    .accessibilityIdentifier("calendar.rebuild")
Button("Disable Calendar Sync", role: .destructive, action: disable)
    .accessibilityIdentifier("calendar.disable")
```

Retain Export ICS in all states.

- [ ] **Step 4: Verify, document, and commit.** Run full core and iPhone suites, `git diff --check`, and `jq empty SubscriptionManager/Resources/Localizable.xcstrings`; record fake-clock, edit/delete, calendar-delete, retry, horizon, foreground, EventKit, SwiftData reload, and simulator results. Commit `feat(app): recover calendar projection reconciliation`.

## Plan self-review

| Requirement | Task |
| --- | --- |
| Idempotency and rolling horizon | 1, 2 |
| Edit/cancellation and external edit restore | 2, 3 |
| Explicit deletion recovery | 2, 4 |
| Trigger and persistence verification | 1–4 |

The plan uses one command model, has no placeholder steps, and keeps EventKit out of SwiftUI.
