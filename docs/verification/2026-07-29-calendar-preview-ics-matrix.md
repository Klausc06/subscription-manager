# Calendar preview and ICS export verification

Date: 2026-07-29

## Core projection

- The projection uses the existing deterministic Fixed Billing Schedule forecast.
- Archived and cancelled subscriptions produce no projected events through the
  existing eligibility rule; expired subscriptions are already recorded as
  cancelled lifecycle facts.
- The selected six- or twelve-month horizon and the calendar amount privacy
  preference are read from UserPreferences.
- Trial projections use 3- and 1-day alarms; active projections use 7- and
  1-day alarms.

## Automated evidence

| Check | Result |
| --- | --- |
| `swift test --package-path Packages/SubscriptionCore` | 81 tests passed |
| iPhone 17 Pro simulator build, `CODE_SIGNING_ALLOWED=NO` | passed |
| iPhone 17 Pro `SubscriptionManagerTests/AppDependenciesTests` | passed |
| `icalendar` 7.2.2 parses generated `.ics` | 1 all-day event; UID, URL, and 2 alarms verified |
| source scan for `EventKit`, `EKEventStore`, or access requests | no matches |

## Parser scenario

The exported fixture contains an event for 2026-08-02 through 2026-08-03
(exclusive `DTEND`), UID `subscription-20260802@subscription-manager`, its
management URL, and display alarms at 7 and 1 days before the renewal.

The independent `icalendar` parser decoded those fields successfully. The
application itself uses no EventKit API, so preview and export are independent
of Calendar authorization state.

## Known external limitation

The macOS target remains unable to sign in this checkout until the Apple
Developer team provisions `iCloud.com.klausc06.SubscriptionManager`. This is
the pre-existing CloudKit signing prerequisite documented for TB-16; simulator
build and test verification above do not need that profile.
