# Safe JSON Backup Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a validated portable JSON backup through an explicit preview and one non-destructive atomic merge.

**Architecture:** Core validates and plans a merge from immutable snapshots. `SubscriptionWorkspace` exposes that preview and submits one resolved mutation through an injected import repository. A SwiftData adapter performs all selected record and preference writes in one `ModelContext` save; SwiftUI owns file selection and conflict controls only.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, UniformTypeIdentifiers, XCTest UI automation.

## Global Constraints

- Support iOS 27, iPadOS 27, and macOS 27 with no new dependency or backend.
- Route behavior through `SubscriptionWorkspace`; use injected adapters for persistence.
- Ship English and Simplified Chinese copy plus accessibility identifiers.
- Never delete a local record absent from a backup; reject unknown schemas before mutation.
- CSV remains export-only; Calendar and CloudKit identifiers remain excluded.

---

### Task 1: Validate and plan a portable merge in SubscriptionCore

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/PortableBackup.swift`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/PortableExportTests.swift`

**Interfaces:**
- Produces `PortableBackupValidationError`, `PortableBackupValidator`, `PortableBackupMergePreview`, and `PortableBackupMergePlanner`.

- [ ] **Step 1: Write failing validation and planning tests**

```swift
let result = PortableBackupValidator().decode(data)
#expect(throws: PortableBackupValidationError.unsupportedSchema)

let preview = try PortableBackupMergePlanner().makePreview(
    backup: backup, localSubscriptions: [local], localPreferences: .default
)
#expect(preview.conflicts.map(\.id) == [local.id])
#expect(preview.retainedLocalSubscriptionIDs == [localOnly.id])
```

- [ ] **Step 2: Run the focused test and confirm red**

Run: `swift test --package-path Packages/SubscriptionCore --filter PortableExportTests`

- [ ] **Step 3: Implement immutable validation and preview values**

```swift
public func decode(_ data: Data) throws -> PortableBackup {
    let backup = try decoder.decode(PortableBackup.self, from: data)
    guard backup.schema == PortableBackup.schemaName else { throw .unsupportedSchema }
    guard backup.schemaVersion == PortableBackup.currentSchemaVersion else { throw .unsupportedVersion }
    guard Set(backup.subscriptions.map(\.id)).count == backup.subscriptions.count else { throw .duplicateSubscriptionID }
    return backup
}
```

- [ ] **Step 4: Run the focused test and commit**

Run: `swift test --package-path Packages/SubscriptionCore --filter PortableExportTests`

Commit: `git commit -am "feat(core): plan portable backup restores"`

### Task 2: Resolve a preview through a single workspace command

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/PortableExportTests.swift`

**Interfaces:**
- Consumes the Task 1 preview.
- Produces `PortableBackupImportRepository.apply(_:) throws`, `SubscriptionWorkspace.preparePortableBackupImport(_:)`, and `SubscriptionWorkspace.applyPortableBackupImport(_:)`.

- [ ] **Step 1: Add failing workspace tests**

```swift
let preview = try workspace.preparePortableBackupImport(data)
#expect(preview.isReadyToApply == false)
workspace.applyPortableBackupImport(resolutions)
#expect(repository.appliedMerges == [expectedMerge])
```

- [ ] **Step 2: Run the focused test and confirm red**

Run: `swift test --package-path Packages/SubscriptionCore --filter PortableExportTests`

- [ ] **Step 3: Add resolution validation and one adapter call**

```swift
@MainActor public protocol PortableBackupImportRepository {
    func apply(_ merge: PortableBackupMerge) throws
}
```

The workspace rejects incomplete resolutions, never calls the adapter on a validation error, reloads library state only after success, and exposes a recoverable failure state.

- [ ] **Step 4: Run all core tests and commit**

Run: `swift test --package-path Packages/SubscriptionCore`

Commit: `git commit -am "feat(core): resolve portable backup merges"`

### Task 3: Commit the resolved merge atomically in SwiftData

**Files:**
- Modify: `SubscriptionManager/Persistence/SwiftDataSubscriptionRepository.swift`
- Modify: `SubscriptionManager/App/AppDependencies.swift`
- Test: `SubscriptionManagerTests/SwiftDataSubscriptionRepositoryTests.swift`

**Interfaces:**
- Consumes `PortableBackupImportRepository` and `PortableBackupMerge` from Task 2.
- Produces `SwiftDataPortableBackupImportRepository` injected into `SubscriptionWorkspace`.

- [ ] **Step 1: Add save-failure and idempotence tests**

```swift
XCTAssertThrowsError(try repository.apply(merge))
XCTAssertEqual(try subscriptions.listSubscriptions(), originalSubscriptions)
XCTAssertEqual(try preferences.loadPreferences(), originalPreferences)
```

- [ ] **Step 2: Run the focused XCTest and confirm red**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' -only-testing:SubscriptionManagerTests`

- [ ] **Step 3: Implement one-context create/update/preference save**

```swift
do {
    apply(merge, in: modelContext)
    try save(modelContext)
} catch {
    modelContext.rollback()
    throw error
}
```

- [ ] **Step 4: Run the focused XCTest and commit**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' -only-testing:SubscriptionManagerTests`

Commit: `git commit -am "feat(app): atomically restore portable backups"`

### Task 4: Add the native restore preview and verify the full journey

**Files:**
- Create: `SubscriptionManager/Library/PortableRestoreView.swift`
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Create: `docs/verification/2026-07-29-safe-backup-restore-matrix.md`

**Interfaces:**
- Consumes workspace preview and apply state from Task 2.

- [ ] **Step 1: Add a failing UI test for Settings restore navigation**

```swift
app.buttons["preferences.portable-restore"].tap()
XCTAssertTrue(app.buttons["portable-restore.select-file"].waitForExistence(timeout: 5))
```

- [ ] **Step 2: Run the UI test and confirm red**

Run: `xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSettingsOffersPortableRestore`

- [ ] **Step 3: Implement JSON-only importer, preview, conflict choices, and confirmation**

Use `fileImporter(isPresented:allowedContentTypes:[.json])`; disable Apply until every conflict and changed preference has a resolution. Give every action a stable `portable-restore.*` accessibility identifier.

- [ ] **Step 4: Validate bilingual UI and final matrix**

Run: `jq empty SubscriptionManager/Resources/Localizable.xcstrings && swift test --package-path Packages/SubscriptionCore && xcodebuild test -project SubscriptionManager.xcodeproj -scheme SubscriptionManager -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012'`

Commit: `git commit -am "feat(app): preview portable backup restores"`
