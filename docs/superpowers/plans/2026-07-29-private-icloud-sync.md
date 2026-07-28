# TB-16 Private iCloud Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the private subscription library available offline while SwiftData synchronizes it through the configured private iCloud container and exposes an honest status.

**Architecture:** Add a small injected `LibrarySyncMonitor` to `SubscriptionCore` and keep it independent of SwiftData/CloudKit. `AppDependencies` supplies a CloudKit-backed account probe, asks the workspace to refresh after account changes and successful local mutations, and exposes the result through existing SwiftUI roots. SwiftData remains the sole record synchronizer.

**Tech Stack:** Swift 6, SwiftData, CloudKit, SwiftUI, Swift Testing, iOS/iPadOS/macOS 27.

## Global Constraints

- Use only `iCloud.com.klausc06.SubscriptionManager`'s private database; do not add a public database, custom backend, account, analytics, or Calendar behavior.
- All mutations go through `SubscriptionWorkspace` and must complete against the local repository before any sync status update.
- Keep model fields CloudKit compatible: defaults/optionals only; stable application UUIDs remain the identity.
- User-facing copy, accessibility labels, and error states ship in English and Simplified Chinese.
- UI-test and in-memory stores opt out with `cloudKitDatabase: .none` and never contact CloudKit.

---

### Task 1: Model an injected, local-first sync status

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Interfaces:**
- Produces `public enum LibrarySyncStatus: Equatable, Sendable { case notLoaded, localOnly, synchronizing, current, signedOut, requiresAttention }`.
- Produces `public protocol LibrarySyncMonitor: Sendable { func refreshStatus() async -> LibrarySyncStatus }`.
- Produces `SubscriptionWorkspace.syncStatus`, `refreshSyncStatus() async`, and `markLocalChangesForSync()`.

- [ ] **Step 1: Write failing workspace tests**

```swift
let monitor = SyncMonitorFixture(result: .signedOut)
let workspace = SubscriptionWorkspace(repository: repository, syncMonitor: monitor)
await workspace.refreshSyncStatus()
#expect(workspace.syncStatus == .signedOut)

workspace.createSubscription(
    SubscriptionCreationInput(
        serviceName: "Atlas",
        plan: "Monthly",
        category: "Productivity",
        originalAmount: Money(minorUnits: 999, currency: .usd),
        startDate: Date(timeIntervalSince1970: 1_767_225_600),
        confirmedNextRenewal: Date(timeIntervalSince1970: 1_769_904_000),
        managementURL: nil,
        notes: ""
    )
)
#expect(workspace.syncStatus == .signedOut)
```

- [ ] **Step 2: Verify the tests fail because the monitor and status do not exist**

Run: `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests`

Expected: compilation failure mentioning `LibrarySyncMonitor` or `syncStatus`.

- [ ] **Step 3: Add the smallest status seam**

```swift
public protocol LibrarySyncMonitor: Sendable {
    func refreshStatus() async -> LibrarySyncStatus
}

public private(set) var syncStatus: LibrarySyncStatus = .notLoaded

public func refreshSyncStatus() async {
    syncStatus = await syncMonitor?.refreshStatus() ?? .localOnly
}
```

Call `markLocalChangesForSync()` after each successful repository mutation and
preferences save; it sets `.synchronizing` only when the prior status is
`.current` or `.synchronizing`, preserving signed-out and attention states.

- [ ] **Step 4: Run the focused and full core suites**

Run: `swift test --package-path Packages/SubscriptionCore`

Expected: all existing tests plus the sync status tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/SubscriptionCore
git commit -m "feat(core): expose local-first sync status"
```

### Task 2: Configure private CloudKit and account monitoring

**Files:**
- Create: `SubscriptionManager/Sync/CloudKitLibrarySyncMonitor.swift`
- Create: `SubscriptionManager/SubscriptionManager.entitlements`
- Modify: `SubscriptionManager/App/AppDependencies.swift`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`
- Test: `SubscriptionManagerTests/AppDependenciesTests.swift`

**Interfaces:**
- `CloudKitLibrarySyncMonitor(container: CKContainer)` maps `.available` to `.current`, `.noAccount` to `.signedOut`, `.restricted`/`.couldNotDetermine` to `.localOnly`, and thrown errors to `.requiresAttention`.
- `AppDependencies.make(failsLifecycleMutations:allowsExchangeRateNetworking:syncMonitor:modelContainer:)` injects the monitor into `SubscriptionWorkspace`.

- [ ] **Step 1: Write failing adapter/configuration tests**

```swift
#expect(AppDependencies.productionCloudKitDatabase ==
    .private("iCloud.com.klausc06.SubscriptionManager"))
#expect(AppDependencies.uiTestingCloudKitDatabase == .none)
```

Use a closure-backed monitor fixture to assert each CloudKit account mapping
without reaching the network.

- [ ] **Step 2: Verify focused app tests fail**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerTests/AppDependenciesTests`

Expected: compilation failure for the missing monitor/configuration symbols.

- [ ] **Step 3: Implement the private-only configuration**

```swift
static let cloudKitContainerID = "iCloud.com.klausc06.SubscriptionManager"
static let productionCloudKitDatabase: ModelConfiguration.CloudKitDatabase =
    .private(cloudKitContainerID)
```

Set the production `ModelConfiguration` to that value; retain `.none` for
in-memory and named UI-test configurations. Add iCloud container services and
`remote-notification` background mode to the entitlement file, then set
`CODE_SIGN_ENTITLEMENTS = SubscriptionManager/SubscriptionManager.entitlements`
for the app target's Debug and Release configurations. Do not set the
entitlement on test targets.

- [ ] **Step 4: Run focused app tests and builds**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerTests/AppDependenciesTests`

Expected: adapter/configuration tests pass with no CloudKit network request.

- [ ] **Step 5: Commit**

```bash
git add SubscriptionManager/Sync SubscriptionManager/App/AppDependencies.swift SubscriptionManager/SubscriptionManager.entitlements SubscriptionManager.xcodeproj SubscriptionManagerTests/AppDependenciesTests.swift
git commit -m "feat(app): configure private iCloud sync"
```

### Task 3: Present status and refresh it safely

**Files:**
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**
- `SyncStatusView(workspace:)` presents status icon/text and a retry button only for `.requiresAttention`.
- Root views call `await workspace.refreshSyncStatus()` on initial task and when the app becomes active.

- [ ] **Step 1: Write the failing UI assertion**

```swift
app.launchArguments = ["--ui-testing", "--ui-testing-sync-status", "signed-out"]
app.launch()
#expect(app.staticTexts["sync.status.signedOut"].exists)
```

- [ ] **Step 2: Verify it fails because no status control is rendered**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSyncStatus`

Expected: failure locating the status accessibility identifier.

- [ ] **Step 3: Implement the compact, bilingual status row**

Render `SyncStatusView` in Settings and use the `sync.status.<state>`
accessibility identifier. Use text plus SF Symbol, not color alone. The retry
button calls `Task { await workspace.refreshSyncStatus() }`. Add English and
Simplified Chinese catalog entries for every state and the retry action.

- [ ] **Step 4: Run focused UI tests and inspect both languages**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSyncStatus`

Expected: signed-out and requires-attention UI states render; retry does not
block the library.

- [ ] **Step 5: Commit**

```bash
git add SubscriptionManager/Library/LibraryView.swift SubscriptionManager/App/SubscriptionManagerApp.swift SubscriptionManager/Resources/Localizable.xcstrings SubscriptionManagerUITests/SubscriptionManagerUITests.swift
git commit -m "feat(app): show private iCloud sync status"
```

### Task 4: Verify convergence boundaries and deliver

**Files:**
- Create: `docs/verification/2026-07-29-private-icloud-sync-matrix.md`
- Modify: `docs/superpowers/specs/2026-07-29-private-icloud-sync-design.md`

- [ ] **Step 1: Add the executable two-device matrix**

Document Device A/B setup with the same iCloud account and the configured
private container. Record expected observations for offline creation,
concurrent scalar edit, append payment/price history, permanent deletion,
reconnect, signed-out startup, account change, and Calendar independence.

- [ ] **Step 2: Run local verification**

Run:

```bash
swift test --package-path Packages/SubscriptionCore
xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
xcodebuild build -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=macOS' -quiet
```

Expected: all core tests pass and both app destinations build.

- [ ] **Step 3: Record the external prerequisite accurately**

Mark the physical two-device matrix as requiring an active Apple Developer
Program administrator to provision the named CloudKit container and remote
notifications; do not claim it passed before that occurs.

- [ ] **Step 4: Commit, push, and open a stacked PR**

```bash
git add docs
git commit -m "docs: add iCloud sync verification matrix"
git push --set-upstream origin feat/tb-16-icloud-sync
gh pr create --base feat/tb-15-mac-window --head feat/tb-16-icloud-sync
```
