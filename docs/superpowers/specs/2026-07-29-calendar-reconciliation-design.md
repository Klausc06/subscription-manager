# Convergent Calendar Projection Design

**Status:** Approved for autonomous implementation from the accepted product
specification and the user’s instruction to complete all non-interactive work.

## Goal

Keep a previously imported, dedicated Calendar projection aligned with the
authoritative Subscription Library over its selected rolling horizon. The app
may update or remove known mapped events automatically, but never silently
recreates a dedicated calendar or an externally deleted managed event.

## Chosen approach

The `SubscriptionWorkspace` owns reconciliation requests and observable
reconciliation state. It builds the projection through the same core query
used by preview, then sends the complete desired event set to an injected
`CalendarProjectionReconciler`. The app-layer implementation owns EventKit,
SwiftData mappings, and calendar-change observation. No SwiftUI view reads or
writes EventKit directly.

Three alternatives were considered:

1. **Silently recreate all missing data.** This is mechanically simple but
   violates user control and can create a recreation loop after external
   deletion.
2. **Require a manual import for every update.** This preserves control but
   fails the rolling-horizon and subscription-change requirements.
3. **Reconcile known mapped state automatically; make external deletion a
   decision.** This preserves a continuously useful projection while treating
   destructive external actions as a user-visible choice. This is the chosen
   approach.

## Core seam and states

`CalendarProjectionReconciler` replaces the first-import-only importer at the
workspace boundary. Its commands distinguish:

- **initial import**: explicit confirmation only;
- **reconcile**: update existing mapped events, delete mappings/events absent
  from the desired rolling projection, and add only new future projection UIDs;
- **rebuild**: explicit user decision after external deletion; and
- **disable**: explicit user decision that stops automatic reconciliation while
  retaining the Subscription Library and ICS export.

The workspace publishes a state such as not imported, reconciling, current,
access unavailable, partially reconciled, or needs decision for missing events
or missing calendar. A reconciliation request while a prior one is active is
coalesced rather than run concurrently.

## EventKit and persistence

The EventKit adapter receives the complete desired projection and all persisted
mapping records. For each mapped UID, it refetches the EventKit event before
writing so external edits to title, notes, URL, date, alarms, and all-day state
are overwritten by the app projection. It removes mappings and events outside
the current projection only when their calendar still exists.

If the dedicated calendar cannot be found, no calendar is created. If a mapped
event cannot be found, no event is created. The adapter returns a decision
request with counts. Rebuild is the only command allowed to create the
dedicated calendar or missing events again; disable persists an opt-out marker.
Mapping metadata gains a calendar-management mode and reconciliation revision
so the decision survives launches and CloudKit delivery. Event UID mappings
remain the idempotency key.

## Triggers and lifecycle

After a successful subscription or preference mutation, the workspace queues a
reconciliation if the dedicated calendar is enabled. The application also asks
for reconciliation when a scene becomes active. EventKit changes are observed
through `EKEventStore.EventStoreChanged`; Apple recommends refetching after
that notification, so the observer supplies only a coalesced trigger, never
cached EventKit objects. Applicable SwiftData/CloudKit deliveries feed the
same trigger after the local repository reloads.

No trigger requests authorization. A reconciler that has lost access reports a
recoverable state. Only the explicit initial-import or rebuild actions can
request EventKit full access.

## UI and accessibility

Calendar Preview remains the control surface. It shows current/reconciling and
recoverable failure states. Missing-event and missing-calendar states present
an accessible explanation with two explicit actions: **Rebuild Calendar** and
**Disable Calendar Sync**. Both English and Simplified Chinese copy are added;
ICS export remains available everywhere.

## Verification

- Workspace tests use a fake clock and reconciler to prove trigger coalescing,
  mutation/foreground delivery, and no authorization during ordinary refresh.
- App adapter tests cover idempotent repeated reconciliation, subscription
  updates/cancellation, external field edits, missing event/calendar decisions,
  explicit rebuild, disable, partial retry, and horizon extension.
- A persistence test verifies mode, decision, and mappings survive a SwiftData
  reload. CloudKit delivery is modelled by a fresh workspace/repository view.
- iPhone simulator tests cover status and explicit decision controls. A final
  manual two-device/same-iCloud-account matrix remains dependent on the Apple
  Developer provisioning noted in TB-16.

## Scope limits

This ticket does not attempt to merge arbitrary user-created Calendar events,
modify subscriptions from Calendar, or run background reconciliation without a
foreground/event-store/iCloud delivery trigger. It owns only the app’s
dedicated projection and its persisted mappings.
