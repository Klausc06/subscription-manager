# TB-04 Subscription Lifecycle Design

- Date: 2026-07-28
- Issue: [#5 — Manage lifecycle, archive, and deletion safely](https://github.com/Klausc06/subscription-manager/issues/5)
- Status: Approved after architecture review

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

`Subscription` also stores `isArchived: Bool`. Archive is orthogonal to the
lifecycle. Restoring an archived subscription changes only `isArchived` and
preserves the lifecycle facts. TB-04 does not display, sort, or audit archive
dates, so it does not persist an unused timestamp.

When the add form creates a Trial subscription, the person enters Next Renewal
once. Core snapshots that value as `firstPaidChargeAt`; it is not a second
user-facing field. Later renewal-date edits cannot make a completed trial
become Trial again.

### Effective status

`SubscriptionStatus` is derived at a supplied instant by comparing calendar
days in the subscription billing time zone:

| Persisted lifecycle | Billing-local day rule | Effective status |
| --- | --- | --- |
| Trial | `asOfDay < firstPaidChargeDay` | Trial |
| Trial | `asOfDay >= firstPaidChargeDay` | Active |
| Active | Always | Active |
| Cancelled | `asOfDay < accessUntilDay` | Cancelled with Access |
| Cancelled | `asOfDay >= accessUntilDay` | Expired |

The whole boundary day belongs to the new status. Persisted date-only values
remain normalized to local noon for DST safety, but lifecycle status never
changes halfway through a local day. No background task is needed. Workspace
queries and commands resolve status with the injected clock.

### Allowed transitions

| Starting state | Required archive state | Action | Result |
| --- | --- | --- | --- |
| Trial or Active | Current | Record Cancellation | Cancelled lifecycle facts |
| Cancelled with Access or Expired | Current | Reactivate | Active lifecycle facts |
| Any lifecycle | Current | Archive | Same lifecycle, archived |
| Any lifecycle | Archived | Restore | Same lifecycle, current |
| Any lifecycle | Current or Archived | Permanently Delete | Selected record removed |

There is no manual Active-to-Expired transition. Expired is derived from
cancelled lifecycle facts. Reactivation requires a newly confirmed Next
Renewal and clears cancellation and access-until facts by replacing the
lifecycle with Active. It preserves the existing Fixed Billing Schedule and
uses the new Confirmed Next Renewal as its forecast gate; changing the schedule
remains the existing edit flow.

Every other action/state combination fails with one
`invalidLifecycleTransition` action error and performs no repository mutation.
Ordinary subscription editing must copy lifecycle facts, archive state, and
Confirmed Charge history unchanged.

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

The current non-optional `Subscription.firstExpectedCharge` and
`SubscriptionSummary.firstExpectedCharge` are removed.
`SubscriptionSummary` instead contains the Workspace-resolved status and an
optional `nextExpectedCharge`. `SubscriptionDetailState.loaded` carries the
full Subscription, resolved status, and the same optional next Expected Charge
as associated values. Cancelled, Expired, and Archived presentations always
carry `nil`, so SwiftUI never invents or hides a charge by reimplementing
lifecycle rules.

## Workspace API and Observable State

All behavior remains behind `SubscriptionWorkspace`:

- `recordCancellation(id:cancelledAt:accessUntil:)`
- `reactivate(id:nextRenewal:)`
- `archive(id:)`
- `restore(id:)`
- `loadLibrary(scope:)`, where scope is `.current` or `.archived`
- `deletePermanently(id:)`

The native SwiftUI view owns only the temporary identity used to present its
confirmation dialog. Cancelling the dialog calls no Workspace command.
Confirming it calls `deletePermanently(id:)`; all actual mutation remains
behind the Workspace.

The Workspace exposes lifecycle-action validation and persistence failures
separately from library/detail loading failures. A failed action keeps the
currently loaded subscription visible and unchanged so the UI can explain the
failure and allow retry.

The repository returns complete `Subscription` aggregates for list queries.
The Workspace owns clock-based status resolution, current/archived filtering,
and construction of `SubscriptionSummary` values. This keeps presentation
queries and lifecycle rules out of persistence.

`SubscriptionLibraryState` carries its `SubscriptionLibraryScope` in loading,
empty, loaded, and failed states. The Workspace maintains one current scope,
not separate caches. A Current or Archived page loads its target scope whenever
the observable state belongs to a different scope, preventing one page from
displaying the other page's records after navigation.

The loaded detail presentation contains the full Subscription, its effective
status, and optional next Expected Charge. SwiftUI renders those values without
calculating lifecycle or forecast eligibility.

## Repository and SwiftData

`SubscriptionRepository` gains:

- Listing complete `Subscription` aggregates.
- Deleting one subscription by stable UUID.

SwiftData adds optional fields so records written before TB-04 remain readable:

- Lifecycle discriminator.
- Trial first-paid-charge date.
- Cancellation date.
- Access-until date.
- Archive flag.

Existing records with no lifecycle fields decode as Active and unarchived.
The valid storage combinations are:

| Discriminator | Trial date | Cancellation date | Access-until date |
| --- | --- | --- | --- |
| Legacy `nil` | `nil` | `nil` | `nil` |
| Trial | Required | `nil` | `nil` |
| Active | `nil` | `nil` | `nil` |
| Cancelled | `nil` | Required | Required |

Non-applicable fields must be `nil`. Unknown discriminators, partial required
fields, and lifecycle dates attached to a legacy/Active record fail explicitly
rather than silently inventing facts. A missing archive flag means unarchived.

Permanent deletion fetches by stable UUID, deletes only the matching
`SubscriptionRecord`, and saves atomically. A failed save rolls back the model
context.

## Validation

Lifecycle actions use the subscription billing time zone. Date-only input is
normalized to local noon, consistent with existing billing-date behavior.
Validation and effective-status boundaries compare billing-local calendar
days, not absolute instants.

Rules:

- Cancellation date defaults to today and may be in the past.
- Cancellation date cannot be later than today.
- Access-until cannot be earlier than cancellation.
- Reactivation requires Next Renewal on or after today, preserves the Fixed
  Billing Schedule, and replaces only the Confirmed Next Renewal gate.
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
view state without calling the Workspace.

All new controls, status labels, validation messages, alerts, and destructive
copy ship in English and Simplified Chinese with stable accessibility
identifiers.

## Error Handling

- A missing target produces the existing not-found behavior.
- Validation errors leave the loaded aggregate and forecasts unchanged.
- Invalid action/state combinations expose
  `invalidLifecycleTransition` and perform no mutation.
- Repository failures keep current content visible and expose a retryable
  lifecycle-action error.
- A successful action reloads the currently selected library scope and detail.
- Deleting the open record changes detail state to not found and reloads the
  current scope.

## Test Strategy

Implementation follows strict red-green-refactor TDD.

### SubscriptionCore

- Table-driven effective-status tests on the billing-local day before, on, and
  after every boundary.
- Allowed and rejected lifecycle transition tests through public Workspace
  commands.
- Cancellation and archive tests proving future forecasts disappear
  immediately.
- Restoration tests proving the prior lifecycle is preserved.
- Reactivation tests proving a new renewal is required and cancellation facts
  are cleared.
- Permanent-deletion tests proving only the selected UUID is deleted.
- Ordinary-edit tests proving lifecycle, archive state, and Confirmed Charge
  history survive unchanged.
- Current/Archived scope tests proving navigation never displays records from
  the other scope.
- Repository failure tests proving the loaded detail remains visible.

### SwiftData adapter

- Old records load as Active and unarchived.
- Every valid lifecycle representation round-trips.
- Every invalid storage combination fails explicitly.
- Permanent deletion removes one selected record and keeps unrelated records.
- Delete-save failure rolls back.

### SwiftUI

- Critical UI automation covers recording cancellation, archive/restore,
  deletion confirmation, and English/Simplified Chinese status copy.
- Deletion UI automation proves cancelling confirmation preserves the selected
  record and confirming it removes that record.
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
