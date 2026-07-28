# Convergent Calendar projection verification

Date: 2026-07-29

## Automated evidence

| Check | Result |
| --- | --- |
| `swift test --package-path Packages/SubscriptionCore` | 83 tests passed |
| iPhone 17 Pro `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO` | passed |
| Xcode result bundle for `SubscriptionManagerTests` | EventKit reconciliation fixtures executed and passed |
| localized string catalog JSON | passed |
| `git diff --check` | passed |

## Reconciliation scenarios

| Scenario | Evidence |
| --- | --- |
| Repeated import | one calendar and one mapped event are reused |
| Subscription edit / managed field restoration | reconciliation writes the complete projected event to its mapped EventKit event |
| Cancellation or horizon contraction | mappings absent from the new projection remove their EventKit event and mapping |
| Horizon extension | a new, unmapped projection UID is written into the existing managed calendar |
| External event deletion | the importer returns `eventsMissing`; it creates neither a replacement event nor a calendar |
| External calendar deletion | the importer returns `calendarMissing`; the UI offers explicit rebuild or disable |
| Disable | persisted metadata stops later automatic reconciliation without requesting access |
| Rebuild | explicit command is the only recovery path that may request access and recreate projection data |
| Local subscription/preference mutation | queues a coalesced reconciliation request through `SubscriptionWorkspace` |
| Foreground / EventKit change | the app requests the same no-authorization reconciliation command |

## Privacy and user control

Normal reconciliation only reads/writes already-authorized, mapped content. It
does not call `requestFullAccessToEvents`. The first import and explicit rebuild
remain the only EventKit access request paths. The Calendar Preview keeps ICS
export available and presents localized, accessible **Rebuild Calendar** and
**Disable Calendar Sync** choices when external deletion is detected.

## External verification limitation

The same-account, multi-device iCloud delivery matrix cannot run in this
checkout because the Apple Developer team has not provisioned
`iCloud.com.klausc06.SubscriptionManager`; this is the existing TB-16 signing
prerequisite. A production device test should verify SwiftData/CloudKit delivery
while both devices enable Apple Calendar, then foreground either device to
exercise the convergent projection path. No production code is blocked from
building or simulator-testing by this limitation.
