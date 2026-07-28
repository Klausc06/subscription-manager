# Explicit Calendar import verification

Date: 2026-07-29

## Behavioural contract

- Calendar access is requested only by the confirmed import command; loading a
  Calendar preview only creates the existing in-app projection.
- The importer accepts the precise projection snapshot that was visible at
  confirmation time, creates or reuses a dedicated `Subscription Manager`
  calendar, and persists the event identifier for every projection UID.
- A denial, revoked access, or unavailable writable source does not alter a
  subscription and leaves ICS export available. Individual event write errors
  report partial completion; retry updates already-mapped events and creates
  only the missing ones.

## Automated evidence

| Check | Result |
| --- | --- |
| `swift test --package-path Packages/SubscriptionCore` | 82 tests passed |
| iPhone 17 Pro `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO` | passed |
| Core confirmation timing fixture | preview causes no importer call; confirmed snapshot is the one imported |
| EventKit adapter fixture | repeat import reuses one calendar and mapped event; exact projected event is passed through |
| Access and source fixtures | denied and no-writable-source return recoverable states without writes |
| Partial-write fixture | retry creates the missing event and updates the existing mapped event |
| SwiftData mapping fixture | dedicated calendar metadata and per-event mapping survive repository reload |
| String-catalog JSON and whitespace checks | passed |

## Simulator evidence

On an iPhone 17 Pro simulator launched with `--ui-testing`, opening Settings
and then Calendar Preview showed the preview screen without any system Calendar
permission prompt. The available fixture had no renewal inside the selected
horizon, so Import to Calendar was correctly disabled; this establishes that
navigation and preview loading themselves do not request permission. The
confirmed-import path is covered by the injected importer timing fixture above,
without invoking EventKit in the test process.

## Privacy and recovery

`NSCalendarsFullAccessUsageDescription` is present in the app bundle and
localized for English and Simplified Chinese. The UI describes failures as
recoverable and keeps the existing ICS export action available.

## Known external limitation

The macOS target still requires Apple Developer provisioning for
`iCloud.com.klausc06.SubscriptionManager`, the pre-existing TB-16 CloudKit
signing prerequisite. iPhone simulator verification does not need that profile.
