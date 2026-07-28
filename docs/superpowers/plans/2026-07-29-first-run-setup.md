# TB-12 First-Run Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a new person choose persisted defaults and add several confirmed catalog subscriptions without Calendar permission.

**Architecture:** Model preferences independently from the subscription library, inject them into `SubscriptionWorkspace`, and persist one SwiftData record. SwiftUI renders the workspace setup state and reuses the existing catalog/confirmation flow; selected IDs stay UI-local.

**Tech Stack:** Swift 6, Observation, SwiftData, SwiftUI, Swift Testing, XCTest UI tests.

## Global Constraints

- Work through `SubscriptionWorkspace`; views never access persistence or Calendar APIs directly.
- Ship all copy in English and Simplified Chinese.
- Twelve months is the recommended default; six months remains selectable.
- Onboarding, catalog browsing, and ordinary launch never request Calendar access.
- Preserve the editable subscription confirmation flow and offline catalog behavior.

---

### Task 1: Model and persist preferences

**Files:** Create `Packages/SubscriptionCore/Sources/SubscriptionCore/UserPreferences.swift` and `SubscriptionManager/Persistence/SwiftDataUserPreferencesRepository.swift`; modify `SubscriptionManager/Persistence/SubscriptionRecord.swift`; test in `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/UserPreferencesTests.swift` and `SubscriptionManagerTests/SwiftDataUserPreferencesRepositoryTests.swift`.

- [ ] Write a failing default-value test: CNY and twelve months.
- [ ] Run `swift test --package-path Packages/SubscriptionCore --filter UserPreferencesTests`; observe missing type/protocol failure.
- [ ] Add `UserPreferences`, `CalendarProjectionHorizon`, and `UserPreferencesRepository` with `loadPreferences()` and `savePreferences(_:)`; store one atomic SwiftData record.
- [ ] Run focused Core and adapter tests.
- [ ] Commit `feat(core): persist user preferences`.

### Task 2: Expose a recoverable workspace setup state

**Files:** Modify `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`; test in `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`.

- [ ] Write failing workspace tests for empty, skip, resume, and preference-repository failure.
- [ ] Run focused workspace tests and observe failure.
- [ ] Add observable `setupState`, `loadSetup`, `updatePreferences`, `skipSetup`, and `resumeSetup` using the injected preference adapter.
- [ ] Run `swift test --package-path Packages/SubscriptionCore`.
- [ ] Commit `feat(core): expose recoverable setup state`.

### Task 3: Build first-run and settings UI

**Files:** Create `SubscriptionManager/Settings/UserPreferencesView.swift` and `SubscriptionManager/Settings/FirstRunSetupView.swift`; modify `SubscriptionManager/App/AppDependencies.swift`, `SubscriptionManager/Library/LibraryView.swift`, `SubscriptionManager/Resources/Localizable.xcstrings`, and `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`.

- [ ] Write failing UI coverage for defaults, two selected presets, per-preset confirmation, skip, and resume.
- [ ] Run the selected simulator test and observe failure.
- [ ] Add a local setup step machine (preferences, catalog selection, confirmation, finished) and use `AddSubscriptionView(preset:)` for every selection.
- [ ] Add English/Simplified Chinese strings and accessibility identifiers.
- [ ] Run focused simulator tests and commit `feat(app): add resumable first-run setup`.

### Task 4: Verify non-Calendar and recovery contracts

**Files:** Modify `SubscriptionManagerTests/AppDependenciesTests.swift`, `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`, and this design document.

- [ ] Add failing tests for interrupted setup with no duplicate saved subscription and zero Calendar authorization calls.
- [ ] Make the smallest recovery fix: retain only saved preferences/setup completion; selection stays `@State`.
- [ ] Run final gates: `swift test --package-path Packages/SubscriptionCore` and `xcodebuildmcp test_sim`.
- [ ] Commit `test: verify first-run setup recovery`, push `feat/tb-12-onboarding`, and create a PR.

## Self-Review

- Task 1 supplies persistence; Task 2 owns state; Task 3 supplies UI and copy; Task 4 proves recovery and no Calendar access.
- There are no unresolved implementation choices or placeholders.
- The only cross-layer interface is the injected `UserPreferencesRepository` consumed by `SubscriptionWorkspace`.
