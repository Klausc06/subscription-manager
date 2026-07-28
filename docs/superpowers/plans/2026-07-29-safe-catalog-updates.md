# Safe Catalog Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt only a newer, fully validated fixed-source catalog snapshot while retaining a usable bundled fallback.

**Architecture:** Core validates versioned catalog snapshots and chooses bundled or cached data through injected catalog adapters. The app target owns URLSession and application-support persistence. Workspace publishes catalog diagnostics and an explicit async refresh command; SwiftUI invokes that command without direct network or filesystem work.

**Tech Stack:** Swift 6, Foundation URLSession, SwiftUI, Swift Testing/XCTest, JSON resources.

## Global Constraints

- The only remote location is a fixed HTTPS GitHub raw-content URL.
- A failed, stale, corrupt, or unsafe remote payload never replaces the active catalog.
- Catalog refresh never mutates Subscription Repository records.
- All metadata is CC0 `originalSymbol` provenance; application code remains Apache-2.0.
- Ship English, Simplified-Chinese, and accessibility copy; preserve offline browsing.

---

### Task 1: Versioned provenance-aware catalog validation

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogTests.swift`
- Modify: `SubscriptionManager/Resources/catalog-v1.json`

**Interfaces:** Produces `CatalogSnapshot.catalogVersion`,
`CatalogAssetProvenance`, and field-addressable `CatalogValidationError`.

- [ ] **Step 1: Write failing snapshot validation tests**

```swift
#expect(throws: CatalogValidationError.self) {
    try CatalogSnapshot(schemaVersion: 1, catalogVersion: 0, presets: [preset])
}
#expect(throws: CatalogValidationError.self) {
    try CatalogSnapshot(schemaVersion: 1, catalogVersion: 2, presets: [unsafeURLPreset])
}
```

- [ ] **Step 2: Run the selected test and verify failure**

Run: `swift test --package-path Packages/SubscriptionCore --filter CatalogTests`

- [ ] **Step 3: Add immutable version and provenance values**

```swift
public struct CatalogAssetProvenance: Codable, Equatable, Sendable {
    public let kind: CatalogAssetKind
    public let license: String
    public let source: String
}
public struct CatalogSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let catalogVersion: Int
    public let presets: [CatalogPreset]
}
```

Validate each failure with a stable `preset=<id> field=<field>` description,
then update the bundled resource to catalog version 1 and explicit CC0
provenance.

- [ ] **Step 4: Re-run Core tests and commit**

Run: `swift test --package-path Packages/SubscriptionCore --filter CatalogTests`

Commit: `feat(core): validate versioned catalog provenance`

### Task 2: Cached activation and remote update decision

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Interfaces:** Produces `CatalogUpdateSource`, `CatalogCache`,
`CatalogDiagnostics`, and `SubscriptionWorkspace.refreshCatalog()`.

- [ ] **Step 1: Write failing workspace tests**

```swift
await workspace.refreshCatalog()
#expect(workspace.catalogDiagnostics.version == 2)
#expect(workspace.catalogDiagnostics.source == .cached)
#expect(subscriptionRepository.updateAttemptCount == 0)
```

Cover newer activation, stale rejection, corrupt payload, duplicate ID,
unsupported interval, unsafe URL/provenance, and offline fallback.

- [ ] **Step 2: Run the selected test and verify failure**

Run: `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests`

- [ ] **Step 3: Implement atomic update selection**

Decode data before writing cache; compare `catalogVersion` against the active
snapshot; call the cache's atomic replace only for a valid newer candidate;
reload and republish existing filters. Map every refresh failure to a
non-destructive diagnostics status.

- [ ] **Step 4: Re-run Core tests and commit**

Run: `swift test --package-path Packages/SubscriptionCore`

Commit: `feat(core): activate only valid newer catalog snapshots`

### Task 3: Fixed HTTPS source, cache, and repository validator

**Files:**
- Create: `SubscriptionManager/Catalog/GitHubCatalogUpdateSource.swift`
- Create: `SubscriptionManager/Catalog/FileCatalogCache.swift`
- Create: `Scripts/validate-catalog.swift`
- Modify: `SubscriptionManager/Catalog/BundledCatalogRepository.swift`
- Modify: `SubscriptionManager/App/AppDependencies.swift`
- Modify: `SubscriptionManagerTests/BundledCatalogRepositoryTests.swift`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`

**Interfaces:** App injects a fixed `https://raw.githubusercontent.com/`
source and an application-support cache; `validate-catalog.swift <path>` exits
nonzero and prints the exact failing preset/field.

- [ ] **Step 1: Write failing app tests with a fake source and temporary URL**

```swift
let cache = FileCatalogCache(directory: temporaryDirectory)
try cache.replace(with: validV2Data)
#expect(try cache.load()?.catalogVersion == 2)
```

- [ ] **Step 2: Run app tests and verify failure**

Run: `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:SubscriptionManagerTests/BundledCatalogRepositoryTests test`

- [ ] **Step 3: Implement fixed source and atomic cache**

Use `URLSession.data(from:)` only against the declared constant URL; require
HTTP 200 and JSON bytes; write a temporary file then replace the cache URL.
The validator decodes with the same catalog decoder and prints the validation
description before returning a nonzero exit status.

- [ ] **Step 4: Re-run app tests and commit**

Commit: `feat(app): cache validated catalog updates`

### Task 4: Diagnostics and explicit refresh UI

**Files:**
- Modify: `SubscriptionManager/Catalog/CatalogBrowserView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:** `catalog.refresh`, `catalog.diagnostics`, and localized visible
source/version/status copy.

- [ ] **Step 1: Write a failing UI test**

```swift
app.buttons["catalog.refresh"].tap()
XCTAssertTrue(app.staticTexts["catalog.diagnostics"].waitForExistence(timeout: 5))
XCTAssertTrue(app.staticTexts["Catalog version 1 · Bundled"].exists)
```

- [ ] **Step 2: Run it and verify missing controls**

Run: `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCatalogDiagnosticsAndOfflineFallback test`

- [ ] **Step 3: Implement non-blocking diagnostics**

Add a catalog footer and explicit refresh button. Keep current presets visible
during requests and show a localized failure status without an alert or a
library mutation.

- [ ] **Step 4: Run full verification and commit**

Run: `swift test --package-path Packages/SubscriptionCore`

Run: `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test`

Commit: `feat(ui): show safe catalog update diagnostics`
