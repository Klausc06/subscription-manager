# Direct Editor and Atomic Subscription Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the read-only-first subscription flow with a compact direct
editor whose ordinary Save atomically updates price history, linked billing
dates, and all amount consumers without removing lifecycle or library actions.

**Architecture:** Keep `SubscriptionWorkspace` as the public command/state seam
and keep the current repository, Fixed Billing Schedule, lifecycle, catalog
matcher, and platform adapters. Add a public effective-amount resolver, extend
the existing edit input/command to save price history in the same repository
update, and share one app-layer draft plus semantic form sections between Add
and Edit. Reuse the existing UUID navigation destination so deep links and
Library/Upcoming routes converge without a second router.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, Swift Testing, XCTest
UI tests, `SubscriptionCore`, iOS/iPadOS/macOS system controls.

**Source-of-truth crosswalk:** Requirements live in
`docs/research/2026-07-30-round-2-requirements.md`; researched decisions and
batch boundaries live in `docs/research/2026-08-01-round-2-synthesis.md`; the
evidence shipping gate lives in
`docs/research/2026-08-01-round-2-manifest-validation.md`. The Plan Self-Review
at the end maps Batch A tasks back to requirement IDs. If implementation
evidence contradicts a decision, update the synthesis explicitly rather than
quietly changing this plan or weakening a test.

## Global Constraints

- The Subscription Library remains authoritative; Calendar is a projection.
- Service Name, price, actual charge currency, positive Fixed Billing Schedule
  interval, and one billing date are required.
- Plan, category, management URL, and notes are optional and never block Save.
- `originalAmount` remains immutable; Confirmed Charges remain immutable.
- Effective Subscription Status is derived from Subscription Lifecycle and is
  not edited as a stored enum.
- Renewal Anchor stays internal and never appears in Add/Edit copy or
  accessibility labels.
- Save is the only persistence boundary; dirty Back/dismiss never discards
  silently.
- Full-swipe Delete continues to open named permanent-delete confirmation.
- Query/typeahead and exact catalog reconciliation remain separate operations.
- Batch A does not import, reclassify, or make selectable any provisional
  catalog offer. The shipped `CatalogSnapshot` remains byte-for-byte unchanged;
  OFF/OGD and second-community findings remain research inputs until the
  normalized evidence gate receives an independent PASS.
- No TCA/Redux, DI framework, third-party search, third-party calendar, new
  persistent store, or runtime `Service -> Edition -> Offer -> Price` graph.
- Preserve native design language, existing localization system, VoiceOver,
  Dynamic Type, iPhone, iPad, and macOS behavior.
- Tests observe public domain/Workspace/UI seams, not private implementation
  calls.

---

## Public Test Seams

The approved seams for this batch are:

1. `Subscription.amount(onBillingDay:)` for effective-money rules;
2. `SubscriptionWorkspace.editSubscription(id:input:forecastThrough:)` for
   atomic edit, validation, history, reconciliation, and consumer refresh;
3. `SubscriptionDraft` public-to-app behavior through value operations and
   visible validation;
4. real SwiftUI accessibility identifiers for Add, Edit, lifecycle, row
   actions, and dirty navigation;
5. `SubscriptionRepository` only as an injected persistence boundary in
   Workspace tests, and an in-memory SwiftData container for adapter tests.

## File Map

### Core files

- Modify `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
  for `Subscription.amount(onBillingDay:)`, summary amount, edit input, atomic
  edit behavior, validation, sorting, quote discovery, and amount consumers.
- Modify `Packages/SubscriptionCore/Sources/SubscriptionCore/CatalogOfferMatcher.swift`
  to reconcile against effective next-renewal amount.
- Modify `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionDomainTests.swift`
  for resolver examples.
- Modify `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
  for atomic edit and consumer behavior.
- Modify `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogOfferMatcherTests.swift`
  for effective-amount reconciliation.
- Modify `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/FixedBillingScheduleTests.swift`
  and every `SubscriptionEditInput` call site to pass the required amount.

### App files

- Create `SubscriptionManager/Library/SubscriptionDraft.swift` for shared
  app-layer draft state and date-source operations.
- Create `SubscriptionManager/Library/SubscriptionEditorSections.swift` for
  compact shared Service, Price, Schedule, and Additional Details sections.
- Create `SubscriptionManager/Library/BillingDateTaskView.swift` for explicit
  Cancel/Done date editing.
- Create `SubscriptionManager/Library/SubscriptionEditorSession.swift` for the
  one draft baseline, pending exit, and dirty-navigation coordinator shared by
  compact navigation and regular-width selection.
- Modify `SubscriptionManager/Library/AddSubscriptionView.swift` to use the
  shared draft/sections and optional metadata policy.
- Modify `SubscriptionManager/Library/EditSubscriptionView.swift` to use the
  shared draft/sections, amount/currency editing, and direct-navigation save.
- Modify `SubscriptionManager/Library/SubscriptionDetailView.swift` to become
  the direct editor destination with lifecycle/history sections rather than a
  read-only form and catch-all menu.
- Modify `SubscriptionManager/Library/LibraryView.swift` for direct routing,
  archived editor destination, dirty navigation, overdue Confirm Charge, and
  accessibility action parity.
- Modify `SubscriptionManager/Library/SubscriptionRow.swift` and
  `SubscriptionManager/App/SubscriptionManagerApp.swift` to display effective
  summary amount.
- Modify `SubscriptionManager/Library/RecordPriceChangeView.swift` only to
  remove its production route; delete the file if no test or preview consumer
  remains after the route removal.
- Modify `SubscriptionManager/Resources/Localizable.xcstrings` for new editor,
  date-task, discard, Price Required, and lifecycle copy.
- Modify `SubscriptionManager.xcodeproj/project.pbxproj` to add every new app
  and app-test Swift file to its PBX group and Sources build phase. This project
  explicitly enumerates files and has no generated project definition.

### App tests

- Create `SubscriptionManagerTests/SubscriptionDraftTests.swift`.
- Modify `SubscriptionManagerTests/SwiftDataSubscriptionRepositoryTests.swift`
  only if adapter behavior changes; a Workspace-only atomic update should not
  require a repository protocol expansion.
- Modify `SubscriptionManagerUITests/SubscriptionManagerUITests.swift` for
  direct edit, optional metadata, explicit date completion, dirty navigation,
  lifecycle relocation, archived editing, and row-action parity.

### Xcode project rule

The project has no generated project definition and no `.xctestplan`. Every
new Swift file must receive a `PBXFileReference`, `PBXBuildFile`, group child,
and Sources build-phase entry in
`SubscriptionManager.xcodeproj/project.pbxproj`. The three editor app files and
`SubscriptionEditorSession.swift` belong only to the app target;
`SubscriptionDraftTests.swift` belongs only to `SubscriptionManagerTests`.
New UI scenarios stay in the already-wired
`SubscriptionManagerUITests.swift`. If `RecordPriceChangeView.swift` is deleted,
remove all four of its PBX entries in the same change.

### Host preflight for every Xcode command

Run on the macOS host, not a restricted shell that cannot reach
CoreSimulatorService:

```bash
xcodebuild -list -project SubscriptionManager.xcodeproj
xcodebuild -showdestinations -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager
xcrun simctl list devices available
```

Record one bootable iPhone and one iPad UDID, then export task-scoped variables
used by every command below:

```bash
export SUBSCRIPTION_BATCH_A_SIMULATOR_UDID='<available iPhone simulator UDID>'
export SUBSCRIPTION_BATCH_A_IPAD_UDID='<available iPad simulator UDID>'
xcrun simctl bootstatus "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" -b
```

The preflight is a hard gate: never reuse an unavailable historical UUID. All
Xcode commands use writable Derived Data and cloned-package directories. The
shared scheme directly contains `SubscriptionManagerTests` and
`SubscriptionManagerUITests`; there is no test plan or named test
configuration to select.

---

### Task 1: Make effective amount a public domain rule

**Files:**

- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift:100-220,447-526,824-833,2571-2576`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/CatalogOfferMatcher.swift:148-159`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionDomainTests.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift:4204-4318`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogOfferMatcherTests.swift`
- Modify: `SubscriptionManager/Library/SubscriptionRow.swift:18-24`
- Modify: `SubscriptionManager/Library/LibraryView.swift:892-905`
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift:500-510`

**Interfaces:**

- Produces: `Subscription.amount(onBillingDay:) -> Money`.
- Produces: `SubscriptionSummary.amount: Money` while retaining
  `SubscriptionSummary.originalAmount` as immutable-source data for
  compatibility during this batch.
- Produces: `CatalogOfferMatcher.match(subscription:in:onBillingDay:)`; catalog
  reconciliation always compares the charge due on
  `subscription.confirmedNextRenewal`, not an ambiguous wall-clock `now()`.
- Preserves: persistence and portable export continue to serialize
  `Subscription.originalAmount` plus `priceChanges` separately.

- [ ] **Step 1: Add failing resolver examples.** Add these behaviors to
  `SubscriptionDomainTests.swift` using literal UTC dates: before the first
  change returns USD 9.99; the effective day returns USD 14.99; after a second
  change returns CNY 68; an unsorted `priceChanges` array still chooses the
  latest applicable local day. Add an imported-history edge case with two
  changes at different wall-clock times on the same billing-local day; select
  deterministically by UUID because production commands reject duplicates but
  imported legacy data can still contain them. Add an invalid stored TimeZone
  case proving the resolver fails deterministically to GMT.

```swift
@Test("Effective amount follows billing-local price history")
func effectiveAmountFollowsBillingLocalHistory() throws {
    let calendar = utcCalendar()
    let start = try actionDate(
        year: 2026, month: 1, day: 10, hour: 12, calendar: calendar
    )
    let firstChange = try actionDate(
        year: 2026, month: 2, day: 10, hour: 12, calendar: calendar
    )
    let secondChange = try actionDate(
        year: 2026, month: 3, day: 10, hour: 12, calendar: calendar
    )
    let subscription = makeSubscription(
        originalAmount: Money(minorUnits: 999, currency: .usd),
        startDate: start,
        priceChanges: [
            PriceChange(
                id: UUID(), effectiveDate: secondChange,
                amount: Money(minorUnits: 6_800, currency: .cny)
            ),
            PriceChange(
                id: UUID(), effectiveDate: firstChange,
                amount: Money(minorUnits: 1_499, currency: .usd)
            )
        ]
    )

    #expect(subscription.amount(onBillingDay: start) == Money(
        minorUnits: 999, currency: .usd
    ))
    #expect(subscription.amount(onBillingDay: firstChange) == Money(
        minorUnits: 1_499, currency: .usd
    ))
    #expect(subscription.amount(onBillingDay: secondChange) == Money(
        minorUnits: 6_800, currency: .cny
    ))
}
```

- [ ] **Step 2: Verify red.** Run:

```bash
swift test --package-path Packages/SubscriptionCore \
  --filter SubscriptionDomainTests/effectiveAmountFollowsBillingLocalHistory
```

Expected: compile failure because `Subscription.amount(onBillingDay:)` does
not exist.

- [ ] **Step 3: Implement the single resolver.** Add this public method to
  `Subscription`; compare billing-local start-of-day values and use local day
  plus UUID as the deterministic tie-breaker. Two timestamps on the same local
  day are one effective billing day.

```swift
public func amount(onBillingDay date: Date) -> Money {
    let timeZone = TimeZone(
        identifier: billingSchedule.timeZoneIdentifier
    ) ?? .gmt
    let calendar = billingLocalCalendar(timeZone: timeZone)
    let billingDay = calendar.startOfDay(for: date)
    return priceChanges
        .filter {
            calendar.startOfDay(for: $0.effectiveDate) <= billingDay
        }
        .max {
            let leftDay = calendar.startOfDay(for: $0.effectiveDate)
            let rightDay = calendar.startOfDay(for: $1.effectiveDate)
            if leftDay == rightDay {
                return $0.id.uuidString < $1.id.uuidString
            }
            return leftDay < rightDay
        }?
        .amount ?? originalAmount
}
```

- [ ] **Step 4: Move presentation/query consumers.** Replace the private
  `expectedCharge` price selection with the resolver. Add
  `SubscriptionSummary.amount`, initialized from the next expected charge or
  `subscription.amount(onBillingDay: confirmedNextRenewal)`. Use `amount` for
  amount sorting, row display/accessibility, Mac summary display, exchange-rate
  quote discovery, and exact catalog reconciliation. Rename the matcher's
  `asOf:` argument to `onBillingDay:` and pass
  `subscription.confirmedNextRenewal` from every Workspace reconciliation
  path. Remove the matcher's private duplicate amount calculation. Update the
  existing current-date matcher test so a future Price Change effective on the
  Confirmed Next Renewal is the offer that matches. Keep `originalAmount` in
  persistence, backup, migration, and immutable-source assertions.

```swift
amount = nextExpectedCharge?.amount
    ?? subscription.amount(
        onBillingDay: subscription.confirmedNextRenewal
    )
```

- [ ] **Step 5: Extend consumer tests.** Before recording a Price Change,
  assert `SubscriptionSummary.amount == originalAmount`; afterward reload the
  Library and assert summary, row-facing data, expected charges, Upcoming,
  Calendar, Insights, widget snapshot, and catalog reconciliation all observe
  the changed amount while `stored.originalAmount` remains USD 9.99.

- [ ] **Step 6: Run focused and package tests.** Run:

```bash
swift test --package-path Packages/SubscriptionCore \
  --filter SubscriptionDomainTests
swift test --package-path Packages/SubscriptionCore \
  --filter SubscriptionWorkspaceTests/priceChangesRefreshLoadedConsumers
swift test --package-path Packages/SubscriptionCore \
  --filter CatalogOfferMatcherTests
swift test --package-path Packages/SubscriptionCore
```

Expected: all tests pass.

- [ ] **Step 7: Commit.**

```bash
git add Packages/SubscriptionCore SubscriptionManager/Library/SubscriptionRow.swift \
  SubscriptionManager/Library/LibraryView.swift \
  SubscriptionManager/App/SubscriptionManagerApp.swift
git commit -m "refactor(core): centralize effective subscription amount"
```

---

### Task 2: Make ordinary Edit atomically correct price history

**Files:**

- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift:333-399,1362-1460,1631-1687,2110-2180`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogOfferMatcherTests.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/FixedBillingScheduleTests.swift`

**Interfaces:**

- Consumes: `Subscription.amount(onBillingDay:)` from Task 1.
- Produces: `SubscriptionEditInput.amount: Money`.
- Preserves: `editSubscription(id:input:forecastThrough:)` as the one public
  ordinary-edit command and `SubscriptionRepository.updateSubscription` as one
  persistence call.
- Preserves the active-date invariant: the stored Confirmed Next Renewal is
  the resolver result for the supplied Start Date, interval, billing time zone,
  and injected `now`. The app may source either visible date because choosing
  Next Renewal first derives the preceding Start Date before the command runs.

- [ ] **Step 1: Write one failing atomic-edit test.** Create an active monthly
  subscription with USD 9.99 original amount and an existing USD 12.99 Price
  Change on the final renewal day. Edit service metadata and set CNY 68. The
  test must assert one repository update, unchanged `originalAmount`, one
  corrected same-day Price Change retaining its existing ID, changed metadata,
  refreshed consumers, and no intermediate persisted value.

```swift
workspace.editSubscription(
    id: id,
    input: SubscriptionEditInput(
        serviceName: "Edited Service",
        plan: "",
        category: "",
        amount: Money(minorUnits: 6_800, currency: .cny),
        billingSchedule: existing.billingSchedule,
        startDate: existing.startDate,
        confirmedNextRenewal: existing.confirmedNextRenewal,
        managementURL: nil,
        notes: ""
    )
)

let stored = try #require(repository.storedSubscription(id: id))
#expect(stored.originalAmount == Money(minorUnits: 999, currency: .usd))
#expect(stored.priceChanges.count == 1)
#expect(stored.priceChanges[0].id == existingChangeID)
#expect(stored.priceChanges[0].amount == Money(
    minorUnits: 6_800, currency: .cny
))
#expect(repository.updateAttemptCount == 1)
```

Add a second test that chooses an immediate future Next Renewal, derives its
preceding Start Date with `BillingDateResolver.previousCycleStart`, submits both
values, and proves the selected renewal survives the Workspace resolver on the
same billing-local day. Add trial and cancelled edit cases proving their
existing independent/lifecycle-specific date semantics remain unchanged.

- [ ] **Step 2: Verify red.** Run:

```bash
swift test --package-path Packages/SubscriptionCore \
  --filter SubscriptionWorkspaceTests/editAtomicallyCorrectsEffectiveAmount
```

Expected: compile failure because `SubscriptionEditInput` has no `amount`.

- [ ] **Step 3: Add required edit amount and migrate every caller.** Add
  `public let amount: Money` to `SubscriptionEditInput`. Update its designated
  initializer and `init(subscription:billingSchedule:)` to use
  `subscription.amount(onBillingDay: subscription.confirmedNextRenewal)`.
  Remove the deprecated initializer that accepts and discards
  `originalAmount`. Use
  `rg -n 'SubscriptionEditInput\\(' Packages SubscriptionManager
  SubscriptionManagerTests` as the migration inventory. Pass explicit Money
  at every call site, including `FixedBillingScheduleTests.swift:54-61,
  495-499,533-541,613-621,687-695` and all Workspace tests; do not add a
  default amount or optional compatibility path.

- [ ] **Step 4: Build one edited aggregate before persistence.** Keep the
  current lifecycle rules, but make them explicit: Active validates the
  supplied pair by resolving the first occurrence strictly after injected
  `now` from `input.startDate`; Trial keeps Start Date and First Paid Charge
  independent; Cancelled preserves its internal Renewal Anchor while accepting
  only valid existing date facts. Normalize the final dates to billing-local
  noon. For Active, reject a supplied Confirmed Next Renewal whose local day
  differs from the resolver result; otherwise store the normalized resolver
  result. Then compare input amount with
  `existing.amount(onBillingDay: finalNextRenewal)`. Keep history unchanged
  when equal; replace an existing same-day Price Change while retaining its ID;
  otherwise append one generated Price Change. Construct one `Subscription`,
  reconcile catalog identity once, and call `repository.updateSubscription`
  once.

```swift
let priceChanges: [PriceChange]
let currentAmount = existing.amount(
    onBillingDay: confirmedNextRenewal
)
if input.amount == currentAmount {
    priceChanges = existing.priceChanges
} else if let index = existing.priceChanges.firstIndex(where: {
    localCalendar.isDate(
        $0.effectiveDate, inSameDayAs: confirmedNextRenewal
    )
}) {
    var corrected = existing.priceChanges
    let existingChange = corrected[index]
    corrected[index] = PriceChange(
        id: existingChange.id,
        effectiveDate: normalizedRenewal,
        amount: input.amount
    )
    priceChanges = corrected
} else {
    priceChanges = existing.priceChanges + [
        PriceChange(
            id: identifierGenerator(),
            effectiveDate: normalizedRenewal,
            amount: input.amount
        )
    ]
}
```

- [ ] **Step 5: Keep failure atomic.** Use the existing repository fake's
  `updateAttemptCount` and throwing-update configuration. Assert exactly one
  attempted update for a successful edit and one failed attempt for the
  failure case. Add a repository fake that throws on
  update. Assert the original stored aggregate, Price Changes, detail state,
  requested consumers, and sync marker remain unchanged except for the visible
  failure state.

- [ ] **Step 6: Verify Workspace behavior.** Run:

```bash
swift test --package-path Packages/SubscriptionCore \
  --filter SubscriptionWorkspaceTests/editAtomicallyCorrectsEffectiveAmount
swift test --package-path Packages/SubscriptionCore \
  --filter SubscriptionWorkspaceTests/editFailureDoesNotPartiallyRecordPrice
swift test --package-path Packages/SubscriptionCore
```

Expected: all tests pass and existing lifecycle/history tests remain green.

- [ ] **Step 7: Commit.**

```bash
git add Packages/SubscriptionCore
git commit -m "feat(core): save ordinary edits and price history atomically"
```

---

### Task 3: Introduce the shared draft and validation policy

**Files:**

- Create: `SubscriptionManager/Library/SubscriptionDraft.swift`
- Create: `SubscriptionManagerTests/SubscriptionDraftTests.swift`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift:409-430,2110-2180`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `BillingDateResolver`, `MoneyTextParser`, `BillingInterval`,
  `SubscriptionCreationInput`, and the required-amount
  `SubscriptionEditInput` from Task 2.
- Produces one app-layer value, `SubscriptionDraft`; it owns all editable text
  and domain selections, but no persistence and no dirty baseline.
- Produces the exact APIs below; callers do not reconstruct Money, schedules,
  date linkage, or URL parsing independently.

```swift
struct SubscriptionDraft: Equatable {
    enum DateSource: Hashable { case startDate, nextRenewal }
    enum Mode: Equatable {
        case creating(SubscriptionInitialStatus)
        case editing(SubscriptionLifecycle)
    }
    enum Validation: Hashable {
        case serviceName, amount, currency, billingInterval
        case billingDate, managementURL
    }

    var serviceName: String
    var plan: String
    var category: String
    var amountText: String
    var currency: Currency?
    var billingInterval: BillingInterval?
    var customIntervalValueText: String
    var customIntervalUnit: BillingIntervalUnit
    var billingTimeZoneIdentifier: String
    var startDate: Date
    var confirmedNextRenewal: Date
    var dateSource: DateSource
    var acceptedDateSources: Set<DateSource>
    var managementURLText: String
    var notes: String
    var mode: Mode
    var catalogPresetID: String?
    var catalogOfferID: String?

    static func manual(
        now: Date,
        timeZoneIdentifier: String
    ) -> Self
    static func catalog(
        preset: CatalogPreset,
        offer: CatalogOffer?,
        now: Date,
        locale: Locale,
        timeZoneIdentifier: String
    ) -> Self
    static func editing(
        subscription: Subscription,
        locale: Locale
    ) -> Self

    @discardableResult mutating func selectStartDate(
        _ date: Date,
        asOf now: Date
    ) -> Bool
    @discardableResult mutating func selectNextRenewal(
        _ date: Date,
        asOf now: Date
    ) -> Bool
    @discardableResult mutating func changeBillingInterval(
        _ interval: BillingInterval?,
        asOf now: Date
    ) -> Bool

    func parsedAmount(locale: Locale) -> Money?
    func requiredBillingSchedule() -> FixedBillingSchedule?
    func makeCreationInput(locale: Locale) -> SubscriptionCreationInput?
    func makeEditInput(locale: Locale) -> SubscriptionEditInput?
    var validation: Set<Validation> { get }
}
```

- [ ] **Step 1: Remove optional-metadata required errors at the Workspace
  seam.** Add failing creation/edit tests proving empty Plan and Category save
  while empty Service Name, missing/non-positive amount, invalid interval,
  malformed finite dates, and invalid time-zone identifiers remain invalid.
  Delete `.plan` and `.category` required errors from creation/edit validators,
  not the stored fields. URL validity and explicit date acceptance remain
  app-layer concerns because the domain input already contains `URL?` and real
  dates.

- [ ] **Step 2: Verify red.** Run:

```bash
swift test --package-path Packages/SubscriptionCore \
  --filter SubscriptionWorkspaceTests/creationAllowsEmptyOptionalMetadata
```

Expected: failure because current validation requires plan/category.

- [ ] **Step 3: Implement the smallest validation-policy change.** Preserve
  trimming and required Service Name/amount/schedule/date checks; stop emitting
  `.plan` and `.category` errors. Keep the enum cases temporarily only if old
  decoded/UI code still references them; remove the cases and localization
  branches in Task 4 when call sites are migrated.

- [ ] **Step 4: Write failing draft value tests.** Use explicit UTC and
  Asia/Shanghai fixtures. Cover Active Start Date -> first recurrence strictly
  after injected `now`; Active Next Renewal -> preceding Start Date; interval
  changes rederive from the current source; Trial Start and First Paid Charge
  stay independent; Cancelled edit does not invent a future charge; manual Add
  starts with nil currency/interval and no accepted dates; verified catalog
  adoption uses its evidenced amount/currency/interval but still requires date
  acceptance; Edit starts with both persisted dates accepted. Cover month-end,
  leap year, invalid TimeZone, non-finite Date, optional metadata, malformed
  nonempty URL, service-name requirement, locale parsing, >2 decimal rejection,
  and positive amount validation.

```swift
var draft = SubscriptionDraft.manual(
    now: now,
    timeZoneIdentifier: "UTC"
)
draft.serviceName = "Example"
draft.amountText = "9.99"
draft.currency = .usd
draft.billingInterval = .monthly
#expect(draft.validation.contains(.billingDate))

#expect(draft.selectStartDate(start, asOf: now))
#expect(draft.startDate == start)
#expect(draft.confirmedNextRenewal == expectedRenewal)
#expect(draft.validation.isEmpty)
```

- [ ] **Step 5: Implement the value-only draft contract.** Normalize selected
  days to billing-local noon through the existing calendar helpers; return
  `false` and leave the draft unchanged when interval, TimeZone, or Date is
  invalid. For Active, either selector updates both values and records exactly
  that `dateSource`. For Trial, each selector updates only its own fact and both
  sources must be accepted before Save. For Cancelled, preserve independent
  stored facts and never derive a fake future charge. Changing Active interval
  reruns the resolver from the current source.

  `amountText` plus optional `currency` are the sole price-editing state;
  `parsedAmount(locale:)` delegates to `MoneyTextParser` and therefore accepts
  only a positive value exactly representable in minor units. A manual draft
  may hold local placeholder dates for the picker but `acceptedDateSources` is
  empty, so those placeholders can never be saved accidentally. A verified
  offer prepopulates only evidenced facts. Empty management URL maps to nil;
  nonempty malformed text yields `.managementURL` until corrected or cleared.

  `validation` requires one accepted source for Active, both for Trial, and the
  already-persisted date facts for Edit. `makeCreationInput` and
  `makeEditInput` return nil unless validation is empty; both use
  `requiredBillingSchedule()`. The draft owns no initial snapshot and no
  `isDirty`: Task 7 compares this entire value with a canonical baseline.
  `catalogPresetID`/`catalogOfferID` are task-local only; do not add persisted
  override flags.

- [ ] **Step 6: Wire the explicit Xcode project.** Add
  `SubscriptionDraft.swift` to the Library group/app Sources phase and
  `SubscriptionDraftTests.swift` to the test group/`SubscriptionManagerTests`
  Sources phase. Run `xcodebuild -list -project
  SubscriptionManager.xcodeproj` and inspect the project diff to prove each
  file appears exactly once and in only its intended target.

- [ ] **Step 7: Run draft and core tests.** Run the whole Swift Testing target;
  do not attempt XCTest-style method selection for `SubscriptionDraftTests`:

```bash
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerTests
swift test --package-path Packages/SubscriptionCore
```

Expected: all tests pass.

- [ ] **Step 8: Commit.**

```bash
git add Packages/SubscriptionCore SubscriptionManager/Library/SubscriptionDraft.swift \
  SubscriptionManagerTests/SubscriptionDraftTests.swift \
  SubscriptionManager.xcodeproj/project.pbxproj
git commit -m "feat(editor): share subscription draft and validation"
```

---

### Task 4: Build shared compact sections and explicit date task

**Files:**

- Create: `SubscriptionManager/Library/SubscriptionEditorSections.swift`
- Create: `SubscriptionManager/Library/BillingDateTaskView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionFormSupport.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManagerTests/SubscriptionDraftTests.swift` (value-operation coverage only)
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`

The Edit-driven UI acceptance test remains in Task 5, after the Add/Edit
shells exist; Task 4 must not add or commit `SubscriptionManagerUITests`.

**Interfaces:**

- Consumes: `Binding<SubscriptionDraft>`; the draft owns `amountText`, optional
  currency, optional/invalid interval state, TimeZone, and all metadata. Views
  do not maintain mirror copies.
- Produces: `SubscriptionEditorSections`, `BillingDateTaskView`, and stable
  accessibility IDs under `subscription.editor.*` and
  `subscription.date-task.*`.

- [ ] **Step 1: Add failing draft value-operation coverage.** Extend
  `SubscriptionDraftTests` with explicit UTC and Asia/Shanghai fixtures for
  Start Date -> derived Next Renewal, Next Renewal -> preceding Start Date,
  interval re-derivation, and independent Trial Start/First Paid Charge
  updates. Cover month-end and leap-year boundaries, invalid TimeZone and
  non-finite Date rejection, optional metadata, malformed nonempty URL,
  service-name/amount/currency/interval/date requirements, locale parsing,
  exact minor-unit rounding, and positive amount validation. The
  Edit-driven UI scenario `testDateTaskHasExplicitDoneAndCancel` is added in
  Task 5 once the Add/Edit shells can host the date task.

- [ ] **Step 2: Verify red.** Run the app unit/value-operation target:

```bash
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerTests
```

Expected: failure from the newly added draft value-operation assertions before
the shared sections/date-task implementation is complete. No UI test is
introduced or selected in this task.

- [ ] **Step 3: Build semantic shared sections.** The parent Add/Edit surface
  owns the only `Form`; `SubscriptionEditorSections.body` emits sibling native
  `Section` values and never nests another Form/List/ScrollView. Use
  `TextField`, `Picker`, `LabeledContent`, and `DisclosureGroup`. Primary order:
  Service, Price, Fixed Billing Schedule, Dates, derived status/next charge.
  Additional Details contains Plan, Category, management URL, and notes. Empty
  optional fields show no validation error.

  Manual entry uses an explicit nil `Select Currency` row and nil `Select
  Billing Interval` row; it never defaults to USD/monthly. Verified offers bind
  evidenced values. The amount field binds directly to `draft.amountText` and
  currency directly to `draft.currency`. Custom interval text/unit update the
  draft's optional `billingInterval` through one binding adapter. Validation
  IDs are `subscription.validation.service-name`, `.amount`, `.currency`,
  `.billing-interval`, `.billing-date`, and `.management-url`.

```swift
struct SubscriptionEditorSections: View {
    @Binding var draft: SubscriptionDraft
    let status: SubscriptionStatus?
    let nextExpectedCharge: ExpectedCharge?
    let onEditDate: (SubscriptionDraft.DateSource) -> Void

    var body: some View {
        ServiceEditorSection(draft: $draft)
        PriceEditorSection(draft: $draft)
        ScheduleEditorSection(draft: $draft, onEditDate: onEditDate)
        AdditionalDetailsSection(draft: $draft)
    }
}
```

Use these stable visible IDs: `subscription.editor.service-name`, `.amount`,
`.currency`, `.billing-interval`, `.start-date`, `.next-renewal`, `.status`,
`.next-charge`, `.additional-details`, `.plan`, `.category`,
`.management-url`, and `.notes`. The two date rows announce which is Source and
which is Derived for Active during the current task. Trial rows are labeled
Trial Start and First Paid Charge and announce neither as derived. Cancelled
editing shows no fabricated next-charge summary.

- [ ] **Step 4: Build the date task over a local working copy.** Present one
  sheet/item from the Add/Edit shell; the item carries only `DateSource` and
  injected `now`. `BillingDateTaskView` snapshots the bound draft into
  `workingDraft` on entry. Its graphical/native `DatePicker` updates the
  working copy through `selectStartDate`/`selectNextRenewal` and shows both
  resulting values. Done invokes the selector at least once (so deliberately
  accepting the initially displayed day counts), writes `workingDraft` back to
  the editor binding, then dismisses. Cancel dismisses without writing. A later
  failed form Save leaves the Done-committed editor draft intact. Trial Start
  and First Paid Charge use the same two sources but independent draft rules.

```swift
struct BillingDateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: SubscriptionDraft
    let source: SubscriptionDraft.DateSource
    @State private var workingDraft: SubscriptionDraft
    @State private var selectedDate: Date
    let now: Date

    var body: some View {
        Form { graphicalPicker; sourceAndCounterpartSummary }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("subscription.date-task.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applySelectionAtLeastOnce()
                        draft = workingDraft
                        dismiss()
                    }
                        .accessibilityIdentifier("subscription.date-task.done")
                }
            }
    }
}
```

The picker ID is `subscription.date-task.picker`; the two visible values use
`subscription.date-task.source-value` and `.counterpart-value`. Titles reuse
localized Start Date/Next Renewal or Trial Start/First Paid Charge strings.

- [ ] **Step 5: Wire new app files into Xcode.** Add
  `SubscriptionEditorSections.swift` and `BillingDateTaskView.swift` to the
  Library group and app Sources phase. Do not add either to a test target.
  Re-run `xcodebuild -list` and inspect the PBX diff for exactly-one membership.

- [ ] **Step 6: Validate localization data.** Run:

```bash
jq empty SubscriptionManager/Resources/Localizable.xcstrings
```

Expected: exit 0.

- [ ] **Step 7: Run app tests and build both platforms.** Run the unit/value
  test command from Step 2, then:

```bash
xcodebuild build -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages
xcodebuild build -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager -destination 'platform=macOS' \
  -derivedDataPath /tmp/subscription-manager-macos-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages
```

Expected: test and builds pass.

- [ ] **Step 8: Commit.**

```bash
git add SubscriptionManager/Library/SubscriptionEditorSections.swift \
  SubscriptionManager/Library/BillingDateTaskView.swift \
  SubscriptionManager/Library/SubscriptionFormSupport.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  SubscriptionManagerTests \
  SubscriptionManager.xcodeproj/project.pbxproj
git commit -m "feat(editor): add compact fields and explicit date task"
```

---

### Task 5: Migrate Add and Edit to the shared draft

**Files:**

- Modify: `SubscriptionManager/Library/AddSubscriptionView.swift`
- Modify: `SubscriptionManager/Library/EditSubscriptionView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionEditorSections.swift`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**

- Consumes: `SubscriptionDraft`, `SubscriptionEditorSections`,
  `BillingDateTaskView`, and atomic `SubscriptionEditInput.amount`.
- Produces: one shared field behavior with separate Add/Edit toolbar shells.

- [ ] **Step 1: Add named failing Add/Edit acceptance tests.** Add XCTest
  methods `testManualAddAllowsEmptyPlanAndCategory`,
  `testManualAddRequiresFiveMinimumFacts`,
  `testVerifiedOfferKeepsEvidencedDefaultsUntilExplicitOverride`,
  `testEditPriceWritesHistoryAutomatically`, and
  `testCatalogRenameClearsStaleIdentityWhilePriceOverrideRetainsIt`, and
  `testDateTaskHasExplicitDoneAndCancel`. Prove:
  manual Add saves with empty Plan/Category but blocks missing Service Name,
  amount/currency, interval, or accepted date; verified offer activation keeps
  exact evidenced defaults; Edit exposes price/currency/interval/dates on the
  first screen; one Save records price history automatically; renaming beyond
  every formal name/alias converts a stale `catalog:*` identity to manual while
  changing price or interval alone retains catalog identity. Extend the
  existing official-catalog relaunch test to assert that “User-adjusted price”
  and “User-adjusted schedule” are derived after reload, with no stored flags.
  From an open Edit editor, the date-task test activates Start Date, selects a
  different day, asserts source and derived values change while the task stays
  visible, taps Done, and verifies the editor remains open and unsaved with the
  new values. It then reopens the task, selects a second different day, taps
  Cancel, and verifies the Done-committed values remain. Repeat the same
  value-operation assertions for Next Renewal and a Trial fixture; Cancel must
  never be a no-op assertion.

- [ ] **Step 2: Verify red.** Run:

```bash
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testManualAddAllowsEmptyPlanAndCategory \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testEditPriceWritesHistoryAutomatically \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDateTaskHasExplicitDoneAndCancel
```

Expected: the optional-metadata test fails at current validation and Edit has
no price controls.

- [ ] **Step 3: Migrate Add without changing its catalog shell.** Initialize
  exactly one draft using `.manual` or `.catalog`, render shared sections, and
  preserve the existing A-Z Browse Catalog and Add Manually entry. Manual has
  no default currency/interval and an empty accepted-date set. Activating a
  verified offer is the only action that adopts its price/currency/interval;
  date acceptance is still explicit. A service-only preset adopts only its
  evidenced identity metadata and any independently evidenced currency, never
  an offer price or cadence.

  On Save, call `draft.makeCreationInput(locale:)` first. No valid input means
  visible draft validation and no Workspace call. For a verified offer, build
  `CatalogOfferSubscriptionInput` with `actualChargeOverride == nil` only when
  parsed Money equals official Money and `.official` only when interval equals
  official interval; otherwise pass explicit override values. For a
  service-only preset use the existing `.legacy(input)` catalog command; for
  manual use `workspace.createSubscription(input)`. Empty URL becomes nil and
  empty optional metadata is passed through. One Save makes one creation call.

- [ ] **Step 4: Migrate Edit to the atomic input.** Initialize with
  `SubscriptionDraft.editing(subscription:locale:)` and the already-loaded
  Effective Subscription Status. Render shared sections and lifecycle-aware
  labels. Trial dates remain independent; Active dates use the source/derived
  rule; Cancelled and Archived records remain editable without fabricating an
  active next charge or changing lifecycle/archive state. On Save call exactly:

```swift
guard let input = draft.makeEditInput(locale: locale) else {
    showDraftValidation = true
    return false
}
workspace.editSubscription(id: subscription.id, input: input)
return workspace.editingValidationErrors.isEmpty
    && workspace.detailState.loadedSubscriptionID == subscription.id
```

  The real implementation pattern-matches `.loaded(let saved, _, _)` rather
  than adding the illustrative `loadedSubscriptionID` helper unless it is
  reused. `MoneyTextParser` owns locale parsing and exact minor-unit rounding;
  neither Add nor Edit parses a second time. Validation or persistence failure
  returns false, keeps the same draft/session visible, and never advances a
  pending route. Success refreshes from the stored aggregate before dismissing.
  Simultaneous amount/schedule/date edits produce one Price Change on the final
  Confirmed Next Renewal day through Task 2's one repository update.

- [ ] **Step 5: Keep context-specific chrome.** Add child retains Back + Save
  inside the catalog task. Edit destination retains system Back when clean and
  Save; it never shows a duplicate Cancel. Both use the same field sections,
  not one conditional full-screen mega-view.

- [ ] **Step 6: Implement catalog identity/override derivation at the existing
  reconciliation seam.** Exact localized formal name or alias plus exact
  offer facts may attach/retain catalog identity. A renamed catalog-associated
  service that no longer exactly matches clears to the existing manual identity
  convention. Do not let fuzzy/typeahead ranking participate. After reload,
  compare effective amount and interval with the current verified offer to
  derive override labels in the editor; do not persist booleans or a new offer
  entity.

- [ ] **Step 7: Run focused and regression tests.** Run:

```bash
swift test --package-path Packages/SubscriptionCore
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerTests \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testManualAddAllowsEmptyPlanAndCategory \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testEditPriceWritesHistoryAutomatically \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDateTaskHasExplicitDoneAndCancel \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCreatesSubscriptionFromOfficialCatalogOffer
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit.**

```bash
git add SubscriptionManager/Library/AddSubscriptionView.swift \
  SubscriptionManager/Library/EditSubscriptionView.swift \
  SubscriptionManager/Library/SubscriptionEditorSections.swift \
  SubscriptionManagerUITests SubscriptionManagerTests
git commit -m "refactor(editor): share add and edit field behavior"
```

---

### Task 6: Route rows directly to the editor and relocate actions

**Files:**

- Modify: `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Library/ConfirmChargeView.swift`
- Modify: `SubscriptionManager/Library/RecordCancellationView.swift`
- Modify: `SubscriptionManager/Library/ReactivateSubscriptionView.swift`
- Modify/Delete: `SubscriptionManager/Library/RecordPriceChangeView.swift`
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**

- Preserves: UUID destinations and `subscription-manager://subscription/<UUID>`.
- Produces: direct editable destination, semantic Lifecycle section, and
  overdue Confirm Charge from Upcoming while retaining the temporary Payment
  History fallback required until Batch B.
- Preserves: Workspace lifecycle/payment commands unchanged.

- [ ] **Step 1: Add named failing topology and capability tests.** Add XCTest
  methods `testRowOpensDirectEditor`,
  `testArchivedRowOpensEditorWithExternalRestore`,
  `testOnlyDueExpectedOccurrenceOffersConfirmCharge`, and
  `testConfirmChargeFallbackRemainsUntilBatchB`. Assert a Library row exposes
  Service/Price/Schedule fields without activating Actions or Edit; identifiers
  `subscription.lifecycle.actions` and `subscription.edit` and the unlabeled
  chevron are absent; lifecycle buttons live in the Lifecycle section;
  Archived opens the same editor while Restore/Delete remain external.

  For the safety tracer, seed a quarterly occurrence scheduled two months ago
  with no matching Confirmed Charge. Its Payment History expected row exposes a
  labeled Confirm Charge action and invokes the existing Workspace command. A
  current Upcoming expected item dated today exposes the same action; future
  expected and already-confirmed items do not. After confirmation/reload, the
  traced expected row/action is replaced by exactly one immutable Confirmed
  Charge. A throwing repository keeps the expected row/action and shows error.

- [ ] **Step 2: Verify red.** Run:

```bash
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testRowOpensDirectEditor \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testArchivedRowOpensEditorWithExternalRestore \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testOnlyDueExpectedOccurrenceOffersConfirmCharge \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testConfirmChargeFallbackRemainsUntilBatchB
```

Expected: current read-only Detail and Actions menu make the tests fail.

- [ ] **Step 3: Turn the existing UUID destination into the editor loader.**
  Keep `SubscriptionDetailView` as the UUID/deep-link-compatible loader only;
  it owns no `Form` and never wraps another Form. Once Workspace detail state
  is `.loaded` for the requested ID, initialize/reuse the one editor draft and
  render `EditSubscriptionView` inline. `EditSubscriptionView` owns the single
  Form and appends compact derived status, next charge, Payment History, and
  Lifecycle sections after `SubscriptionEditorSections`. A successful Save
  reloads the stored aggregate, resets the baseline, and exits/updates the
  source route; validation or persistence failure leaves the same draft and
  route visible. Remove the Edit sheet and duplicate Cancel from the editor
  destination.

- [ ] **Step 4: Relocate lifecycle actions.** For Trial/Active, show Record
  Cancellation in Lifecycle; for Cancelled, show Reactivate. Keep their
  existing focused forms and Workspace commands. Remove Record Price Change,
  Archive, Restore, and Delete from the editor toolbar/menu. IDs are
  `subscription.lifecycle.section`, `.record-cancellation`, and `.reactivate`.
  Archived shows read-only Archived status and no lifecycle mutation button.
  Keep `ConfirmChargeView`, cancellation, and reactivation as focused route-only
  forms; do not invent new domain commands. Delete the catch-all Actions menu
  only after the Payment History fallback in Step 5 passes.

- [ ] **Step 5: Relocate Confirm Charge without a capability gap.** Create one
  pure eligibility helper that receives an expected occurrence, confirmed
  charge IDs, injected `now`, and billing TimeZone. It returns true only when
  the occurrence is expected, its normalized `ScheduledChargeID` is not already
  confirmed, and its billing-local scheduled day is no later than local today.
  Both surfaces route to the existing
  `workspace.confirmCharge(id:scheduledDate:chargedDate:amount:)` command:

  1. the current Upcoming expected row, seeded with its exact date/amount; and
  2. a temporary labeled action on an eligible expected row in the editor's
     Payment History section.

  `ConfirmChargeView` accepts an optional occurrence seed instead of guessing
  from `originalAmount`; it uses that occurrence's effective amount/currency.
  Workspace remains the final occurrence and duplicate validator. Do **not**
  remove the Payment History fallback in Batch A. Batch B may delete it only
  after the month-range agenda proves the two-month-old tracer, confirmed
  replacement, duplicate suppression, future hiding, and failure behavior.

- [ ] **Step 6: Preserve row actions.** Keep current leading Pin/Unpin and
  trailing Delete + Archive/Restore ordering. Keep `allowsFullSwipe: true` on
  the Delete-first trailing actions and route full swipe into the existing
  named confirmation, never direct deletion.

  Swipe, accessibility, context-menu, and keyboard paths reuse the same named
  deletion confirmation state/handler. Precedence is: leading Pin/Unpin;
  trailing Delete then Archive/Restore; a full trailing swipe selects Delete
  but only opens confirmation.

- [ ] **Step 7: Remove the macOS edit-sheet detour.** In
  `SubscriptionManagerApp.swift`, remove `editingSubscription` and its sheet.
  Edit menu/keyboard commands select and focus the existing split-detail editor
  for the one selected UUID. The regular-width editor stays in the detail
  column and is not presented as a nested modal.

- [ ] **Step 8: Run topology and lifecycle regressions.** Run the four tests
  from Step 2 plus existing cancellation, reactivation, archive/restore,
  permanent delete, pin/unpin, payment-history idempotency/failure, and
  full-swipe confirmation tests.

- [ ] **Step 9: Commit.**

```bash
git add SubscriptionManager/Library \
  SubscriptionManager/App/SubscriptionManagerApp.swift \
  SubscriptionManagerUITests
git commit -m "feat(navigation): open subscriptions in the direct editor"
```

---

### Task 7: Guard dirty navigation and add non-gesture parity

**Files:**

- Create: `SubscriptionManager/Library/SubscriptionEditorSession.swift`
- Modify: `SubscriptionManager/Library/AddSubscriptionView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionDetailView.swift`
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Catalog/CatalogBrowserView.swift`
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManagerTests/SubscriptionDraftTests.swift`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Modify: `SubscriptionManagerTests/MacMenuBarPresentationTests.swift` only if
  the existing Mac command presentation needs new labels.
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`

**Interfaces:**

- Produces: one `SubscriptionEditorSession`; it owns the draft baseline and one
  pending route/selection request, not a second Subscription model/store.
- Produces: VoiceOver custom actions and iPad/macOS context/keyboard parity.

- [ ] **Step 1: Add named failing session/UI tests.** In
  `SubscriptionDraftTests`, cover clean exit, same-selection no-op, dirty exit,
  Continue Editing, Discard, successful Save baseline reset, pending selection
  application (including a multi-selection Set), and failed Save retention;
  name the selection case “Dirty Mac selection waits for resolution.” In iOS
  UI XCTest add
  `testDirtyBackCanContinueDiscardOrSave`,
  `testDirtySaveFailureKeepsDraftAndRoute`,
  `testDirtyAddDismissalDoesNotLoseDraft`. Each test first changes Service Name.
  Continue preserves the changed text; Discard exits without persistence; Save
  persists then exits. A throwing repository leaves editor, draft, current
  selection, and pending destination unchanged.

- [ ] **Step 2: Verify red.** Run the focused session target and UI tests and
  expect missing coordinator/confirmation identifiers or premature dismissal.

- [ ] **Step 3: Implement this one coordinator contract.**

```swift
enum EditorExitRequest: Equatable {
    case dismiss
    case open(UUID)
    case replaceSelection(Set<UUID>)
}

enum EditorExitResolution: Equatable {
    case ignored
    case proceed(EditorExitRequest)
    case confirmationRequired
}

@MainActor @Observable
final class SubscriptionEditorSession {
    let subscriptionID: UUID?
    private(set) var baseline: SubscriptionDraft
    var draft: SubscriptionDraft
    private(set) var pendingExit: EditorExitRequest?
    private(set) var saveFailed = false

    var isDirty: Bool { draft != baseline }

    init(subscriptionID: UUID?, draft: SubscriptionDraft)
    func requestExit(
        _ request: EditorExitRequest,
        currentSelection: Set<UUID> = []
    ) -> EditorExitResolution
    func markSaved(using persistedDraft: SubscriptionDraft?)
        -> EditorExitRequest?
    func discardAndTakePendingExit() -> EditorExitRequest?
    func continueEditing()
    func markSaveFailed()
}
```

  The baseline is the canonical draft created from the loaded subscription or
  initial Add selection; equality is exact draft-value equality. Save success
  replaces the baseline with a draft rebuilt from the persisted aggregate (or
  the current Add draft after creation), clears failure, and returns/takes the
  pending exit. Discard restores baseline before returning the pending exit.
  Continue clears the pending request only. Save failure preserves draft,
  baseline, and pending request. Requesting the already-current ID/set is
  `.ignored`. There is no auto-save and no repository call in this class.

- [ ] **Step 4: Define ownership and navigation integration.**

  - `AddSubscriptionView` owns one session initialized from its manual/catalog
    draft. `CatalogAddFlowView` receives dirty state/dismiss-attempt callbacks;
    clean root Cancel dismisses immediately.
  - `LibraryView` and `MacLibraryView` each own the optional session associated
    with the current UUID. `SubscriptionDetailView` receives that binding,
    initializes it only after the matching subscription loads, and resets it
    only after a proven route change.
  - Compact clean navigation keeps the system Back/edge swipe. Dirty navigation
    hides system Back (which disables the destructive edge pop), exposes
    `subscription.editor.back`, and calls `requestExit(.dismiss)`.
  - Sheet interactive dismissal is disabled while dirty and a presentation
    dismissal-attempt observer routes the attempted swipe to the same request.
    Prefer a native SwiftUI attempt callback at the deployment target; if none
    exists, add a minimal conditional `UIAdaptivePresentationControllerDelegate`
    adapter in `SubscriptionEditorSession.swift`. It owns no product state.
  - Mac `Table` uses a guarded selection Binding. Until Save/Discard succeeds,
    its setter records `.replaceSelection(requestedSet)` without mutating the
    visible selection. Empty/multi-selection sets are preserved. Menu/deep-link
    open uses `.open(UUID)` through the same resolver.

  Present one alert/dialog with IDs `subscription.unsaved.alert`, `.save`,
  `.discard`, and `.continue`. Save calls the Task 5 closure; on true, call
  `markSaved` then apply the returned request; on false, call `markSaveFailed`
  and keep the editor. Apply pending selection/path only in the parent that owns
  it, never inside the draft/session.

- [ ] **Step 5: Add action parity.** Add labeled accessibility actions for
  Pin/Unpin, Archive/Restore, and Delete to the row. Reuse the same handlers and
  confirmation state as swipe actions. Preserve current Mac context and
  keyboard commands; add only missing iPad context actions. VoiceOver names are
  exactly Pin/Unpin, Archive/Restore, and Delete; Delete only opens
  `subscription.delete.confirmation`, whose destructive button is
  `subscription.delete.confirm`.

- [ ] **Step 6: Fix confirmation copy.** Use Service Name directly so optional
  Plan never creates empty parentheses. The destructive description states
  that payment/lifecycle history is permanently removed.

- [ ] **Step 7: Wire and verify.** Add `SubscriptionEditorSession.swift` once to
  the Library group/app Sources phase. Then run:

```bash
jq empty SubscriptionManager/Resources/Localizable.xcstrings
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerTests \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDirtyBackCanContinueDiscardOrSave \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDirtySaveFailureKeepsDraftAndRoute \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDirtyAddDismissalDoesNotLoseDraft \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSubscriptionRowHasAccessibleManagementActions
xcodebuild build -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager -destination 'platform=macOS' \
  -derivedDataPath /tmp/subscription-manager-macos-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages
```

Expected: selected tests and macOS build pass.

- [ ] **Step 8: Commit.**

```bash
git add SubscriptionManager/Library/LibraryView.swift \
  SubscriptionManager/Library/SubscriptionEditorSession.swift \
  SubscriptionManager/Library/AddSubscriptionView.swift \
  SubscriptionManager/Library/SubscriptionDetailView.swift \
  SubscriptionManager/Catalog/CatalogBrowserView.swift \
  SubscriptionManager/App/SubscriptionManagerApp.swift \
  SubscriptionManager/Resources/Localizable.xcstrings \
  SubscriptionManagerUITests SubscriptionManagerTests \
  SubscriptionManager.xcodeproj/project.pbxproj
git commit -m "feat(editor): protect drafts and expose accessible row actions"
```

---

### Task 8: Remove superseded paths and run the Batch A release gate

**Files:**

- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Modify/Delete: production files only when `rg` proves the old route is dead.
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj` if a dead file is
  removed.
- Create: `docs/verification/2026-08-01-round-2-batch-a.md`.
- Modify: `docs/research/2026-08-01-round-2-synthesis.md` only if runtime
  evidence changes an approved interaction; do not rewrite requirements to
  hide a regression.

**Interfaces:**

- Verifies: S2, S3, S4, S5, S7 and the Batch A portions of S1/S6.
- Preserves: all existing Repository, lifecycle, sync, backup, widget, App
  Intent, EventKit, and catalog tests.
- Proves: Batch A has not imported provisional catalog prices and has not
  removed overdue Confirm Charge before its Batch B replacement exists.

- [ ] **Step 1: Prove old production routes are unused.** Run:

```bash
rg -n "subscription\.lifecycle\.actions|subscription\.edit|RecordPriceChangeView|Original Amount" \
  SubscriptionManager SubscriptionManagerTests SubscriptionManagerUITests
```

Expected after migration: no production route for Actions -> Edit or manual
Record Price Change. Test references appear only where a negative assertion is
intentional.

- [ ] **Step 2: Delete dead view/state branches.** Remove obsolete sheet cases,
  toolbar menu branches, duplicate field state, and the price-change form file
  if Step 1 proves it has no consumer. Keep the Workspace
  `recordPriceChange` command and historical domain type because imports,
  backups, and advanced history remain valid callers.

  If `RecordPriceChangeView.swift` is deleted, remove its PBX build file, file
  reference, Library group child, and app Sources entry. Run `rg` against
  `project.pbxproj` and `xcodebuild -list` to prove no dangling reference.

- [ ] **Step 3: Enforce the catalog non-import gate.** Batch A's bundled
  catalog must retain this baseline hash from commit
  `28ebd05b0cf252c5ce22948578e7755e423afb81`:

```bash
shasum -a 256 SubscriptionManager/Resources/catalog-v1.json
git diff --exit-code 28ebd05b0cf252c5ce22948578e7755e423afb81 -- \
  SubscriptionManager/Resources/catalog-v1.json
swift test --package-path Packages/SubscriptionCore --filter CatalogTests
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerTests/BundledCatalogRepositoryTests
```

Expected SHA-256:
`85bb5cb457f98e99cfb28cc54e7d938743b4bf850872446e6151b59108fc28a1`.
The existing exact-offer pin test passes and no second-pass/OGD price becomes
selectable. The 187-record normalized manifest is only a first-pass schema
PASS; the 84 OFF/OGD gap-pass records and 52 second-community records remain
provisional and unmerged. A later Batch C import must first require exact
charged amount, ISO currency, charged cadence, market, channel,
standard-renewal semantics, official source, verification date, and sanitized
content-addressed snapshot hash, then receive an independent evidence PASS.

- [ ] **Step 4: Run static data/project checks.** Run:

```bash
jq empty SubscriptionManager/Resources/Localizable.xcstrings
python3 -m json.tool SubscriptionManager/Resources/catalog-v1.json >/dev/null
rg -n "SubscriptionDraft.swift|SubscriptionEditorSections.swift|BillingDateTaskView.swift|SubscriptionEditorSession.swift|SubscriptionDraftTests.swift" \
  SubscriptionManager.xcodeproj/project.pbxproj
git diff --check
```

Expected: data parses, each new file has exactly one reference and one intended
Sources membership, and the diff check is clean.

- [ ] **Step 5: Run the complete core and app unit suites.** Run:

```bash
swift test --package-path Packages/SubscriptionCore
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerTests
```

Expected: all tests pass.

- [ ] **Step 6: Run the exact Batch A iPhone UI matrix.** Every method below
  must exist as an XCTest method in the already-wired UI test file before this
  command runs:

```bash
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testManualAddAllowsEmptyPlanAndCategory \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testManualAddRequiresFiveMinimumFacts \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testVerifiedOfferKeepsEvidencedDefaultsUntilExplicitOverride \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDateTaskHasExplicitDoneAndCancel \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testEditPriceWritesHistoryAutomatically \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCatalogRenameClearsStaleIdentityWhilePriceOverrideRetainsIt \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testRowOpensDirectEditor \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testArchivedRowOpensEditorWithExternalRestore \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testOnlyDueExpectedOccurrenceOffersConfirmCharge \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testConfirmChargeFallbackRemainsUntilBatchB \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDirtyBackCanContinueDiscardOrSave \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDirtySaveFailureKeepsDraftAndRoute \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testDirtyAddDismissalDoesNotLoseDraft \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSubscriptionRowHasAccessibleManagementActions \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCreatesSubscriptionFromOfficialCatalogOffer \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testLeadingSwipePinsAndUnpinsLibraryRows \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testTrailingSwipeRequiresConfirmationBeforePermanentDelete \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testArchivedRowsSwipeToRestoreOrConfirmedDelete \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testRecordsCancellationAndHidesNextExpectedCharge \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testReactivatesWithConfirmedNextRenewal \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSimplifiedChineseAddFlowUsesLocalizedCopy
```

Expected: all selected tests pass; no request reports “0 tests executed.” Then
run the whole `SubscriptionManagerUITests` target once to catch unlisted
regressions.

- [ ] **Step 7: Build iPhone, iPad, and macOS, and exercise the iPad path.** Run:

```bash
xcodebuild build -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" \
  -derivedDataPath /tmp/subscription-manager-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_IPAD_UDID" \
  -derivedDataPath /tmp/subscription-manager-ipad-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -destination "platform=iOS Simulator,id=$SUBSCRIPTION_BATCH_A_IPAD_UDID" \
  -derivedDataPath /tmp/subscription-manager-ipad-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testWideIPadUsesSidebarToSwitchDestinations
xcodebuild build -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager -destination 'platform=macOS' \
  -derivedDataPath /tmp/subscription-manager-macos-derived-data \
  -clonedSourcePackagesDirPath /tmp/subscription-manager-source-packages \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all builds pass.

- [ ] **Step 8: Produce named current-run surface evidence.** Create
  `docs/research/evidence/screenshots/round-2-batch-a/` and capture these files:

  `01-add-manual-en.png`, `02-add-manual-zh-Hans.png`,
  `03-verified-offer-provenance.png`, `04-direct-edit.png`,
  `05-date-task-source-derived.png`, `06-dirty-exit-dialog.png`,
  `07-lifecycle-section.png`, `08-archived-editor.png`,
  `09-partial-swipe-actions.png`, `10-full-swipe-delete-confirmation.png`,
  `11-ipad-regular-width.png`, `12-ax-xxxl.png`, and
  `13-macos-split-editor.png`.

  Export one absolute artifact directory, verify the content-size tokens from
  the installed `simctl`, and use these executable commands after placing each
  deterministic UI fixture:

```bash
export SUBSCRIPTION_BATCH_A_ARTIFACT_DIR="$PWD/docs/research/evidence/screenshots/round-2-batch-a"
mkdir -p "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR"
xcrun simctl help ui
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/01-add-manual-en.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/02-add-manual-zh-Hans.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/03-verified-offer-provenance.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/04-direct-edit.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/05-date-task-source-derived.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/06-dirty-exit-dialog.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/07-lifecycle-section.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/08-archived-editor.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/09-partial-swipe-actions.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/10-full-swipe-delete-confirmation.png"
xcrun simctl io "$SUBSCRIPTION_BATCH_A_IPAD_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/11-ipad-regular-width.png"
xcrun simctl ui "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" content_size accessibility-extra-extra-extra-large
xcrun simctl io "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" screenshot "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/12-ax-xxxl.png"
xcrun simctl ui "$SUBSCRIPTION_BATCH_A_SIMULATOR_UDID" content_size medium
screencapture -x "$SUBSCRIPTION_BATCH_A_ARTIFACT_DIR/13-macos-split-editor.png"
```

  The installed Xcode `simctl` names AX XXXL
  `accessibility-extra-extra-extra-large`; if `help ui` does not list that exact
  token, stop rather than guessing. Store focused test summaries,
  fixture/time-zone/locale values, and accessibility-tree dumps beside the
  images as `core-tests.log`, `app-tests.log`, `ui-tests.log`,
  `fixture-matrix.json`, `accessibility-tree-en.txt`, and
  `accessibility-tree-zh-Hans.txt`.

  Compare the new images with
  `docs/research/evidence/screenshots/round-2-current-ui/` at the same state and
  record findings in `docs/verification/2026-08-01-round-2-batch-a.md`. Check
  information density, truncation, duplicate chrome, keyboard focus, native
  spacing, partial/full swipe behavior, English/zh-Hans, 280–336-point split
  widths, RTL where system controls support it, non-Gregorian display Calendar,
  Reduce Motion, Reduce Transparency, Increased Contrast, and default through
  AX XXXL. Manually run VoiceOver through date selection and row actions and
  record selected-state/read-order results; screenshots alone are not a pass.

- [ ] **Step 9: Build, install, launch, and smoke-test the registered iPhone.**
  Use the previously verified Personal Team/local-storage configuration:

```bash
xcodebuild -project SubscriptionManager.xcodeproj \
  -scheme SubscriptionManager \
  -configuration Debug \
  -destination 'platform=iOS,id=00008150-000245CA1AB8401C' \
  -derivedDataPath /tmp/subscription-manager-device-build \
  DEVELOPMENT_TEAM=Z23GL5RZH7 \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGN_ENTITLEMENTS='' \
  build -allowProvisioningUpdates -allowProvisioningDeviceRegistration
xcrun devicectl device install app \
  --device 45FA0ADF-6F6D-5926-9115-A6421AA55115 \
  /tmp/subscription-manager-device-build/Build/Products/Debug-iphoneos/SubscriptionManager.app
xcrun devicectl device process launch \
  --device 45FA0ADF-6F6D-5926-9115-A6421AA55115 \
  com.klausc06.SubscriptionManager
xcrun devicectl device info processes \
  --device 45FA0ADF-6F6D-5926-9115-A6421AA55115 \
  --filter 'executable.path CONTAINS "SubscriptionManager"'
```

  Expected: signed build, install, launch, and process check pass. On the actual
  phone smoke-test Add -> date Done -> Save, direct Edit -> Save, dirty Back,
  partial/full swipe, and permanent-delete cancellation before claiming the
  binary accepted.

- [ ] **Step 10: Review and commit the release-gate cleanup locally.** Confirm
  every task checkbox/evidence row, run `git diff --check`, inspect the complete
  diff, and commit only if all required gates pass:

```bash
git add SubscriptionManager Packages/SubscriptionCore \
  SubscriptionManager.xcodeproj SubscriptionManagerTests \
  SubscriptionManagerUITests docs/research docs/verification
git commit -m "test(editor): complete direct editor regression gate"
git status --short
git log -5 --oneline
```

Expected: local Batch A commits exist and the worktree is clean. Do not hide a
failed gate by editing requirements or evidence. Remote push is a separate
post-review action, never part of a test command.

---

## Plan Self-Review

### Spec coverage

- R2-01: Tasks 3 and 5.
- R2-02/R2-03: Tasks 5-7.
- R2-05: Tasks 3-5.
- Price-history and currency correctness: Tasks 1-2 and 5.
- Existing row semantics and permanent-delete confirmation: Tasks 6-8.
- Lifecycle capability preservation: Task 6.
- iPhone/iPad/macOS, VoiceOver, and localization: Tasks 4, 7, and 8.
- R2-04 and audited catalog expansion remain Batch C; Task 5 preserves the
  existing catalog shell and exact matcher without prematurely adding fuzzy
  identity adoption.
- R2-12 month plus agenda remains Batch B; Task 6 only relocates Confirm Charge
  while retaining the temporary Payment History fallback, so removing the
  catch-all menu does not remove a capability.
- R2-06/R2-07/R2-11 remain evidence-open; Task 8 freezes the bundled catalog
  hash so Batch A cannot accidentally ship provisional prices.

### Type consistency

- One resolver: `Subscription.amount(onBillingDay:)`.
- One edit amount: `SubscriptionEditInput.amount`.
- One app draft: `SubscriptionDraft`.
- One draft-baseline/navigation coordinator: `SubscriptionEditorSession`, with
  one optional `EditorExitRequest`.
- Existing `SubscriptionWorkspace.editSubscription` remains the command.
- Existing `SubscriptionRepository.updateSubscription` remains the persistence
  boundary; no speculative mutation protocol is added.

### Complexity check

The plan adds one draft value and one mutable session owner, zero custom visual
controls, zero third-party dependencies, zero persistent stores, and zero new
recurrence engines. A conditional presentation-dismiss observer is a platform
adapter and owns no product state. The current 704-line Add, 374-line Edit, and
531-line Detail surfaces must lose duplicated state/menu/read-only code as
shared sections land. If the net non-test product delta exceeds the synthesis
guardrail, stop before Task 8 and re-review the implementation boundary.
