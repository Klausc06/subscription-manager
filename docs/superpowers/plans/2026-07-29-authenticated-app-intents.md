# Authenticated App Intents implementation plan

**Goal:** Expose authenticated, localized Subscription Library actions in
Siri, Spotlight, and Shortcuts through the existing workspace.

**Architecture:** `SubscriptionWorkspace` gains small, explicit command and
query results so every surface can observe the same behavior without reading a
repository. The app target registers one workspace adapter with App Intents;
entities, queries, and handlers remain thin system-facing types.

**Tech stack:** Swift 6, AppIntents, SwiftUI, SwiftData, Swift Testing, Xcode
iOS Simulator.

## Task 1: Add explicit workspace command and query results

**Files:**

- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

- [ ] Return a creation result containing the exactly-one persisted
  Subscription or a validation/persistence outcome.
- [ ] Expose stable subscription lookup/list and an upcoming-timeline query;
  keep the existing state-loading APIs as state projections over those queries.
- [ ] Verify validation, missing/archived selection, and sorted results in
  core tests.

## Task 2: Build the narrow App Intents adapter and entities

**Files:**

- Create: `SubscriptionManager/AppIntents/SubscriptionIntentService.swift`
- Create: `SubscriptionManager/AppIntents/SubscriptionAppEntity.swift`
- Create: `SubscriptionManager/AppIntents/SubscriptionIntents.swift`
- Modify: `SubscriptionManager/App/SubscriptionManagerApp.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`

- [ ] Register the live workspace service when the app starts.
- [ ] Implement entity resolution and localized disambiguation labels without
  financial values.
- [ ] Implement the three discoverable App Intents, their parameter summaries,
  result dialogs, local-device authentication, and App Shortcuts phrases.

## Task 3: Test handlers and real app integration

**Files:**

- Create: `SubscriptionManagerTests/SubscriptionIntentServiceTests.swift`
- Modify: `SubscriptionManagerTests/AppDependenciesTests.swift`
- Modify: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`
- Create: `docs/verification/2026-07-29-authenticated-app-intents-matrix.md`

- [ ] Test success, validation failure, missing, archived, and duplicate-name
  cases with an injected workspace service.
- [ ] Confirm authentication policies and Shortcuts discovery metadata.
- [ ] Run Swift Package tests, Xcode iOS/macOS builds, and targeted iOS
  Simulator tests; document the results and remaining physical-device smoke.
