# TB20 portable exports verification

Date: 2026-07-29

## Acceptance matrix

| Requirement | Evidence | Result |
| --- | --- | --- |
| Versioned JSON retains stable subscription facts and preferences | `PortableExportTests.backupRoundTrips` encodes twice, independently decodes both JSON values, and compares their logical contents with the fixture | Pass |
| JSON preserves UUIDs, money minor units/currency, lifecycle, history, and archived state | JSON fixture contains each of those fields and compares the decoded model to the source model | Pass |
| CSV is portable across locale and safely quotes text | Independent `CSVFixtureParser` verifies Unicode, comma, quote, newline, empty URL, integer minor units, currency, and archived flag | Pass |
| Export includes archived records without mutation | `workspaceExportIsReadOnlyAndIncludesArchivedSubscriptions` verifies the returned backup and repository contents | Pass |
| Export remains offline and excludes sync/device calendar data | `PortableBackup` is constructed only from `SubscriptionRepository` and `PreferencesRepository`; no CloudKit or EventKit type appears in the encoder or export view | Pass by source inspection |
| User can reach both native export formats | `testSettingsOffersPortableExports` launches the app on iPhone 17 Pro simulator, opens Settings, enters Export Data, and finds JSON and CSV buttons | Pass |

## Commands run

```text
swift test --package-path Packages/SubscriptionCore
# 86 tests in 9 suites passed

xcodebuild build -quiet -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator'
# passed

xcodebuild test -quiet -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -only-testing:SubscriptionManagerTests
# passed

xcodebuild test -quiet -project SubscriptionManager.xcodeproj -scheme SubscriptionManager \
  -destination 'platform=iOS Simulator,id=4BF01B14-BD88-40E6-8DCD-2E91C9857012' \
  -only-testing:SubscriptionManagerUITests/SubscriptionManagerUITests/testSettingsOffersPortableExports
# passed
```

The native Files destination sheet is owned by iOS. The app presents it via
SwiftUI `fileExporter`; the test covers the app-owned navigation and controls.
