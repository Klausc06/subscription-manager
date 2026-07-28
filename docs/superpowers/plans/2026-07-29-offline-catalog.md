# Offline Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let people create ordinary subscriptions from a bundled bilingual offline catalog without allowing a preset to decide personal billing facts.

**Architecture:** Add Codable catalog value types and a narrow `CatalogRepository` adapter to SubscriptionCore. SubscriptionWorkspace owns observable catalog state and delegates normal creation after it attaches the selected preset's stable service identity. The production app loads a validated JSON resource; SwiftUI presents catalog browsing before reusing the existing creation form.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing/XCTest, SwiftData, JSON resources.

## Global Constraints

- Keep all behavior behind `SubscriptionWorkspace`.
- No network request, third-party logo, tracking, or provider action.
- Ship English and Simplified-Chinese copy and accessibility identifiers.
- Presets may suggest metadata but never price, currency, plan, or renewal facts.
- Preserve manual creation and current lifecycle/payment behavior.

---

### Task 1: Catalog domain and validation

**Files:**
- Create: `Packages/SubscriptionCore/Sources/SubscriptionCore/Catalog.swift`
- Create: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CatalogTests.swift`

**Interfaces:**
- Produces `CatalogSnapshot`, `CatalogPreset`, `CatalogLocalizedText`, `CatalogIcon`, `CatalogRepository`, and `CatalogLoadError`.

- [ ] **Step 1: Write failing domain tests**

```swift
@Test func localizedSearchMatchesChineseAndEnglish() throws {
    let snapshot = try CatalogSnapshot.validating(version: 1, presets: fixtures)
    #expect(snapshot.search(query: "音乐", locale: Locale(identifier: "zh-Hans")).count == 1)
    #expect(snapshot.search(query: "music", locale: Locale(identifier: "en")).count == 1)
}
```

- [ ] **Step 2: Run the selected test and expect missing catalog types**

Run: `swift test --package-path Packages/SubscriptionCore --filter CatalogTests`

- [ ] **Step 3: Implement immutable Codable catalog values and snapshot validation**

```swift
public protocol CatalogRepository: Sendable {
    func loadSnapshot() throws -> CatalogSnapshot
}

public struct CatalogPreset: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let serviceName: CatalogLocalizedText
    public let category: CatalogLocalizedText
    public let suggestedInterval: BillingInterval
    public let managementURL: URL?
    public let icon: CatalogIcon
}
```

- [ ] **Step 4: Re-run catalog tests and commit**

Run: `swift test --package-path Packages/SubscriptionCore --filter CatalogTests`

Commit: `feat(core): define offline catalog domain`

### Task 2: Workspace catalog queries and catalog-originated creation

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Interfaces:**
- Consumes `CatalogRepository`, `CatalogPreset`.
- Produces `CatalogState`, `CatalogCategory`, `loadCatalog(locale:)`, `setCatalogSearchQuery(_:)`, `setCatalogCategory(_:)`, and `createCatalogSubscription(presetID:input:)`.

- [ ] **Step 1: Write failing workspace tests**

```swift
workspace.loadCatalog(locale: Locale(identifier: "zh-Hans"))
workspace.setCatalogSearchQuery("音乐")
#expect(workspace.catalogState == .loaded(...))
workspace.createCatalogSubscription(presetID: "music.example", input: input)
#expect(stored.serviceIdentity == ServiceIdentity(rawValue: "catalog:music.example"))
```

- [ ] **Step 2: Run and expect missing Workspace catalog API**

Run: `swift test --package-path Packages/SubscriptionCore --filter SubscriptionWorkspaceTests`

- [ ] **Step 3: Inject the adapter and publish query state**

```swift
public enum CatalogState: Equatable, Sendable {
    case notLoaded
    case loaded(categories: [CatalogCategory], presets: [CatalogPreset])
    case failed
}
```

Use the existing creation validation and repository command; copy only preset
service identity and safe metadata into the incoming creation input.

- [ ] **Step 4: Re-run full Core suite and commit**

Run: `swift test --package-path Packages/SubscriptionCore`

Commit: `feat(core): create subscriptions from catalog presets`

### Task 3: Bundled JSON repository

**Files:**
- Create: `SubscriptionManager/Catalog/BundledCatalogRepository.swift`
- Create: `SubscriptionManager/Resources/catalog-v1.json`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`
- Modify: `SubscriptionManager/App/AppDependencies.swift`
- Test: `SubscriptionManagerTests/BundledCatalogRepositoryTests.swift`

**Interfaces:**
- Consumes `CatalogRepository` and `CatalogSnapshot`.
- Produces production resource decoding and an injected production workspace.

- [ ] **Step 1: Write failing resource tests**

```swift
let snapshot = try BundledCatalogRepository(bundle: .main).loadSnapshot()
#expect(snapshot.schemaVersion == 1)
#expect(snapshot.presets.allSatisfy { !$0.id.isEmpty })
```

- [ ] **Step 2: Run the selected Xcode test and expect missing resource repository**

Run: `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:SubscriptionManagerTests/BundledCatalogRepositoryTests test`

- [ ] **Step 3: Add representative bilingual JSON and fail-fast resource loading**

Use only original `CatalogIcon` system-symbol tokens; include media, music,
productivity, cloud, reading, and membership categories. Register the JSON in
the app target and inject the repository through `AppDependencies`.

- [ ] **Step 4: Re-run selected app tests and commit**

Commit: `feat(app): load bundled offline catalog`

### Task 4: Catalog browse and confirmation UI

**Files:**
- Create: `SubscriptionManager/Catalog/CatalogBrowserView.swift`
- Create: `SubscriptionManager/Catalog/CatalogPresetDetailView.swift`
- Modify: `SubscriptionManager/Library/AddSubscriptionView.swift`
- Modify: `SubscriptionManager/Library/SubscriptionFormSupport.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**
- Consumes `workspace.catalogState` and `createCatalogSubscription`.
- Produces an offline browse/search/confirm flow with stable accessibility IDs.

- [ ] **Step 1: Write a failing UI test**

```swift
app.buttons["subscription.add.catalog"].tap()
app.searchFields["catalog.search"].typeText("Music")
app.buttons["catalog.preset.music.example"].tap()
app.buttons["catalog.use-preset"].tap()
// Enter actual amount and save; assert the created detail remains editable.
```

- [ ] **Step 2: Run the selected UI test and expect missing controls**

Run: `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testCreatesSubscriptionFromOfflineCatalog test`

- [ ] **Step 3: Build native browse and confirmation views**

Present category filter and `searchable` catalog list; show original symbol plus
localized service name for every preset. Reuse the existing form with a catalog
creation mode that retains editable actual terms and submits through the
workspace command.

- [ ] **Step 4: Run UI test, full Core suite, app build, and commit**

Run: `swift test --package-path Packages/SubscriptionCore`

Run: `xcodebuild -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' build`

Commit: `feat(ui): browse and add offline catalog presets`
