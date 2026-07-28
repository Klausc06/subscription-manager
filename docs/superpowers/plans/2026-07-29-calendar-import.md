# Explicit Calendar Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import the already-previewed renewal events into one dedicated Apple
Calendar only after explicit confirmation, with safe retry and no impact on the
Subscription Library.

**Architecture:** Add a Calendar importer protocol and observable import state
to `SubscriptionWorkspace`. Implement EventKit plus SwiftData mapping only in
the app target behind a fakeable event-store protocol, then bind the existing
preview to a confirmation-driven import control.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, EventKit,
iOS/iPadOS/macOS 27.

## Global Constraints

- Keep `SubscriptionWorkspace` as the only SwiftUI command/query seam.
- Never request Calendar access before an explicit confirmed import action.
- Preserve the existing permission-free ICS export for denied, revoked, and
  unavailable Calendar states.
- Ship every user-facing string in English and Simplified Chinese.
- Treat Calendar as a projection; never change Subscription Library data from
  an EventKit result.

---

### Task 1: Model workspace-facing Calendar import state

**Files:**
- Create: `Packages/SubscriptionCore/Sources/SubscriptionCore/CalendarImport.swift`
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Test: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`

**Interfaces:**
- Produces `CalendarProjectionImporter`, `CalendarProjectionImportResult`, and
  `CalendarImportState` for the app adapter.
- Produces `SubscriptionWorkspace.importCalendarProjection(_:)` accepting the
  exact `[CalendarProjectionEvent]` rendered in the preview.

- [ ] Write failing workspace tests with a recording fake importer. Assert no
  import call after `loadCalendarProjection`, then assert the explicit command
  receives the unchanged projection and exposes denied/partial results.
- [ ] Add the public result/state values and the optional importer dependency.
  Set `.importing` before awaiting it and publish its returned result without
  touching library or preferences state.
- [ ] Run `swift test --package-path Packages/SubscriptionCore --filter
  SubscriptionWorkspaceTests` and commit the core seam.

### Task 2: Persist mappings and adapt EventKit

**Files:**
- Create: `SubscriptionManager/Calendar/EventKitCalendarProjectionImporter.swift`
- Modify: `SubscriptionManager/Persistence/SubscriptionRecord.swift`
- Modify: `SubscriptionManager/App/AppDependencies.swift`
- Modify: `SubscriptionManager/Info.plist`
- Test: `SubscriptionManagerTests/EventKitCalendarProjectionImporterTests.swift`
- Test: `SubscriptionManagerTests/AppDependenciesTests.swift`

**Interfaces:**
- Consumes `CalendarProjectionImporter` and `CalendarProjectionEvent`.
- Produces `EventKitCalendarProjectionImporter` wired only for production
  dependencies, plus `CalendarProjectionMappingRecord` in the additive schema.

- [ ] Write fake-store tests for granted creation, repeat update with no
  duplicate calendar/event, denial, no writable source, partial write, and
  retry. Assert only the importer invokes `requestFullEventAccess`.
- [ ] Implement a fakeable app-layer `CalendarEventStore`, EventKit adapter,
  mapping repository, and importer. Store event IDs after individual success;
  return partial counts instead of throwing a library-changing error.
- [ ] Add `NSCalendarsFullAccessUsageDescription` and wire the importer into
  production dependencies while UI-testing stores receive a deterministic
  unavailable adapter.
- [ ] Run the focused simulator test target and commit the adapter.

### Task 3: Bind explicit confirmation to the preview

**Files:**
- Modify: `SubscriptionManager/Library/CalendarProjectionView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**
- Consumes `SubscriptionWorkspace.calendarImportState` and
  `importCalendarProjection(_:)`.
- Produces an accessible **Import to Calendar** confirmation and import-status
  presentation without removing the existing ICS exporter.

- [ ] Add a confirmation dialog whose affirmative button starts the async
  workspace import using the current preview snapshot. Do not initialize or
  call EventKit from `.task`, `body`, or the exporter.
- [ ] Render success, denied, unavailable, and partial retry messages with
  accessibility identifiers; keep export enabled in every state.
- [ ] Add English/Simplified Chinese copy and run the iPhone simulator build
  plus relevant UI smoke test. Commit the UI.

### Task 4: Complete verification and PR handoff

**Files:**
- Create: `docs/verification/2026-07-29-explicit-calendar-import-matrix.md`

- [ ] Run the full core suite and the app test target, then record exact
  commands and outcomes.
- [ ] Scan the app source for EventKit access calls and verify the only request
  path is the production importer invoked by confirmed import.
- [ ] Create a TB-18 PR based on `feat/tb-17-calendar-preview-ics`, request
  review, and do not merge it.
