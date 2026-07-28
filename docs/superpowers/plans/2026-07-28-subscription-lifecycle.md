# Subscription Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic trial, active, cancelled-with-access, expired,
archive, restore, reactivation, and explicitly confirmed permanent-deletion
behavior through `SubscriptionWorkspace`.

**Architecture:** Persist only lifecycle facts plus one archive flag. Resolve
the effective status and optional next expected charge inside
`SubscriptionWorkspace` using the injected clock and billing-local calendar
days. SwiftData remains a persistence adapter; SwiftUI renders Workspace-built
presentation values and owns only temporary native-dialog state.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, Observation, SwiftData,
XcodeGen, iOS/iPadOS/macOS 27.

## Global Constraints

- Work only inside Issue #5; do not add TB-05 payment history, Calendar,
  catalog, rates, CloudKit, widgets, or App Intents.
- Never contact, automate, or simulate cancellation with a provider.
- Use `SubscriptionWorkspace` as the only application mutation/query seam.
- Use strict red-green-refactor TDD: every production behavior starts with a
  test that fails for the expected reason.
- Compare lifecycle boundaries by Gregorian billing-local calendar day.
- Normalize lifecycle date-only input to local noon.
- Preserve `FixedBillingSchedule`, Renewal Anchor, Confirmed Charge history,
  lifecycle facts, and archive state unless the named command changes them.
- Ship all new user-facing copy in English and Simplified Chinese with stable
  accessibility identifiers.
- Keep the implementation additive and YAGNI: no event log, service layer,
  retry state machine, archive timestamp, or duplicate library cache.

---

### Task 1: Lifecycle facts and billing-local effective status

**Files:**

- Create:
  `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionLifecycle.swift`
- Create:
  `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionLifecycleTests.swift`
- Modify:
  `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify:
  `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionDomainTests.swift`

**Interfaces:**

- Produces:
  `SubscriptionLifecycle`,
  `SubscriptionStatus`,
  `SubscriptionInitialStatus`,
  `SubscriptionLifecycle.status(asOf:timeZone:)`,
  `Subscription.lifecycle`,
  and `Subscription.isArchived`.
- Later tasks consume these exact names.

- [ ] **Step 1: Write failing effective-status boundary tests**

Create `SubscriptionLifecycleTests.swift` with real UTC and
America/Los_Angeles dates. The boundary date must already belong to the new
status:

```swift
import Foundation
@testable import SubscriptionCore
import Testing

@Suite("Subscription lifecycle")
struct SubscriptionLifecycleTests {
    @Test("Trial becomes active for the whole first paid local day")
    func trialBoundaryUsesBillingLocalDay() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let firstPaidCharge = try date(
            year: 2026, month: 3, day: 8, hour: 12, timeZone: timeZone
        )
        let lifecycle = SubscriptionLifecycle.trial(
            firstPaidChargeAt: firstPaidCharge
        )

        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 3, day: 7, hour: 23, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .trial
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 3, day: 8, hour: 1, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .active
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 3, day: 9, hour: 12, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .active
        )
    }

    @Test("Cancelled access expires for the whole access-until local day")
    func cancellationBoundaryUsesBillingLocalDay() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let lifecycle = SubscriptionLifecycle.cancelled(
            cancelledAt: try date(
                year: 2026, month: 7, day: 1, hour: 12, timeZone: timeZone
            ),
            accessUntil: try date(
                year: 2026, month: 7, day: 31, hour: 12, timeZone: timeZone
            )
        )

        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 7, day: 30, hour: 23, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .cancelledWithAccess
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 7, day: 31, hour: 1, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .expired
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 8, day: 1, hour: 12, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .expired
        )
    }
}
```

Add a private test `date(...)` helper using a pinned Gregorian POSIX calendar.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/subscription-manager-tb04-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/subscription-manager-tb04-swiftpm-cache \
swift test --disable-sandbox \
  --scratch-path /private/tmp/subscription-manager-tb04-swiftpm-build \
  --filter SubscriptionLifecycleTests
```

Expected: compilation fails because `SubscriptionLifecycle` does not exist.

- [ ] **Step 3: Implement the minimal lifecycle values**

Create `SubscriptionLifecycle.swift`:

```swift
import Foundation

public enum SubscriptionInitialStatus:
    String, CaseIterable, Hashable, Sendable
{
    case active
    case trial
}

public enum SubscriptionStatus: String, Codable, Equatable, Sendable {
    case trial
    case active
    case cancelledWithAccess
    case expired
}

public enum SubscriptionLifecycle: Codable, Equatable, Sendable {
    case trial(firstPaidChargeAt: Date)
    case active
    case cancelled(cancelledAt: Date, accessUntil: Date)

    public func status(
        asOf date: Date,
        timeZone: TimeZone
    ) -> SubscriptionStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let day = calendar.startOfDay(for: date)

        switch self {
        case .trial(let firstPaidChargeAt):
            return day >= calendar.startOfDay(for: firstPaidChargeAt)
                ? .active
                : .trial
        case .active:
            return .active
        case .cancelled(_, let accessUntil):
            return day >= calendar.startOfDay(for: accessUntil)
                ? .expired
                : .cancelledWithAccess
        }
    }
}
```

Modify `Subscription` so both initializers accept these backward-compatible
defaults and store them:

```swift
public let lifecycle: SubscriptionLifecycle
public let isArchived: Bool

// Add at the end of each public initializer before the closing parenthesis:
lifecycle: SubscriptionLifecycle = .active,
isArchived: Bool = false
```

Modify `SubscriptionCreationInput`:

```swift
public let initialStatus: SubscriptionInitialStatus

// Initializer default:
initialStatus: SubscriptionInitialStatus = .active
```

Do not change forecast or Workspace behavior yet.

- [ ] **Step 4: Add creation-domain regression assertions**

In `SubscriptionDomainTests.swift`, construct one Trial Subscription and assert:

```swift
#expect(
    subscription.lifecycle
        == .trial(firstPaidChargeAt: subscription.confirmedNextRenewal)
)
#expect(subscription.isArchived == false)
```

At this task boundary, construct the lifecycle explicitly; Workspace creation
will consume `initialStatus` in Task 5.

- [ ] **Step 5: Run Core tests and verify GREEN**

Run the focused test, then the full Core command from Step 2 without
`--filter`. Expected: all 26 or more tests pass with zero failures.

- [ ] **Step 6: Commit**

```bash
git add Packages/SubscriptionCore
git commit -m "feat(core): model subscription lifecycle"
```

---

### Task 2: Scoped Workspace presentation and optional next charge

**Files:**

- Modify:
  `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify:
  `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
- Modify:
  `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/FixedBillingScheduleTests.swift`
- Modify:
  `SubscriptionManager/Persistence/SwiftDataSubscriptionRepository.swift`
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify:
  `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify: app preview/test repositories conforming to `SubscriptionRepository`

**Interfaces:**

- Consumes: Task 1 lifecycle/status types.
- Produces:
  `SubscriptionLibraryScope`,
  scoped `SubscriptionLibraryState`,
  status-aware `SubscriptionSummary`,
  status-aware `SubscriptionDetailState`,
  and `SubscriptionRepository.listSubscriptions() -> [Subscription]`.

- [ ] **Step 1: Write failing scoped-library and optional-charge tests**

Add tests using an in-memory repository with one Active, one Cancelled, and one
Archived subscription:

```swift
@Test("Current and archived scopes never mix records")
@MainActor
func libraryScopesRemainDisjoint() throws {
    let repository = LifecycleRepository(
        subscriptions: [
            makeSubscription(id: currentID, lifecycle: .active),
            makeSubscription(
                id: archivedID,
                lifecycle: .cancelled(
                    cancelledAt: cancelledAt,
                    accessUntil: accessUntil
                ),
                isArchived: true
            ),
        ]
    )
    let workspace = SubscriptionWorkspace(
        repository: repository,
        now: { now },
        calendar: calendar
    )

    workspace.loadLibrary(scope: .current)
    guard case .loaded(.current, let current) = workspace.libraryState else {
        Issue.record("Expected current scope")
        return
    }
    #expect(current.map(\.id) == [currentID])

    workspace.loadLibrary(scope: .archived)
    guard case .loaded(.archived, let archived) = workspace.libraryState else {
        Issue.record("Expected archived scope")
        return
    }
    #expect(archived.map(\.id) == [archivedID])
    #expect(archived.first?.nextExpectedCharge == nil)
}
```

Add a detail test asserting a Cancelled subscription loads with
`.cancelledWithAccess` and `nextExpectedCharge == nil`. Add an Active assertion
that the optional next charge is non-`nil`.

- [ ] **Step 2: Run the focused Workspace suite and verify RED**

Run the Core command from Task 1 with:

```bash
--filter SubscriptionWorkspaceTests
```

Expected: compile failures for `.current`, scoped state patterns, and
`nextExpectedCharge`.

- [ ] **Step 3: Replace the presentation and repository contracts**

In `SubscriptionCore.swift`, define:

```swift
public enum SubscriptionLibraryScope: Hashable, Sendable {
    case current
    case archived
}

public enum SubscriptionLibraryState: Equatable, Sendable {
    case loading(SubscriptionLibraryScope)
    case empty(SubscriptionLibraryScope)
    case loaded(SubscriptionLibraryScope, [SubscriptionSummary])
    case failed(SubscriptionLibraryScope)
}

public enum SubscriptionDetailState: Equatable, Sendable {
    case notLoaded
    case loaded(
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    )
    case notFound
    case failed
}
```

Remove `Subscription.firstExpectedCharge`. Replace the old Summary initializer
and field with:

```swift
public let status: SubscriptionStatus
public let nextExpectedCharge: ExpectedCharge?

public init(
    subscription: Subscription,
    status: SubscriptionStatus,
    nextExpectedCharge: ExpectedCharge?
) {
    id = subscription.id
    serviceIdentity = subscription.serviceIdentity
    serviceName = subscription.serviceName
    plan = subscription.plan
    category = subscription.category
    originalAmount = subscription.originalAmount
    billingSchedule = subscription.billingSchedule
    confirmedNextRenewal = subscription.confirmedNextRenewal
    self.status = status
    self.nextExpectedCharge = nextExpectedCharge
}
```

Change the repository protocol exactly:

```swift
func listSubscriptions() throws -> [Subscription]
```

Every Core test repository must return full Subscriptions. Do not add deletion
or archive-specific repository methods in this task.

- [ ] **Step 4: Make Workspace own presentation resolution**

Initialize:

```swift
public private(set) var libraryState: SubscriptionLibraryState =
    .loading(.current)
```

Implement:

```swift
public func loadLibrary(
    scope: SubscriptionLibraryScope = .current
) {
    libraryState = .loading(scope)
    do {
        let subscriptions = try repository.listSubscriptions()
            .filter { $0.isArchived == (scope == .archived) }
        let summaries = subscriptions.map(makeSummary)
        libraryState = summaries.isEmpty
            ? .empty(scope)
            : .loaded(scope, summaries)
    } catch {
        libraryState = .failed(scope)
    }
}
```

Add private `makeSummary(_:)` and `makeDetail(_:)` methods. Resolve the status
with the billing schedule time zone and produce `nextExpectedCharge` only when
`subscription.isArchived == false` and the persisted lifecycle is not
`.cancelled`. Use the existing forecast generator with
`through: .distantFuture, maximumCount: 1`.

Add the same eligibility guard to `makeExpectedCharges`; a Cancelled or
Archived subscription returns `[]` immediately.

Update `loadSubscription(id:)`, create, and edit success paths to construct the
new detail state through `makeDetail`.

- [ ] **Step 5: Update existing Core tests and verify GREEN**

Update pattern matches from `.loaded(subscription)` to:

```swift
case .loaded(let subscription, _, _)
```

Update `LibraryView` for scoped library-state patterns and
`SubscriptionDetailView` to pass the associated optional
`nextExpectedCharge` into its detail form. Render the existing Next Expected
Charge section only when that value is non-`nil`; status styling and lifecycle
actions remain deferred to Tasks 5 and 6.

Update every Core and app repository to return `[Subscription]`. The SwiftData
adapter already constructs each full aggregate before mapping it to Summary, so
remove only that final mapping. Replace legacy test assertions against
`Subscription.firstExpectedCharge` with assertions against Workspace
presentation or the persisted renewal gate, as appropriate. Run the complete
Core and app-unit suites and XcodeBuildMCP `build_sim`. Expected: all tests
pass; Active legacy behavior remains unchanged and the App compiles at this
commit boundary.

- [ ] **Step 6: Commit**

```bash
git add Packages/SubscriptionCore SubscriptionManager SubscriptionManagerTests
git commit -m "refactor(core): resolve lifecycle presentations in workspace"
```

---

### Task 3: SwiftData lifecycle contract and single-record deletion

**Files:**

- Modify: `SubscriptionManager/Persistence/SubscriptionRecord.swift`
- Modify:
  `SubscriptionManager/Persistence/SwiftDataSubscriptionRepository.swift`
- Modify:
  `SubscriptionManagerTests/SwiftDataSubscriptionRepositoryTests.swift`
- Modify:
  `SubscriptionManagerTests/SubscriptionLookupTests.swift`
- Modify: all app preview/test repositories conforming to
  `SubscriptionRepository`
- Modify:
  `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify: Core test repositories conforming to `SubscriptionRepository`

**Interfaces:**

- Consumes the Task 2 list contract and Task 1 lifecycle values.
- Produces additive SwiftData lifecycle fields,
  `SubscriptionRepository.deleteSubscription(id:)`, and atomic UUID deletion.

- [ ] **Step 1: Write failing adapter tests**

Add tests for:

```swift
@Test("Legacy rows load as active and unarchived")
@Test("Trial active and cancelled lifecycle representations round trip")
@Test("Partial lifecycle storage fails explicitly")
@Test("Deleting one identifier preserves unrelated subscriptions")
@Test("A failed delete save rolls back the selected record")
```

The round-trip test must assert all lifecycle associated dates and
`isArchived`. The invalid combinations table must include:

- legacy/Active with a trial date;
- Trial without a trial date;
- Trial with cancellation dates;
- Cancelled with only one cancellation field;
- Cancelled with access before cancellation;
- unknown discriminator.

- [ ] **Step 2: Run the app unit tests and verify RED**

Use XcodeBuildMCP `test_sim` with:

```json
{
  "extraArgs": [
    "-only-testing:SubscriptionManagerTests/SwiftDataSubscriptionRepositoryTests"
  ],
  "progress": true
}
```

Expected: compile failures for missing record fields and delete method.

- [ ] **Step 3: Add the minimal repository deletion contract**

Add exactly:

```swift
func deleteSubscription(id: UUID) throws
```

to `SubscriptionRepository`. Update Core and app test/preview repositories with
an explicit implementation. Do not add archive-specific persistence methods.

- [ ] **Step 4: Add only the additive record fields**

In `SubscriptionRecord.swift` add optional storage fields with `nil` defaults:

```swift
var lifecycleRawValue: String?
var trialFirstPaidChargeAt: Date?
var cancelledAt: Date?
var accessUntil: Date?
var isArchived: Bool?
```

Do not add an archive timestamp or event collection.

- [ ] **Step 5: Encode and decode the exact truth table**

In `apply(_:to:)`:

```swift
record.isArchived = subscription.isArchived
switch subscription.lifecycle {
case .active:
    record.lifecycleRawValue = "active"
    record.trialFirstPaidChargeAt = nil
    record.cancelledAt = nil
    record.accessUntil = nil
case .trial(let firstPaidChargeAt):
    record.lifecycleRawValue = "trial"
    record.trialFirstPaidChargeAt = firstPaidChargeAt
    record.cancelledAt = nil
    record.accessUntil = nil
case .cancelled(let cancelledAt, let accessUntil):
    record.lifecycleRawValue = "cancelled"
    record.trialFirstPaidChargeAt = nil
    record.cancelledAt = cancelledAt
    record.accessUntil = accessUntil
}
```

Decode only the four valid rows from the design truth table. Throw one private
`RepositoryError.invalidLifecycleStorage` for unknown, partial, or
chronologically invalid representations. `nil` archive means false.

- [ ] **Step 6: Implement atomic deletion**

Implement:

```swift
func deleteSubscription(id: UUID) throws {
    let lookupID = id
    var descriptor = FetchDescriptor<SubscriptionRecord>(
        predicate: #Predicate { $0.id == lookupID }
    )
    descriptor.fetchLimit = 1
    do {
        guard let record = try modelContext.fetch(descriptor).first else {
            return
        }
        modelContext.delete(record)
        try save(modelContext)
    } catch {
        modelContext.rollback()
        throw error
    }
}
```

- [ ] **Step 7: Run adapter and full app-unit tests**

Run the focused XcodeBuildMCP test from Step 2, then:

```json
{
  "extraArgs": ["-only-testing:SubscriptionManagerTests"],
  "progress": true
}
```

Expected: all app unit tests pass and every conformer compiles.

- [ ] **Step 8: Commit**

```bash
git add Packages/SubscriptionCore SubscriptionManager/Persistence \
  SubscriptionManagerTests SubscriptionManager/Library SubscriptionManager/App
git commit -m "feat(persistence): store subscription lifecycle"
```

---

### Task 4: Workspace lifecycle commands and transition validation

**Files:**

- Modify:
  `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionLifecycle.swift`
- Modify:
  `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify:
  `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Interfaces:**

- Produces:
  `SubscriptionLifecycleActionError`,
  `recordCancellation`,
  `reactivate`,
  `archive`,
  `restore`,
  and `deletePermanently`.
- Consumes Task 3's explicit repository deletion contract.
- Commands mutate one repository aggregate, then reload the selected scope and
  current detail.

- [ ] **Step 1: Write the failing transition matrix tests**

Add public-Workspace tests for:

1. Trial/Active cancellation succeeds.
2. Cancellation in the future fails.
3. Access before cancellation fails.
4. Cancellation immediately empties existing forecasts.
5. Cancelled/Expired reactivation succeeds only with a next-renewal local day
   on or after today.
6. Archive succeeds only for current records and empties forecasts.
7. Restore succeeds only for archived records and preserves lifecycle.
8. Every other transition returns `.invalidLifecycleTransition`.
9. Ordinary edit preserves lifecycle, archive flag, and Confirmed Charges.
10. Permanent delete succeeds for current and archived records across every
    lifecycle and removes only the requested UUID.
11. Repository failure preserves the loaded detail and existing forecasts,
    and exposes `.persistenceFailed`.

Use assertions shaped like:

```swift
workspace.recordCancellation(
    id: subscription.id,
    cancelledAt: cancelledAt,
    accessUntil: accessUntil
)

#expect(repository.subscription(id: subscription.id)?.lifecycle == expected)
#expect(workspace.expectedCharges == [])
#expect(workspace.lifecycleActionError == nil)
```

For an invalid transition:

```swift
workspace.restore(id: currentSubscription.id)
#expect(workspace.lifecycleActionError == .invalidLifecycleTransition)
#expect(repository.subscription(id: currentSubscription.id) == currentSubscription)
```

- [ ] **Step 2: Run Workspace lifecycle tests and verify RED**

Run the Task 1 Core command with:

```bash
--filter SubscriptionWorkspaceTests
```

Expected: compile failures because commands and action errors do not exist.

- [ ] **Step 3: Implement one action-error enum and local-day helpers**

In `SubscriptionLifecycle.swift`:

```swift
public enum SubscriptionLifecycleActionError: Equatable, Sendable {
    case invalidLifecycleTransition
    case cancellationDateInFuture
    case accessEndsBeforeCancellation
    case nextRenewalInPast
    case persistenceFailed
}

func billingLocalCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
}

func normalizedBillingLocalNoon(
    _ date: Date,
    timeZone: TimeZone
) -> Date? {
    var calendar = billingLocalCalendar(timeZone: timeZone)
    var components = calendar.dateComponents(
        [.era, .year, .month, .day],
        from: date
    )
    components.hour = 12
    return calendar.date(from: components)
}
```

Workspace stores one optional:

```swift
public private(set) var lifecycleActionError:
    SubscriptionLifecycleActionError?
```

Do not add a retry state machine.

- [ ] **Step 4: Implement minimal copy and mutation paths**

Add one internal Subscription copy helper whose optional parameters mean
"preserve existing value":

```swift
func replacingLifecycleFacts(
    lifecycle: SubscriptionLifecycle? = nil,
    isArchived: Bool? = nil,
    confirmedNextRenewal: Date? = nil
) -> Subscription
```

It must copy every other source field and `confirmedCharges`.

Implement exact public signatures:

```swift
public func recordCancellation(
    id: UUID,
    cancelledAt: Date,
    accessUntil: Date
)

public func reactivate(id: UUID, nextRenewal: Date)
public func archive(id: UUID)
public func restore(id: UUID)
public func deletePermanently(id: UUID)
```

Each method:

1. Clears the previous action error.
2. Fetches the selected aggregate.
3. Checks the transition matrix and billing-local validation.
4. Normalizes date-only inputs to local noon.
5. Updates or deletes one UUID.
6. Rebuilds loaded detail/presentation and reloads the currently selected
   library scope.
7. Maps repository failure to `.persistenceFailed` without replacing loaded
   detail.

`reactivate` preserves `FixedBillingSchedule` and Renewal Anchor, replaces the
Confirmed Next Renewal gate, and changes lifecycle to `.active`.

- [ ] **Step 5: Verify RED-to-GREEN one command at a time**

Run each newly added test after implementing only its required command. After
the transition matrix is green, run the full Core suite. Expected: zero
failures and no regression in fixed-schedule boundary tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/SubscriptionCore
git commit -m "feat(core): add lifecycle workspace commands"
```

---

### Task 5: Active/Trial creation and localized lifecycle presentation

**Files:**

- Create:
  `SubscriptionManager/Library/SubscriptionLifecycleSupport.swift`
- Modify: `SubscriptionManager/Library/AddSubscriptionView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify:
  `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
- Modify: `SubscriptionManagerTests/ManagementURLValidationTests.swift`
- Modify:
  `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Regenerate:
  `SubscriptionManager.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces localized status titles, status badge, lifecycle action-error copy,
  and Active/Trial add-form selection.

- [ ] **Step 1: Write failing Workspace creation tests**

Add two tests:

```swift
@Test("Active creation stores an active lifecycle")
@Test("Trial creation snapshots next renewal as first paid charge")
```

For Trial:

```swift
workspace.createSubscription(
    SubscriptionCreationInput(
        serviceName: "Example",
        plan: "Trial",
        category: "Other",
        originalAmount: money,
        startDate: start,
        confirmedNextRenewal: firstPaidCharge,
        managementURL: nil,
        notes: "",
        initialStatus: .trial
    )
)
#expect(
    repository.storedSubscription?.lifecycle
        == .trial(firstPaidChargeAt: firstPaidCharge)
)
```

- [ ] **Step 2: Verify RED**

Run the focused `SubscriptionWorkspaceTests`. Expected: the created
Subscription is still Active because Workspace ignores `initialStatus`.

- [ ] **Step 3: Implement creation mapping**

When Workspace constructs a new Subscription:

```swift
let lifecycle: SubscriptionLifecycle =
    input.initialStatus == .trial
        ? .trial(firstPaidChargeAt: input.confirmedNextRenewal)
        : .active
```

Pass `lifecycle` and `isArchived: false` into the aggregate. Verify the focused
tests turn green.

- [ ] **Step 4: Write failing Trial and Simplified Chinese UI tests**

Add:

```swift
func testCreatesTrialWithVisibleTrialStatus()
func testSimplifiedChineseLifecycleStatusIsLocalized()
```

The first test opens Add, selects the Trial segment through
`subscription.form.initial-status`, saves, opens detail, and expects
`subscription.status` to contain `Trial`. The second performs the same flow in
`zh-Hans` and expects `试用中`.

- [ ] **Step 5: Run each new UI test and verify RED**

Use XcodeBuildMCP `test_sim` with one
`-only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/<name>`
argument at a time.

Expected: the tests fail because the initial-status picker and status badge do
not exist.

- [ ] **Step 6: Add the native initial-status picker**

In `AddSubscriptionView` add:

```swift
@State private var initialStatus: SubscriptionInitialStatus = .active
```

Add a segmented Picker in the Subscription Details section:

```swift
Picker("Initial Status", selection: $initialStatus) {
    Text("Active").tag(SubscriptionInitialStatus.active)
    Text("Trial").tag(SubscriptionInitialStatus.trial)
}
.pickerStyle(.segmented)
.accessibilityIdentifier("subscription.form.initial-status")

if initialStatus == .trial {
    Text("Next Renewal is the first paid charge date.")
        .font(.footnote)
        .foregroundStyle(.secondary)
}
```

Pass `initialStatus` to `SubscriptionCreationInput`.

- [ ] **Step 7: Create minimal shared UI support**

`SubscriptionLifecycleSupport.swift` contains:

```swift
func localizedSubscriptionStatus(
    _ status: SubscriptionStatus
) -> String

func lifecycleActionErrorText(
    _ error: SubscriptionLifecycleActionError
) -> LocalizedStringKey

struct SubscriptionStatusBadge: View {
    let status: SubscriptionStatus
    var body: some View {
        Text(localizedSubscriptionStatus(status))
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("subscription.status")
    }
}
```

Use a plain label treatment; do not introduce custom glass, animation, or a
design-system abstraction. Render this badge from the loaded detail
presentation so the UI tests observe Workspace-resolved status.

- [ ] **Step 8: Add exact English and Simplified Chinese strings**

Update `Localizable.xcstrings` for Active, Trial, Cancelled with Access,
Expired, Initial Status, the trial explanation, lifecycle validation, archive,
restore, reactivation, record-cancellation, and permanent-delete copy.

Validate:

```bash
jq empty SubscriptionManager/Resources/Localizable.xcstrings
```

Expected: exit 0.

- [ ] **Step 9: Verify GREEN and commit**

Run:

```bash
xcodegen generate
git diff --check
```

Then run both new UI tests, the full Core and app-unit suites, and
XcodeBuildMCP `build_sim`.

```bash
git add Packages/SubscriptionCore SubscriptionManager.xcodeproj \
  SubscriptionManager/Library \
  SubscriptionManager/Resources SubscriptionManagerTests \
  SubscriptionManagerUITests
git commit -m "feat(ui): add trial creation state"
```

---

### Task 6: Cancellation/reactivation detail actions and focused date forms

**Files:**

- Create:
  `SubscriptionManager/Library/RecordCancellationView.swift`
- Create:
  `SubscriptionManager/Library/ReactivateSubscriptionView.swift`
- Modify:
  `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify:
  `SubscriptionManager/Library/SubscriptionLifecycleSupport.swift`
- Modify:
  `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify:
  `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Regenerate:
  `SubscriptionManager.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes Workspace commands from Task 4.
- Produces native cancellation/reactivation sheets and their valid action-menu
  entries. Archive, restore, and delete entries remain deferred until their
  own failing UI tests in Tasks 7 and 8.

- [ ] **Step 1: Write the failing cancellation and reactivation UI tests**

Add:

```swift
func testRecordsCancellationAndHidesNextExpectedCharge()
func testReactivatesWithConfirmedNextRenewal()
```

The test creates a subscription, opens detail, invokes
`subscription.lifecycle.record-cancellation`, saves the cancellation form,
then asserts:

- `subscription.status` contains `Cancelled with Access`;
- `Next Expected Charge` is absent;
- the detail still shows the access-until date.

The reactivation test continues from a cancelled record, invokes
`subscription.lifecycle.reactivate`, chooses a valid future local day, and
asserts Active status plus a visible Next Expected Charge on the confirmed
date.

- [ ] **Step 2: Run both focused UI tests and verify RED**

Use XcodeBuildMCP once per test:

```json
{
  "extraArgs": [
    "-only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testRecordsCancellationAndHidesNextExpectedCharge"
  ],
  "progress": true
}
```

Expected: both fail because lifecycle actions and their forms do not exist.

- [ ] **Step 3: Build the two small forms**

`RecordCancellationView` owns only two Date values and calls:

```swift
workspace.recordCancellation(
    id: subscription.id,
    cancelledAt: selectedCancellationDate,
    accessUntil: selectedAccessUntil
)
```

Required identifiers:

```text
subscription.cancellation.form
subscription.cancellation.date
subscription.cancellation.access-until
subscription.cancellation.save
```

`ReactivateSubscriptionView` owns one Next Renewal Date and calls:

```swift
workspace.reactivate(
    id: subscription.id,
    nextRenewal: selectedNextRenewal
)
```

Required identifiers:

```text
subscription.reactivation.form
subscription.reactivation.next-renewal
subscription.reactivation.save
```

Both forms set the subscription billing time zone for their graphical
date-only pickers and leave normalization/validation to Workspace. They show
`lifecycleActionErrorText`, dismiss only after the Workspace detail reflects
the successful mutation, and contain no provider-contact behavior.

- [ ] **Step 4: Make detail rendering status-aware**

Update `SubscriptionDetailView` patterns for:

```swift
case .loaded(
    let subscription,
    let status,
    let nextExpectedCharge
)
```

Render `SubscriptionStatusBadge(status:)`. Render the Next Expected Charge
section only when `nextExpectedCharge` is non-`nil`. For a persisted
`.cancelled` lifecycle, add one Lifecycle section that shows the normalized
Cancellation Date and Access Until date using the billing time zone.

Use one action Menu:

- Trial/Active current record: Record Cancellation.
- Cancelled/Expired current record: Reactivate.

Edit remains available only for current records. Archive and Restore call
Workspace only after their failing test in Task 7. Cancellation and
reactivation present their focused sheets. Permanent Delete is added
test-first in Task 8.

- [ ] **Step 5: Verify GREEN and run build checks**

Run:

```bash
xcodegen generate
git diff --check
```

Then run both focused UI tests, all app unit tests, and XcodeBuildMCP
`build_sim`. Expected: zero failures and no warning introduced by the new
views.

- [ ] **Step 6: Commit**

```bash
git add SubscriptionManager.xcodeproj SubscriptionManager/Library \
  SubscriptionManager/Resources SubscriptionManagerUITests
git commit -m "feat(ui): add subscription lifecycle actions"
```

---

### Task 7: Current/Archived navigation and list status

**Files:**

- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionRow.swift`
- Modify:
  `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify:
  `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: preview repositories in affected SwiftUI files
- Modify:
  `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**

- Consumes scoped library state from Task 2.
- Produces one root `NavigationStack` and one private scope-parameterized
  library screen for `.current` and `.archived`; no nested navigation stack
  and no second Workspace cache.

- [ ] **Step 1: Write a failing scoped-state regression test**

In `SubscriptionWorkspaceTests`, reproduce:

1. Load `.archived`.
2. Load `.current`.
3. Assert the state carries `.current` and no archived IDs.
4. Archive a current detail.
5. Assert current scope reloads without that ID.

Run the focused Workspace suite. Expected: RED until action refresh preserves
the selected scope.

- [ ] **Step 2: Make the scoped Workspace regression GREEN**

Update the Task 4 mutation-refresh helper so it reads the scope currently
carried by `libraryState` and reloads that scope after archive/restore. Run the
focused Core test until GREEN.

- [ ] **Step 3: Write and run the failing archive/restore UI test**

Add:

```swift
func testArchivesAndRestoresSubscription()
```

The test archives a detail, verifies it disappears from Current, opens
`library.archived`, restores it, and verifies it returns to Current with the
same lifecycle status.

Run only this test. Expected: failure because Archived navigation does not
exist.

- [ ] **Step 4: Parameterize the Library view by scope**

Keep `LibraryView` as the only owner of `NavigationStack`. Extract its existing
screen body into one private `ScopedLibraryView`:

```swift
private struct ScopedLibraryView: View {
    let workspace: SubscriptionWorkspace
    let scope: SubscriptionLibraryScope
}
```

Match only state values carrying the requested scope. If the state scope does
not match, show loading while `.task(id: scope)` calls:

```swift
workspace.loadLibrary(scope: scope)
```

`LibraryView` renders `ScopedLibraryView(..., scope: .current)` inside its
single stack. Current title: `Subscriptions`. Archived title: `Archived`.

- [ ] **Step 5: Add the one Archived entry**

The Current toolbar adds a native NavigationLink:

```swift
NavigationLink(value: SubscriptionLibraryScope.archived) {
    Label("Archived", systemImage: "archivebox")
}
.accessibilityIdentifier("library.archived")
```

Register one navigation destination for the scope and render
`ScopedLibraryView(workspace: workspace, scope: .archived)`. Do not create a
fourth tab, a nested `NavigationStack`, or a second Workspace.

After the failing test exists, add Archive to the current detail action menu
for every lifecycle, and Restore to the archived detail action menu. Both call
Workspace directly. Keep Edit current-only.

- [ ] **Step 6: Show status in each row**

`SubscriptionRow` renders the Workspace-resolved
`SubscriptionStatusBadge(status: subscription.status)`. Its accessibility
label includes localized status. When `nextExpectedCharge` is nil, show the
status rather than a stale confirmed-renewal date.

- [ ] **Step 7: Run Core, app-unit, and build checks**

Run the full Core suite, app unit suite, and XcodeBuildMCP `build_sim`.
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add Packages/SubscriptionCore SubscriptionManager/Library \
  SubscriptionManager/Resources SubscriptionManagerUITests
git commit -m "feat(ui): browse archived subscriptions"
```

---

### Task 8: Confirmed permanent deletion, generated project, and delivery gates

**Files:**

- Modify:
  `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify:
  `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Modify:
  `SubscriptionManager/Resources/Localizable.xcstrings`
- Regenerate:
  `SubscriptionManager.xcodeproj/project.pbxproj`

**Interfaces:**

- Verifies the complete externally observable TB-04 contract.

- [ ] **Step 1: Add the failing permanent-deletion UI test**

Add this focused test with existing launch/store helpers:

```swift
func testPermanentDeleteRequiresConfirmation()
```

Stable identifiers to assert:

```text
subscription.status
subscription.lifecycle.actions
subscription.lifecycle.record-cancellation
subscription.lifecycle.archive
subscription.lifecycle.restore
subscription.lifecycle.delete
library.archived
subscription.detail.not-found
```

The test must:

1. Open Delete.
2. Cancel the confirmation.
3. Assert the detail still exists.
4. Open Delete again and confirm.
5. Assert `subscription.detail.not-found`.

- [ ] **Step 2: Run the UI test and verify RED**

Use XcodeBuildMCP `test_sim` with one
`-only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/<name>`
argument. Expected: failure because Permanent Delete is not yet present.

- [ ] **Step 3: Add only local destructive dialog state**

In `SubscriptionDetailView`, store only:

```swift
@State private var subscriptionPendingDeletion: Subscription?
```

Add Permanent Delete to both current and archived action menus. Use a native
destructive confirmation dialog. Cancel calls no Workspace method; confirm
calls:

```swift
workspace.deletePermanently(id: subscription.id)
```

Do not add pending-deletion state to Core. Re-run the focused UI test until
GREEN. Do not add animations, custom navigation, screenshots, or provider
links.

- [ ] **Step 4: Regenerate and validate the tracked Xcode project**

Run:

```bash
xcodegen generate
git diff --check
jq empty SubscriptionManager/Resources/Localizable.xcstrings
```

Expected: the three new SwiftUI files and new Core/test file are included in
the generated build graph. The three SwiftUI files are explicit
`project.pbxproj` sources, while Swift Package Manager discovers the new Core
source and test files from the package directories. Validation commands exit
0.

- [ ] **Step 5: Run the complete test matrix**

Core:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/subscription-manager-tb04-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/subscription-manager-tb04-swiftpm-cache \
swift test --disable-sandbox \
  --scratch-path /private/tmp/subscription-manager-tb04-swiftpm-build
```

XcodeBuildMCP app unit tests:

```json
{
  "extraArgs": ["-only-testing:SubscriptionManagerTests"],
  "progress": true
}
```

XcodeBuildMCP UI tests:

```json
{
  "extraArgs": ["-only-testing:SubscriptionManagerUITests"],
  "progress": true
}
```

Switch XcodeBuildMCP defaults to `iPad Pro 13-inch (M5)` and run `build_sim`.

macOS:

```bash
xcodebuild -quiet \
  -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/subscription-manager-tb04-macos-derived \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: all tests pass; iPhone, iPad, and macOS builds succeed.

- [ ] **Step 6: Commit the completed implementation**

```bash
git add SubscriptionManager.xcodeproj SubscriptionManager/Library \
  SubscriptionManagerUITests SubscriptionManager/Resources
git commit -m "test: cover subscription lifecycle flows"
```

- [ ] **Step 7: Final pre-PR audit**

Run:

```bash
git status --short
git diff origin/main...HEAD --check
git log --oneline origin/main..HEAD
```

Expected: clean worktree, no whitespace errors, and only TB-04 commits.
Then run independent verification, open a PR with `Closes #5`, wait for real
CodeRabbit/Codex output, regression-test valid findings, and merge only when
the PR is clean.
