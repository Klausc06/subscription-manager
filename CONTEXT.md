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
- **Renewal Anchor**: The original local date and time from which every
  expected charge is derived, so clamped month-end dates never become a new
  recurrence basis.
- **Confirmed Next Renewal**: The next charge date supplied or verified by the
  person. It gates the forecast but never replaces the Renewal Anchor.
  Date-only form input is stored at local noon in the billing time zone.
- **Confirmed Charge**: An immutable record that a past expected charge
  occurred. Editing a Fixed Billing Schedule never rewrites it.
  _Avoid_: Expected charge, transaction.

## Current invariant

A fresh local store is a valid Subscription Library and is represented as an
empty, usable state rather than an error or onboarding requirement.
