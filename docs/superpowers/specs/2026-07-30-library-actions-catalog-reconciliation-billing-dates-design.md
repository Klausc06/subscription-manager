# Library Actions, Catalog Reconciliation, and Billing Dates

**Date:** 2026-07-30  
**Status:** Approved design; implementation not started  
**Target version:** 0.1 development line

## Goal

Make the Subscription Library behave like a native Apple list, normalize
manually entered subscriptions when the verified catalog has one exact match,
and reduce billing-date entry to the two dates a person understands:
**Start Date** and **Next Renewal**.

This repository is still in development. This change may update the current
SwiftData development schema and development fixtures without preserving
existing local test data. Current-format persistence and export round trips
must still be tested.

## Superseded Decisions

This design intentionally replaces the following earlier decisions:

1. `Confirmed Next Renewal` is no longer only a forecast gate that can never
   influence the Renewal Anchor. In the active-subscription form, editing
   Next Renewal also derives the preceding Start Date and internal anchor.
2. Renewal Anchor is no longer directly editable or visible in Add, Edit, or
   Detail UI. It remains an internal fact of `FixedBillingSchedule`.
3. Existing `catalog:chatgpt-plus` and manual `ChatGPT Plus` development
   records do not have to retain their old identity. An exact verified match
   is normalized to the canonical `chatgpt` preset.
4. Catalog download and activation remain read-only with respect to the
   Subscription Library, but a separate explicit Workspace reconciliation
   command may normalize subscriptions against the active catalog.
5. Earlier edit-state tests that preserve Next Renewal after every interval
   or anchor change are replaced by the linked-date rules in this document.

## Scope

### In scope

- Native row actions on the iPhone and iPad current and archived libraries.
- Equivalent commands for the macOS table.
- Persistent pin state and pinned-first sorting.
- Permanent deletion confirmation and failure handling.
- Strict, unique reconciliation of manual or legacy records with verified
  catalog offers.
- Canonical normalization of the development ChatGPT Plus record.
- Shared billing-date derivation in `SubscriptionCore`.
- Active and trial date semantics across Add, Edit, catalog Add, App Intents,
  Reactivate, details, forecasts, widgets, Calendar projections, and macOS.
- Current-format SwiftData, private CloudKit schema, JSON backup, restore, and
  CSV export changes required by pinning.

### Out of scope

- Preserving arbitrary pre-release local stores or old portable backups.
- Guessing a service from fuzzy text, partial words, or price alone.
- Automatically marking derived historical occurrences as Confirmed Charges.
- Displaying an unbounded history from a very old Start Date.
- Changing provider prices or adding new catalog services.
- A new offer-provenance field on `Subscription`.

## Domain Semantics

### Start Date

Start Date is a known paid-period start chosen by the person. It is not
intended to preserve the first date on which the person ever bought the
service.

A person may enter a Start Date from last week, last month, last year, or many
years ago. The system treats that date as a valid occurrence and derives the
schedule from it.

For an active subscription:

- `billingSchedule.renewalAnchor == startDate`;
- Start Date is visible and editable;
- Renewal Anchor is internal and hidden;
- Next Renewal is the first schedule occurrence whose billing-local calendar
  day is strictly later than today.

If Start Date is in the future, Next Renewal is one complete interval after
Start Date.

If an occurrence falls on today, it is not considered the next renewal; the
following occurrence is used.

### Next Renewal

Next Renewal is the next paid-period boundary supplied or verified by the
person.

When a person edits Next Renewal for an active subscription:

- Start Date becomes exactly one calendar interval before Next Renewal;
- the internal Renewal Anchor becomes that derived Start Date;
- no older subscription history is inferred beyond the new Start Date.

Calendar subtraction is deterministic and does not guess an unknowable older
month-end intent. For example, reversing a monthly schedule from February 28
produces January 28, not January 31.

### Fixed Billing Schedule

All recurrence calculations use the billing time zone and the shared
Gregorian, `en_US_POSIX` billing calendar.

The following intervals must be supported:

- weekly;
- monthly;
- quarterly;
- half-yearly;
- yearly;
- valid custom day, week, month, and year intervals.

Invalid or non-representable custom intervals are rejected without trapping.
Month-end clamping, leap years, and daylight-saving transitions follow
calendar arithmetic in the billing time zone.

### Trial

Trial dates are not linked by the paid billing interval:

- Start Date is presented as **Trial Start**;
- Confirmed Next Renewal is presented as **First Paid Charge**;
- editing the paid interval does not move First Paid Charge;
- the formal paid schedule uses First Paid Charge as its Renewal Anchor;
- expected paid renewals after the first charge use the selected paid
  interval.

Changing Trial Start does not change First Paid Charge, and changing First
Paid Charge does not rewrite Trial Start.

### Derived historical occurrences

The schedule may derive occurrences between an old Start Date and a bounded
end date. Such occurrences are Expected Charges, never Confirmed Charges.

Any API that returns historical occurrences must require:

- a closed date range; and
- a positive maximum result count.

The existing detail history remains bounded. It must not render every weekly
occurrence from an arbitrarily old Start Date.

## Subscription Library Actions

### Current library on iPhone and iPad

Each row provides:

- trailing/left swipe:
  - **Delete**, destructive and first in the full-swipe direction;
  - **Archive**, non-destructive;
- leading/right swipe:
  - **Pin** when unpinned;
  - **Unpin** when pinned.

`swipeActions(edge:allowsFullSwipe:content:)` uses `allowsFullSwipe: true`.
Apple documents that a full swipe performs the first action for that
direction. Delete is therefore the primary trailing action.

A partial left swipe reveals both Delete and Archive. Continuing to a full
left swipe enters the same deletion flow as tapping Delete.

### Permanent deletion

Delete never removes data immediately. Tapping Delete or completing a full
swipe sets a pending deletion and presents a destructive confirmation dialog.

The dialog identifies the subscription and states that its schedule, notes,
lifecycle facts, and payment history will be permanently removed.

- Cancel leaves the row unchanged.
- Confirm calls the Workspace permanent-delete command.
- Persistence failure leaves the row present and shows an accessible error.
- A full swipe cannot bypass confirmation.

Full swipe is enabled because it is familiar and efficient; the confirmation
is retained because this action is irreversible. Mail-like no-confirmation
swipes are appropriate for recoverable Trash operations, not permanent
deletion.

### Archive

Archive calls the existing Workspace archive command without a confirmation.
It removes the row from the current library and preserves all subscription
facts, including pin state.

### Archived library on iPhone and iPad

Each archived row provides a trailing/left swipe with:

- **Delete**, using the same confirmation flow;
- **Restore**, using the existing Workspace restore command.

Archived rows do not offer Pin or Unpin. If an archived subscription has a
stored pin date, restoring it returns the subscription to the pinned group.

### macOS

The macOS `Table` does not emulate touch swipe gestures. Its context menu and
toolbar/commands expose the same Workspace operations:

- current scope: Pin/Unpin, Archive, Delete;
- archived scope: Restore, Delete.

The permanent-delete confirmation and error behavior match iPhone and iPad.

## Pinning and Ordering

`Subscription` gains:

```swift
public let pinnedAt: Date?
```

`nil` means unpinned. A date means pinned and records recency. No separate
`isPinned` field is added.

The Workspace owns:

```swift
setPinned(id: UUID, pinned: Bool)
```

- Pin sets `pinnedAt` to the injected current time.
- Re-pinning an already pinned row is idempotent.
- Unpin sets `pinnedAt` to `nil`.
- Pinning an archived subscription is rejected.
- Archive preserves `pinnedAt`.
- Restore preserves `pinnedAt`.

Filtering happens before ordering. Every current-library sort uses two groups:

1. pinned subscriptions, ordered by `pinnedAt` descending and UUID ascending
   as a deterministic tie-breaker;
2. unpinned subscriptions, ordered by the selected
   `SubscriptionTableQuery` sort and direction.

Pinned-first behavior applies to iPhone, iPad, macOS, and search results.

## Verified Catalog Reconciliation

### Explicit command boundary

Catalog download, validation, caching, and activation do not mutate
subscriptions.

The Workspace exposes an explicit, idempotent command:

```swift
reconcileCatalogAssociations(locale: Locale)
```

The app may invoke this command after the bundled or active catalog has loaded
and before publishing the current library. Manual Add and Edit also run the
same matcher before persistence.

The command returns a summary suitable for tests and diagnostics:

- matched and normalized IDs;
- unchanged IDs;
- ambiguous IDs;
- failed IDs.

### Text aliases

`CatalogPreset` gains explicit human-entered aliases:

```swift
public let matchAliases: [String]
```

The ChatGPT preset includes `ChatGPT Plus`. `legacyPresetIDs` continue to
canonicalize stored catalog identities; they are not treated as human-visible
text unless the catalog also declares a corresponding `matchAliases` value.

Text normalization is limited to:

- trimming leading and trailing whitespace;
- collapsing internal whitespace;
- Unicode case-insensitive folding;
- Unicode diacritic-insensitive folding.

The matcher does not remove arbitrary words, split plan names, perform fuzzy
matching, or derive a display alias from a preset ID.

### Candidate key

Only offers with `reviewStatus == .verified` participate.

At the reconciliation date, a candidate must match all of:

1. normalized manual service name equals a preset service name or explicit
   match alias;
2. effective current amount equals the offer price in minor units;
3. currency equals;
4. billing interval equals.

The effective amount includes applicable recorded price changes as of the
billing-local current day.

Across the full catalog:

- exactly one `(preset, offer)` candidate: normalize;
- zero candidates: no-op;
- more than one candidate: no-op and report ambiguous.

Plan text is not required for matching because a verified price and interval
may identify the correct official plan. It is replaced only after a unique
match.

### Normalized fields

On a unique match, synchronize:

- `serviceIdentity` to `catalog:<canonical preset ID>`;
- canonical localized service name;
- canonical localized offer plan name;
- canonical localized category;
- preset management URL.

Preserve:

- amount, currency, and billing interval;
- Start Date, Renewal Anchor, and Next Renewal;
- notes;
- lifecycle facts;
- Confirmed Charges and Price Changes;
- archive state;
- `pinnedAt`.

The development record `ChatGPT Plus / USD 20 / monthly` uniquely matches the
verified ChatGPT Plus offer and becomes:

- Service: `ChatGPT`;
- Plan: `Plus`;
- Identity: `catalog:chatgpt`;
- Category and management URL from the ChatGPT preset.

Repeated reconciliation is a no-op.

## Architecture

### SubscriptionCore

Add a pure `BillingDateResolver` that owns date rules:

```swift
nextRenewal(
    afterStart: Date,
    interval: BillingInterval,
    asOf: Date,
    timeZone: TimeZone
) -> Date?

previousCycleStart(
    before nextRenewal: Date,
    interval: BillingInterval,
    timeZone: TimeZone
) -> Date?

expectedOccurrences(
    in range: ClosedRange<Date>,
    schedule: FixedBillingSchedule,
    limit: Int
) -> [Date]
```

Add a pure `CatalogOfferMatcher` that returns `.none`, `.unique`, or
`.ambiguous`.

`SubscriptionWorkspace` remains the sole application mutation seam, in
accordance with ADR 0001. Add, Edit, catalog Add, App Intents, Reactivate,
macOS, and reconciliation call Workspace commands rather than implementing
calendar or matching rules in views.

### App target

SwiftUI bindings decide which user action occurred and send it to the shared
resolver or Workspace. They do not duplicate recurrence algorithms.

The app owns presentation state for:

- pending deletion;
- deletion confirmation;
- deletion failure;
- swipe and context-menu labels.

### Persistence and export

The development SwiftData model gains optional `pinnedAt`.

Current-format round trips must include pin state in:

- SwiftData;
- private CloudKit-backed SwiftData;
- JSON portable backup and restore;
- CSV as `pinned_at` in ISO 8601 form.

Because the app remains pre-release, no old-store migration or old-backup
decoder is required by this change.

## Error Handling

- Failed Delete keeps the row and reports an accessible error.
- Failed Pin, Unpin, Archive, Restore, or reconciliation keeps the last
  persisted state and reports a Workspace mutation error.
- Invalid date derivation prevents Save and identifies the affected field.
- Invalid custom intervals never enter Calendar arithmetic.
- An ambiguous catalog match does not change any subscription.
- One reconciliation persistence failure does not discard prior successful
  normalizations; the result reports the failed ID.

## Localization and Accessibility

All action labels, dialogs, validation, and errors are localized in English
and Simplified Chinese.

Swipe buttons use text plus SF Symbols:

- Delete: `trash`;
- Archive: `archivebox`;
- Restore: `arrow.uturn.backward`;
- Pin: `pin`;
- Unpin: `pin.slash`.

VoiceOver exposes each action independently. Delete confirmation identifies
the service and plan. Pin state is included in the row accessibility value.

Removing Renewal Anchor from visible UI must also remove its VoiceOver label;
the internal value is not exposed as unexplained terminology.

## Test Strategy

### Core date tests

- weekly, monthly, quarterly, half-yearly, yearly;
- custom day, week, month, and year;
- occurrence equals today;
- old Start Date;
- future Start Date;
- January 31 month-end progression;
- February 28 reverse subtraction;
- February 29 yearly progression;
- daylight-saving boundaries;
- invalid and overflowing custom intervals;
- editing Next Renewal derives the previous Start Date;
- changing interval recomputes Next Renewal.

### Trial tests

- Trial Start and First Paid Charge remain independent;
- paid interval changes do not move First Paid Charge;
- paid schedule begins at First Paid Charge;
- lifecycle status changes correctly across the billing-local first-paid day.

### Catalog tests

- canonical service name;
- explicit text alias;
- legacy catalog identity;
- verified offers only;
- zero candidates;
- ambiguous candidates;
- price, currency, or interval mismatch;
- ChatGPT USD 20 monthly normalization;
- repeated reconciliation;
- every preserved field remains unchanged.

### Pin and ordering tests

- pin, unpin, and idempotent re-pin;
- multiple pins use newest-first order;
- equal pin dates use UUID order;
- search and every macOS table sort remain pinned-first;
- archive and restore preserve `pinnedAt`;
- SwiftData and export round trips.

### Swipe and presentation tests

- partial left swipe exposes Delete and Archive;
- full left swipe opens confirmation but does not delete;
- Cancel preserves the row;
- Confirm deletes the row;
- injected persistence failure preserves the row and shows an error;
- right swipe toggles Pin and Unpin;
- archived rows expose Delete and Restore;
- detail-view permanent deletion remains valid.

### Downstream tests

After date or catalog normalization, verify the same persisted subscription is
used by:

- library and detail;
- upcoming timeline;
- forecasts and insights;
- Calendar projection;
- widgets;
- App Intents;
- macOS table.

## Acceptance Criteria

1. A current iPhone row partially left-swipes to Delete and Archive.
2. A full left swipe enters a destructive confirmation; it never silently
   deletes.
3. A right swipe pins or unpins, and pin order survives reload.
4. Archived rows offer Restore and confirmed permanent Delete.
5. macOS exposes equivalent commands and ordering.
6. Renewal Anchor is absent from Add, Edit, and Detail UI.
7. Editing an active Start Date computes the first recurrence strictly after
   today; editing Next Renewal computes the preceding period start.
8. Weekly, monthly, yearly, and custom intervals follow the same Core rules.
9. Trial Start and First Paid Charge remain independent.
10. An old Start Date can produce bounded expected occurrences without
    creating Confirmed Charges.
11. `ChatGPT Plus / USD 20 / monthly` becomes canonical ChatGPT / Plus through
    one exact verified match.
12. Zero or ambiguous catalog matches never modify a subscription.
13. Core, app, UI, persistence, export, simulator, macOS, and physical-device
    gates pass before delivery.

