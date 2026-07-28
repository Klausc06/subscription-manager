# TB-04 Subscription Lifecycle Design

- Date: 2026-07-28
- Issue: [#5 — Manage lifecycle, archive, and deletion safely](https://github.com/Klausc06/subscription-manager/issues/5)
- Status: Approved

## Outcome

A person can record the real lifecycle of a subscription without the
application claiming to cancel a service on their behalf. Trial conversion,
remaining access after cancellation, expiry, archive, restoration, and
permanent deletion remain explicit and deterministic across iOS, iPadOS, and
macOS.

## Scope

TB-04 includes:

- Trial, Active, Cancelled with Access, and Expired user-visible states.
- Local recording of cancellation and access-until dates.
- Immediate removal of cancelled subscriptions from future forecasts.
- Archive, archived browsing, restoration, reactivation, and separately
  confirmed permanent deletion.
- English and Simplified Chinese copy plus accessible native controls.

TB-04 does not:

- Contact Apple, Alipay, WeChat, or any subscription provider.
- Automate or simulate provider cancellation.
- Confirm that a charge occurred or build price history; those belong to
  TB-05.
- Add Calendar, exchange-rate, catalog, CloudKit, widget, or App Intent
  behavior.

## Chosen Approach

Persist lifecycle facts and derive the effective status at a supplied instant.
Do not maintain a mutable "current status" with background tasks or writes on
read.

This approach keeps behavior correct after long periods without launching the
application, makes tests deterministic through the Workspace clock, and
preserves the facts needed to explain the current state.

Rejected alternatives:

1. Persisting the current status would require periodic or read-triggered
   mutation and could become stale.
2. A full lifecycle event log would add audit, migration, synchronization, and
   UI scope that TB-04 does not require.

## Domain Model

### Persisted lifecycle facts

`SubscriptionLifecycle` is a Codable value:

- `trial(firstPaidChargeAt: Date)`
- `active`
- `cancelled(cancelledAt: Date, accessUntil: Date)`

`Subscription` also stores `archivedAt: Date?`. Archive is orthogonal to the
lifecycle. Restoring an archived subscription clears only `archivedAt` and
preserves the lifecycle facts.

When the add form creates a Trial subscription, the person enters Next Renewal
once. Core snapshots that value as `firstPaidChargeAt`; it is not a second
user-facing field. Later renewal-date edits cannot make a completed trial
become Trial again.

### Effective status

`SubscriptionStatus` is derived at a supplied instant:

| Persisted lifecycle | Boundary rule | Effective status |
| --- | --- | --- |
| Trial | `asOf < firstPaidChargeAt` | Trial |
| Trial | `asOf >= firstPaidChargeAt` | Active |
| Active | Always | Active |
| Cancelled | `asOf < accessUntil` | Cancelled with Access |
| Cancelled | `asOf >= accessUntil` | Expired |

The boundary instant belongs to the new status. No background task is needed.
Workspace queries and commands resolve status with the injected clock.

### Allowed transitions

| Starting state | Action | Result |
| --- | --- | --- |
| Trial or Active | Record Cancellation | Cancelled lifecycle facts |
| Cancelled with Access or Expired | Reactivate | Active lifecycle facts |
| Any non-deleted lifecycle | Archive | Same lifecycle, `archivedAt` set |
| Any archived lifecycle | Restore | Same lifecycle, `archivedAt` cleared |
| Any record | Confirm Permanent Delete | Selected record removed |

There is no manual Active-to-Expired transition. Expired is derived from
cancelled lifecycle facts. Reactivation requires a newly confirmed Next
Renewal and clears cancellation and access-until facts by replacing the
lifecycle with Active.

## Forecast Rules

A subscription generates future expected charges only when all conditions are
true:

1. It is not archived.
2. Its effective status is Trial or Active.
3. The existing fixed-schedule and confirmed-next-renewal rules admit an
   occurrence.

Recording cancellation stops forecasts immediately, even while access remains.
Access entitlement and future billing obligation are separate concepts.
Archiving also removes the subscription from forecasts immediately.

Confirmed Charge history remains unchanged by every lifecycle and archive
operation.

## Workspace API and Observable State

All behavior remains behind `SubscriptionWorkspace`:

- `recordCancellation(id:cancelledAt:accessUntil:)`
- `reactivate(id:nextRenewal:)`
- `archive(id:)`
- `restore(id:)`
- `loadLibrary(scope:)`, where scope is `.current` or `.archived`
- `requestPermanentDeletion(id:)`
- `confirmPermanentDeletion(id:)`
- `cancelPermanentDeletion()`

Permanent deletion is a two-stage Workspace flow. Requesting deletion exposes
the selected record as pending but does not mutate persistence. Only explicit
confirmation invokes the repository deletion command.

The Workspace exposes lifecycle-action validation and persistence failures
separately from library/detail loading failures. A failed action keeps the
currently loaded subscription visible and unchanged so the UI can explain the
failure and allow retry.

The repository returns complete `Subscription` aggregates for list queries.
The Workspace owns clock-based status resolution, current/archived filtering,
and construction of `SubscriptionSummary` values. This keeps presentation
queries and lifecycle rules out of persistence.

## Repository and SwiftData

`SubscriptionRepository` gains:

- Listing complete `Subscription` aggregates.
- Deleting one subscription by stable UUID.

SwiftData adds optional, CloudKit-compatible fields:

- Lifecycle discriminator.
- Trial first-paid-charge date.
- Cancellation date.
- Access-until date.
- Archive date.

Existing records with no lifecycle fields decode as Active and unarchived.
Invalid new-field combinations fail explicitly rather than silently inventing
lifecycle facts.

Permanent deletion fetches by stable UUID, deletes only the matching
`SubscriptionRecord`, and saves atomically. A failed save rolls back the model
context.

## Validation

Lifecycle actions use the subscription billing time zone. Date-only input is
normalized to local noon, consistent with existing billing-date behavior.

Rules:

- Cancellation date defaults to today and may be in the past.
- Cancellation date cannot be later than today.
- Access-until cannot be earlier than cancellation.
- Reactivation requires Next Renewal on or after today.
- Lifecycle actions are unavailable while a record is archived; restore comes
  first.
- Permanent deletion is available for current and archived records.

Validation failure performs no repository mutation and exposes a
field-specific, localized message.

## Native UI

### Add flow

The add form includes an Active/Trial initial-state picker. For Trial, Next
Renewal is explained as the first paid charge date. No duplicate trial date
field is shown.

### Library and details

Current rows and details display an accessible status label:

- Trial
- Active
- Cancelled with Access
- Expired

The current Library toolbar provides an Archived entry that navigates to a
separate archived list. Expired records remain in the current list until the
person archives them.

The detail action menu offers only actions valid for the current record:

- Trial/Active: Record Cancellation, Archive, Permanently Delete.
- Cancelled/Expired: Reactivate, Archive, Permanently Delete.
- Archived: Restore, Permanently Delete.

"Record Cancellation" describes a local record update. It never says that the
application cancels, submits, contacts, or completes an operation with a
provider.

### Destructive confirmation

Permanent deletion uses a native destructive confirmation dialog that names
the selected subscription and says the action cannot be undone. Typing the
subscription name is not required. Cancelling the dialog clears pending
deletion without changing data.

All new controls, status labels, validation messages, alerts, and destructive
copy ship in English and Simplified Chinese with stable accessibility
identifiers.

## Error Handling

- A missing target produces the existing not-found behavior.
- Validation errors leave the loaded aggregate and forecasts unchanged.
- Repository failures keep current content visible and expose a retryable
  lifecycle-action error.
- A successful action reloads the active library scope and detail.
- Deleting the open record changes detail state to not found and reloads the
  current scope.

## Test Strategy

Implementation follows strict red-green-refactor TDD.

### SubscriptionCore

- Table-driven effective-status tests before, at, and after every boundary.
- Allowed and rejected lifecycle transition tests through public Workspace
  commands.
- Cancellation and archive tests proving future forecasts disappear
  immediately.
- Restoration tests proving the prior lifecycle is preserved.
- Reactivation tests proving a new renewal is required and cancellation facts
  are cleared.
- Two-stage deletion tests proving request/cancel do not mutate data and
  confirmation deletes only the selected UUID.
- Repository failure tests proving the loaded detail remains visible.

### SwiftData adapter

- Old records load as Active and unarchived.
- Every lifecycle representation round-trips.
- Archive/restore and reactivation persist across repository relaunch.
- Permanent deletion removes one selected record and keeps unrelated records.
- Delete-save failure rolls back.

### SwiftUI

- Critical UI automation covers recording cancellation, archive/restore,
  deletion confirmation, and English/Simplified Chinese status copy.
- Tests assert user-visible behavior through stable accessibility identifiers,
  not private view structure.

### Delivery gates

- Full SubscriptionCore suite.
- Full iPhone application and UI suites.
- iPadOS simulator build.
- macOS no-signing build.
- Localization JSON validation and `git diff --check`.
- Independent verification and real PR review; valid findings receive
  regression tests before merge.

