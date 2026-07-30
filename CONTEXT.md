# Domain Context

## Glossary

- **Subscription Library**: The person's authoritative collection of tracked
  subscriptions. Calendar is a projection of this library, never its source.
- **Subscription Workspace**: The application seam used by SwiftUI and future
  widgets, App Intents, and menu-bar surfaces to issue commands and read
  user-observable state.
- **Subscription Repository**: The persistence boundary used by the workspace.
  The production repository is local SwiftData; application tests use
  in-memory implementations.
- **Subscription Summary**: The smallest stable, identifiable representation
  needed to list a subscription. Later tickets add user-facing fields
  additively.
- **Adapter**: An injected boundary between the workspace and an external
  concern such as catalog data, exchange rates, Calendar, or synchronization.
- **Fixed Billing Schedule**: A positive calendar interval, renewal anchor,
  and billing time zone that deterministically define expected charges.
  _Avoid_: Billing cycle.
- **Start Date**: A known paid-period start chosen by the person. It may be an
  old billing occurrence and does not mean the first date the subscription was
  ever purchased.
- **Renewal Anchor**: The internal local recurrence basis used to derive
  expected charges. It is hidden from Add, Edit, and Detail. For an active
  subscription it equals Start Date.
- **Confirmed Next Renewal**: The next charge date supplied or verified by the
  person. Editing an active Start Date derives the first recurrence strictly
  after today. Editing Next Renewal derives the preceding Start Date and
  internal Renewal Anchor. Date-only form input is stored at local noon in the
  billing time zone.
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
- **Archived Subscription**: A Subscription hidden from current-library
  queries, forecasts, and insights while retaining its lifecycle and history.
  Restoring it changes visibility only.

## Current invariant

A fresh local store is a valid Subscription Library and is represented as an
empty, usable state rather than an error or onboarding requirement.
