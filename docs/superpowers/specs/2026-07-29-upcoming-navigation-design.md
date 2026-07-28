# TB-13 Upcoming Navigation Design

- Date: 2026-07-29
- Issue: #14 — Review upcoming charges with native iPhone and iPad navigation
- Status: Approved for autonomous implementation

## Decision

Add a workspace-owned `UpcomingTimelineItem` projection rather than asking a
SwiftUI view to merge subscription, forecast, and payment data. Each item
contains its subscription identifier, service name, date, money, and an
explicit kind (`expected` or `confirmed`). The workspace reads the existing
local repository once, excludes archived and lifecycle-ineligible forecasts,
and returns a stable chronological ordering.

The UI gains a root `TabView` with persistent Subscriptions, Upcoming, and
Insights destinations on compact iPhone widths. Settings remains a toolbar
action in the Subscriptions destination. The initial Insights destination is
an honest unavailable placeholder; TB-14 owns conversion and spending
insights. iPad uses the same destinations with adaptive SwiftUI navigation,
not device-name branching.

## Upcoming interaction

Upcoming supplies Today, Next 30 Days, and Next 90 Days filters. It calls one
workspace command for its selected date range, groups the resulting entries by
calendar day, and opens `SubscriptionDetailView` when an entry is selected.
Expected charges show an `Expected Charge` label and calendar badge; confirmed
payments show a `Confirmed Payment` label and checkmark badge. Those labels
are part of the accessibility value, so status is never represented by colour
alone.

The first release includes confirmed payments whose charge date falls in the
selected date range. It does not show price changes as upcoming entries because
they are not charges. Cancellation, expiry, archiving, and permanent deletion
are excluded through the existing domain lifecycle rules and repository state.

## Boundaries and recovery

- Views invoke only `SubscriptionWorkspace`; they do not read SwiftData or
  recreate schedules.
- A repository error produces an empty/recoverable upcoming state without
  changing the library.
- `now` and `Calendar` remain injected workspace dependencies so date ranges,
  filtering, and ordering have deterministic core tests.
- No Calendar/EventKit, exchange-rate, network, or account API is introduced.

## Verification

- Core tests cover chronology, range boundaries, confirmed/expected labels,
  lifecycle exclusions, archive exclusion, and subscription selection IDs.
- UI tests cover compact tab navigation, both status labels, expected-detail
  navigation, Chinese copy, and iPad split-width rendering.
- Existing library, lifecycle, payment, and first-run test suites remain green.
