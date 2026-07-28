# Explicit Calendar Import Design

**Status:** Approved for autonomous implementation from the accepted product
specification and the user’s instruction to complete all non-interactive work.

## Goal

Let a person explicitly import the already-visible Calendar Projection into one
dedicated Apple Calendar. The app requests full EventKit access only after the
person confirms that action. The Subscription Library remains usable regardless
of access or write outcome, and the existing permission-free ICS export remains
available.

## Chosen architecture

`SubscriptionWorkspace` owns user-observable import state and invokes an
injected `CalendarProjectionImporter`. Its import command accepts the exact
`CalendarProjectionEvent` snapshot shown by the preview, so the first import
cannot silently regenerate a different set of events between confirmation and
write.

The production importer belongs to the app layer. It uses EventKit behind a
small `CalendarEventStore` protocol and persists calendar/event mappings in
SwiftData. The core package does not import EventKit or SwiftData. Unit tests
use a fake importer or fake event store to prove authorization timing,
idempotency, denial, unavailable sources, partial writes, and retry behavior.

## Import flow

1. Calendar Preview loads the selected six- or twelve-month projection without
   creating an EventKit store or requesting authorization.
2. The person chooses **Import to Calendar** and receives a confirmation that
   the listed events will be written to a dedicated Subscription Manager
   calendar.
3. Only the confirmed action calls EventKit’s full-event access request.
4. After access is granted, the importer reuses its persisted calendar ID or
   creates `Subscription Manager` under the system default writable event
   calendar’s source.
5. For each preview event, the importer reuses its persisted EventKit event ID
   when available, otherwise creates the event. It writes the all-day dates,
   title, notes, management URL, and trial or normal alarms from the existing
   projection. A stable projection UID is included in the note marker.
6. The importer persists each successful event mapping immediately. Retrying
   after a partial failure updates mapped events and creates only missing ones.

## States and errors

Core import state is one of: not requested, importing, imported with counts,
access denied, unavailable calendar source, or partially imported with success
and failure counts. UI surfaces a retry action for partial/unavailable outcomes
and leaves ICS export enabled for every state. No failure mutates subscriptions,
preferences, or the existing preview.

Full access is required because mapping-based idempotency must read prior events.
The app declares `NSCalendarsFullAccessUsageDescription`; the string explains
that access is used only to manage the person’s dedicated renewal calendar.

## Persistence

`CalendarProjectionMappingRecord` is additive SwiftData schema: projection UID,
EventKit event identifier, and the dedicated calendar identifier. The mapping
is application metadata only; CloudKit internals and EventKit object layout are
never exposed by the core workspace. An app-generated note marker makes each
created event recoverable by the later convergence ticket.

## Verification

- Core workspace tests prove no importer authorization before explicit import,
  capture the previewed event snapshot, and preserve usability on denial.
- Importer tests with a fake `CalendarEventStore` cover create, repeat import,
  denied, revoked, no writable source, partial failure, and retry.
- App dependency tests round-trip mappings through in-memory SwiftData.
- The iPhone simulator app build and relevant test target compile EventKit code
  without prompting for calendar access.

## Deliberately deferred

Rolling-horizon reconciliation, foreground/store/iCloud triggers, external
edit restoration, and external-deletion prompts remain TB-19. This ticket only
establishes the explicit, idempotent first import and safe retry foundation.
