# Implementation Plan: Round 3 Optimization

**Date:** 2026-08-25
**Fixed point:** `7b0ab3a`
**Scope:** Top 8 recommendations that don't require product decisions.

---

## Phase 1: Code Quality (iOS 27 SwiftData adoption)

### 1A. SwiftData `.codable` attribute for compound types
**Current state:** `SubscriptionRecord` uses raw-value storage (separate fields for
billing schedule components). Exchange rate snapshots use manual JSON serialization.
**Change:** Where a compound Codable struct is stored as multiple scalar columns today,
evaluate whether `.codable` attribute simplifies without breaking CloudKit compatibility.
**Risk:** CloudKit private database may not support opaque `.codable` blobs. Verify first.
**Effort:** S | **Impact:** Medium (reduces boilerplate if compatible)

### 1B. SwiftData `ResultsObserver` for widget timeline
**Current state:** Widget reads from a UserDefaults plist snapshot published by the workspace.
**Change:** Evaluate whether `ResultsObserver` can replace the manual publish→plist→widget pipeline.
**Risk:** Widget extensions run in a separate process; `ResultsObserver` requires a `ModelContainer`.
Need to verify cross-process observation works with the app-group container.
**Effort:** S | **Impact:** Medium (eliminates manual snapshot publishing if viable)

> **Decision gate after Phase 1:** If `.codable` breaks CloudKit or `ResultsObserver` doesn't
> work cross-process, skip those items and proceed to Phase 2.

---

## Phase 2: Platform Features

### 2A. App Intents — enrich for Siri AI / App Schemas
**Current state:** 3 intents (Add, Show Upcoming, Monthly Forecast) + AppEntity + AppShortcutsProvider.
**Change:**
- Add `FindSubscriptionsIntent` returning structured results Siri can speak
- Add `NextRenewalIntent` — "When does X renew?" answering with date + amount
- Add `MonthlySpendIntent` — "How much do I spend monthly?" with total
- Expose richer `SubscriptionAppEntity` properties (amount, nextRenewal, currency)
- Consider `AppSchema` conformance if API is available in this beta
**Effort:** M | **Impact:** High

### 2B. Control Center widget
**Current state:** No Control Center integration.
**Change:** Add a `ControlWidget` showing next renewal (service name + date) or monthly total.
Requires a WidgetBundle entry and a small `ControlWidgetToggle` or `ControlWidgetButton`.
**Effort:** M | **Impact:** Medium

---

## Phase 3: UX Polish

### 3A. Animated renewal countdown visualization
**Current state:** Detail view shows static "Next: Sep 26" text.
**Change:** Add a `RenewalProgressView` — circular progress ring showing elapsed fraction
of current billing period. Placed in subscription detail and optionally in the list row for
the nearest renewal.
**Effort:** S | **Impact:** Medium (visual differentiation from all competitors)

### 3B. Configurable notification advance timing
**Current state:** No local notifications at all.
**Change:**
- Add `notificationAdvanceDays: Int` to UserPreferences (default: 1)
- Schedule `UNLocalNotification` for each active subscription at (renewalDate - advanceDays)
- Reschedule on subscription add/edit/delete and preference change
- Permission request flow on first enable
**Effort:** S–M | **Impact:** Medium (table stakes feature currently missing)

### 3C. Daily spending velocity indicator
**Current state:** Insights show total monthly spend.
**Change:** Add a "cost per day" derived value in the insights section:
`totalMonthlySpend / daysInMonth`. Display as a small callout card.
**Effort:** S | **Impact:** Medium (novel framing of existing data)

---

## Execution Order

| Step | Item | Depends on | Deliverable |
|------|------|-----------|-------------|
| 1 | 1A | — | Feasibility spike: test `.codable` + CloudKit |
| 2 | 1B | — | Feasibility spike: test `ResultsObserver` in widget extension |
| 3 | 3C | — | Spending velocity in insights (pure logic + UI) |
| 4 | 3A | — | Renewal countdown progress ring |
| 5 | 3B | — | Local notification scheduling |
| 6 | 2A | — | App Intents enrichment |
| 7 | 2B | — | Control Center widget |

Steps 1–2 are spikes that may terminate early. Steps 3–7 are full implementations.
Each step produces one commit, verified per production-flow before proceeding.

---

## Out of scope (requires product decision)

- Foundation Models NL entry (P9)
- Screenshot/receipt import (C1)
- Portal/cancellation links (C4)
- Sectioned queries (API not available in current beta)
