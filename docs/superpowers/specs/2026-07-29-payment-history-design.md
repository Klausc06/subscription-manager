# TB-05 Payment Confirmation and Price History Design

- Date: 2026-07-29
- Issue: [#6 — Confirm charges and preserve price history](https://github.com/Klausc06/subscription-manager/issues/6)
- Status: Approved product direction and adversarial review complete

## Outcome

People can distinguish a forecast from a real payment, record what actually
occurred without duplicating it on retry, and understand an effective-dated
price change without rewriting historical facts.

## Scope

- Confirm a scheduled charge with an actual charge date, original amount, and
  original currency.
- Persist immutable confirmed-payment facts and immutable price-change facts.
- Resolve forecast amounts from price changes by their billing-local effective
  day.
- Present expected, confirmed, and price-change entries in chronological order.
- Preserve payment and price history while a subscription is archived.

## Explicit non-goals

- No provider contact, automatic charge detection, receipt validation, or
  payment account integration.
- No display-currency conversion, totals, charts, or exchange-rate behavior;
  TB-14 owns those concerns.
- No editing or deletion of a confirmed payment or recorded price change in
  TB-05. Corrections are separate future work rather than mutation of facts.
- No change to cancellation, archive, restoration, or deletion semantics.

## Domain model

### Scheduled charge identity

`ExpectedCharge` gains a stable, Codable scheduled-charge identity. It contains
the subscription UUID plus Gregorian year, month, and day components computed
in the stored billing time zone. That canonical structure, rather than a
locale-formatted string or absolute `Date`, identifies a schedule occurrence.
A price correction therefore does not create a second occurrence.

The identity is derived from the immutable renewal anchor and billing-local
scheduled day. A schedule or time-zone edit can change future identities; it
never changes the identity already recorded by a confirmed payment. The
workspace only accepts a newly confirmed occurrence that validates against the
current schedule; it does not retrofit an historical schedule after an edit.

### Confirmed charge

`ConfirmedCharge` remains an immutable UUID-identified payment record with its
actual charge date and original `Money`. It gains an optional scheduled-charge
identity source. Optional storage keeps every TB-04 record readable: an older
record has no source identity but remains valid history.

Confirming an occurrence whose source identity is already present is a success
without a new repository write. The original payment is returned in the
refreshed presentation, which makes a retried command idempotent.

### Price change

`PriceChange` is a new immutable Codable, identifiable value:

- application-generated UUID;
- positive original `Money` amount;
- effective date normalized to billing-local noon.

`Subscription` gains `priceChanges: [PriceChange]`, defaulting to an empty
collection for existing callers. There is at most one price change per
billing-local effective day, removing same-day ordering ambiguity. A correction
is an additional change with a different effective day, never an edit or
deletion. The base `originalAmount` remains the amount before the first change.

For an expected occurrence, the resolved amount is the latest price change
whose billing-local effective day is on or before the scheduled day. If none
qualify, the base original amount is used. A price change never changes a
`ConfirmedCharge` amount.

## Workspace behavior

The new commands remain behind `SubscriptionWorkspace`:

- `confirmCharge(id:scheduledDate:chargedDate:amount:)`
- `recordPriceChange(id:effectiveDate:amount:)`

The workspace validates the selected scheduled day against the subscription's
fixed billing schedule and billing time zone. A charge can be confirmed after
its forecast day has passed. The actual charge day cannot be in the future;
the selected schedule occurrence cannot be in the future; and the amount must
be positive. Actual payment date is allowed to differ from scheduled date.

A price change must have a positive amount and an effective day on or after the
subscription start day. It can be recorded for a past, current, or future day.
This permits a known upcoming price change while retaining a factual correction
path for an unconfirmed past forecast.

Both commands are unavailable for archived subscriptions. Archive preserves all
facts and history for viewing; Restore is required before any mutation. Failed
validation or repository writes perform no mutation. On a successful write, the
workspace immediately publishes persisted detail, history, and forecast truth;
a later library refresh failure changes only the carried library state, matching
TB-04 semantics.

Ordinary subscription editing no longer accepts amount or currency changes.
Those changes must use `recordPriceChange`, so the previous price and every
confirmed charge stay immutable.

The idempotency promise covers retries delivered to the current local
workspace/repository: the scheduled-charge identity is the de-duplication key.
The app does not yet configure CloudKit synchronization; TB-16 owns concurrent
multi-device merge behavior and will use this stable source key to merge
independent confirmations. TB-05 retains the existing atomic local aggregate
save rather than introducing speculative synchronization infrastructure.

## Forecast and history presentation

Expected charges remain derived, never persisted. Forecast generation:

1. retains the TB-04 lifecycle and archive eligibility rules;
2. resolves each occurrence amount from effective-dated price changes;
3. excludes an occurrence whose scheduled-charge identity has already been
   confirmed.

The detail presentation receives workspace-derived history entries rather than
reimplementing schedule or price rules in SwiftUI. Entries are an explicit sum
type for expected, confirmed, and price-change events. The detail timeline
contains the most recent unconfirmed occurrence on or before the current
billing-local day, the next unconfirmed future occurrence, plus every confirmed
payment and price change. These two derived expected entries make late
confirmation reachable after a forecast date passes without inventing an
unbounded historical forecast. Entries sort chronologically; on the same day a
Price Change precedes Expected, which precedes Confirmed. A confirmed expected
entry disappears and its confirmed entry remains.

Archived detail displays confirmed payments and price changes only because
archived subscriptions never forecast future charges.

## Persistence and compatibility

SwiftData adds one optional `priceChangesData` JSON field to
`SubscriptionRecord`. Existing `confirmedChargesData` remains the persistence
boundary for payment records. `nil` price data decodes as an empty collection,
and a missing optional source identity in an older confirmed-charge payload
remains valid. The repository preserves legacy payment JSON until a TB-05
command writes the updated aggregate, then encodes the additive optional source
identity.

All new SwiftData schema fields are additive. Repository encode/decode failures
remain fail-fast for the selected aggregate; no list path silently invents
payment or price facts.

## Native UI

Current active or trial detail pages expose:

- **Confirm Charge**: a native form for the scheduled date, actual payment
  date, original amount, and original currency; defaults come from the selected
  eligible schedule occurrence.
- **Record Price Change**: a native form for effective date, original amount,
  and original currency.

The detail screen displays a localized chronological history with distinct
Expected, Confirmed, and Price Change labels. Existing status labels and
accessibility identifiers remain stable. New controls and rows receive
app-owned accessibility identifiers. All new copy ships in English and
Simplified Chinese. The domain term remains `ConfirmedCharge`; user-facing copy
uses “Confirmed Payment” to distinguish it from an Expected Charge.

TB-05 retains the product's existing CNY and USD `Currency` domain. It stores
the selected original money exactly and makes no display-currency conversion
claim; conversion and selected display currency begin in TB-14.

## Errors

Payment-history validation and persistence failures are separate from library
loading and lifecycle-action errors. The UI presents a localized recoverable
error while retaining loaded detail and history. Validation cases include an
invalid scheduled occurrence, a future scheduled or actual charge day, a
non-positive amount, a price effective before subscription start, archived
mutation, and persistence failure.

## Verification

Core workspace tests drive every command through observable state and cover:

- confirmation creates exactly one source-linked payment and a retry is a
  no-op;
- a past scheduled occurrence can be confirmed;
- the most recent missed and next expected occurrences are reachable in the
  workspace-owned history;
- confirmed occurrences disappear from forecasts;
- price changes apply at the billing-local effective-day boundary and reject a
  second change on the same billing day;
- old confirmed payment amounts remain unchanged after a price change;
- archive retains history and blocks payment-history mutation;
- persistence failure preserves detail, forecast, and history.

SwiftData tests cover old records without price data or source-linked charges,
round trips for new values, the pre-TB-05 disk-store reopen path, and decoding
failures. UI tests cover confirmation, price-change entry, chronological
labels, archives, and English/Simplified Chinese copy. Simulator validation
uses the Build iOS Apps Xcode tools after the test-first implementation is
complete.
