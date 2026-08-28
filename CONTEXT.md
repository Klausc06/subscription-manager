# Domain Context

## Glossary

- **Subscription Library**: The person's authoritative collection of tracked
  subscriptions. Calendar is a projection of this library, never its source.
- **Subscription Workspace**: The application seam used by SwiftUI, widgets,
  App Intents, and menu-bar surfaces to issue commands and read
  user-observable state.
- **Subscription Repository**: The persistence boundary used by the workspace.
  The production repository is SwiftData and can use the app's private
  CloudKit configuration; application tests use in-memory implementations.
- **Subscription Summary**: The stable user-facing projection of a tracked
  subscription: identity and name, optional plan and category, original and
  effective amount, schedule, confirmed renewal, effective status, next
  expected charge, and pin state.
- **Adapter**: An injected boundary between the workspace and an external
  concern such as catalog data, exchange rates, Calendar, or synchronization.
- **Catalog Preset**: A stable service identity and localized metadata offered
  by the bundled catalog. A preset can have zero or more market- and
  channel-specific offers without inventing a price.
- **Catalog Offer**: A market-, purchase-channel-, currency-, amount-, and
  billing-interval-specific option associated with a Catalog Preset. Its
  verification state records whether it can be adopted automatically or needs
  review.
- **Fixed Billing Schedule**: A positive calendar interval, renewal anchor,
  and billing time zone that deterministically define expected charges.
  _Avoid_: Billing cycle.
- **Start Date**: A known paid-period start chosen by the person. It may be an
  old billing occurrence and does not mean the first date the subscription was
  ever purchased. For a trial it is presented as Trial Start and remains
  independent from the paid schedule.
- **Renewal Anchor**: The internal local recurrence basis used to derive
  expected charges. It is hidden from Add, Edit, and Detail. For an active
  subscription it equals Start Date; for a trial it equals First Paid Charge.
- **Confirmed Next Renewal**: The next charge date supplied or verified by the
  person. Editing an active Start Date derives the first recurrence strictly
  after today. Editing Next Renewal derives the preceding Start Date and
  internal Renewal Anchor. Date-only form input is stored at local noon in the
  billing time zone. For a trial it is presented as First Paid Charge; changing
  Trial Start or the paid interval does not move it.
- **Renewal Period Progress**: The elapsed fraction of the current billing
  period and the whole days remaining before the Confirmed Next Renewal,
  derived at a specific instant. The period starts one billing interval before
  the Confirmed Next Renewal, by the same derivation Editing Next Renewal uses
  for the preceding Start Date. The fraction is clamped to 0 through 1 and the
  days remaining never fall below zero, so a renewal already past reads as a
  complete period with no days left rather than counting backwards. An interval
  that cannot step back, such as a custom value outside the representable
  range, degrades to a zero-length period and reports a fraction of 0; that is
  the only case that leaves the reading wholly empty. The Fixed Billing
  Schedule's billing time zone rather than the device's fixes the period start
  and the day boundaries the days remaining are counted across. The fraction is
  a ratio of absolute time, so the billing time zone reaches it only through
  that period start. When the billing time zone identifier cannot be resolved,
  the derivation falls back to the device's time zone. Like Effective
  Subscription Status it is derived on demand, never stored.
- **Confirmed Charge**: An immutable record that a past expected charge
  occurred. Editing a Fixed Billing Schedule never rewrites it.
  _Avoid_: Expected charge, transaction.
- **Subscription Lifecycle**: The persisted facts that describe whether a
  subscription began as a trial, is active, or was cancelled, including the
  first paid charge, cancellation, and access-until dates when applicable.
- **Effective Subscription Status**: The user-visible Trial, Active,
  Cancelled with Access, or Expired status derived from Subscription Lifecycle
  facts at a specific instant. It is not a background-maintained field.
- **Recorded Cancellation**: A local fact that the person has already
  cancelled a service. Recording it never contacts, automates, or simulates an
  action with the subscription provider.
- **Reactivation**: The person chooses the next renewal date. The workspace
  derives the preceding Start Date and internal Renewal Anchor from the stored
  paid interval so every projection observes one coherent active schedule.
- **Archived Subscription**: A Subscription hidden from current-library
  queries, forecasts, and insights while retaining its lifecycle and history.
  Restoring it changes visibility only.
- **Pinned Subscription**: A current-library subscription with a persisted
  `pinnedAt` timestamp. Pinned rows always precede ordinary rows; newer pin
  timestamps sort first, with UUID as the deterministic tie-breaker. Archive
  and restore preserve the timestamp.

## Current invariant

The Subscription Library remains authoritative whether first-run setup is
needed, completed, skipped, or failed. Setup and preferences never become a
second source of subscription facts, and a failed or incomplete load is not
represented as a trustworthy empty library.
