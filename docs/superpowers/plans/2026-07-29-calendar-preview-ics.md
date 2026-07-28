# TB-17 Calendar Preview and ICS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person preview and export the exact upcoming renewal calendar projection without requesting Calendar access.

**Architecture:** `SubscriptionWorkspace` derives one pure projection from subscriptions, preferences, locale, and a deterministic clock. A focused encoder turns that projection into RFC 5545 text. SwiftUI displays the projection and exports the exact bytes through a native file exporter; neither layer imports EventKit.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Foundation, Swift Testing, iOS/iPadOS/macOS 27.

## Global Constraints

- Do not import EventKit, call Calendar authorization, create a Calendar, or make a network request.
- Generate individual all-day events only; use stable application UUID-derived UIDs and the existing Gregorian billing calendar.
- All user-visible copy and accessibility output must exist in English and Simplified Chinese.
- `DTSTART;VALUE=DATE`, exclusive next-day `DTEND;VALUE=DATE`, RFC 5545 TEXT escaping, CRLF, and UTF-8-safe 75-octet folding are mandatory.
- The preview and exported file must consume the same `CalendarProjectionEvent` array.

---

### Task 1: Add preferences and deterministic event projection

**Files:**
- Modify: `Packages/SubscriptionCore/Sources/SubscriptionCore/SubscriptionCore.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/SubscriptionWorkspaceTests.swift`
- Modify: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/UserPreferencesTests.swift`
- Modify: `SubscriptionManager/Persistence/SubscriptionRecord.swift`
- Modify: `SubscriptionManager/Persistence/SwiftDataSubscriptionRepository.swift`
- Test: `SubscriptionManagerTests/AppDependenciesTests.swift`

**Interfaces:**
- `UserPreferences.hideAmountsInCalendar: Bool` defaults to `false`.
- `CalendarProjectionEvent` contains `uid`, `startDate`, `endDate`, `title`, `notes`, `managementURL`, and `[CalendarAlarm]`.
- `SubscriptionWorkspace.loadCalendarProjection(locale:now:)` derives events from the saved horizon and publishes `calendarProjection`.

- [ ] Write failing tests for a six-month boundary, cancellation/archive exclusion, amount hiding, and trial alarm offsets.
- [ ] Run the focused core test and observe the missing projection API failure.
- [ ] Implement only the projection types, preference persistence, and query; preserve existing schedule and lifecycle behavior.
- [ ] Run the full core suite plus the SwiftData preference round-trip tests.
- [ ] Commit `feat(core): project renewal calendar events`.

### Task 2: Encode and independently parse RFC 5545 output

**Files:**
- Create: `Packages/SubscriptionCore/Sources/SubscriptionCore/CalendarICS.swift`
- Create: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/CalendarICSTests.swift`
- Create: `Packages/SubscriptionCore/Tests/SubscriptionCoreTests/Fixtures/calendar-projection.ics`

**Interfaces:**
- `CalendarICSEncoder.encode(events:generatedAt:) throws -> Data` is deterministic for equal input.
- The output contains RFC 5545 VCALENDAR/VEVENT/VALARM components, escaped text, CRLF, and folded UTF-8 lines.

- [ ] Write failing fixture tests that pass encoded data through an independent iCalendar parser and inspect all-day boundaries, UID, URL, and alarm triggers.
- [ ] Run the focused encoder test and observe that the encoder does not exist.
- [ ] Implement text escaping, date formatters, byte-safe folding, and component serialization without referencing SwiftUI or EventKit.
- [ ] Run full core tests and the independent-parser command on the fixture.
- [ ] Commit `feat(core): encode calendar projection as ICS`.

### Task 3: Add preview, amount preference, and native export

**Files:**
- Create: `SubscriptionManager/Calendar/CalendarProjectionView.swift`
- Create: `SubscriptionManager/Calendar/CalendarProjectionDocument.swift`
- Modify: `SubscriptionManager/Library/LibraryView.swift`
- Modify: `SubscriptionManager/Resources/Localizable.xcstrings`
- Modify: `SubscriptionManager.xcodeproj/project.pbxproj`
- Test: `SubscriptionManagerUITests/SubscriptionManagerUITests.swift`

**Interfaces:**
- Settings links to `CalendarProjectionView(workspace:)`.
- The view loads `workspace.calendarProjection`, renders its events, and presents `fileExporter` with `CalendarProjectionDocument` built from `CalendarICSEncoder`.

- [ ] Write a failing UI test that reaches the preview, observes an exported-event row, and asserts no Calendar authorization adapter invocation.
- [ ] Run the focused UI test and observe the missing navigation/accessibility identifiers.
- [ ] Add the Settings toggle, accessible list, export action, `FileDocument`, and bilingual copy; retain the exact projection array for preview and exporter.
- [ ] Run focused iPhone/iPad UI tests and simulator builds; build macOS when signing is provisioned.
- [ ] Commit `feat(app): preview and export calendar projection`.

### Task 4: Record evidence and deliver

**Files:**
- Create: `docs/verification/2026-07-29-calendar-preview-ics.md`

- [ ] Record exact core/parser/simulator commands and the statement that export has no EventKit authorization path.
- [ ] Push `feat/tb-17-calendar-preview-ics`, create a stacked PR on `feat/tb-16-icloud-sync`, and request independent review without merging.
