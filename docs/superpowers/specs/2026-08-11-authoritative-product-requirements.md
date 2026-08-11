# Authoritative Product Requirements — 2026-08-11

This is the binding product requirements document for Subscription Manager.
Workflow is Superpowers (`brainstorming` → `writing-plans` → TDD / verification).
Older Matt-only session constraints and “frozen iCloud forever” readings are
superseded by this file when they conflict with the requirements below.

**Highest rule:** choose the path that completes a better product. User
statements are commands, not suggestions.

## Product outcome

Help a person understand what they pay for, when the next charge is expected,
and safely maintain that record across iPhone, iPad, and Mac.

The **Subscription Library** is the only source of truth. Calendar, widgets,
exports, and other surfaces are projections or supporting interfaces—not a
second subscription database.

## Required capabilities (do not cut)

### Capture and edit

- Add from catalog match or manual entry.
- Minimum facts: service name, positive amount, currency in `{CNY, USD, EUR}`,
  Fixed Billing Schedule with Start Date and Confirmed Next Renewal.
- Plan and category are optional and must not block save.
- Open a subscription into the same editable presentation—no separate
  read-only detail layer for ordinary edits.
- Unknown prices and eligibility stay unknown. Do not guess prices.

### Lifecycle (explicit actions only)

- Pin, Archive, Restore, Record Cancellation, Reactivate, confirm destructive
  Delete.
- Recorded Cancellation is a local fact. Never contact or automate the
  provider’s cancel flow.

### Schedule and views

- Gregorian billing calendar only. No alternate or user-selectable calendar
  system.
- Upcoming has readable month and day views.
- Catalog remains trustworthy: market offers keep their own currency; aliases
  must never silently bind the wrong service identity.

### Platform surfaces (all in scope)

- Offline bundled catalog.
- ICS preview/export without requiring calendar permission.
- Explicit EventKit import and reconciliation.
- JSON/CSV export and JSON backup/restore.
- Exchange-rate snapshot spend comparison.
- iOS Widget and App Intents.
- Mac window and optional menu bar.
- English and Simplified Chinese.
- System / light / dark appearance.
- Local persistence with **private CloudKit / iCloud sync**.

### iCloud / sync

- Private CloudKit sync is a product requirement.
- “Temporarily not expanding sync” meant defer work in an earlier
  stabilization round—not permanent removal from the product.
- Preserve and ship sync capability; extend it when a ticket explicitly
  approves that work.

### Engineering shape

- Route UI and system surfaces through a workspace-style seam (today:
  `SubscriptionWorkspace`). UI does not talk to persistence or EventKit
  directly.
- Catalog facts need current primary-source evidence.
- One approved requirement at a time.

## Out of scope

- Alternate calendar systems or a user-facing calendar-system selector.
- Guessed prices, inferred promotions, or unverified “standard” offers.
- Provider-side cancellation automation.

## Rebuild direction (approved product intent)

- UI may be rebuilt with Expo (React Native).
- Apple-system capabilities stay via native modules / extensions: EventKit,
  SwiftData/CloudKit, Widget, App Intents, Mac menu bar, and equivalent
  bridges as needed.
- Library remains authoritative; calendar remains a projection.
- Existing native candidate and domain behavior are the behavior oracle.
  Do not discard required capabilities to make Expo easier.

## Success criteria

A build satisfies these requirements when a person can:

1. add, edit, and maintain subscriptions with the minimum facts above;
2. run every listed lifecycle action explicitly;
3. see trustworthy Upcoming dates and catalog selections;
4. use ICS, EventKit import/reconcile, export/backup, rate insights, widgets,
   intents, and Mac surfaces without losing Library authority;
5. sync via private CloudKit as an implemented product capability—not a
   deleted or permanently deferred one.
